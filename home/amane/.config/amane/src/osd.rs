use std::borrow::Cow;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use amane::{
    Align, Animation, Color, Column, Horizontal, Keyboard, Layer, LayerWindow, Margin, Media,
    MediaPlayer, Monitor, Padding, Rectangle, Row, Service, Size, Text, Vertical, Widget, Zone,
};

use crate::{
    theme,
    utils::{WakeTimer, focused_output},
};

const DURATION: Duration = Duration::from_millis(1_800);
const ANIMATION: Duration = Duration::from_millis(120);

static TIMER: WakeTimer = WakeTimer::new();
static LAST_MEDIA_TOGGLE: Mutex<Option<MediaToggle>> = Mutex::new(None);

struct MediaToggle {
    player: String,
    playing: bool,
    until: Instant,
}

fn next_media_toggle(
    last: &mut Option<MediaToggle>,
    player: &str,
    reported_playing: bool,
    now: Instant,
) -> bool {
    // Keep flipping the requested state while Amane's cached value may still be stale.
    let playing = !last
        .as_ref()
        .filter(|request| request.player == player && now < request.until)
        .map_or(reported_playing, |request| request.playing);
    *last = Some(MediaToggle {
        player: player.to_owned(),
        playing,
        until: now + Media::interval() + Duration::from_millis(200),
    });
    playing
}

enum PopupMessage {
    Text(String),
    TrackAfterSkip(MediaPlayer),
}

impl PopupMessage {
    fn text(&self) -> Option<Cow<'_, str>> {
        match self {
            Self::Text(text) => Some(Cow::Borrowed(text)),
            Self::TrackAfterSkip(before) => {
                // Reading Media in the view redraws this popup on the existing media poll.
                let media = Media::read();
                let title = media
                    .players()
                    .iter()
                    .find(|player| player.name() == before.name())
                    .filter(|player| {
                        (player.title(), player.artist()) != (before.title(), before.artist())
                            || before.position().saturating_sub(player.position())
                                > Duration::from_secs(1)
                    })
                    .map(MediaPlayer::title)
                    .filter(|title| !title.is_empty());
                title.map(|title| Cow::Owned(title.to_owned()))
            }
        }
    }
}

struct Popup {
    icon: String,
    message: PopupMessage,
    progress: bool,
    target: Option<String>,
    until: Instant,
}

struct Osd {
    popup: Option<Popup>,

    progress: Animation<f32>,
}

impl Service for Osd {
    fn new() -> Self {
        Self {
            popup: None,

            progress: Animation::new(0.).duration(ANIMATION),
        }
    }

    fn listen() {
        loop {
            TIMER.wait();
            let until = Self::read().popup.as_ref().map(|popup| popup.until);
            if let Some(until) = until {
                if until > Instant::now() {
                    TIMER.schedule(until);
                } else {
                    let mut state = Self::write();
                    if state
                        .popup
                        .as_ref()
                        .is_some_and(|popup| popup.until <= Instant::now())
                    {
                        state.popup = None;
                    }
                }
            }
        }
    }
}

pub(crate) fn show(icon: impl Into<String>, message: String, progress: Option<f32>) {
    show_popup(icon, PopupMessage::Text(message), progress);
}

fn show_popup(icon: impl Into<String>, message: PopupMessage, progress: Option<f32>) {
    let target = focused_output();
    let until = Instant::now() + DURATION;
    let progress = progress
        .filter(|value| value.is_finite())
        .map(|value| value.clamp(0., 1.));
    {
        let mut state = Osd::write();
        if let Some(value) = progress {
            if state
                .popup
                .as_ref()
                .is_some_and(|popup| popup.progress && popup.until > Instant::now())
            {
                state.progress.to(value);
            } else {
                state.progress = Animation::new(value).duration(ANIMATION);
            }
        }

        state.popup = Some(Popup {
            target,
            icon: icon.into(),
            message,
            progress: progress.is_some(),
            until,
        });
    }
    TIMER.schedule(until);
}

