use std::sync::{Condvar, Mutex};
use std::time::{Duration, Instant};

use amane::{Audio, Service, Workspaces};

use crate::osd;

pub const ABOUT: &str = "fastfetch";
pub const UPDATE: &str = "update";
pub const TERMINAL: &str = "alacritty";
pub const SYSTEM_MONITOR: &str = "btop";
pub const BLUETOOTH: &str = "bluetui";
pub const NETWORK: &str = "wlctl";
pub const VPN: &str = "vpn";
pub const MIC: &str = "wiremix -v input";
pub const AUDIO: &str = "wiremix -v output";
pub const CALENDER: &str = "chroncal";

pub fn execute_about() {
    amane::spawn(&format!(
        "{} --title smolfloat -e fish -c '{}; show_done'",
        TERMINAL, ABOUT
    ));
}

pub fn execute_floating(app: &str) {
    amane::spawn(&format!("{} --title float -e {}", TERMINAL, app));
}

pub fn execute_install(source: &str) {
    amane::spawn(&format!("install {}", source));
}

pub fn execute_remove(source: &str) {
    amane::spawn(&format!("remove {}", source));
}

pub fn shutdown() {
    amane::spawn("systemctl poweroff");
}

pub fn reboot() {
    amane::spawn("systemctl reboot");
}

pub fn logout() {
    amane::spawn("hyprctl dispatch 'hl.dsp.exit()'");
}

pub fn suspend() {
    amane::spawn("systemctl suspend");
}

pub(crate) fn focused_output() -> Option<String> {
    Workspaces::read()
        .list()
        .iter()
        .find(|workspace| workspace.focused())
        .and_then(|workspace| workspace.output())
        .map(str::to_owned)
}

const LEVEL_STEP: i16 = 5;
const CONTROL_SETTLE_TIME: Duration = Duration::from_millis(500);

struct Pending<T>(Option<(T, Instant)>);

impl<T: Copy> Pending<T> {
    fn value(&self, confirmed: T, now: Instant) -> T {
        self.0
            .filter(|(_, until)| now < *until)
            .map_or(confirmed, |(value, _)| value)
    }

