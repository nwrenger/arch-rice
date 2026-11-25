# arch-rice

Arch Linux + Hyprland, themed in Catppuccin Mocha / Mauve.

Waybar provides the bar and system tray. Rofi handles app launching and runs Fish-powered system and power menus. Mako handles notifications, and awob shows on-screen feedback for audio and VPN changes. Wallpaper transitions use `awww`, and authentication prompts use `hyprpolkitagent`.

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
- Enable Waybar, awob, `awww`, `hyprpolkitagent`, and OpenTabletDriver for the graphical session
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
│   ├── waybar/           → .config/waybar/
│   ├── rofi/             → .config/rofi/
│   ├── mako/             → .config/mako/
│   ├── awob/             → .config/awob/ (settings and themes)
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
│   ├── systemd/          → .config/systemd/user/ (local units and awob drop-in)
│   ├── local-bin/        → .local/bin/ (custom scripts)
│   └── wallpaper/        → Pictures/wallpaper/
│
└── system/               ← system configs and installer assets
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

| Binding             | Action                                                     |
| ------------------- | ---------------------------------------------------------- |
| `Super+Space`       | Application launcher                                       |
| `Super+Alt+Space`   | System menu                                                |
| `Super+Escape`      | Power menu                                                 |
| `Super+Shift+E`     | Wi-Fi manager (`wlctl`)                                    |
| `Super+Shift+V`     | Mullvad menu                                               |
| `Super+Shift+W`     | Random wallpaper                                           |
| Volume keys         | WirePlumber volume controls with awob feedback             |
| Media playback keys | Previous track, play/pause, and next track via `playerctl` |

Use `launcher apps`, `launcher root`, or `launcher power` to open the corresponding Rofi menu. Invoking the same launcher again closes it. The system menu includes Fastfetch, `update`, and the `pkg-install` and `pkg-remove` helpers. Run `random-wallpaper` to change the wallpaper from a terminal.

Waybar exposes separate output and microphone controls and opens Wiremix for either one. The awob PipeWire listener displays volume and mute feedback automatically. Waybar runs `vpn-tracker`, which listens to Mullvad events and updates the VPN widget and awob when the connection state changes.

## Desktop services and reloads

Waybar uses the repo's user unit. awob uses the packaged `awob.service` with the exported `~/.config/systemd/user/awob.service.d/override.conf` drop-in. Its `ReadWritePaths=%h/.config/awob` setting allows the service to write to its config directory. The Catppuccin Mocha theme is selected in `~/.config/awob/awob.toml`. Mako starts on demand through D-Bus, and Rofi reads its config on each launch.

```bash
systemctl --user daemon-reload                 # After editing a unit or drop-in
systemctl --user restart waybar.service        # Also restarts the VPN tracker
systemctl --user restart awob.service
makoctl reload
hyprctl reload
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
