#!/usr/bin/env bash
# Fedora + Niri configuration installer.
#
# Runs unattended by default. Use --dry-run to inspect the planned actions.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly DOTFILES_DIR="$SCRIPT_DIR/dotfiles"
readonly FONTS_DIR="$SCRIPT_DIR/fonts"
readonly WALLPAPERS_DIR="$SCRIPT_DIR/Wallpapers"
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lancetfish-niri"
readonly RUN_ID="$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR="$STATE_DIR/backups/$RUN_ID"
readonly LOG_FILE="$STATE_DIR/install-$RUN_ID.log"

APPLY=true
INSTALL_PACKAGES=true
INSTALL_FLATPAK=true
INSTALL_OMF=true
COPY_DOTFILES=true
COPY_ASSETS=true
APPLY_DESKTOP_SETTINGS=false
SET_FISH_SHELL=false

# The minimum packages needed by the supplied Niri session.
CORE_PACKAGES=(
    niri waybar swaybg swaylock wl-clipboard fuzzel mako wlsunset
    foot fish fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-rime
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome
    pipewire-utils playerctl brightnessctl curl flatpak
)

# Personal COPR repositories used by this Fedora setup. They are enabled before
# package installation so their packages stay available for later DNF use too.
COPR_REPOSITORIES=(
    deltacopy/waterfox
    lihaohong/yazi
    phracek/PyCharm
    xmp360/spark-store
)

# Missing optional packages are reported but do not fail the installation.
OPTIONAL_PACKAGES=(
    kitty vim-enhanced neovim nodejs20 nodejs20-npm
    bat eza zoxide btop fastfetch chafa timg jq gdu xclip
    yazi Thunar file-roller gvfs-smb gvfs-mtp gvfs-gphoto2 gnome-keyring
    tumbler poppler-glib ffmpegthumbnailer thunar-archive-plugin thunar-volman
    google-noto-fonts-common google-noto-sans-cjk-fonts jetbrains-mono-fonts
    breeze-cursor-theme mpv wf-recorder imv pavucontrol strace firefox
    ImageMagick sxhkd ydotool matugen
    gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugin-libav
)

usage() {
    cat <<'EOF'
Usage: ./lancetfi.sh [options]

Runs the complete installation without an interactive confirmation. Use
--dry-run when you only want to inspect the plan.

Options:
  --apply               Perform the selected actions (the default).
  --dry-run             Show the plan only; do not change anything.
  --no-packages         Do not install RPM packages or enable RPM Fusion.
  --no-flatpak          Do not install Zen Browser through Flatpak.
  --no-omf              Do not install Oh My Fish.
  --no-dotfiles         Do not copy dotfiles.
  --no-assets           Do not copy fonts or wallpapers.
  --desktop-settings    Apply optional GNOME dark-theme preferences.
  --set-fish-shell      Set fish as the login shell after it is installed.
  -h, --help            Show this help text.

Existing managed files are backed up individually under:
  ~/.local/state/lancetfish-niri/backups/<timestamp>/

Examples:
  ./lancetfi.sh
  ./lancetfi.sh --dry-run
  ./lancetfi.sh --no-flatpak --desktop-settings
EOF
}

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

on_error() {
    local line="$1" command="$2"
    printf '[ERROR] Stopped at line %s while running: %s\n' "$line" "$command" >&2
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

validate_environment() {
    (( EUID != 0 )) || die "Run this script as a regular user, not as root."
    [[ -n "${HOME:-}" && -d "$HOME" ]] || die "HOME is not a usable directory."
    [[ -r /etc/os-release ]] || die "Cannot identify the operating system."

    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "fedora" ]] || die "This installer currently supports Fedora only."
    [[ -d "$DOTFILES_DIR" ]] || die "Missing required directory: $DOTFILES_DIR"
}

print_plan() {
    info "Installation plan"
    printf '  RPM packages:        %s\n' "$INSTALL_PACKAGES"
    printf '  Zen Browser:         %s\n' "$INSTALL_FLATPAK"
    printf '  Oh My Fish:          %s\n' "$INSTALL_OMF"
    printf '  Dotfiles:            %s\n' "$COPY_DOTFILES"
    printf '  Fonts/wallpapers:    %s\n' "$COPY_ASSETS"
    printf '  Desktop preferences: %s\n' "$APPLY_DESKTOP_SETTINGS"
    printf '  Fish login shell:    %s\n\n' "$SET_FISH_SHELL"
    info "The script runs without confirmation unless you pass --dry-run."
}

