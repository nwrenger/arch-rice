use std::cell::RefCell;
use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime};

use amane::{
    Align, Apps, Button, Color, Column, Cursor, Horizontal, Image, InputArea, Keyboard, Layer,
    LayerWindow, Margin, Monitor, Notification, Notifications, Rectangle, Row, Service,
    Size::Parent, Text, Urgency, Vertical, Weight, Widget, Zone, children,
};

use crate::{
    theme,
    utils::{WakeTimer, focused_output},
};

const LIFETIME: Duration = Duration::from_secs(5);
const MAX_VISIBLE: usize = 6;
const MAX_ACTIONS: usize = 3;
const TEXT_GAP: f32 = 5.;
const ACTION_HEIGHT: f32 = 28.;
static TIMER: WakeTimer = WakeTimer::new();

struct Route {
    received: SystemTime,
    monitor: Option<String>,
}

thread_local! {
    // Views for every monitor share the first observed location of each notification.
    static ROUTES: RefCell<HashMap<u32, Route>> = RefCell::new(HashMap::new());
}

struct PopupClock;

impl Service for PopupClock {
    fn new() -> Self {
        Self
    }

    fn listen() {
        loop {
            TIMER.wait();
            drop(Self::write());
        }
    }
}

fn remaining(urgency: Urgency, received: SystemTime, now: SystemTime) -> Option<Duration> {
    (urgency != Urgency::Critical)
        .then(|| LIFETIME.saturating_sub(now.duration_since(received).unwrap_or_default()))
}

fn belongs_here(
    routes: &mut HashMap<u32, Route>,
    id: u32,
    received: SystemTime,
    focused: Option<&str>,
    monitor: &str,
) -> bool {
    let route = routes.entry(id).or_insert_with(|| Route {
        received,
        monitor: focused.map(str::to_owned),
    });
    if route.received != received {
        route.received = received;
        route.monitor = focused.map(str::to_owned);
    }
    // Workspaces may not report focus until shortly after startup.
    if route.monitor.is_none() {
        route.monitor = focused.map(str::to_owned);
    }
    route
        .monitor
        .as_deref()
        .is_none_or(|target| target == monitor)
}

fn visible_on(monitor: &Monitor) -> Vec<Notification> {
    let notifications = Notifications::read();
    if notifications.list().is_empty() {
        ROUTES.with_borrow_mut(HashMap::clear);
        return Vec::new();
    }
    let focused = focused_output();
    let now = SystemTime::now();
    let mut live = HashSet::new();
    let mut visible = Vec::new();
    ROUTES.with_borrow_mut(|routes| {
        for notification in notifications.list() {
            let left = remaining(notification.urgency(), notification.received(), now);
            if left == Some(Duration::ZERO) {
                continue;
            }
            live.insert(notification.id());
            if belongs_here(
                routes,
                notification.id(),
                notification.received(),
                focused.as_deref(),
                &monitor.name,
            ) {
                visible.push((notification, left));
            }
        }
        routes.retain(|id, _| live.contains(id));
    });

    visible.sort_by_key(|(notification, _)| Reverse(notification.received()));
    visible.truncate(MAX_VISIBLE);
    if let Some(next) = visible.iter().filter_map(|(_, left)| *left).min() {
        TIMER.schedule(Instant::now() + next);
    }
    visible
        .into_iter()
        .map(|(notification, _)| notification.clone())
        .collect()
}

pub(crate) fn clear(args: &[String]) -> String {
    if !args.is_empty() {
        return "usage: clearNotifications".into();
    }
    Notifications::clear();
    "ok".into()
}

pub(crate) fn root(monitor: &Monitor) -> LayerWindow {
    drop(PopupClock::read());
    let visible = visible_on(monitor);
    let mut cards: Vec<Box<dyn Widget>> = Vec::with_capacity(visible.len());
    let mut input = Vec::with_capacity(visible.len());
    let mut height = 0.;
    if !visible.is_empty() {
        let apps = Apps::read();
        for notification in &visible {
            if !cards.is_empty() {
                height += theme::PADDING_SM;
            }
            let (card, card_height) = card(notification, &apps);
            input.push(InputArea {
                x: 0,
                y: height.floor() as i32,
                width: theme::NOTIFICATION_WIDTH as i32,
                height: (height + card_height).ceil() as i32 - height.floor() as i32,
            });
            height += card_height;
            cards.push(Box::new(card));
        }
    }

    LayerWindow::new()
        .width(theme::NOTIFICATION_WIDTH)
        .height(height.ceil().max(1.))
        .anchor_horizontal(Horizontal::Right)
        .anchor_vertical(Vertical::Top)
        .margin(Margin {
            top: (theme::BAR_HEIGHT + theme::GAB) as i32,
            right: theme::GAB as i32,
            ..Margin::default()
        })
        .namespace("amane-notifications")
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .keyboard(Keyboard::None)
        .input_region(input)
        .visible(!cards.is_empty())
        .child(Column::new(cards).gap(theme::PADDING_SM))
}

