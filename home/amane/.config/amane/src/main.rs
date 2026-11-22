mod bar;
mod launcher;
mod notifications;
mod osd;
mod theme;
mod tray;
mod utils;

use amane::{App, Apps, Service};

fn main() {
    drop(Apps::read());

    App::new()
        .ipc("launcher", launcher::toggle)
        .ipc("volume", utils::volume)
        .ipc("mic", utils::mic)
        .ipc("showOsd", osd::ipc)
        .ipc("clearNotifications", notifications::clear)
        .window_per_monitor(launcher::root)
        .window_per_monitor(bar::root)
        .window_per_monitor(notifications::root)
        .window_per_monitor(osd::root)
        .run();
}
