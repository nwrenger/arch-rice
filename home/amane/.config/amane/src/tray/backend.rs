use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use zbus::blocking::{Connection, MessageIterator, Proxy, connection::Builder, fdo::DBusProxy};
use zbus::fdo::{self, RequestNameFlags};
use zbus::message::Type;
use zbus::names::BusName;
use zbus::zvariant::{ObjectPath, OwnedValue};
use zbus::{MatchRule, Message};

use super::actions::Target;
use super::{TrayItem, item, watcher};

const PROPERTIES: &str = "org.freedesktop.DBus.Properties";
const DBUS: &str = "org.freedesktop.DBus";
const TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(super) struct Key {
    pub owner: String,
    pub path: String,
}

#[derive(Default)]
struct Source {
    owner: Option<String>,
    keys: BTreeSet<Key>,
}

struct Entry {
    target: Arc<Target>,
    icon: Option<item::Icon>,
    view: TrayItem,
}

struct Session {
    rpc: Connection,
    watchers: watcher::Watchers,
    host: String,
    sources: [Source; 2],
    entries: BTreeMap<Key, Option<Entry>>,
    last: Vec<TrayItem>,
}

pub(super) fn run(mut publish: impl FnMut(Vec<TrayItem>)) {
    let mut last_error = None;
    loop {
        let result = (|| {
            let rpc = Builder::session()?.method_timeout(TIMEOUT).build()?;
            let signals = Builder::session()?
                .method_timeout(TIMEOUT)
                .max_queued(256)
                .build()?;
            run_session(rpc, signals, &mut publish)
        })();
        if let Err(error) = result {
            let message = error.to_string();
            if last_error.as_ref() != Some(&message) {
                eprintln!("tray: D-Bus unavailable: {message}");
                last_error = Some(message);
            }
        }
        publish(Vec::new());
        thread::sleep(Duration::from_secs(2)); // Reconnect only after a failure, never poll a live bus.
    }
}

fn run_session(
    rpc: Connection,
    signals: Connection,
    mut publish: impl FnMut(Vec<TrayItem>),
) -> zbus::Result<()> {
    let bus = DBusProxy::new(&signals)?;
    let messages = MessageIterator::from(&signals);
    // Use a dedicated signal connection so an icon burst cannot block method replies.
    for interface in watcher::INTERFACES.into_iter().chain(item::INTERFACES) {
        bus.add_match_rule(
            MatchRule::builder()
                .msg_type(Type::Signal)
                .interface(interface)?
                .build(),
        )?;
        bus.add_match_rule(
            MatchRule::builder()
                .msg_type(Type::Signal)
                .interface(PROPERTIES)?
                .member("PropertiesChanged")?
                .arg(0, interface)?
                .build(),
        )?;
    }
    bus.add_match_rule(
        MatchRule::builder()
            .msg_type(Type::Signal)
            .sender(DBUS)?
            .interface(DBUS)?
            .member("NameOwnerChanged")?
            .build(),
    )?;

    let watchers = watcher::Watchers::default();
    watchers.install(&rpc)?;
    let unique = rpc
        .unique_name()
        .expect("session bus must assign a unique name");
    let suffix = unique.as_str().replace([':', '.'], "_");
    let host = format!("org.kde.StatusNotifierHost-{}-{suffix}", std::process::id());
    rpc.request_name_with_flags(host.as_str(), RequestNameFlags::DoNotQueue.into())?;
    let mut session = Session {
        rpc,
        watchers,
        host,
        sources: Default::default(),
        entries: BTreeMap::new(),
        last: Vec::new(),
    };
    for index in 0..watcher::INTERFACES.len() {
        session.attach(index)?;
    }
    session.reconcile();
    session.publish(&mut publish);

    for message in messages {
        session.handle(&message?)?;
        session.publish(&mut publish);
    }
    Ok(())
}

impl Session {
    fn attach(&mut self, index: usize) -> zbus::Result<()> {
        let interface = watcher::INTERFACES[index];
        let bus = DBusProxy::new(&self.rpc)?;
        let name = BusName::try_from(interface)?;
        let owner = match bus.get_name_owner(name.clone()) {
            Ok(owner) => owner,
            Err(fdo::Error::NameHasNoOwner(_)) => {
                self.rpc
                    .request_name_with_flags(interface, RequestNameFlags::DoNotQueue.into())?;
                bus.get_name_owner(name)?
            }
            Err(error) => return Err(error.into()),
        };
        let source = &mut self.sources[index];
        if source.owner.as_deref() != Some(owner.as_str()) {
            source.keys.clear();
            source.owner = Some(owner.to_string());
            if self.rpc.unique_name().map(|n| n.as_str()) != Some(owner.as_str()) {
                let proxy = Proxy::new(&self.rpc, owner.as_str(), watcher::PATH, interface)?;
                // Some watcher implementations host items without implementing this method.
                let _ = proxy.call::<_, _, ()>("RegisterStatusNotifierHost", &(&self.host,));
            }
        }
        self.read_watcher(index);
        Ok(())
    }