setup_logging() {
    mkdir -p -- "$STATE_DIR" "$BACKUP_DIR"
    : > "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
    info "Log: $LOG_FILE"
    info "Backup directory: $BACKUP_DIR"
}

enable_rpmfusion() {
    if rpm -q rpmfusion-free-release >/dev/null 2>&1 && \
       rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
        info "RPM Fusion is already enabled."
        return
    fi

    local fedora_release
    fedora_release="$(rpm -E %fedora)"
    info "Enabling RPM Fusion for Fedora $fedora_release."
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_release}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_release}.noarch.rpm"
}

enable_copr_repositories() {
    local repository
    for repository in "${COPR_REPOSITORIES[@]}"; do
        info "Enabling COPR repository: $repository"
        if ! sudo dnf copr enable "$repository" -y; then
            warn "Could not enable COPR repository: $repository"
        fi
    done
}

collect_missing_packages() {
    local -n destination="$1"
    shift
    destination=()

    local package
    for package in "$@"; do
        rpm -q "$package" >/dev/null 2>&1 || destination+=("$package")
    done
}

install_required_packages() {
    local missing=()
    collect_missing_packages missing "${CORE_PACKAGES[@]}"
    if (( ${#missing[@]} == 0 )); then
        info "All core packages are already installed."
        return
    fi
    info "Installing core packages: ${missing[*]}"
    sudo dnf install -y "${missing[@]}"
}

install_optional_packages() {
    local missing=()
    collect_missing_packages missing "${OPTIONAL_PACKAGES[@]}"
    if (( ${#missing[@]} == 0 )); then
        info "All optional packages are already installed."
        return
    fi

    info "Installing optional packages: ${missing[*]}"
    if ! sudo dnf install -y --skip-unavailable "${missing[@]}"; then
        warn "Some optional packages could not be installed; continuing."
    fi

    local unavailable=() package
    for package in "${missing[@]}"; do
        rpm -q "$package" >/dev/null 2>&1 || unavailable+=("$package")
    done
    (( ${#unavailable[@]} == 0 )) || warn "Unavailable optional packages: ${unavailable[*]}"
}

install_packages() {
    require_command dnf
    require_command rpm
    enable_copr_repositories
    enable_rpmfusion
    install_required_packages
    install_optional_packages
}

install_zen_browser() {
    if ! command -v flatpak >/dev/null 2>&1; then
        warn "Flatpak is unavailable; skipped Zen Browser."
        return
    fi
    if ! flatpak remote-info flathub app.zen_browser.zen >/dev/null 2>&1; then
        info "Adding the user-level Flathub remote."
        flatpak remote-add --if-not-exists --user flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
    info "Installing Zen Browser for the current user."
    flatpak install -y --user flathub app.zen_browser.zen || \
        warn "Zen Browser could not be installed; retry later with Flatpak."
}

install_omf() {
    if ! command -v fish >/dev/null 2>&1; then
        warn "fish is unavailable; skipped Oh My Fish."
        return
    fi
    require_command curl

    local omf_init="$HOME/.local/share/omf/init.fish"
    if [[ -s "$omf_init" ]]; then
        info "Oh My Fish is already installed."
        return
    fi

    local installer
    installer="$(mktemp)"
    info "Downloading and installing Oh My Fish."
    if ! curl --fail --location --proto '=https' --tlsv1.2 \
        --output "$installer" \
        https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install; then
        rm -f -- "$installer"
        warn "Oh My Fish download failed; continuing."
        return
    fi

    if ! fish "$installer" --noninteractive; then
        rm -f -- "$installer"
        warn "Oh My Fish installation failed; continuing."
        return
    fi
    rm -f -- "$installer"

    [[ -s "$omf_init" ]] && info "Oh My Fish installed." || \
        warn "Oh My Fish did not create its expected initialization file."
}

backup_existing_file() {
    local destination="$1" relative_path="$2"
    if [[ -e "$destination" || -L "$destination" ]]; then
        local backup_file="$BACKUP_DIR/$relative_path"
        mkdir -p -- "$(dirname -- "$backup_file")"
        cp -a -- "$destination" "$backup_file"
        rm -f -- "$destination"
    fi
}

replace_home_placeholder() {
    local file="$1"
    grep -Iq . "$file" || return 0
    grep -qF '/home/lancetfish' "$file" || return 0

    local escaped_home="${HOME//\\/\\\\}"
    escaped_home="${escaped_home//&/\\&}"
    escaped_home="${escaped_home//|/\\|}"
    sed -i "s|/home/lancetfish|$escaped_home|g" "$file"
}

copy_dotfiles() {
    info "Copying dotfiles with per-file backups."
    local copied=0 source_file relative_path destination_file
    while IFS= read -r -d '' source_file; do
        relative_path="${source_file#"$DOTFILES_DIR"/}"
        destination_file="$HOME/$relative_path"
        [[ "$destination_file" == "$HOME/"* ]] || die "Unsafe destination path: $destination_file"
        [[ ! -d "$destination_file" || -L "$destination_file" ]] || \
            die "Cannot replace directory with file: $destination_file"
        backup_existing_file "$destination_file" "$relative_path"
        mkdir -p -- "$(dirname -- "$destination_file")"
        cp -a -- "$source_file" "$destination_file"
        replace_home_placeholder "$destination_file"
        ((copied += 1))
    done < <(find "$DOTFILES_DIR" -type f -print0)
    info "Installed $copied dotfile(s)."
}

copy_optional_tree() {
    local source_dir="$1" destination_dir="$2" label="$3"
    [[ -d "$source_dir" ]] || { warn "No $label directory found; skipped."; return; }

    local copied=0 source_file relative_path destination_file
    while IFS= read -r -d '' source_file; do
        relative_path="${source_file#"$source_dir"/}"
        destination_file="$destination_dir/$relative_path"
        mkdir -p -- "$(dirname -- "$destination_file")"
        [[ ! -e "$destination_file" && ! -L "$destination_file" ]] || continue
        cp -a -- "$source_file" "$destination_file"
        ((copied += 1))
    done < <(find "$source_dir" -type f -print0)
    info "Installed $copied new $label file(s); existing files were kept."
}

copy_assets() {
    copy_optional_tree "$FONTS_DIR" "$HOME/.local/share/fonts" "font"
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f
    else
        warn "fc-cache is unavailable; refresh the font cache manually later."
    fi
    copy_optional_tree "$WALLPAPERS_DIR" "$HOME/Pictures/Wallpapers" "wallpaper"
}

apply_desktop_settings() {
    if ! command -v gsettings >/dev/null 2>&1; then
        warn "gsettings is unavailable; skipped desktop preferences."
        return
    fi
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || warn "Could not set colour scheme."
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' || warn "Could not set GTK theme."
    gsettings set org.gnome.desktop.wm.preferences button-layout ':close' || warn "Could not set window buttons."
}

set_fish_as_login_shell() {
    local fish_path
    fish_path="$(command -v fish || true)"
    [[ -n "$fish_path" ]] || { warn "fish is not installed; skipped login shell change."; return; }
    if ! grep -qxF "$fish_path" /etc/shells; then
        printf '%s\n' "$fish_path" | sudo tee -a /etc/shells >/dev/null
    fi
    chsh -s "$fish_path" "$USER"
    info "Fish is now the login shell for $USER."
}

parse_arguments() {
    while (( $# > 0 )); do
        case "$1" in
            --apply) APPLY=true ;;
            --dry-run) APPLY=false ;;
            --no-packages) INSTALL_PACKAGES=false ;;
            --no-flatpak) INSTALL_FLATPAK=false ;;
            --no-omf) INSTALL_OMF=false ;;
            --no-dotfiles) COPY_DOTFILES=false ;;
            --no-assets) COPY_ASSETS=false ;;
            --desktop-settings) APPLY_DESKTOP_SETTINGS=true ;;
            --set-fish-shell) SET_FISH_SHELL=true ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown option: $1 (use --help for usage)" ;;
        esac
        shift
    done
}

main() {
    parse_arguments "$@"
    print_plan
    if [[ "$APPLY" != true ]]; then
        info "Dry run complete. Re-run without --dry-run to make changes."
        return 0
    fi

    validate_environment
    setup_logging
    info "Starting installation."
    if [[ "$INSTALL_PACKAGES" == true || "$SET_FISH_SHELL" == true ]]; then
        info "Requesting administrator permission when needed."
        sudo -v
    fi

    [[ "$INSTALL_PACKAGES" != true ]] || install_packages
    [[ "$INSTALL_OMF" != true ]] || install_omf
    [[ "$INSTALL_FLATPAK" != true ]] || install_zen_browser
    [[ "$COPY_DOTFILES" != true ]] || copy_dotfiles
    [[ "$COPY_ASSETS" != true ]] || copy_assets
    [[ "$APPLY_DESKTOP_SETTINGS" != true ]] || apply_desktop_settings
    [[ "$SET_FISH_SHELL" != true ]] || set_fish_as_login_shell

    info "Installation complete."
    info "Backups (if any): $BACKUP_DIR"
}

main "$@"
