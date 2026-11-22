use std::time::Duration;

use amane::{
    Align, Audio, Bluetooth, Button, Color, Cpu, Cursor, Link, Network, Rectangle, Row, Service,
    Size::Parent, Text, Widget, children,
};

use crate::{
    osd, theme,
    tray::Tray,
    utils::{self, AudioTarget, execute_floating},
};

pub fn root() -> impl Widget {
    let mut rows: Vec<Box<dyn Widget>> =
        children!(cpu(), bluetooth(), network(), vpn(), mic(), audio());

    let tray = Tray::read();
    for item in tray.list() {
        let item = item.clone(); // Clone the item to move it into the closure
        let icon = Rectangle::new()
            .width(theme::BAR_FONT_LG_SIZE)
            .height(theme::BAR_FONT_LG_SIZE)
            .fill(theme::OVERLAY);

        let icon = match item.icon_image() {
            Some(i) => icon.fill(i),
            None => icon,
        };

        rows.push(Box::new(
            Rectangle::new()
                .width(theme::BAR_HEIGHT)
                .height(theme::BAR_HEIGHT)
                .cursor(Cursor::Pointer)
                .align_child(Align::Center, Align::Center)
                .on_click(move |b| {
                    if b == Button::Left {
                        item.activate(0, 0);
                    } else if b == Button::Right {
                        item.terminate();
                    }
                })
                .child(icon),
        ));
    }

    rows.reverse(); // Right-aligned, so reverse the order of the widgets

    Rectangle::new()
        .width(Parent)
        .height(Parent)
        .align_child(Align::End, Align::Center)
        .child(Row::new(rows))
}

