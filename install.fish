#!/usr/bin/env fish
# usage: curl -fsSL https://raw.githubusercontent.com/nwrenger/arch-rice/main/install.fish | fish

set REPO_URL "https://github.com/nwrenger/arch-rice"
set DOTFILES_DIR "$HOME/.dotfiles"

# ── colors (catppuccin mocha) ────────────────────────────────────────────────
set CLR_MAUVE  "\e[38;2;203;166;247m"
set CLR_GREEN  "\e[38;2;166;227;161m"
set CLR_YELLOW "\e[38;2;249;226;175m"
set CLR_RED    "\e[38;2;243;139;168m"
set CLR_SUBTEXT "\e[38;2;166;173;200m"
set CLR_RESET  "\e[0m"

function info
    echo -e "$CLR_MAUVE  $argv$CLR_RESET"
end
function ok
    echo -e "$CLR_GREEN  $argv$CLR_RESET"
end
function warn
    echo -e "$CLR_YELLOW  $argv$CLR_RESET"
end
function err
    echo -e "$CLR_RED  $argv$CLR_RESET"
    exit 1
end
function step
    echo -e "\n$CLR_MAUVE━━ $argv$CLR_RESET"
end

# ── sanity checks ────────────────────────────────────────────────────────────
if test (id -u) = 0
    err "Do not run as root. The script will sudo when needed."
end

if not command -q git
    sudo pacman -S --needed --noconfirm git
end

# ── remove archinstall hyprland defaults ─────────────────────────────────────
step "Removing archinstall defaults"
set archinstall_bloat dunst kitty dolphin wofi polkit-kde-agent slurp
for pkg in $archinstall_bloat
    if pacman -Q $pkg &>/dev/null
        sudo pacman -Rns --noconfirm $pkg
        and ok "  removed $pkg"
        or warn "  failed to remove $pkg"
    end
end

# ── clone dotfiles ───────────────────────────────────────────────────────────
step "Cloning dotfiles"
if test -d $DOTFILES_DIR
    warn "~/.dotfiles already exists — pulling latest"
    git -C $DOTFILES_DIR pull --ff-only
else
    git clone $REPO_URL $DOTFILES_DIR
    or err "Failed to clone repo"
end

# ── hardware detection ───────────────────────────────────────────────────────
step "Detecting hardware"