pub(crate) fn ipc(args: &[String]) -> String {
    match args {
        [icon, message] => show(icon, message.clone(), None),
        [icon, message, percent] => {
            let Ok(percent) = percent.parse::<f32>() else {
                return "percentage must be 0–100".into();
            };
            if !(0. ..=100.).contains(&percent) {
                return "percentage must be 0–100".into();
            }
            show(icon, message.clone(), Some(percent / 100.));
        }
        _ => return "usage: showOsd <icon> <message> [percent]".into(),
    }
    "ok".into()
}

pub(crate) fn media_ipc(args: &[String]) -> String {
    const USAGE: &str = "usage: media previous | toggle | next";
    let [action] = args else { return USAGE.into() };
    let Some(player) = Media::read().active().cloned() else {
        return "no media player".into();
    };
    let (icon, message) = match action.as_str() {
        "previous" => {
            player.previous();
            ("󰒮", PopupMessage::TrackAfterSkip(player))
        }
        "toggle" => {
            let mut last = LAST_MEDIA_TOGGLE
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let playing =
                next_media_toggle(&mut last, player.name(), player.playing(), Instant::now());
            player.play_pause();
            let icon = if playing { "󰐊" } else { "󰏤" };
            (icon, PopupMessage::Text(player.title().to_owned()))
        }
        "next" => {
            player.next();
            ("󰒭", PopupMessage::TrackAfterSkip(player))
        }
        _ => return USAGE.into(),
    };
    show_popup(icon, message, None);
    "ok".into()
}

pub(crate) fn root(monitor: &Monitor) -> LayerWindow {
    let state = Osd::read();
    let popup = state.popup.as_ref().filter(|popup| {
        popup.until > Instant::now()
            && popup
                .target
                .as_ref()
                .is_none_or(|target| target == &monitor.name)
    });
    let panel = popup.map(|popup| {
        let message = popup.message.text();
        let (text, color) = match message.as_deref() {
            Some(text) => (text, theme::TEXT),
            None => ("Loading...", theme::OVERLAY),
        };
        card(
            &popup.icon,
            text,
            Color::from(color),
            popup.progress.then(|| state.progress.value()),
        )
    });
    let visible = panel.is_some();
    let (width, card) = panel.unwrap_or_else(|| {
        (
            theme::OSD_WIDTH,
            Rectangle::new().width(Size::Parent).height(Size::Parent),
        )
    });

    LayerWindow::new()
        .width(width)
        .height(theme::OSD_HEIGHT)
        .anchor_vertical(Vertical::Bottom)
        .anchor_horizontal(Horizontal::Middle)
        .margin(Margin {
            bottom: theme::OSD_BOTTOM,
            ..Margin::default()
        })
        .namespace("amane-osd")
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .keyboard(Keyboard::None)
        .input_region(Vec::new())
        .visible(visible)
        .child(card)
}

fn message_text(message: &str) -> Text {
    Text::new(message)
        .font(theme::FONT_FAMILY)
        .size(theme::OSD_FONT_SIZE)
        .color(Color::from(theme::TEXT))
}

fn message_width(message: &str) -> f32 {
    let Size::Fixed(width) = message_text(message).width() else {
        unreachable!("unwrapped text has a fixed width")
    };
    width
}

fn fit_message(message: &str, width: f32) -> Cow<'_, str> {
    const SUFFIX: &str = "..";
    if message_width(message) <= width {
        return Cow::Borrowed(message);
    }

    let room = width - message_width(SUFFIX);
    if room < 0. {
        return Cow::Borrowed("");
    }
    let end = message
        .char_indices()
        .skip(1)
        .map(|(index, _)| index)
        .take_while(|&index| message_width(&message[..index]) <= room)
        .last()
        .unwrap_or(0);
    Cow::Owned(format!("{}{SUFFIX}", message[..end].trim_end()))
}

