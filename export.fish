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
    cp -r $argv[1] $argv[2]
end

mkdir -p $OUT

# ── home dotfiles (stow layout: home/<package>/dot-files) ───────────────────
step "Exporting home dotfiles"

function stow_cp
    # usage: stow_cp <pkg> <src-path-relative-to-HOME>
    set pkg $argv[1]
    set src "$HOME/$argv[2]"
    set dst "$OUT/home/$pkg/$argv[2]"
    if test -e $src
        mkdir -p (dirname $dst)
        cp -r $src $dst
        ok "  $argv[2]"
    else
        warn "  missing: $argv[2]"
    end
end

# hypr
stow_cp hypr .config/hypr

# waybar
stow_cp waybar .config/waybar

# alacritty
stow_cp alacritty .config/alacritty

# fish
stow_cp fish .config/fish

# starship
stow_cp starship .config/starship.toml

# walker
stow_cp walker .config/walker

# elephant
stow_cp elephant .config/elephant

# kvantum
stow_cp kvantum .config/Kvantum

# qt
stow_cp qt .config/qt5ct
stow_cp qt .config/qt6ct

# gtk
stow_cp gtk .config/gtk-3.0
stow_cp gtk .config/gtk-4.0

# fontconfig
stow_cp fontconfig .config/fontconfig

# swayosd
stow_cp swayosd .config/swayosd

# mako
stow_cp mako .config/mako

# fastfetch
stow_cp fastfetch .config/fastfetch

# btop
stow_cp btop .config/btop

# zed
stow_cp zed .config/zed

# nwg-look
stow_cp nwg-look .config/nwg-look

# uwsm
stow_cp uwsm .config/uwsm

# systemd user services
stow_cp systemd .config/systemd

# local bin (custom scripts)
stow_cp local-bin .local/bin

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
sys_cp /etc/systemd/zram-generator.conf  etc/systemd/zram-generator.conf
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

# ── limine config (template — strip PARTUUID) ────────────────────────────────
step "Exporting Limine config (as template)"
set limine_src /boot/limine.conf
set limine_dst "$OUT/system/boot/limine.conf.template"
if test -e $limine_src
    mkdir -p "$OUT/system/boot"
    # Scrub PARTUUID, then strip the auto-generated snapshots block
    # (everything from "//Snapshots" up to but not including the next top-level "/" entry)
    sed 's/PARTUUID=[a-f0-9-]*/PARTUUID=YOUR_PARTUUID_HERE/g' $limine_src \
        | sed '/^    \/\/Snapshots/,/^\/[^\/]/{ /^\/[^\/]/!d }' \
        > $limine_dst
    ok "  limine.conf → template (PARTUUID scrubbed, snapshots stripped)"
    warn "  Remember to set your PARTUUID in limine.conf.template before use"
else
    warn "  /boot/limine.conf not found"
end

# ── SDDM theme ───────────────────────────────────────────────────────────────
step "Exporting SDDM theme"
set theme_src "/home/nils/Documents/themes/where-is-my-sddm-theme/where_is_my_sddm_theme"
if test -d $theme_src
    cp_mkdir $theme_src "$OUT/system/sddm-theme/where_is_my_sddm_theme"
    ok "  SDDM theme"
else
    warn "  SDDM theme not found at $theme_src"
end

# ── packages list ────────────────────────────────────────────────────────────
step "Exporting package lists"
# Explicitly installed (non-AUR)
comm -23 \
    (pacman -Qqe | sort | psub) \
    (pacman -Qqm | sort | psub) \
    > "$OUT/packages-pacman.txt"

# AUR packages
pacman -Qqm > "$OUT/packages-aur.txt"

ok "  packages-pacman.txt"
ok "  packages-aur.txt"
warn "  Review and tag hardware-specific packages in packages.txt"

# ── git init hint ────────────────────────────────────────────────────────────
step "Done"
echo ""
echo -e "$CLR_GREEN  Export complete → $OUT$CLR_RESET"
echo ""
echo "Next steps:"
echo "  1. cd $OUT"
echo "  2. git init && git add -A && git commit -m 'initial export'"
echo "  3. git remote add origin git@github.com:USER/REPO.git"
echo "  4. git push -u origin main"
echo "  5. Update REPO_URL in install.fish"
echo "  6. Review packages.txt and add hardware tags"
echo "  7. Add secrets to .gitignore (mullvad settings, keyrings, etc)"
echo ""
echo -e "$CLR_YELLOW  Sensitive files to check before pushing:$CLR_RESET"
echo "  /etc/mullvad-vpn/ → already excluded (not copied)"
echo "  ~/.local/share/keyrings/ → not copied, never commit"
echo "  ~/.ssh/ → not copied"
