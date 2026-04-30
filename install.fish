#!/usr/bin/env fish
# usage: curl -fsSL https://raw.githubusercontent.com/nwrenger/arch-rice/main/install.fish | fish

set REPO_URL "https://github.com/nwrenger/arch-rice"
set DOTFILES_DIR "$HOME/.dotfiles"

# ── colors (catppuccin mocha) ────────────────────────────────────────────────
set CLR_MAUVE "\e[38;2;203;166;247m"
set CLR_GREEN "\e[38;2;166;227;161m"
set CLR_YELLOW "\e[38;2;249;226;175m"
set CLR_RED "\e[38;2;243;139;168m"
set CLR_SUBTEXT "\e[38;2;166;173;200m"
set CLR_RESET "\e[0m"

function info
    echo -e "$CLR_MAUVE  $argv$CLR_RESET"
end
function ok
    echo -e "$CLR_GREEN  $argv$CLR_RESET"
end
function warn
    echo -e "$CLR_YELLOW  $argv$CLR_RESET" >&2
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
    sudo pacman -Syu --noconfirm base-devel
    set tmp (mktemp -d)
    git clone https://aur.archlinux.org/paru.git $tmp/paru
    and pushd $tmp/paru
    and makepkg -si --noconfirm
    and popd
    and rm -rf $tmp
    or err "Failed to install paru"
end

# ── configure pacman ─────────────────────────────────────────────────────────
step "Configuring pacman repos"
sudo cp $DOTFILES_DIR/system/etc/pacman.conf /etc/pacman.conf
or err "Failed to copy pacman.conf"

if test -e $DOTFILES_DIR/system/etc/pacman.d/hooks/fix-hyprshutdown.hook
    sudo mkdir -p /etc/pacman.d/hooks
    and sudo cp $DOTFILES_DIR/system/etc/pacman.d/hooks/fix-hyprshutdown.hook /etc/pacman.d/hooks/fix-hyprshutdown.hook
    or err "Failed to copy fix-hyprshutdown pacman hook"
end

sudo pacman -Syu
or err "Failed to refresh pacman databases"

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
    set file  $argv[1]
    set skips $argv[2..]
    set result

    for line in (grep -v '^[[:space:]]*#' $file | grep -v '^[[:space:]]*$')
        set line (string trim -- $line)
        set line (string replace -ra '\s+' ' ' -- $line)

        set parts (string split -n ' ' -- $line)
        set pkg  $parts[1]
        set tags $parts[2..]

        set should_skip 0
        for tag in $tags
            if contains -- $tag $skips
                warn "  skipping $pkg ($tag)"
                set should_skip 1
                break
            end
        end

        if test $should_skip = 1
            continue
        end

        set result $result $pkg
    end

    printf '%s\n' $result
end

set pacman_pkgs (parse_pkgs $pacman_file $skip_tags)
set aur_pkgs    (parse_pkgs $aur_file    $skip_tags)

if test (count $pacman_pkgs) -gt 0
    sudo pacman -Syu --noconfirm $pacman_pkgs
    or err "pacman install failed"
end
if test (count $aur_pkgs) -gt 0
    paru -Syu --noconfirm $aur_pkgs
    or err "AUR install failed"
end

ok "Packages installed"

# ── copy dotfiles ────────────────────────────────────────────────────────────
step "Copying dotfiles to \$HOME"

for pkg_dir in $DOTFILES_DIR/home/*/
    set pkg (basename $pkg_dir)
    info "Copying $pkg"
    # -rT: merge into target dir, overwrite existing files
    cp -rT $pkg_dir $HOME
    or warn "Copy failed for $pkg — check for permission errors"
end

ok "Dotfiles copied"

# ── system configs (/etc) ────────────────────────────────────────────────────
step "Applying system configs"

# locale
sudo cp $DOTFILES_DIR/system/etc/locale.conf /etc/locale.conf
sudo locale-gen

# sddm
sudo mkdir -p /etc/sddm.conf.d
sudo cp -rT $DOTFILES_DIR/system/etc/sddm.conf.d/ /etc/sddm.conf.d/

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
sudo cp -rT $DOTFILES_DIR/system/sddm-theme/where_is_my_sddm_theme /usr/share/sddm/themes/where_is_my_sddm_theme
ok "SDDM theme installed"

# ── sddm xsetup script ───────────────────────────────────────────────────────
step "Installing SDDM Xsetup"
sudo mkdir -p /usr/share/sddm/scripts
sudo cp $DOTFILES_DIR/system/sddm-scripts/Xsetup /usr/share/sddm/scripts/Xsetup
sudo chmod +x /usr/share/sddm/scripts/Xsetup
ok "SDDM Xsetup installed"

# ── limine bootloader config ─────────────────────────────────────────────────
step "Staging Limine config template"
set limine_template "$HOME/.config/limine.conf.template"
cp $DOTFILES_DIR/system/boot/limine.conf.template $limine_template
ok "Template saved to $limine_template"

# ── enable system services ───────────────────────────────────────────────────
step "Enabling system services"

set system_services \
    avahi-daemon.service \
    bluetooth.service \
    cups.service \
    ddcci-hotplugd.service \
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
step "Enabling user services"

set user_services \
    elephant.service \
    hyprpaper.service \
    hyprpolkitagent.service \
    mako.service \
    swayosd.service \
    walker.service \
    waybar.service

for svc in $user_services
    systemctl --user enable --now $svc
    and ok "  enabled $svc"
    or warn "  failed to enable $svc"
end

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
end

# ── done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "$CLR_GREEN╔═════════════════════════════════════════════════════════════════╗"
echo -e "║  Setup complete!                                                ║"
echo -e "║                                                                 ║"
echo -e "║  Remaining manual steps:                                        ║"
echo -e "║  1. Log into Mullvad: mullvad account login                     ║"
echo -e "║  2. Set default shell: chsh -s /bin/fish                        ║"
echo -e "║  2. Open the template:                                          ║"
echo -e "║       \$HOME/.config/limine.conf.template                        ║"
echo -e "║  3. Copy the options an config into /boot/limine.conf           ║"
echo -e "║     Also rename OS to 'Arch Linux' and set kernel to 'Linux'    ║"
echo -e "║  4. Set 'ESP_PATH=/boot' inside /etc/default/limine             ║"
echo -e "║  4. Run: sudo limine-enroll-config                              ║"
echo -e "║  5. Reboot                                                      ║"
echo -e "╚═════════════════════════════════════════════════════════════════╝$CLR_RESET"
echo ""
echo -e "$CLR_YELLOW  You can now remove archinstall defaults you no longer need:$CLR_RESET"
echo -e "$CLR_SUBTEXT  sudo pacman -Rns dunst kitty dolphin wofi polkit-kde-agent$CLR_RESET"
echo ""

# ── cleanup ──────────────────────────────────────────────────────────────────
rm -rf $DOTFILES_DIR
echo -e "$CLR_SUBTEXT  (.dotfiles removed)$CLR_RESET"
