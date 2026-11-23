# arch-rice

Arch Linux + Hyprland with the Amane desktop shell, themed in Catppuccin Mocha / Mauve.

Amane provides the bar, system tray, launcher, system and power menus, notifications, and OSD. Wallpaper transitions use `awww`, and authentication prompts use `hyprpolkitagent`.

## Fresh install

Install Arch via `archinstall`. Select: `btrfs`, `hyprland`, `limine`, `sddm`. Install Fish beforehand:

```bash
sudo pacman -Syu fish
```

Then run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/nwrenger/arch-rice/main/install.fish | fish
```

The installer will:

- Detect GPU/CPU and skip irrelevant packages
- Install paru
- Install all packages from `packages-pacman.txt`, `packages-aur.txt`, and `packages-flatpak.txt`
- Copy all home dotfiles directly into `$HOME`
- Copy system configs
- Install the Amane CLI with Cargo and compile the desktop shell before enabling `shell.service`
- Enable the desktop user services, including `awww`, `hyprpolkitagent`, and OpenTabletDriver
- Set up NetworkManager and systemd-resolved for the next boot
- Clean up (`~/.dotfiles` removed after install)
- Give instructions for the next manual steps

## Manual post-install steps

1. **Default Shell**: Set the default shell via

```bash
chsh -s /bin/fish
```

2. **Mullvad**: `mullvad account login`

3. **Limine**: A template with your options is staged at `~/.config/limine.conf.template`.
   Copy the options and config into `/boot/limine.conf`, rename the OS to `Arch Linux` and set the kernel to `Linux`.
   Then set `ESP_PATH=/boot` in `/etc/default/limine` and run:

```bash
   sudo limine-enroll-config
```

4. **Snapper (Optional)**: If subvolume layout differs, run `sudo snapper -c root create-config /`

5. **Reboot** to start the configured network services, then log in to Hyprland.

## Networking

NetworkManager manages Ethernet and Wi-Fi. It activates iwd on demand as its Wi-Fi backend and passes DNS information to systemd-resolved. The installer enables NetworkManager and systemd-resolved at boot, points `/etc/resolv.conf` at the resolved stub, and disables standalone startup of iwd and systemd-networkd. Use `wlctl` to manage Wi-Fi.

## Repo layout

```
arch-rice/
├── install.fish          ← run this on a fresh Arch install
├── export.fish           ← snapshot live system into this layout
├── packages-pacman.txt   ← pacman packages, tagged by hardware
├── packages-aur.txt      ← AUR packages, tagged by hardware
├── packages-flatpak.txt  ← Flatpak application IDs installed from Flathub
│
├── home/                 ← copied directly into $HOME
│   ├── hypr/             → .config/hypr/
│   ├── amane/            → .config/amane/ (Rust shell source)
│   ├── alacritty/        → .config/alacritty/
│   ├── fish/             → .config/fish/
│   ├── starship/         → .config/starship.toml
│   ├── kvantum/          → .config/Kvantum/
│   ├── qt/               → .config/qt5ct/ + .config/qt6ct/
│   ├── gtk/              → .config/gtk-3.0/ + .config/gtk-4.0/
│   ├── fontconfig/       → .config/fontconfig/
│   ├── fastfetch/        → .config/fastfetch/
│   ├── btop/             → .config/btop/
│   ├── zed/              → .config/zed/
│   ├── nwg-look/         → .config/nwg-look/
│   ├── uwsm/             → .config/uwsm/
│   ├── systemd/          → .config/systemd/user/ (user services)
│   ├── local-bin/        → .local/bin/ (custom scripts)
│   └── wallpaper/        → Pictures/wallpaper/
│
└── system/               ← system configs and installer assets
    ├── amane/
    │   └── config-dependencies.patch
    ├── etc/
    │   ├── NetworkManager/conf.d/10-network.conf
    │   ├── locale.conf
    │   ├── pacman.conf
    │   ├── snapper/configs/root
    │   ├── default/limine
    │   └── sddm.conf.d/theme.conf
    ├── boot/
    │   └── limine.conf.template  ← options only, no entries, no PARTUUID
    ├── sddm-scripts/
    │   └── Xsetup                ← xrandr monitor layout for SDDM (X11)
    └── sddm-theme/
        └── where_is_my_sddm_theme/
```

## Desktop controls

| Binding           | Action                        |
| ----------------- | ----------------------------- |
| `Super+Space`     | Application launcher          |
| `Super+Alt+Space` | System menu                   |
| `Super+Escape`    | Power menu                    |
| `Super+Shift+E`   | Wi-Fi manager (`wlctl`)       |
| `Super+Shift+V`   | Mullvad menu                  |
| `Super+Shift+W`   | Random wallpaper              |
| Volume keys       | Volume controls and Amane OSD |

`shell.service` runs `~/.cache/amane/amane-shell` in the graphical session. The `shell` command wraps Amane IPC. Try `shell launcher apps`, `shell launcher power`, or `shell volume mute`. Run `random-wallpaper` to change the wallpaper from a terminal.

After editing your installed shell source in `~/.config/amane/src/`, rebuild it and restart the user service from your graphical session.

```bash
env AMANE_CONFIG="$HOME/.config/amane" XDG_CACHE_HOME="$HOME/.cache" amane compile &&
    systemctl --user restart shell.service
```

## Hardware tags

| Tag         | Skipped when           |
| ----------- | ---------------------- |
| `nvidia`    | No NVIDIA GPU detected |
| `intel-cpu` | Not Intel CPU          |
| `amd-cpu`   | Not AMD CPU            |

## What's intentionally NOT exported

- `~/.local/share/keyrings/` — GNOME keyring secrets
- `~/.ssh/` — SSH keys
- `/etc/mullvad-vpn/` — VPN account/device credentials
- Snapper snapshot data in `/boot/` — auto-regenerated by limine-snapper-sync
