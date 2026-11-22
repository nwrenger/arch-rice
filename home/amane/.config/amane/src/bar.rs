mod center;
mod left;
mod right;

use crate::theme;
use amane::{
    Full, Layer, LayerWindow, Monitor, Rectangle, Row, Size::Parent, Vertical, Zone, children,
};

pub fn root(_monitor: &Monitor) -> LayerWindow {
    LayerWindow::new()
        .width(Full)
        .height(theme::BAR_HEIGHT)
        .anchor_vertical(Vertical::Top)
        .layer(Layer::Top)
        .space(Zone::Reserve)
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .fill(theme::BASE)
                .child(Row::new(children!(
                    left::root(),
                    center::root(),
                    right::root()
                ))),
        )
}
