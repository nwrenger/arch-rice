use std::ops::Range;

use amane::{
    Align, Apps, Color, Column, Cursor, DesktopApp, Image, Key, Keyboard, Layer, LayerWindow,
    Monitor, Rectangle, Row, Service, Size::Parent, Text, Widget, WindowSize, Workspaces, Zone,
    children,
};

use crate::{
    theme,
    utils::{
        self, execute_about, execute_floating, execute_install, execute_remove, logout, reboot,
        shutdown, suspend,
    },
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum State {
    Hidden,
    Root,
    Power,
    Apps,
    Install,
    Remove,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum SourceType {
    Official,
    AUR,
    Flatpak,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum PackageType {
    System,
    Flatpak,
}

fn apps_viewport_height(panel_height: f32) -> f32 {
    (panel_height - theme::PADDING_MD * 2. - theme::MENU_ITEM_HEIGHT - theme::GAB).max(0.)
}

fn visible_app_rows(panel_height: f32) -> usize {
    ((apps_viewport_height(panel_height) + theme::PADDING_SM)
        / (theme::MENU_DETAL_HEIGHT + theme::PADDING_SM)) as usize
}

fn search<T>(
    entries: impl IntoIterator<Item = T>,
    query: &str,
    title: impl Fn(&T) -> &str,
) -> Vec<T> {
    let query = query.trim().to_lowercase();
    if query.is_empty() {
        return entries.into_iter().collect();
    }

    let mut prefixes = Vec::new();
    let mut substrings = Vec::new();
    for entry in entries {
        let title = title(&entry).to_lowercase();
        if title.starts_with(&query) {
            prefixes.push(entry);
        } else if title.contains(&query) {
            substrings.push(entry);
        }
    }
    prefixes.extend(substrings);
    prefixes
}

pub struct Launcher {
    state: State,
    query: String,
    entries: Vec<Entry>,
    height: f32,
    selected: usize,
    first_visible_row: usize,
    scroll_remainder: f32,
}

impl Launcher {
    fn set_state(&mut self, state: State) {
        self.state = state;
        self.query.clear();
        self.entries = self.to_entries();
        let length = self.entries.len();
        if state == State::Apps {
            self.height = theme::MAX_HEIGHT;
        } else {
            self.height = theme::MENU_ITEM_HEIGHT * (length + 1) as f32
                + theme::GAB * length as f32
                + theme::PADDING_MD * 2.;
        }
        self.reset_scroll();
        if state == State::Apps {
            self.selected = 0;
        } else {
            self.bound_selected();
        }
    }

    fn add_char(&mut self, c: char) {
        self.query.push(c);
        self.apply_filter();
    }

    fn clear(&mut self) {
        if !self.query.is_empty() {
            self.query.clear();
            self.apply_filter();
        }
    }

    fn reset_scroll(&mut self) {
        self.first_visible_row = 0;
        self.scroll_remainder = 0.;
    }

    fn app_page(&self, count: usize) -> Range<usize> {
        let rows = visible_app_rows(self.height);
        let first = self.first_visible_row.min(count.saturating_sub(rows));
        first..(first + rows).min(count)
    }

    fn app_selection(&self, page: &Range<usize>) -> Option<usize> {
        if page.is_empty() {
            None
        } else {
            Some(self.selected.clamp(page.start, page.end - 1))
        }
    }

    fn app_results<'a>(&self, catalog: &'a Apps) -> Vec<&'a DesktopApp> {
        search(catalog.list(), &self.query, |app| app.name())
    }

    fn move_selection(&mut self, step: isize) {
        if self.state == State::Apps {
            let count = self.app_results(&Apps::read()).len();
            let page = self.app_page(count);
            if let Some(selected) = self.app_selection(&page) {
                self.first_visible_row = page.start;
                self.set_selected(selected.saturating_add_signed(step).min(count - 1));
            }
        } else if let Some(last) = self.entries.len().checked_sub(1) {
            self.set_selected(self.selected.saturating_add_signed(step).min(last));
        }
    }

    fn selected_entry(&self) -> Option<Entry> {
        if self.state != State::Apps {
            return self.entries.get(self.selected).cloned();
        }
        let apps = Apps::read();
        let matches = self.app_results(&apps);
        let selected = self.app_selection(&self.app_page(matches.len()))?;
        Some(Entry::App(matches[selected].clone()))
    }

    fn scroll_apps(&mut self, lines: f32, count: usize) {
        let rows = visible_app_rows(self.height);
        if self.state != State::Apps || rows == 0 || !lines.is_finite() {
            return;
        }
        let last_start = count.saturating_sub(rows);
        let delta = self.scroll_remainder + lines;
        let steps = delta as isize;
        self.first_visible_row = self
            .app_page(count)
            .start
            .saturating_add_signed(steps)
            .min(last_start);
        self.scroll_remainder = if (self.first_visible_row == 0 && delta < 0.)
            || (self.first_visible_row == last_start && delta > 0.)
        {
            0.
        } else {
            delta.fract()
        };
        self.selected = self.app_selection(&self.app_page(count)).unwrap_or(0);
    }

    fn set_selected(&mut self, selected: usize) {
        self.selected = selected;
        if self.state == State::Apps {
            let rows = visible_app_rows(self.height);
            if selected < self.first_visible_row {
                self.first_visible_row = selected;
            } else if rows > 0 && selected >= self.first_visible_row + rows {
                self.first_visible_row = selected + 1 - rows;
            }
        }
    }

    // Bound the select index to the current entries (if there are visible entries)
    fn bound_selected(&mut self) {
        if self.selected >= self.entries.len() && !self.entries.is_empty() {
            self.set_selected(self.entries.len() - 1);
        }
    }

    fn apply_filter(&mut self) {
        self.selected = 0;
        if self.state == State::Apps {
            self.reset_scroll();
        } else {
            self.entries = search(self.to_entries(), &self.query, Entry::to_title);
        }
    }

    fn previous(&mut self) {
        match self.state {
            State::Hidden => {}
            State::Root => self.set_state(State::Hidden),
            State::Power => self.set_state(State::Root),
            State::Apps => self.set_state(State::Hidden),
            State::Install => self.set_state(State::Root),
            State::Remove => self.set_state(State::Root),
        }
    }

    fn to_title(&self) -> String {
        match self.state {
            State::Hidden => String::new(),
            State::Root => String::from("System"),
            State::Power => String::from("Power"),
            State::Apps => String::from("Applications"),
            State::Install => String::from("Install"),
            State::Remove => String::from("Remove"),
        }
    }

    fn to_entries(&self) -> Vec<Entry> {
        match self.state {
            State::Hidden | State::Apps => vec![],
            State::Root => vec![
                Entry::About,
                Entry::Install(None),
                Entry::Update,
                Entry::Remove(None),
                Entry::Power(None),
            ],
            State::Power => vec![
                Entry::Power(Some(PowerEntry::Shutdown)),
                Entry::Power(Some(PowerEntry::Reboot)),
                Entry::Power(Some(PowerEntry::Logout)),
                Entry::Power(Some(PowerEntry::Suspend)),
            ],

            State::Install => vec![
                Entry::Install(Some(SourceType::Official)),
                Entry::Install(Some(SourceType::AUR)),
                Entry::Install(Some(SourceType::Flatpak)),
            ],
            State::Remove => vec![
                Entry::Remove(Some(PackageType::System)),
                Entry::Remove(Some(PackageType::Flatpak)),
            ],
        }
    }
}

impl Service for Launcher {
    fn new() -> Self {
        Self {
            state: State::Hidden,
            query: String::new(),
            entries: vec![],
            height: 0.,
            selected: 0,
            first_visible_row: 0,
            scroll_remainder: 0.,
        }
    }

    fn listen() {}
}

#[derive(Debug, Clone, PartialEq)]
enum Entry {
    About,
    Install(Option<SourceType>),
    Update,
    Remove(Option<PackageType>),
    Power(Option<PowerEntry>),
    App(DesktopApp),
}

#[derive(Debug, Clone, PartialEq)]
enum PowerEntry {
    Shutdown,
    Reboot,
    Logout,
    Suspend,
}

impl Entry {
    fn to_title(&self) -> &str {
        match self {
            Self::About => "About",
            Self::Install(source) => match source {
                Some(SourceType::Official) => "Official",
                Some(SourceType::AUR) => "AUR",
                Some(SourceType::Flatpak) => "Flatpak",
                None => "Install",
            },
            Self::Update => "Update",
            Self::Remove(package) => match package {
                Some(PackageType::System) => "System",
                Some(PackageType::Flatpak) => "Flatpak",
                None => "Remove",
            },
            Self::Power(power) => match power {
                Some(PowerEntry::Shutdown) => "Shutdown",
                Some(PowerEntry::Reboot) => "Reboot",
                Some(PowerEntry::Logout) => "Logout",
                Some(PowerEntry::Suspend) => "Suspend",
                None => "Power",
            },
            Self::App(desktop) => desktop.name(),
        }
    }

    fn to_icon(&self) -> &str {
        match self {
            Self::About => "󰋼",
            Self::Install(source) => match source {
                Some(SourceType::Official) => "󰣇",
                Some(SourceType::AUR) => "󰣇",
                Some(SourceType::Flatpak) => "",
                None => "󰏗",
            },
            Self::Update => "󰚰",
            Self::Remove(package) => match package {
                Some(PackageType::System) => "󰣇",
                Some(PackageType::Flatpak) => "",
                None => "󰆴",
            },
            Self::Power(power) => match power {
                Some(PowerEntry::Shutdown) => "󰐥",
                Some(PowerEntry::Reboot) => "󰜉",
                Some(PowerEntry::Logout) => "󰍃",
                Some(PowerEntry::Suspend) => "󰤄",
                None => "󰐥",
            },
            Self::App(_) => "󰏗",
        }
    }

    fn execute(&self, launcher: &mut Launcher) {
        match self {
            Self::About => {
                launcher.set_state(State::Hidden);
                execute_about();
            }
            Self::Install(source) => match source {
                Some(_) => {
                    launcher.set_state(State::Hidden);
                    execute_install(self.to_title());
                }
                None => launcher.set_state(State::Install),
            },
            Self::Update => {
                launcher.set_state(State::Hidden);
                execute_floating(utils::UPDATE);
            }
            Self::Remove(package) => match package {
                Some(_) => {
                    launcher.set_state(State::Hidden);
                    execute_remove(self.to_title());
                }
                None => launcher.set_state(State::Remove),
            },
            Self::Power(power) => match power {
                Some(PowerEntry::Shutdown) => {
                    launcher.set_state(State::Hidden);
                    shutdown();
                }
                Some(PowerEntry::Reboot) => {
                    launcher.set_state(State::Hidden);
                    reboot();
                }
                Some(PowerEntry::Logout) => {
                    launcher.set_state(State::Hidden);
                    logout();
                }
                Some(PowerEntry::Suspend) => {
                    launcher.set_state(State::Hidden);
                    suspend();
                }
                None => launcher.set_state(State::Power),
            },
            Self::App(desktop) => {
                launcher.set_state(State::Hidden);
                desktop.launch();
            }
        }
    }
}

pub fn root(monitor: &Monitor) -> LayerWindow {
    let state = Launcher::read().state;
    match state {
        State::Hidden => hidden(),
        State::Apps => overlay(monitor, apps()),
        _ => overlay(monitor, menu()),
    }
}

fn hidden() -> LayerWindow {
    LayerWindow::new()
        .width(WindowSize::Full)
        .height(WindowSize::Full)
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .keyboard(Keyboard::OnDemand)
        .visible(false)
}

fn overlay(monitor: &Monitor, child: impl Widget + 'static) -> LayerWindow {
    let workspaces = Workspaces::read();
    let focused_monitor = workspaces
        .list()
        .iter()
        .find(|ws| ws.focused())
        .and_then(|ws| ws.output());

    let visible = focused_monitor == Some(monitor.name.as_str());

    LayerWindow::new()
        .width(WindowSize::Full)
        .height(WindowSize::Full)
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .keyboard(Keyboard::OnDemand)
        .on_key(|k| {
            let mut launcher = Launcher::write();
            match k {
                Key::Up => launcher.move_selection(-1),
                Key::Down => launcher.move_selection(1),
                Key::Enter => {
                    if let Some(entry) = launcher.selected_entry() {
                        entry.execute(&mut launcher);
                    }
                }
                Key::Character(c) => launcher.add_char(c),
                Key::Backspace => launcher.clear(),
                Key::Escape => launcher.previous(),
                _ => {}
            }
        })
        .visible(visible)
        .child(
            // Transparent backdrop: clicking closes launcher
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .fill(Color::TRANSPARENT)
                .on_click(|_| Launcher::write().set_state(State::Hidden))
                .align_child(Align::Center, Align::Center)
                .child(
                    // Launcher content
                    child,
                ),
        )
}

fn menu() -> Rectangle {
    let (title, query, entries, height, selected_index) = {
        let launcher = Launcher::read();
        let entries = launcher.entries.clone();
        (
            launcher.to_title(),
            launcher.query.clone(),
            entries,
            launcher.height,
            launcher.selected,
        )
    };
    let mut columns = children!(search_bar(title, query));

    for (selected, entry) in entries.into_iter().enumerate() {
        columns.push(Box::new(
            Rectangle::new()
                .width(Parent)
                .height(theme::MENU_ITEM_HEIGHT)
                .padding(theme::PADDING_MD)
                .radius(theme::RADIUS)
                .fill(if selected_index == selected {
                    theme::SURFACE_0
                } else {
                    theme::BASE
                })
                .on_hover(move |o| {
                    if o {
                        Launcher::write().set_selected(selected);
                    }
                })
                .cursor(Cursor::Pointer)
                .align_child(Align::Start, Align::Center)
                .child(
                    Row::new(children!(
                        Text::new(entry.to_icon())
                            .font(theme::SYMBOLS_FONT_FAMILY)
                            .size(theme::BAR_FONT_XL_SIZE)
                            .color(Color::from(theme::TEXT)),
                        Text::new(entry.to_title())
                            .font(theme::FONT_FAMILY)
                            .size(theme::BAR_FONT_MD_SIZE)
                            .color(Color::from(theme::TEXT)),
                    ))
                    .gap(theme::PADDING_MD)
                    .align(Align::Center),
                )
                .on_click(move |_| entry.execute(&mut Launcher::write())),
        ));
    }

    if columns.len() == 1 {
        columns.push(Box::new(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .padding(theme::PADDING_MD)
                .radius(theme::RADIUS)
                .fill(theme::BASE)
                .align_child(Align::Center, Align::Center)
                .child(
                    Text::new("No results")
                        .font(theme::FONT_FAMILY)
                        .size(theme::BAR_FONT_MD_SIZE)
                        .color(Color::from(theme::OVERLAY)),
                ),
        ));
    }

    Rectangle::new()
        .width(theme::MENU_WIDTH)
        .height(height)
        .border(theme::BORDER_WIDTH, theme::MAUVE)
        .radius(theme::RADIUS)
        .fill(theme::BASE)
        .padding(theme::PADDING_MD)
        .on_click(|_| {})
        .child(Column::new(columns).gap(theme::GAB))
}

fn apps() -> Rectangle {
    let (title, query, entries, height, selected_index, empty_message) = {
        let launcher = Launcher::read();
        let catalog = Apps::read();
        let matches = launcher.app_results(&catalog);
        let page = launcher.app_page(matches.len());
        let entries: Vec<_> = page
            .clone()
            .map(|index| (index, Entry::App(matches[index].clone())))
            .collect();
        let empty_message = if catalog.list().is_empty() {
            "Waiting for apps…"
        } else {
            "No results"
        };
        (
            launcher.to_title(),
            launcher.query.clone(),
            entries,
            launcher.height,
            launcher.app_selection(&page),
            empty_message,
        )
    };

    let mut columns: Vec<Box<dyn Widget>> = Vec::new();

    for (selected, entry) in entries {
        if let Entry::App(app) = &entry {
            let icon = Rectangle::new()
                .width(theme::ICON_SIZE)
                .height(theme::ICON_SIZE);

            let icon = match app.icon_path() {
                Some(path) => icon.fill(Image::contain(path)),
                None => icon.align_child(Align::Center, Align::Center).child(
                    Text::new(entry.to_icon())
                        .size(theme::BAR_FONT_XXL_SIZE)
                        .font(theme::SYMBOLS_FONT_FAMILY)
                        .color(Color::from(theme::TEXT)),
                ),
            };

            let description = app.description().unwrap_or("");
            let truncated_description = if let Some((end, _)) = description.char_indices().nth(49) {
                format!("{}..", &description[..end])
            } else {
                description.to_string()
            };

            columns.push(Box::new(
                Rectangle::new()
                    .width(Parent)
                    .height(theme::MENU_DETAL_HEIGHT)
                    .padding(theme::PADDING_MD)
                    .radius(theme::RADIUS)
                    .fill(if selected_index == Some(selected) {
                        theme::SURFACE_0
                    } else {
                        theme::BASE
                    })
                    .cursor(Cursor::Pointer)
                    .align_child(Align::Start, Align::Center)
                    .on_hover(move |o| {
                        if o {
                            Launcher::write().set_selected(selected);
                        }
                    })
                    .child(
                        Row::new(children!(
                            icon,
                            Column::new(children!(
                                Text::new(entry.to_title())
                                    .font(theme::FONT_FAMILY)
                                    .size(theme::BAR_FONT_MD_SIZE)
                                    .color(Color::from(theme::TEXT)),
                                Text::new(truncated_description)
                                    .font(theme::FONT_FAMILY)
                                    .size(theme::BAR_FONT_SM_SIZE)
                                    .color(Color::from(theme::SUBTEXT)),
                            ))
                            .gap(theme::BORDER_WIDTH)
                        ))
                        .gap(theme::PADDING_MD)
                        .align(Align::Center),
                    )
                    .on_click(move |_| {
                        entry.execute(&mut Launcher::write());
                    }),
            ));
        }
    }

    if columns.is_empty() {
        columns.push(Box::new(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .align_child(Align::Center, Align::Center)
                .child(
                    Text::new(empty_message)
                        .font(theme::FONT_FAMILY)
                        .size(theme::BAR_FONT_MD_SIZE)
                        .color(Color::from(theme::OVERLAY)),
                ),
        ));
    }

    Rectangle::new()
        .width(theme::APPS_WIDTH)
        .height(height)
        .border(theme::BORDER_WIDTH, theme::MAUVE)
        .radius(theme::RADIUS)
        .fill(theme::BASE)
        .padding(theme::PADDING_MD)
        .on_click(|_| {})
        .child(
            Column::new(children!(
                search_bar(title, query),
                Rectangle::new()
                    .width(Parent)
                    .height(apps_viewport_height(height))
                    .align_child(Align::Start, Align::Start)
                    .on_scroll(|scroll| {
                        let mut launcher = Launcher::write();
                        let count = launcher.app_results(&Apps::read()).len();
                        launcher.scroll_apps(scroll.y, count);
                    })
                    .child(Column::new(columns).gap(theme::PADDING_SM))
            ))
            .gap(theme::GAB),
        )
}

pub fn toggle(args: &[String]) -> String {
    if args.len() != 1 {
        return String::from("invalid number of arguments");
    }

    let mut launcher = Launcher::write();

    let previous_state = launcher.state;
    let mut new_state = match args[0].as_str() {
        "root" => State::Root,
        "power" => State::Power,
        "apps" => State::Apps,
        _ => return String::from("invalid argument"),
    };

    if new_state == previous_state {
        new_state = State::Hidden;
    }

    launcher.set_state(new_state);

    String::from("ok")
}

pub fn open_root() {
    let mut launcher = Launcher::write();
    launcher.set_state(State::Root);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn search_ranks_prefixes_before_substrings_and_keeps_ties_in_order() {
        let names = [
            "XTerm",
            "Terminal",
            "Terminator",
            "Console",
            "Kitty Terminal",
        ];
        assert_eq!(
            search(names, " TeRM ", |name| name),
            ["Terminal", "Terminator", "XTerm", "Kitty Terminal"]
        );
        assert_eq!(search(names, " ", |name| name), names);
    }

    #[test]
    fn changing_a_menu_query_selects_the_top_ranked_action() {
        let mut launcher = Launcher::new();
        launcher.set_state(State::Root);
        launcher.set_selected(4);
        launcher.add_char('P');
        assert_eq!(launcher.entries, [Entry::Power(None), Entry::Update]);
        assert_eq!(launcher.selected_entry(), Some(Entry::Power(None)));
    }

    fn app_list() -> (Launcher, usize) {
        let rows = visible_app_rows(theme::MAX_HEIGHT);
        assert!(rows > 1);
        let mut launcher = Launcher::new();
        launcher.set_state(State::Apps);
        (launcher, rows)
    }

    #[test]
    fn apps_viewport_fits_eight_full_rows() {
        assert_eq!(visible_app_rows(theme::MAX_HEIGHT), 8);
    }

    #[test]
    fn app_scroll_accumulates_fractional_lines_and_clamps_at_the_ends() {
        let (mut launcher, rows) = app_list();

        let count = rows * 3;
        for _ in 0..3 {
            launcher.scroll_apps(0.25, count);
        }
        assert_eq!(launcher.first_visible_row, 0);
        launcher.scroll_apps(0.25, count);
        assert_eq!(launcher.first_visible_row, 1);
        assert_eq!(launcher.selected, 1);

        launcher.scroll_apps(100., count);
        assert_eq!(launcher.first_visible_row, 2 * rows);
        launcher.scroll_apps(-100., count);
        assert_eq!(launcher.first_visible_row, 0);
        assert_eq!(launcher.scroll_remainder, 0.);
    }

    #[test]
    fn app_page_handles_catalog_arriving_and_shrinking() {
        let (mut launcher, rows) = app_list();
        assert_eq!(launcher.app_selection(&launcher.app_page(0)), None);
        assert_eq!(launcher.app_page(rows * 3), 0..rows);
        assert_eq!(
            launcher.app_selection(&launcher.app_page(rows * 3)),
            Some(0)
        );

        launcher.scroll_apps(100., rows * 3);
        assert_eq!(launcher.app_page(2), 0..2);
        assert_eq!(launcher.app_selection(&launcher.app_page(2)), Some(1));

        launcher.add_char('x');
        assert_eq!(launcher.app_page(rows * 3), 0..rows);
        assert_eq!(
            launcher.app_selection(&launcher.app_page(rows * 3)),
            Some(0)
        );
    }

    #[test]
    fn app_scroll_follows_selection_and_resets_on_state_change() {
        let (mut launcher, rows) = app_list();
        launcher.set_selected(rows);
        assert_eq!(launcher.first_visible_row, 1);
        launcher.set_selected(0);
        assert_eq!(launcher.first_visible_row, 0);

        launcher.scroll_apps(1.5, rows * 3);
        launcher.set_state(State::Hidden);
        assert_eq!(launcher.first_visible_row, 0);
        assert_eq!(launcher.scroll_remainder, 0.);
    }
}

fn search_bar(placeholder: String, query: String) -> Rectangle {
    let empty = query.is_empty();
    Rectangle::new()
        .width(Parent)
        .height(theme::MENU_ITEM_HEIGHT)
        .radius(theme::RADIUS)
        .fill(theme::MANTLE)
        .padding(theme::GAB)
        .on_click(|_| {})
        .align_child(Align::Start, Align::Center)
        .child(
            Row::new(children!(
                Text::new("  ")
                    .font(theme::SYMBOLS_FONT_FAMILY)
                    .size(theme::BAR_FONT_LG_SIZE)
                    .color(Color::from(theme::SUBTEXT)),
                Text::new(if empty { placeholder } else { query })
                    .font(theme::FONT_FAMILY)
                    .color(Color::from(if empty {
                        theme::OVERLAY
                    } else {
                        theme::TEXT
                    }))
                    .size(theme::BAR_FONT_LG_SIZE)
            ))
            .gap(theme::GAB)
            .align(Align::Center),
        )
}
