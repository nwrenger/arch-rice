#!/usr/bin/env fish
# usage: fish export.fish [output-dir]
# Snapshots your live system into a git-ready dotfiles repo layout.

set OUT (test -n "$argv[1]"; and echo $argv[1]; or echo "$HOME/dotfiles-export")

set CLR_MAUVE  "\e[38;2;203;166;247m"
set CLR_GREEN  "\e[38;2;166;227;161m"
set CLR_YELLOW "\e[38;2;249;226;175m"
set CLR_RESET  "\e[0m"

function step; echo -e "\n$CLR_MAUVE━━ $argv$CLR_RESET"; end
function ok;   echo -e "$CLR_GREEN  $argv$CLR_RESET"; end
function warn; echo -e "$CLR_YELLOW  $argv$CLR_RESET"; end

function cp_mkdir
    # usage: cp_mkdir <src> <dst>
    mkdir -p (dirname $argv[2])
    cp -rT $argv[1] $argv[2]
end

mkdir -p $OUT

# ── home dotfiles (layout: home/<package>/dot-files) ───────────────────
step "Exporting home dotfiles"

function home_cp
    # usage: home_cp <pkg> <src-path-relative-to-HOME>
    set pkg $argv[1]
    set src "$HOME/$argv[2]"
    set dst "$OUT/home/$pkg/$argv[2]"
    if test -e $src
        mkdir -p (dirname $dst)
        cp -rT $src $dst
        ok "  $argv[2]"
    else
        warn "  missing: $argv[2]"
    end
end

# hypr
home_cp hypr .config/hypr

# waybar
home_cp waybar .config/waybar

# alacritty
home_cp alacritty .config/alacritty

# fish
home_cp fish .config/fish

# starship
home_cp starship .config/starship.toml

# walker
home_cp walker .config/walker

# elephant
home_cp elephant .config/elephant

# kvantum
home_cp kvantum .config/Kvantum

# qt
home_cp qt .config/qt5ct
home_cp qt .config/qt6ct

# gtk
home_cp gtk .config/gtk-3.0
home_cp gtk .config/gtk-4.0

# fontconfig
home_cp fontconfig .config/fontconfig

# swayosd
home_cp swayosd .config/swayosd

# mako
home_cp mako .config/mako

# fastfetch
home_cp fastfetch .config/fastfetch

# btop
home_cp btop .config/btop

# zed
home_cp zed .config/zed

# nwg-look
home_cp nwg-look .config/nwg-look

# uwsm
home_cp uwsm .config/uwsm

# systemd user services
home_cp systemd .config/systemd

# local bin (custom scripts)
home_cp local-bin .local/bin

# ── system configs ───────────────────────────────────────────────────────────
step "Exporting system configs"

function sys_cp
    # usage: sys_cp <src> <dst-relative-to-OUT/system>
    set src $argv[1]
    set dst "$OUT/system/$argv[2]"
    if test -e $src
        cp_mkdir $src $dst
        ok "  $src"
    else
        warn "  missing: $src"
    end
end

sys_cp /etc/locale.conf           etc/locale.conf
sys_cp /etc/pacman.conf           etc/pacman.conf
sys_cp /etc/pacman.d/hooks/fix-hyprshutdown.hook  etc/pacman.d/hooks/fix-hyprshutdown.hook
sys_cp /etc/udev/rules.d/99-ddcci.rules  etc/udev/rules.d/99-ddcci.rules
sys_cp /etc/limine-snapper-sync.conf  etc/limine-snapper-sync.conf
sys_cp /etc/sddm.conf.d           etc/sddm.conf.d

# snapper config needs sudo (root-owned)
mkdir -p "$OUT/system/etc/snapper/configs"
if sudo cat /etc/snapper/configs/root > "$OUT/system/etc/snapper/configs/root" 2>/dev/null
    ok "  /etc/snapper/configs/root"
else
    warn "  /etc/snapper/configs/root — failed (try running with sudo)"
end

# ── limine config (template — strip entries) ─────────────────────────────────
step "Exporting Limine config (as template)"
set limine_src /boot/limine.conf
set limine_dst "$OUT/system/boot/limine.conf.template"
if test -e $limine_src
    mkdir -p "$OUT/system/boot"
    sed '/^\//,$d' $limine_src > $limine_dst
    ok "  limine.conf → template (entries stripped)"
else
    warn "  /boot/limine.conf not found"
end

# ── SDDM theme ───────────────────────────────────────────────────────────────
step "Exporting SDDM theme"
set theme_src "/usr/share/sddm/themes/where_is_my_sddm_theme/"
if test -d $theme_src
    cp_mkdir $theme_src "$OUT/system/sddm-theme/where_is_my_sddm_theme"
    ok "  SDDM theme"
else
    warn "  SDDM theme not found at $theme_src"
end

# ── SDDM Xsetup script ───────────────────────────────────────────────────────
step "Exporting SDDM Xsetup"
sys_cp /usr/share/sddm/scripts/Xsetup  sddm-scripts/Xsetup

# ── wallpaper ────────────────────────────────────────────────────────────────
step "Exporting wallpaper"
home_cp wallpaper Pictures/wallpaper/1-totoro.png

# ── packages list ────────────────────────────────────────────────────────────
step "Exporting package lists"

set pacman_filter \
    # none yet

set aur_filter \
    paru \
    paru-debug

function filter_pkgs
    # usage: filter_pkgs <file> <pkg...>
    set file  $argv[1]
    set skips $argv[2..]
    for skip in $skips
        sed -i "/^$skip\$/d" $file
    end
end

# Explicitly installed (non-AUR)
comm -23 \
    (pacman -Qqe | sort | psub) \
    (pacman -Qqm | sort | psub) \
    > "$OUT/packages-pacman.txt"
filter_pkgs "$OUT/packages-pacman.txt" $pacman_filter

# AUR packages
pacman -Qqm > "$OUT/packages-aur.txt"
filter_pkgs "$OUT/packages-aur.txt" $aur_filter

ok "  packages-pacman.txt"
ok "  packages-aur.txt"
warn "  Review and tag hardware-specific packages in packages.txt"

# ── git init hint ────────────────────────────────────────────────────────────
step "Done"
echo ""
echo -e "$CLR_GREEN  Export complete → $OUT$CLR_RESET"
echo ""
echo -e "$CLR_YELLOW  Sensitive files to check before pushing:$CLR_RESET"
echo "  /etc/mullvad-vpn/ → already excluded (not copied)"
echo "  ~/.local/share/keyrings/ → not copied, never commit"
echo "  ~/.ssh/ → not copied"
