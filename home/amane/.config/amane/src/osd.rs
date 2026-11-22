use std::time::{Duration, Instant};

use amane::{
    Align, Animation, Color, Column, Horizontal, Keyboard, Layer, LayerWindow, Margin, Monitor,
    Rectangle, Row, Service, Size, Text, Vertical, Widget, Zone, children,
};

use crate::{
    theme,
    utils::{WakeTimer, focused_output},
};

const DURATION: Duration = Duration::from_millis(1_800);
const ANIMATION: Duration = Duration::from_millis(120);
static TIMER: WakeTimer = WakeTimer::new();

struct Popup {
    icon: String,
    message: String,
    target: Option<String>,
    progress: bool,
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

pub(crate) fn root(monitor: &Monitor) -> LayerWindow {
    let state = Osd::read();
    let popup = state.popup.as_ref().filter(|popup| {
        popup.until > Instant::now()
            && popup
                .target
                .as_ref()
                .is_none_or(|target| target == &monitor.name)
    });
    let (width, card) = match popup {
        Some(popup) => card(popup, popup.progress.then(|| state.progress.value())),
        None => (
            theme::OSD_WIDTH,
            Rectangle::new().width(Size::Parent).height(Size::Parent),
        ),
    };

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
        .visible(popup.is_some())
        .child(card)
}

fn card(popup: &Popup, progress: Option<f32>) -> (f32, Rectangle) {
    let label = Text::new(&popup.message)
        .font(theme::FONT_FAMILY)
        .size(theme::NOTIFICATION_TITLE_SIZE)
        .color(Color::from(theme::TEXT));
    let Size::Fixed(label_width) = label.width() else {
        unreachable!("unwrapped text has a fixed width")
    };
    let icon_width = if popup.icon.is_empty() {
        0.
    } else {
        theme::OSD_ICON_SIZE + theme::POPUP_PADDING
    };
    let desired_text_width = if progress.is_some() {
        label_width.max(theme::OSD_TRACK_WIDTH)
    } else {
        label_width
    };
    let width = (desired_text_width + icon_width + theme::PADDING_MD * 2.)
        .clamp(theme::OSD_WIDTH, theme::OSD_MAX_WIDTH);
    let text_width = desired_text_width.min(width - icon_width - theme::PADDING_MD * 2.);

    let mut contents = children!(label.elide());
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
        contents.push(Box::new(track));
    }
    let mut row: Vec<Box<dyn Widget>> = Vec::new();
    if !popup.icon.is_empty() {
        row.push(Box::new(
            Rectangle::new()
                .width(theme::OSD_ICON_SIZE)
                .height(theme::OSD_ICON_SIZE + theme::PADDING_SM)
                .align_child(Align::Center, Align::Center)
                .child(
                    Text::new(&popup.icon)
                        .font(theme::SYMBOLS_FONT_FAMILY)
                        .size(theme::OSD_ICON_SIZE)
                        .color(Color::from(theme::MAUVE))
                        .tight(),
                ),
        ));
    }
    row.push(Box::new(
        Column::new(contents)
            .width(text_width)
            .gap(theme::OSD_TRACK_HEIGHT),
    ));
    (
        width,
        Rectangle::new()
            .width(Size::Parent)
            .height(Size::Parent)
            .fill(theme::OSD_BASE)
            .border(theme::BORDER_WIDTH, theme::MAUVE)
            .radius(theme::RADIUS)
            .align_child(Align::Center, Align::Center)
            .child(Row::new(row).gap(theme::POPUP_PADDING).align(Align::Center)),
    )
}