fn card(icon: &str, message: &str, color: Color, progress: Option<f32>) -> (f32, Rectangle) {
    let icon_padding = theme::GAB;
    let icon_width = if icon.is_empty() {
        0.
    } else {
        theme::OSD_ICON_SIZE + icon_padding * 2.
    };
    let text_left = if icon.is_empty() {
        theme::POPUP_PADDING
    } else {
        0.
    };
    let card_padding = Padding {
        left: theme::PADDING_MD,
        ..Padding::default()
    };
    let fixed_width = card_padding.left * 1.5 + icon_width + text_left + theme::POPUP_PADDING;
    let mut text_width = message_width(message);
    if progress.is_some() {
        text_width = text_width.max(theme::OSD_TRACK_WIDTH);
    }
    let width = (fixed_width + text_width)
        .ceil()
        .clamp(theme::OSD_WIDTH, theme::OSD_MAX_WIDTH);
    let message = fit_message(message, (width - fixed_width).max(0.));

    let mut row: Vec<Box<dyn Widget>> = Vec::new();
    if !icon.is_empty() {
        row.push(Box::new(
            Rectangle::new()
                .width(icon_width)
                .height(Size::Parent)
                .padding(icon_padding)
                .align_child(Align::Start, Align::Center)
                .child(
                    Text::new(icon)
                        .font(theme::SYMBOLS_FONT_FAMILY)
                        .size(theme::OSD_ICON_SIZE)
                        .color(Color::from(theme::MAUVE))
                        .elide(),
                ),
        ));
    }

    let mut content: Vec<Box<dyn Widget>> = Vec::new();
    if !message.is_empty() {
        content.push(Box::new(message_text(&message).color(color)));
    }
    if let Some(value) = progress {
        let radius = theme::OSD_TRACK_HEIGHT / 2.;
        let track = Rectangle::new()
            .width(theme::OSD_TRACK_WIDTH)
            .height(theme::OSD_TRACK_HEIGHT)
            .radius(radius)
            .fill(theme::SURFACE_1)
            .align_child(Align::Start, Align::Center);
        let track = if value > 0. {
            track.child(
                Rectangle::new()
                    .width(theme::OSD_TRACK_WIDTH * value)
                    .height(theme::OSD_TRACK_HEIGHT)
                    .radius(radius)
                    .fill(theme::MAUVE),
            )
        } else {
            track
        };
        content.push(Box::new(track));
    }
    row.push(Box::new(
        Rectangle::new()
            .width(Size::Parent)
            .height(Size::Parent)
            .padding(Padding {
                left: text_left,
                right: theme::POPUP_PADDING,
                ..Padding::default()
            })
            .align_child(Align::Start, Align::Center)
            .child(
                Column::new(content)
                    .width(Size::Parent)
                    .gap(theme::OSD_TRACK_HEIGHT),
            ),
    ));

    (
        width,
        Rectangle::new()
            .width(Size::Parent)
            .height(Size::Parent)
            .fill(theme::OSD_BASE)
            .border(theme::BORDER_WIDTH, theme::MAUVE)
            .radius(theme::RADIUS)
            .padding(card_padding)
            .clip()
            .child(
                Row::new(row)
                    .width(Size::Parent)
                    .height(Size::Parent)
                    .align(Align::Center),
            ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn media_toggles_alternate_even_when_the_reported_state_is_stale() {
        let now = Instant::now();
        let mut last = None;
        assert!(!next_media_toggle(&mut last, "player", true, now));
        assert!(next_media_toggle(&mut last, "player", true, now));
        assert!(!next_media_toggle(&mut last, "player", true, now));

        let expired = last.as_ref().unwrap().until;
        assert!(!next_media_toggle(&mut last, "player", true, expired));
        assert!(!next_media_toggle(&mut last, "other", true, expired));
    }

    #[test]
    fn fits_osd_labels_with_two_dots_and_keeps_utf8_intact() {
        let width = message_width("écl..") + 0.01;
        assert_eq!(fit_message("éclair", width), "écl..");
        assert_eq!(fit_message("écl", width), "écl");
        assert_eq!(fit_message("éclair", 0.), "");
    }
}