    fn read_watcher(&mut self, index: usize) {
        let source = &mut self.sources[index];
        let Some(owner) = &source.owner else { return };
        let Ok(proxy) = Proxy::new(&self.rpc, owner.as_str(), watcher::PATH, PROPERTIES) else {
            return;
        };
        let Ok(value) = proxy.call::<_, _, OwnedValue>(
            "Get",
            &(watcher::INTERFACES[index], "RegisteredStatusNotifierItems"),
        ) else {
            return;
        };
        let Ok(ids) = Vec::<String>::try_from(value) else {
            return;
        };
        let Ok(bus) = DBusProxy::new(&self.rpc) else {
            return;
        };
        source.keys = ids
            .iter()
            .filter_map(|id| {
                let (service, path) = watcher::split_id(id);
                ObjectPath::try_from(path).ok()?;
                let name = BusName::try_from(service).ok()?;
                let owner = bus.get_name_owner(name).ok()?.to_string();
                owner.starts_with(':').then(|| Key {
                    owner,
                    path: path.into(),
                })
            })
            .collect();
    }

    fn reconcile(&mut self) {
        let keys: BTreeSet<_> = self
            .sources
            .iter()
            .flat_map(|source| source.keys.iter().cloned())
            .collect();
        self.entries.retain(|key, _| keys.contains(key));
        for key in keys {
            if !self.entries.contains_key(&key) {
                self.entries.insert(key.clone(), None);
                self.refresh(&key);
            }
        }
    }

    fn refresh(&mut self, key: &Key) {
        let Some(entry) = self.entries.get_mut(key) else {
            return;
        };
        let Some(info) = item::read(&self.rpc, &key.owner, &key.path) else {
            return;
        };
        if !info.visible {
            *entry = None;
            return;
        }
        if entry
            .as_ref()
            .is_some_and(|old| old.target.interface == info.interface && old.icon == info.icon)
        {
            return;
        }
        let target = match entry.as_ref() {
            Some(old) if old.target.interface == info.interface => old.target.clone(),
            _ => Arc::new(Target {
                key: key.clone(),
                interface: info.interface,
                connection: self.rpc.clone(),
            }),
        };
        let view = TrayItem::new(info.icon.as_ref().and_then(item::Icon::file), &target);
        *entry = Some(Entry {
            target,
            icon: info.icon,
            view,
        });
    }

    fn handle(&mut self, message: &Message) -> zbus::Result<()> {
        let header = message.header();
        if header.message_type() != Type::Signal {
            return Ok(());
        }
        let (Some(sender), Some(path), Some(interface), Some(member)) = (
            header.sender(),
            header.path(),
            header.interface(),
            header.member(),
        ) else {
            return Ok(());
        };
        let (sender, path, interface, member) = (
            sender.as_str(),
            path.as_str(),
            interface.as_str(),
            member.as_str(),
        );
        if sender == DBUS && interface == DBUS && member == "NameOwnerChanged" {
            let body = message.body();
            let (name, old, new): (&str, &str, &str) = body.deserialize()?;
            if let Some(index) = watcher::INTERFACES.iter().position(|i| *i == name) {
                self.attach(index)?;
                self.reconcile();
            } else if name.starts_with(':') && !old.is_empty() && new.is_empty() {
                self.watchers.remove_owner(&self.rpc, name)?;
                for source in &mut self.sources {
                    source.keys.retain(|key| key.owner != name);
                }
                self.entries.retain(|key, _| key.owner != name);
            }
            return Ok(());
        }
        if path == watcher::PATH {
            for (index, name) in watcher::INTERFACES.into_iter().enumerate() {
                if self.sources[index].owner.as_deref() != Some(sender) {
                    continue;
                }
                let registered = interface == name
                    && matches!(
                        member,
                        "StatusNotifierItemRegistered" | "StatusNotifierItemUnregistered"
                    );
                let properties = interface == PROPERTIES
                    && member == "PropertiesChanged"
                    && message
                        .body()
                        .deserialize::<(&str, BTreeMap<&str, OwnedValue>, Vec<&str>)>()
                        .is_ok_and(|(iface, changed, invalid)| {
                            const ITEMS: &str = "RegisteredStatusNotifierItems";
                            iface == name
                                && (changed.contains_key(ITEMS) || invalid.contains(&ITEMS))
                        });
                if registered || properties {
                    self.read_watcher(index);
                    self.reconcile();
                }
            }
        }
        let item_signal = item::INTERFACES.contains(&interface)
            && matches!(member, "NewIcon" | "NewAttentionIcon" | "NewStatus");
        let item_properties = interface == PROPERTIES
            && member == "PropertiesChanged"
            && message
                .body()
                .deserialize::<(&str, BTreeMap<&str, OwnedValue>, Vec<&str>)>()
                .is_ok_and(|(iface, changed, invalid)| {
                    item::INTERFACES.contains(&iface)
                        && [
                            "Status",
                            "IconName",
                            "IconPixmap",
                            "IconThemePath",
                            "AttentionIconName",
                            "AttentionIconPixmap",
                        ]
                        .iter()
                        .any(|key| changed.contains_key(key) || invalid.contains(key))
                });
        if item_signal || item_properties {
            let key = Key {
                owner: sender.into(),
                path: path.into(),
            };
            self.refresh(&key);
        }
        Ok(())
    }

    fn publish(&mut self, publish: &mut impl FnMut(Vec<TrayItem>)) {
        let views = self
            .entries
            .values()
            .filter_map(|entry| entry.as_ref().map(|entry| &entry.view));
        if views.clone().count() == self.last.len()
            && views.clone().zip(&self.last).all(|(a, b)| a.same_view(b))
        {
            return;
        }
        self.last = views.cloned().collect();
        publish(self.last.clone());
    }
}

#[cfg(test)]
mod tests;