set GPU_VENDOR (lspci 2>/dev/null | grep -i "vga\|3d\|display" | tr '[:upper:]' '[:lower:]')
set CPU_VENDOR (grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')

set HAS_NVIDIA 0
set HAS_AMD_GPU 0
set HAS_INTEL_GPU 0
set HAS_INTEL_CPU 0
set HAS_AMD_CPU 0
set HAS_DDCCI 0

if string match -q "*nvidia*" $GPU_VENDOR
    set HAS_NVIDIA 1
    info "GPU: NVIDIA detected"
end
if string match -q "*amd*" $GPU_VENDOR; or string match -q "*radeon*" $GPU_VENDOR
    set HAS_AMD_GPU 1
    info "GPU: AMD detected"
end
if string match -q "*intel*" $GPU_VENDOR
    set HAS_INTEL_GPU 1
    info "GPU: Intel detected"
end
if test $CPU_VENDOR = "GenuineIntel"
    set HAS_INTEL_CPU 1
    info "CPU: Intel detected"
end
if test $CPU_VENDOR = "AuthenticAMD"
    set HAS_AMD_CPU 1
    info "CPU: AMD detected"
end

# ddcci only useful with external monitors — ask
if test $HAS_NVIDIA = 1; or test $HAS_AMD_GPU = 1
    read -l -P "Do you use external DDC/CI monitors (brightness control via ddcutil)? [y/N] " ddcci_ans
    if string match -qi "y" $ddcci_ans
        set HAS_DDCCI 1
    end
end

# ── install paru ─────────────────────────────────────────────────────────────
step "Setting up paru (AUR helper)"
if command -q paru
    ok "paru already installed"
else
    sudo pacman -S --needed base-devel git
    set tmp (mktemp -d)
    git clone https://aur.archlinux.org/paru.git $tmp/paru
    and pushd $tmp/paru
    and makepkg -si --noconfirm
    and popd
    and rm -rf $tmp
    or err "Failed to install paru"
end

# ── install packages ─────────────────────────────────────────────────────────
step "Installing packages"

set pacman_file "$DOTFILES_DIR/packages-pacman.txt"
set aur_file    "$DOTFILES_DIR/packages-aur.txt"

# build skip tags based on hardware
set skip_tags
if test $HAS_NVIDIA = 0;    set skip_tags $skip_tags nvidia;    end
if test $HAS_INTEL_CPU = 0; set skip_tags $skip_tags intel-cpu; end
if test $HAS_AMD_CPU = 0;   set skip_tags $skip_tags amd-cpu;   end
if test $HAS_DDCCI = 0;     set skip_tags $skip_tags ddcci;     end

function parse_pkgs
    # usage: parse_pkgs <file> <skip_tags...>
    set file $argv[1]
    set skips $argv[2..]
    set result
    for line in (grep -v '^\s*#' $file | grep -v '^\s*$')
        set parts (string split -n " " $line)
        set pkg $parts[1]
        set tag $parts[2]
        if test -n "$tag"; and contains $tag $skips
            warn "  skipping $pkg ($tag)"
            continue
        end
        set result $result $pkg
    end
    echo $result
end

set pacman_pkgs (parse_pkgs $pacman_file $skip_tags)
set aur_pkgs    (parse_pkgs $aur_file    $skip_tags)

if test (count $pacman_pkgs) -gt 0
    sudo pacman -S --needed --noconfirm $pacman_pkgs
    or err "pacman install failed"
end
if test (count $aur_pkgs) -gt 0
    paru -S --needed --noconfirm $aur_pkgs
    or err "AUR install failed"
end

ok "Packages installed"

# ── stow dotfiles ────────────────────────────────────────────────────────────
step "Symlinking dotfiles (GNU Stow)"

if not command -q stow
    sudo pacman -S --noconfirm stow
end

set stow_packages (ls -d $DOTFILES_DIR/home/*/ | xargs -n1 basename)
for pkg in $stow_packages
    info "Stowing $pkg"
    stow --dir=$DOTFILES_DIR/home --target=$HOME $pkg
    or warn "Conflict in $pkg — resolve manually"
end

ok "Dotfiles linked"

# ── system configs (/etc) ────────────────────────────────────────────────────
step "Applying system configs"

# locale
sudo cp $DOTFILES_DIR/system/etc/locale.conf /etc/locale.conf
sudo locale-gen

# pacman.conf
sudo cp $DOTFILES_DIR/system/etc/pacman.conf /etc/pacman.conf

# zram
sudo cp $DOTFILES_DIR/system/etc/systemd/zram-generator.conf /etc/systemd/zram-generator.conf

# sddm
sudo mkdir -p /etc/sddm.conf.d
sudo cp $DOTFILES_DIR/system/etc/sddm.conf.d/theme.conf /etc/sddm.conf.d/theme.conf

# udev rules
if test $HAS_DDCCI = 1
    sudo cp $DOTFILES_DIR/system/etc/udev/rules.d/99-ddcci.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules
    ok "ddcci udev rule installed"
end

# snapper config
sudo cp $DOTFILES_DIR/system/etc/snapper/configs/root /etc/snapper/configs/root
or warn "snapper config copy failed — run manually"

# limine-snapper-sync
sudo cp $DOTFILES_DIR/system/etc/limine-snapper-sync.conf /etc/limine-snapper-sync.conf

ok "System configs applied"

# ── sddm theme ───────────────────────────────────────────────────────────────
step "Installing SDDM theme"
sudo mkdir -p /usr/share/sddm/themes
sudo cp -r $DOTFILES_DIR/system/sddm-theme/where_is_my_sddm_theme /usr/share/sddm/themes/
ok "SDDM theme installed"

# ── limine bootloader config ─────────────────────────────────────────────────
step "Configuring Limine"
warn "Limine config contains your disk's PARTUUID — cannot copy blindly."
info "Template saved at: $DOTFILES_DIR/system/boot/limine.conf.template"
info "Run this to get your PARTUUID:"
echo -e "$CLR_SUBTEXT    blkid -s PARTUUID -o value /dev/sdXY$CLR_RESET"
info "Then manually set it in /boot/limine.conf and run:"
echo -e "$CLR_SUBTEXT    sudo limine-enroll-config && sudo limine-reset-enroll$CLR_RESET"

# ── enable system services ───────────────────────────────────────────────────
step "Enabling system services"

set system_services \
    bluetooth.service \
    cups.service \
    iwd.service \
    limine-snapper-sync.service \
    mullvad-daemon.service \
    mullvad-early-boot-blocking.service \
    sddm.service \
    swayosd-libinput-backend.service \
    snapper-cleanup.timer \
    snapper-timeline.timer

if test $HAS_NVIDIA = 1
    set system_services $system_services \
        nvidia-hibernate.service \
        nvidia-resume.service \
        nvidia-suspend.service
end

for svc in $system_services
    sudo systemctl enable $svc
    and ok "  enabled $svc"
    or warn "  failed to enable $svc"
end

# ── enable user services ─────────────────────────────────────────────────────
# systemctl --user requires a running user session (graphical-session.target)
# Since we're pre-first-login, write a one-shot Fish login script instead.
step "Scheduling user services (enabled on first login)"

set user_services \
    elephant.service \
    hyprpaper.service \
    hyrpolkitagent.service \
    mako.service \
    swayosd.service \
    walker.service \
    waybar.service

# enable linger so user services survive without an active session
sudo loginctl enable-linger $USER

# write a one-shot conf.d script that enables services on first login then removes itself
set once_script "$HOME/.config/fish/conf.d/99-enable-user-services.fish"
mkdir -p (dirname $once_script)
echo "# one-shot: enable user systemd services on first login" > $once_script
for svc in $user_services
    echo "systemctl --user enable $svc" >> $once_script
end
echo "rm -- (status filename)" >> $once_script
ok "User services will be enabled on first Hyprland login"

# ── set fish as default shell ────────────────────────────────────────────────
step "Setting Fish as default shell"
set fish_path (which fish)
if not grep -q $fish_path /etc/shells
    echo $fish_path | sudo tee -a /etc/shells
end
chsh -s $fish_path
ok "Default shell set to Fish"

# ── snapper setup ────────────────────────────────────────────────────────────
step "Setting up Snapper"
if not test -f /etc/snapper/configs/root
    sudo snapper -c root create-config /
    ok "Snapper root config created"
else
    ok "Snapper root config already exists"
end

# ── NVIDIA extras ────────────────────────────────────────────────────────────
if test $HAS_NVIDIA = 1
    step "NVIDIA setup"
    info "Make sure nvidia-open-dkms and dkms are installed (done via packages)"
    info "If Wayland has issues, ensure kernel parameter 'nvidia_drm.modeset=1' is set"
    warn "Check /boot/limine.conf cmdline includes: nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
end

# ── done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "$CLR_GREEN╔══════════════════════════════════════╗"
echo -e "║  Setup complete!                     ║"
echo -e "║                                      ║"
echo -e "║  Remaining manual steps:             ║"
echo -e "║  1. Set PARTUUID in limine.conf      ║"
echo -e "║  2. Run limine-enroll-config         ║"
echo -e "║  3. Log out and back in (or reboot)  ║"
echo -e "╚══════════════════════════════════════╝$CLR_RESET"
