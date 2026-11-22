use amane::{
    Align, Color, Cursor, Rectangle, Row, Service, Size::Parent, Text, Widget, Workspace,
    Workspaces, children,
};

use crate::{launcher, theme};

pub fn root() -> Rectangle {
    let workspaces = Workspaces::read();
    let available_workspaces: Vec<i64> = (1..=4).collect();

    let mut rows: Vec<Box<dyn Widget>> = children!(home_button());

    for id in available_workspaces {
        let workspace = workspaces.list().iter().find(|ws| ws.id() == id);
        rows.push(Box::new(workspace_select_button(id, workspace)));
    }

    Rectangle::new()
        .width(Parent)
        .height(Parent)
        .align_child(Align::Start, Align::Center)
        .child(Row::new(rows))
}

fn home_button() -> Rectangle {
    Rectangle::new()
        .width(theme::BAR_HEIGHT)
        .height(theme::BAR_HEIGHT)
        .cursor(Cursor::Pointer)
        .on_click(|_| launcher::open_root())
        .align_child(Align::Center, Align::Center)
        .child(
            Text::new("󰗀")
                .font(theme::SYMBOLS_FONT_FAMILY)
                .size(theme::BAR_FONT_SIZE)
                .color(Color::from(theme::TEXT)),
        )
}

fn workspace_select_button(id: i64, workspace: Option<&Workspace>) -> Rectangle {
    let filled = workspace.is_some();
    let focused = workspace.map_or(false, |ws| ws.focused());

    Rectangle::new()
        .width(theme::BAR_HEIGHT)
        .height(theme::BAR_HEIGHT)
        .cursor(Cursor::Pointer)
        .on_click(move |_| Workspaces::focus(id))
        .align_child(Align::Center, Align::Center)
        .child(
            Text::new(if focused {
                String::from("󱓻")
            } else {
                id.to_string()
            })
            .font(theme::SYMBOLS_FONT_FAMILY)
            .size(theme::BAR_FONT_SIZE)
            .color(Color::from(if !filled {
                theme::OVERLAY
            } else {
                theme::TEXT
            })),
        )
}