    fn set(&mut self, value: T, now: Instant) {
        self.0 = Some((value, now + CONTROL_SETTLE_TIME));
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct AudioLevel {
    volume: u8,
    muted: bool,
}

#[derive(Clone, Copy)]
pub(crate) enum AudioTarget {
    Output,
    Microphone,
}

#[derive(Clone, Copy)]
enum AudioAction {
    Adjust(i16),
    Toggle,
}

impl AudioAction {
    fn apply(self, current: AudioLevel) -> AudioLevel {
        match self {
            Self::Adjust(step) => AudioLevel {
                volume: (i16::from(current.volume) + step).clamp(0, 100) as u8,
                muted: false,
            },
            Self::Toggle => AudioLevel {
                muted: !current.muted,
                ..current
            },
        }
    }
}

static OUTPUT_PENDING: Mutex<Pending<AudioLevel>> = Mutex::new(Pending(None));
static MIC_PENDING: Mutex<Pending<AudioLevel>> = Mutex::new(Pending(None));

impl AudioTarget {
    pub(crate) fn icon(self, volume: u8, muted: bool) -> &'static str {
        match (self, muted, volume) {
            (Self::Microphone, true, _) => "󰍭",
            (Self::Microphone, false, _) => "󰍬",
            (Self::Output, true, _) => "󰝟",
            (Self::Output, false, 0..=33) => "󰕿",
            (Self::Output, false, 34..=66) => "󰖀",
            (Self::Output, false, _) => "󰕾",
        }
    }

    pub(crate) fn scroll(self, y: f32) {
        if y.is_finite() && y != 0. {
            self.control(AudioAction::Adjust(if y < 0. {
                LEVEL_STEP
            } else {
                -LEVEL_STEP
            }));
        }
    }

    pub(crate) fn toggle(self) {
        self.control(AudioAction::Toggle);
    }

    fn control(self, action: AudioAction) {
        let (pending, toggle, set_volume) = match self {
            Self::Output => (
                &OUTPUT_PENDING,
                Audio::toggle_mute as fn(),
                Audio::set_volume as fn(u8),
            ),
            Self::Microphone => (
                &MIC_PENDING,
                Audio::toggle_microphone_mute as fn(),
                Audio::set_microphone_volume as fn(u8),
            ),
        };
        let mut pending = pending
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let confirmed = {
            let audio = Audio::read();
            match self {
                Self::Output => AudioLevel {
                    volume: audio.volume(),
                    muted: audio.muted(),
                },
                Self::Microphone => AudioLevel {
                    volume: audio.microphone_volume(),
                    muted: audio.microphone_muted(),
                },
            }
        };
        let now = Instant::now();
        // Amane queues writes; repeated input must advance from the last requested level.
        let current = pending.value(confirmed, now);
        let next = action.apply(current);
        if next.muted != current.muted {
            toggle();
        }
        if next.volume != current.volume {
            set_volume(next.volume);
        }
        pending.set(next, now);
        drop(pending);

        let message = match (self, next.muted) {
            (Self::Output, true) => "Muted".into(),
            (Self::Output, false) => format!("{}%", next.volume),
            (Self::Microphone, true) => "Microphone muted".into(),
            (Self::Microphone, false) => format!("Microphone {}%", next.volume),
        };
        let percent = if next.muted { 0 } else { next.volume };
        osd::show(
            self.icon(next.volume, next.muted),
            message,
            Some(f32::from(percent) / 100.),
        );
    }

    fn ipc(self, args: &[String]) -> String {
        let action = match args {
            [action] if action == "up" => AudioAction::Adjust(LEVEL_STEP),
            [action] if action == "down" => AudioAction::Adjust(-LEVEL_STEP),
            [action] if action == "mute" => AudioAction::Toggle,
            _ => return "usage: up | down | mute".into(),
        };
        self.control(action);
        "ok".into()
    }
}

pub(crate) fn volume(args: &[String]) -> String {
    AudioTarget::Output.ipc(args)
}

pub(crate) fn mic(args: &[String]) -> String {
    AudioTarget::Microphone.ipc(args)
}

// Overlay services sleep until an actual UI deadline instead of ticking every frame.
pub(crate) struct WakeTimer {
    next: Mutex<Option<Instant>>,
    changed: Condvar,
}

impl WakeTimer {
    pub(crate) const fn new() -> Self {
        Self {
            next: Mutex::new(None),
            changed: Condvar::new(),
        }
    }

    pub(crate) fn schedule(&self, at: Instant) {
        let mut next = self.next.lock().unwrap();
        if next.is_none_or(|old| at < old) {
            *next = Some(at);
            self.changed.notify_one();
        }
    }

    pub(crate) fn wait(&self) {
        let mut next = self.next.lock().unwrap();
        loop {
            let Some(at) = *next else {
                next = self.changed.wait(next).unwrap();
                continue;
            };
            let remaining = at.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                *next = None;
                return;
            }
            next = self.changed.wait_timeout(next, remaining).unwrap().0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repeated_volume_actions_accumulate_before_backend_catches_up() {
        let start = Instant::now();
        let original = AudioLevel {
            volume: 94,
            muted: true,
        };
        let mut pending = Pending(None);
        let first = AudioAction::Adjust(LEVEL_STEP).apply(pending.value(original, start));
        pending.set(first, start);
        let next = AudioAction::Adjust(LEVEL_STEP).apply(pending.value(original, start));
        assert_eq!(first.volume, 99);
        assert_eq!(next.volume, 100);
        assert!(!next.muted);
        assert!(AudioAction::Toggle.apply(next).muted);
        assert!(pending.value(original, start + CONTROL_SETTLE_TIME) == original);
    }
}
