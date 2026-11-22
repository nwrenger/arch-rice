mod actions;
mod backend;
mod item;
mod pixmap;
mod watcher;

use std::sync::{Arc, Weak};

use amane::{Image, Service};

use actions::{Action, Target};

#[derive(Default)]
pub(crate) struct Tray {
    items: Vec<TrayItem>,
}

impl Service for Tray {
    fn new() -> Self {
        Self::default()
    }

    fn listen() {
        backend::run(|items| {
            if !items.is_empty() || !Self::read().items.is_empty() {
                Self::write().items = items;
            }
        });
    }
}

impl Tray {
    pub(crate) fn list(&self) -> &[TrayItem] {
        &self.items
    }
}

#[derive(Clone)]
pub(crate) struct TrayItem(Arc<View>);

struct View {
    icon: Option<item::IconFile>,
    target: Weak<Target>,
}

impl TrayItem {
    fn new(icon: Option<item::IconFile>, target: &Arc<Target>) -> Self {
        Self(Arc::new(View {
            icon,
            target: Arc::downgrade(target),
        }))
    }

    fn same_view(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }

    pub(crate) fn icon_image(&self) -> Option<Image> {
        self.0.icon.as_ref().map(|icon| Image::contain(icon.path()))
    }

    pub(crate) fn activate(&self, x: i32, y: i32) {
        actions::submit(self.0.target.clone(), Action::Activate(x, y));
    }

    pub(crate) fn terminate(&self) {
        actions::submit(self.0.target.clone(), Action::Terminate);
    }
}
