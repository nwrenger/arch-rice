use super::*;
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::{Mutex, mpsc};
use std::time::Instant;

struct Bus(Child, String);

impl Bus {
    fn start() -> Self {
        let mut child = Command::new("dbus-daemon")
            .args(["--session", "--nofork", "--print-address=1"])
            .stdout(Stdio::piped())
            .spawn()
            .expect("tray integration tests need dbus-daemon");
        let mut address = String::new();
        BufReader::new(child.stdout.take().unwrap())
            .read_line(&mut address)
            .unwrap();
        assert!(!address.is_empty());
        Self(child, address.trim().into())
    }

    fn connection(&self) -> Connection {
        self.builder().build().unwrap()
    }

    fn builder(&self) -> Builder<'_> {
        Builder::address(self.1.as_str())
            .unwrap()
            .method_timeout(TIMEOUT)
    }
}

impl Drop for Bus {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

struct Fixture {
    calls: mpsc::Sender<(i32, i32)>,
    pixel: Arc<Mutex<Vec<u8>>>,
}

#[zbus::interface(name = "org.kde.StatusNotifierItem")]
impl Fixture {
    #[zbus(property)]
    fn status(&self) -> &str {
        "Active"
    }

    #[zbus(property)]
    fn icon_pixmap(&self) -> Vec<(i32, i32, Vec<u8>)> {
        vec![(1, 1, self.pixel.lock().unwrap().clone())]
    }

    fn activate(&self, x: i32, y: i32) {
        self.calls.send((x, y)).unwrap();
    }
}

#[test]
fn watcher_hosts_updates_activates_and_removes_items() {
    let bus = Bus::start();
    let (send, receive) = mpsc::channel();
    let rpc = bus.connection();
    let signals = bus.connection();
    let expected_owner = rpc.unique_name().unwrap().to_string();
    let worker = thread::spawn(move || {
        run_session(rpc, signals, |view| {
            let _ = send.send(view);
        })
    });

    let (calls, activated) = mpsc::channel();
    let pixel = Arc::new(Mutex::new(vec![255, 10, 20, 30]));
    let app = bus
        .builder()
        .serve_at(
            "/Fixture",
            Fixture {
                calls,
                pixel: pixel.clone(),
            },
        )
        .unwrap()
        .build()
        .unwrap();
    let bus_proxy = DBusProxy::new(&app).unwrap();
    let name = BusName::try_from(watcher::INTERFACES[0]).unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    let owner = loop {
        if let Ok(owner) = bus_proxy.get_name_owner(name.clone()) {
            break owner;
        }
        assert!(Instant::now() < deadline, "watcher did not claim its name");
        thread::sleep(Duration::from_millis(10));
    };
    assert_eq!(owner.as_str(), expected_owner);
    let watcher = Proxy::new(&app, owner.as_str(), watcher::PATH, watcher::INTERFACES[0]).unwrap();
    watcher
        .call::<_, _, ()>("RegisterStatusNotifierItem", &("/Fixture",))
        .unwrap();
    let initial = receive.recv_timeout(TIMEOUT).unwrap();
    assert_eq!(initial.len(), 1);
    assert!(initial[0].icon_image().is_some());
    initial[0].activate(12, 34);
    assert_eq!(activated.recv_timeout(TIMEOUT).unwrap(), (12, 34));

    // A second host discovers the same item through the existing watcher, without replacing it.
    let (host_send, host_receive) = mpsc::channel();
    let (host_rpc, host_signals) = (bus.connection(), bus.connection());
    let host = thread::spawn(move || {
        run_session(host_rpc, host_signals, |view| {
            let _ = host_send.send(view);
        })
    });
    assert_eq!(host_receive.recv_timeout(TIMEOUT).unwrap().len(), 1);
    assert_eq!(
        bus_proxy.get_name_owner(name).unwrap().as_str(),
        expected_owner
    );

    *pixel.lock().unwrap() = vec![255, 30, 20, 10];
    app.emit_signal(
        None::<&str>,
        "/Fixture",
        item::INTERFACES[0],
        "NewIcon",
        &(),
    )
    .unwrap();
    let updated = receive.recv_timeout(TIMEOUT).unwrap();
    assert_eq!(updated.len(), 1);
    assert!(!updated[0].same_view(&initial[0]));
    app.emit_signal(
        None::<&str>,
        "/Fixture",
        item::INTERFACES[0],
        "NewIcon",
        &(),
    )
    .unwrap();
    assert!(matches!(
        receive.recv_timeout(Duration::from_millis(100)),
        Err(mpsc::RecvTimeoutError::Timeout)
    ));

    drop(watcher);
    drop(bus_proxy);
    drop(app);
    assert!(receive.recv_timeout(TIMEOUT).unwrap().is_empty());
    drop(bus);
    worker.join().unwrap().ok();
    host.join().unwrap().ok();
}