fn card(notification: &Notification, apps: &Apps) -> (Rectangle, f32) {
    let summary = [
        notification.summary(),
        notification.app_name(),
        "Notification",
    ]
    .into_iter()
    .find(|text| !text.is_empty())
    .unwrap_or("Notification");
    let text_width = theme::NOTIFICATION_WIDTH
        - theme::NOTIFICATION_PADDING * 3.
        - theme::NOTIFICATION_ICON_SIZE;
    let title = Text::new(summary)
        .font(theme::FONT_FAMILY)
        .weight(Weight::Bold)
        .size(theme::NOTIFICATION_TITLE_SIZE)
        .color(Color::from(theme::TEXT))
        .elide();
    let mut text_height = title.height_in(text_width);
    let mut text = children!(title);
    if !notification.body().trim().is_empty() {
        let body = Text::new(plain_text(notification.body()))
            .font(theme::FONT_FAMILY)
            .size(theme::NOTIFICATION_BODY_SIZE)
            .color(Color::from(theme::SUBTEXT))
            .wrap()
            .max_lines(4)
            .elide();
        let body_height = body.height_in(text_width);
        text_height += TEXT_GAP + body_height;
        text.push(Box::new(
            Rectangle::new()
                .width(Parent)
                .height(body_height)
                .align_child(Align::Start, Align::Start)
                .child(body),
        ));
    }
    let icon = Rectangle::new()
        .width(theme::NOTIFICATION_ICON_SIZE)
        .height(theme::NOTIFICATION_ICON_SIZE);
    let icon = match icon_path(notification, apps) {
        Some(path) => icon.fill(Image::contain(path)),
        None => icon.fill(theme::SURFACE_1).radius(theme::RADIUS),
    };
    let mut contents = children!(
        Row::new(children!(
            icon,
            Column::new(text)
                .width(text_width)
                .height(text_height)
                .gap(TEXT_GAP)
        ))
        .gap(theme::NOTIFICATION_PADDING)
        .align(Align::Center)
    );
    let mut height =
        text_height.max(theme::NOTIFICATION_ICON_SIZE) + theme::NOTIFICATION_PADDING * 2.;
    let id = notification.id();
    if !notification.actions().is_empty() {
        let acts = notification
            .actions()
            .iter()
            .take(MAX_ACTIONS)
            .map(|action| {
                let key = action.key().to_owned();
                Box::new(
                    Rectangle::new()
                        .width(Parent)
                        .height(ACTION_HEIGHT)
                        .radius(theme::RADIUS)
                        .padding(4.)
                        .fill(theme::SURFACE_0)
                        .align_child(Align::Center, Align::Center)
                        .on_click(move |button| match button {
                            Button::Left => Notifications::invoke(id, &key),
                            Button::Right => Notifications::dismiss(id),
                            _ => {}
                        })
                        .child(
                            Text::new(action.label())
                                .font(theme::FONT_FAMILY)
                                .size(theme::NOTIFICATION_BODY_SIZE)
                                .color(Color::from(theme::TEXT))
                                .elide(),
                        ),
                ) as Box<dyn Widget>
            })
            .collect();
        contents.push(Box::new(
            Row::new(acts).width(Parent).gap(theme::PADDING_SM),
        ));
        height += ACTION_HEIGHT + theme::PADDING_SM;
    }
    let height = height.max(theme::NOTIFICATION_MIN_HEIGHT).ceil();
    let border = if notification.urgency() == Urgency::Critical {
        theme::RED
    } else {
        theme::MAUVE
    };
    (
        Rectangle::new()
            .width(Parent)
            .height(height)
            .padding(theme::NOTIFICATION_PADDING)
            .fill(theme::BASE)
            .border(theme::BORDER_WIDTH, border)
            .radius(theme::RADIUS)
            .cursor(Cursor::Pointer)
            .align_child(Align::Start, Align::Center)
            .on_click(move |button| match button {
                Button::Left => Notifications::click(id),
                Button::Right => Notifications::dismiss(id),
                _ => {}
            })
            .child(Column::new(contents).gap(theme::PADDING_SM)),
        height,
    )
}

fn icon_path(notification: &Notification, apps: &Apps) -> Option<PathBuf> {
    local_image(notification.image())
        .or_else(|| local_image(notification.icon()))
        .or_else(|| {
            apps.list()
                .iter()
                .filter(|app| {
                    app.icon() == Some(notification.icon())
                        || app.name().eq_ignore_ascii_case(notification.app_name())
                })
                .find_map(|app| app.icon_path().map(Path::to_owned))
        })
}

fn local_image(value: &str) -> Option<PathBuf> {
    let path = Path::new(value.strip_prefix("file://").unwrap_or(value));
    (path.is_absolute() && path.is_file()).then(|| path.to_owned())
}

fn plain_text(body: &str) -> String {
    let mut text = body.replace("<br>", "\n").replace("<br/>", "\n");
    for tag in ["<b>", "</b>", "<i>", "</i>", "<u>", "</u>"] {
        if text.contains(tag) {
            text = text.replace(tag, "");
        }
    }
    text.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normal_popups_expire_but_critical_popups_do_not() {
        let now = SystemTime::now();
        assert_eq!(remaining(Urgency::Normal, now, now), Some(LIFETIME));
        assert_eq!(
            remaining(Urgency::Normal, now, now + LIFETIME),
            Some(Duration::ZERO)
        );
        assert_eq!(remaining(Urgency::Critical, now, now + LIFETIME), None);
    }

    #[test]
    fn focus_changes_do_not_move_an_existing_popup() {
        let now = SystemTime::now();
        let mut routes = HashMap::new();
        assert!(belongs_here(&mut routes, 1, now, Some("DP-1"), "DP-1"));
        assert!(!belongs_here(&mut routes, 1, now, Some("DP-2"), "DP-2"));
        assert!(belongs_here(
            &mut routes,
            1,
            now + LIFETIME,
            Some("DP-2"),
            "DP-2"
        ));
    }
}
