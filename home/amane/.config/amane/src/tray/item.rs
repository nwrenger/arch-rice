use std::collections::HashMap;
use std::env;
use std::path::{Path, PathBuf};

use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::OwnedValue;

use super::pixmap::PixmapFile;

pub(super) const INTERFACES: [&str; 2] = [
    "org.kde.StatusNotifierItem",
    "org.freedesktop.StatusNotifierItem",
];

#[derive(PartialEq, Eq)]
pub(super) enum Icon {
    File(PathBuf),
    Pixels(u32, u32, Vec<u8>),
}

impl Icon {
    pub(super) fn file(&self) -> Option<IconFile> {
        match self {
            Self::File(path) => Some(IconFile::Theme(path.clone())),
            Self::Pixels(w, h, rgba) => match PixmapFile::new(*w, *h, rgba) {
                Ok(file) => Some(IconFile::Pixmap(file)),
                Err(error) => {
                    eprintln!("tray: could not cache pixmap: {error}");
                    None
                }
            },
        }
    }
}

pub(super) enum IconFile {
    Theme(PathBuf),
    Pixmap(PixmapFile),
}

impl IconFile {
    pub(super) fn path(&self) -> &Path {
        match self {
            Self::Theme(path) => path,
            Self::Pixmap(file) => &file.path,
        }
    }
}

pub(super) struct Item {
    pub interface: &'static str,
    pub visible: bool,
    pub icon: Option<Icon>,
}

type Properties = HashMap<String, OwnedValue>;
type Pixmap = (i32, i32, Vec<u8>);

pub(super) fn read(connection: &Connection, owner: &str, path: &str) -> Option<Item> {
    let proxy = Proxy::new(connection, owner, path, "org.freedesktop.DBus.Properties").ok()?;
    for interface in INTERFACES {
        let Ok(mut props) = proxy.call::<_, _, Properties>("GetAll", &(interface,)) else {
            continue;
        };
        if props.is_empty() {
            continue;
        }
        let status = text(&props, "Status");
        let visible = status != "Passive";
        let attention = status == "NeedsAttention";
        let icon = if visible {
            (if attention {
                source(&mut props, "AttentionIcon")
            } else {
                None
            })
            .or_else(|| source(&mut props, "Icon"))
        } else {
            None
        };
        return Some(Item {
            interface,
            visible,
            icon,
        });
    }
    None
}

fn text<'a>(props: &'a Properties, key: &str) -> &'a str {
    props
        .get(key)
        .and_then(|v| <&str>::try_from(v).ok())
        .unwrap_or("")
}

fn source(props: &mut Properties, prefix: &str) -> Option<Icon> {
    let name = text(props, &format!("{prefix}Name"));
    let custom = text(props, "IconThemePath");
    if let Some(path) = icon_file(name, custom) {
        return Some(Icon::File(path));
    }
    let pixmaps = Vec::<Pixmap>::try_from(props.remove(&format!("{prefix}Pixmap"))?).ok()?;
    pixmap(pixmaps)
}

fn pixmap(pixmaps: Vec<Pixmap>) -> Option<Icon> {
    let (width, height, mut bytes) = pixmaps
        .into_iter()
        .filter(|(w, h, bytes)| {
            (1..=512).contains(w) && (1..=512).contains(h) && bytes.len() == (*w * *h * 4) as usize
        })
        .min_by_key(|(w, h, _)| {
            // Aim for two physical pixels per logical pixel without picking huge pixmaps.
            let size = (*w).max(*h);
            ((size - 32).abs(), size < 32)
        })?;
    for pixel in bytes.chunks_exact_mut(4) {
        pixel.rotate_left(1); // SNI sends A,R,G,B in network byte order; Amane wants R,G,B,A.
    }
    Some(Icon::Pixels(width as u32, height as u32, bytes))
}

fn icon_file(name: &str, custom: &str) -> Option<PathBuf> {
    let path = Path::new(name);
    if path.is_absolute() {
        return supported(path).then(|| path.to_owned());
    }
    if name.is_empty() || name == "." || name == ".." || name.contains('/') {
        return None;
    }
    let find = |dir: &Path| {
        let exact = dir.join(name);
        if supported(&exact) {
            return Some(exact);
        }
        ["svg", "png"]
            .into_iter()
            .map(|ext| dir.join(format!("{name}.{ext}")))
            .find(|candidate| supported(candidate))
    };
    let home = env::var_os("HOME").map(PathBuf::from);
    let data_home = env::var_os("XDG_DATA_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| home.as_ref().map(|p| p.join(".local/share")));
    let data_dirs = env::var_os("XDG_DATA_DIRS")
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".into());
    let roots: Vec<_> = data_home
        .into_iter()
        .chain(env::split_paths(&data_dirs))
        .collect();
    let custom = Path::new(custom);
    let folders = [
        "scalable", "32x32", "24x24", "22x22", "16x16", "48x48", "symbolic",
    ];
    let in_theme = |dir: &Path| {
        if !dir.is_dir() {
            return None;
        }
        find(dir).or_else(|| {
            folders.iter().find_map(|size| {
                let base = dir.join(size);
                ["apps", "status", "actions", "devices", "panel", ""]
                    .iter()
                    .find_map(|category| find(&base.join(category)))
            })
        })
    };
    if custom.is_absolute() {
        if let Some(found) = in_theme(custom).or_else(|| in_theme(&custom.join("hicolor"))) {
            return Some(found);
        }
    }
    let theme = env::var("XDG_ICON_THEME")
        .ok()
        .filter(|s| !s.is_empty() && !s.contains('/') && s != "." && s != "..");
    let icon_roots: Vec<_> = home
        .into_iter()
        .map(|p| p.join(".icons"))
        .chain(roots.iter().map(|p| p.join("icons")))
        .collect();
    theme
        .as_deref()
        .into_iter()
        .chain(["hicolor", "Adwaita", "Papirus"])
        .find_map(|theme| {
            icon_roots
                .iter()
                .find_map(|root| in_theme(&root.join(theme)))
        })
        .or_else(|| icon_roots.iter().find_map(|root| find(root)))
        .or_else(|| roots.iter().find_map(|root| find(&root.join("pixmaps"))))
}

fn supported(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|ext| ext.to_str()),
        Some("png" | "svg")
    ) && path.is_file()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_argb_and_rejects_invalid_sizes() {
        let icon = pixmap(vec![(32, 32, vec![0; 4]), (1, 1, vec![128, 12, 34, 56])]);
        let Some(Icon::Pixels(w, h, pixels)) = icon else {
            panic!("no pixmap")
        };
        assert_eq!((w, h, pixels), (1, 1, vec![12, 34, 56, 128]));
        assert!(pixmap(vec![(0, 1, vec![]), (i32::MAX, 1, vec![])]).is_none());
    }
}