fn cpu() -> Rectangle {
    let cpu = Cpu::read();
    let (icon, level) = usage_bar(cpu.percent());

    Rectangle::new()
        .width(theme::BAR_HEIGHT * 1.5)
        .height(theme::BAR_HEIGHT)
        .cursor(Cursor::Pointer)
        .align_child(Align::Center, Align::Center)
        .on_click(|_| execute_floating(utils::SYSTEM_MONITOR))
        .child(
            Row::new(children!(
                Text::new("󰍛")
                    .font(theme::SYMBOLS_FONT_FAMILY)
                    .size(theme::BAR_FONT_LG_SIZE)
                    .color(Color::from(theme::GREEN)),
                Text::new(format!(" {icon}"))
                    .font(theme::FONT_FAMILY)
                    .size(theme::BAR_FONT_SIZE)
                    .color(Color::from(match level {
                        UsageLevel::Low => theme::GREEN,
                        UsageLevel::Mid => theme::YELLOW,
                        UsageLevel::High => theme::RED,
                    })),
            ))
            .align(Align::Center),
        )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum UsageLevel {
    Low,
    Mid,
    High,
}

fn usage_bar(percent: u8) -> (char, UsageLevel) {
    const LEVELS: [char; 8] = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

    let percent = percent.min(100);
    let index = (percent as usize * 7 + 50) / 100;

    let level = match percent {
        0..=49 => UsageLevel::Low,
        50..=79 => UsageLevel::Mid,
        _ => UsageLevel::High,
    };

    (LEVELS[index], level)
}

fn bluetooth() -> Rectangle {
    let bluetooth = Bluetooth::read();

    let icon = if bluetooth.devices().iter().any(|d| d.connected()) {
        "󰂱"
    } else if bluetooth.powered() {
        "󰂯"
    } else {
        "󰂲"
    };

    Rectangle::new()
        .width(theme::BAR_HEIGHT)
        .height(theme::BAR_HEIGHT)
        .cursor(Cursor::Pointer)
        .align_child(Align::Center, Align::Center)
        .on_click(|_| execute_floating(utils::BLUETOOTH))
        .child(
            Row::new(children!(
                Text::new(icon)
                    .font(theme::SYMBOLS_FONT_FAMILY)
                    .size(theme::BAR_FONT_SIZE)
                    .color(Color::from(if bluetooth.powered() {
                        theme::SKY
                    } else {
                        theme::OVERLAY
                    })),
            ))
            .align(Align::Center),
        )
}

fn network() -> Rectangle {
    let network = Network::read();
    let icon = match network.link() {
        Link::Wifi => "󰤨",
        Link::Wired => "󰈀",
        Link::Other => "󰛳",
        Link::Offline => "󰈂",
    };

    Rectangle::new()
        .width(theme::BAR_HEIGHT)
        .height(theme::BAR_HEIGHT)
        .cursor(Cursor::Pointer)
        .align_child(Align::Center, Align::Center)
        .on_click(|_| execute_floating(utils::NETWORK))
        .child(
            Text::new(icon)
                .font(theme::SYMBOLS_FONT_FAMILY)
                .size(theme::BAR_FONT_SIZE)
                .color(Color::from(if network.link() != Link::Offline {
                    theme::SKY
                } else {
                    theme::OVERLAY
                })),
        )
}

const VPN_CONNECTED_ICON: &str = "󰒃";
const VPN_DISCONNECTED_ICON: &str = "󰌙";

struct Vpn {
    connected: Option<bool>,
}

fn parse_vpn_status(output: &str) -> Option<bool> {
    match output.split_whitespace().next()? {
        "Connected" => Some(true),
        "Disconnected" => Some(false),
        _ => None,
    }
}

impl Service for Vpn {
    fn new() -> Self {
        Self { connected: None }
    }

    fn interval() -> Duration {
        Duration::from_secs(2)
    }

    fn update(&mut self) -> bool {
        let Some(connected) = parse_vpn_status(&amane::output("mullvad status")) else {
            return false;
        };
        let previous = self.connected.replace(connected);
        if previous.is_some_and(|last| last != connected) {
            let (icon, message) = if connected {
                (VPN_CONNECTED_ICON, "VPN connected")
            } else {
                (VPN_DISCONNECTED_ICON, "VPN disconnected")
            };
            osd::show(icon, message.to_owned(), None);
        }
        previous != Some(connected)
    }
}

fn vpn() -> Rectangle {
    let connected = Vpn::read().connected == Some(true);
    let icon = if connected {
        VPN_CONNECTED_ICON
    } else {
        VPN_DISCONNECTED_ICON
    };

    Rectangle::new()
        .width(theme::BAR_HEIGHT)
        .height(theme::BAR_HEIGHT)
        .cursor(Cursor::Pointer)
        .align_child(Align::Center, Align::Center)
        .on_click(|_| execute_floating(utils::VPN))
        .child(
            Text::new(icon)
                .font(theme::SYMBOLS_FONT_FAMILY)
                .size(theme::BAR_FONT_SIZE)
                .color(Color::from(if connected {
                    theme::LAVENDER
                } else {
                    theme::OVERLAY
                })),
        )
}

fn mic() -> Rectangle {
    let audio = Audio::read();
    let icon = AudioTarget::Microphone.icon(audio.microphone_volume(), audio.microphone_muted());

    Rectangle::new()
        .width(theme::BAR_HEIGHT)
        .height(theme::BAR_HEIGHT)
        .cursor(Cursor::Pointer)
        .align_child(Align::Center, Align::Center)
        .on_click(|b| match b {
            Button::Right => AudioTarget::Microphone.toggle(),
            _ => execute_floating(utils::MIC),
        })
        .on_scroll(|scroll| AudioTarget::Microphone.scroll(scroll.y))
        .child(
            Text::new(icon)
                .font(theme::SYMBOLS_FONT_FAMILY)
                .size(theme::BAR_FONT_SIZE)
                .color(Color::from(if !audio.microphone_muted() {
                    theme::YELLOW
                } else {
                    theme::OVERLAY
                })),
        )
}

fn audio() -> Rectangle {
    let audio = Audio::read();
    let icon = AudioTarget::Output.icon(audio.volume(), audio.muted());

    Rectangle::new()
        .width(theme::BAR_HEIGHT)
        .height(theme::BAR_HEIGHT)
        .cursor(Cursor::Pointer)
        .align_child(Align::Center, Align::Center)
        .on_click(|b| match b {
            Button::Right => AudioTarget::Output.toggle(),
            _ => execute_floating(utils::AUDIO),
        })
        .on_scroll(|scroll| AudioTarget::Output.scroll(scroll.y))
        .child(
            Text::new(icon)
                .font(theme::SYMBOLS_FONT_FAMILY)
                .size(theme::BAR_FONT_SIZE)
                .color(Color::from(if !audio.muted() {
                    theme::RED
                } else {
                    theme::OVERLAY
                })),
        )
}

#[cfg(test)]
mod tests {
    use super::parse_vpn_status;

    #[test]
    fn only_confirmed_mullvad_states_change_the_indicator() {
        assert_eq!(
            parse_vpn_status(" Connected\n    Relay: se-got-wg-001"),
            Some(true)
        );
        assert_eq!(parse_vpn_status("Disconnected\n"), Some(false));
        assert_eq!(parse_vpn_status("Connecting\n"), None);
        assert_eq!(
            parse_vpn_status("Failed to query: Connected state unavailable"),
            None
        );
        assert_eq!(parse_vpn_status(""), None);
    }
}
