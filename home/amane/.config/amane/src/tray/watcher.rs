use std::collections::BTreeSet;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use zbus::blocking::Connection;
use zbus::names::BusName;
use zbus::object_server::SignalEmitter;
use zbus::{fdo, message::Header, zvariant::ObjectPath};

pub(super) const PATH: &str = "/StatusNotifierWatcher";
pub(super) const INTERFACES: [&str; 2] = [
    "org.kde.StatusNotifierWatcher",
    "org.freedesktop.StatusNotifierWatcher",
];

#[derive(Clone, Default)]
pub(super) struct Watchers(Arc<Mutex<BTreeSet<String>>>);

impl Watchers {
    fn items(&self) -> MutexGuard<'_, BTreeSet<String>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    pub(super) fn install(&self, connection: &Connection) -> zbus::Result<()> {
        connection.object_server().at(PATH, Kde(self.clone()))?;
        connection
            .object_server()
            .at(PATH, Freedesktop(self.clone()))?;
        Ok(())
    }

    pub(super) fn remove_owner(&self, connection: &Connection, owner: &str) -> zbus::Result<()> {
        let removed = {
            let mut items = self.items();
            items
                .extract_if(.., |id| split_id(id).0 == owner)
                .collect::<Vec<_>>()
        };
        for id in removed {
            for interface in INTERFACES {
                connection.emit_signal(
                    None::<&str>,
                    PATH,
                    interface,
                    "StatusNotifierItemUnregistered",
                    &(&id,),
                )?;
            }
        }
        Ok(())
    }

    async fn register(
        &self,
        connection: &zbus::Connection,
        header: Header<'_>,
        service: &str,
    ) -> fdo::Result<()> {
        let sender = header
            .sender()
            .ok_or_else(|| fdo::Error::Failed("missing sender".into()))?;
        let path = if service.starts_with('/') {
            service
        } else {
            let (name, path) = split_id(service);
            if name != sender.as_str() {
                let name =
                    BusName::try_from(name).map_err(|e| fdo::Error::InvalidArgs(e.to_string()))?;
                let bus = fdo::DBusProxy::new(connection).await?;
                if bus.get_name_owner(name).await?.as_str() != sender.as_str() {
                    return Err(fdo::Error::AccessDenied(
                        "item must belong to the sender".into(),
                    ));
                }
            }
            path
        };
        ObjectPath::try_from(path).map_err(|e| fdo::Error::InvalidArgs(e.to_string()))?;
        let id = format!("{sender}{path}");
        let new = self.items().insert(id.clone());
        if new {
            let emitter = SignalEmitter::new(connection, PATH)?;
            Kde::status_notifier_item_registered(&emitter, &id).await?;
            Freedesktop::status_notifier_item_registered(&emitter, &id).await?;
        }
        Ok(())
    }
}

pub(super) fn split_id(id: &str) -> (&str, &str) {
    id.find('/')
        .map_or((id, "/StatusNotifierItem"), |at| id.split_at(at))
}

macro_rules! watcher {
    ($name:ident, $interface:literal) => {
        struct $name(Watchers);

        #[zbus::interface(name = $interface)]
        impl $name {
            async fn register_status_notifier_item(
                &self,
                service: &str,
                #[zbus(header)] header: Header<'_>,
                #[zbus(connection)] connection: &zbus::Connection,
            ) -> fdo::Result<()> {
                self.0.register(connection, header, service).await
            }

            async fn register_status_notifier_host(
                &self,
                _service: &str,
                #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
            ) -> fdo::Result<()> {
                Self::status_notifier_host_registered(&emitter).await?;
                Ok(())
            }

            #[zbus(property(emits_changed_signal = "false"))]
            fn registered_status_notifier_items(&self) -> Vec<String> {
                self.0.items().iter().cloned().collect()
            }

            #[zbus(property)]
            fn is_status_notifier_host_registered(&self) -> bool {
                true
            }

            #[zbus(property)]
            fn protocol_version(&self) -> i32 {
                0
            }

            #[zbus(signal)]
            async fn status_notifier_item_registered(
                emitter: &SignalEmitter<'_>,
                id: &str,
            ) -> zbus::Result<()>;

            #[zbus(signal)]
            #[allow(dead_code)] // Advertised here; emitted by the blocking disconnect handler.
            async fn status_notifier_item_unregistered(
                emitter: &SignalEmitter<'_>,
                id: &str,
            ) -> zbus::Result<()>;

            #[zbus(signal)]
            async fn status_notifier_host_registered(
                emitter: &SignalEmitter<'_>,
            ) -> zbus::Result<()>;
        }
    };
}

watcher!(Kde, "org.kde.StatusNotifierWatcher");
watcher!(Freedesktop, "org.freedesktop.StatusNotifierWatcher");
