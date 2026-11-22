use std::{thread, time::Duration};

use amane::{Align, Color, Cursor, Rectangle, Service, Size::Parent, Text, Widget};
use chrono::Local;

use crate::{
    theme,
    utils::{self, execute_floating},
};

struct Clock {
    time: String,
}

impl Service for Clock {
    fn new() -> Self {
        Self { time: read_time() }
    }

    fn listen() {
        loop {
            let now = Local::now();

            // Sleep until the next second boundary.
            let remaining = 1_000_000_000 - now.timestamp_subsec_nanos() as u64;

            thread::sleep(Duration::from_nanos(remaining));

            Self::write().time = read_time();
        }
    }
}

fn read_time() -> String {
    Local::now().format("%A %H:%M").to_string()
}

pub fn root() -> impl Widget {
    let clock = Clock::read();

    Rectangle::new()
        .width(Parent)
        .height(Parent)
        .align_child(Align::Center, Align::Center)
        .child(
            Rectangle::new()
                .width(theme::BAR_HEIGHT * 3.5)
                .height(theme::BAR_HEIGHT)
                .align_child(Align::Center, Align::Center)
                .cursor(Cursor::Pointer)
                .on_click(|_| execute_floating(utils::CALENDER))
                .child(
                    Text::new(clock.time.clone())
                        .font(theme::FONT_FAMILY)
                        .size(theme::BAR_FONT_SIZE)
                        .color(Color::from(theme::BLUE)),
                ),
        )
}
