use std::process::{Command, Stdio};
use std::sync::{LazyLock, Weak, mpsc};

use zbus::blocking::{Connection, Proxy, fdo::DBusProxy};
use zbus::names::BusName;

use super::backend::Key;

pub(super) struct Target {
    pub key: Key,
    pub interface: &'static str,
    pub connection: Connection,
}

pub(super) enum Action {
    Activate(i32, i32),
    Terminate,
}

type Job = (Weak<Target>, Action);

static ACTIONS: LazyLock<mpsc::SyncSender<Job>> = LazyLock::new(|| {
    let (send, receive) = mpsc::sync_channel::<Job>(32);
    std::thread::spawn(move || {
        for (target, action) in receive {
            let Some(target) = target.upgrade() else {
                continue;
            };
            match action {
                Action::Activate(x, y) => {
                    if let Err(error) = target.activate(x, y) {
                        eprintln!("tray: activation failed: {error}");
                    }
                }
                Action::Terminate => {
                    if let Err(error) = target.terminate() {
                        eprintln!("tray: termination refused or failed: {error}");
                    }
                }
            }
        }
    });
    send
});

pub(super) fn submit(target: Weak<Target>, action: Action) {
    if ACTIONS.try_send((target, action)).is_err() {
        eprintln!("tray: action queue is full or unavailable");
    }
}

impl Target {
    fn activate(&self, x: i32, y: i32) -> zbus::Result<()> {
        let proxy = Proxy::new(
            &self.connection,
            self.key.owner.as_str(),
            self.key.path.as_str(),
            self.interface,
        )?;
        proxy.call("Activate", &(x, y))
    }

    fn terminate(&self) -> Result<(), Box<dyn std::error::Error>> {
        let bus = DBusProxy::new(&self.connection)?;
        let owner = BusName::try_from(self.key.owner.as_str())?;
        let us = self
            .connection
            .unique_name()
            .ok_or("missing shell bus name")?;
        let pid = bus.get_connection_unix_process_id(owner.clone())?;
        if !self.key.owner.starts_with(':') || pid <= 1 || pid == std::process::id() {
            return Err("not an application process".into());
        }
        if bus.get_connection_unix_user(owner.clone())?
            != bus.get_connection_unix_user(BusName::from(us.clone()))?
            || bus.get_connection_unix_process_id(owner)? != pid
        {
            return Err("the registered peer changed or belongs to a different user".into());
        }
        // No process-name matching or shell: use only the PID reported for the live bus peer.
        let status = Command::new("kill")
            .args(["-TERM", "--", &pid.to_string()])
            .stdin(Stdio::null())
            .status()?;
        if !status.success() {
            return Err(format!("kill exited with {status}").into());
        }
        Ok(())
    }
}
