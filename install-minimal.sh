#!/usr/bin/env bash
# KDElite minimal installer: installs only the core of KDE Plasma, without
# the full "kde"/"plasma" meta packages (no PIM suite, Akonadi, Discover,
# KDE Connect, games, office apps, ...).
#
#   sudo ./install-minimal.sh [--dry-run] [--no-dm] [--bluetooth] [--extras]
set -euo pipefail

DRY_RUN=0 WITH_DM=1 WITH_BT=0 WITH_EXTRAS=0

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Install a minimal KDE Plasma desktop.

Usage: sudo $0 [options]

  --dry-run     Print the install command without running it
  --no-dm       Don't install/enable the SDDM login screen
  --bluetooth   Also install Bluetooth support (bluedevil)
  --extras      Also install a text editor, image viewer and archive tool
                (kate, gwenview, ark)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1 ;;
        --no-dm) WITH_DM=0 ;;
        --bluetooth) WITH_BT=1 ;;
        --extras) WITH_EXTRAS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

if (( ! DRY_RUN )) && [[ $EUID -ne 0 ]]; then
    die "run as root (e.g. sudo $0), or use --dry-run"
fi

[[ -r /etc/os-release ]] || die "/etc/os-release not found; unsupported system"
# shellcheck disable=SC1091
. /etc/os-release
FAMILY=""
for id in ${ID:-} ${ID_LIKE:-}; do
    case "$id" in
        arch|manjaro|endeavouros|cachyos|garuda) FAMILY=arch; break ;;
        debian|ubuntu|linuxmint|pop|neon|raspbian) FAMILY=debian; break ;;
        fedora|rhel|centos|rocky|almalinux|nobara) FAMILY=fedora; break ;;
        opensuse*|suse|sles) FAMILY=suse; break ;;
    esac
done
[[ -n "$FAMILY" ]] || die "unsupported distribution '${ID:-unknown}'. See README for manual package lists."

# Candidate package names per family. Several names are listed where they
# changed between Plasma 5 and 6 or between releases; only those that exist
# in your repositories are installed.
case "$FAMILY" in
    arch)
        CORE=(plasma-desktop plasma-workspace kwin plasma-nm plasma-pa kscreen
              powerdevil breeze breeze-gtk kde-gtk-config xdg-desktop-portal-kde
              konsole dolphin)
        DM=(sddm sddm-kcm)
        BT=(bluedevil)
        EXTRAS=(kate gwenview ark)
        ;;
    debian)
        CORE=(plasma-desktop plasma-workspace plasma-workspace-wayland kwin-wayland
              kwin-x11 plasma-nm plasma-pa kscreen powerdevil breeze
              breeze-gtk-theme kde-config-gtk-style xdg-desktop-portal-kde
              konsole dolphin)
        DM=(sddm sddm-theme-breeze kde-config-sddm)
        BT=(bluedevil)
        EXTRAS=(kate gwenview ark)
        ;;
    fedora)
        CORE=(plasma-desktop plasma-workspace plasma-workspace-wayland kwin
              plasma-nm plasma-pa kscreen powerdevil plasma-breeze breeze-gtk
              kde-gtk-config xdg-desktop-portal-kde konsole dolphin)
        DM=(sddm sddm-wayland-plasma sddm-breeze sddm-kcm)
        BT=(bluedevil)
        EXTRAS=(kate gwenview ark)
        ;;
    suse)
        CORE=(plasma6-desktop plasma6-workspace kwin6 plasma6-nm plasma6-pa
              kscreen6 powerdevil6 breeze6-style breeze6-wallpapers kde-gtk-config6
              xdg-desktop-portal-kde6 konsole dolphin
              plasma5-desktop plasma5-workspace plasma-nm5 plasma5-pa kscreen5
              powerdevil5 breeze5-style kde-gtk-config5 xdg-desktop-portal-kde)
        DM=(sddm-qt6 sddm sddm-conf)
        BT=(bluedevil6 bluedevil5)
        EXTRAS=(kate gwenview ark)
        ;;
esac

available() {
    local p="$1"
    case "$FAMILY" in
        arch)   pacman -Si "$p" >/dev/null 2>&1 ;;
        debian) [[ -n "$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)"')" ]] ;;
        fedora) dnf -q info "$p" >/dev/null 2>&1 ;;
        suse)   zypper --non-interactive -q search -x --match-exact "$p" >/dev/null 2>&1 ;;
    esac
}

WANT=("${CORE[@]}")
(( WITH_DM )) && WANT+=("${DM[@]}")
(( WITH_BT )) && WANT+=("${BT[@]}")
(( WITH_EXTRAS )) && WANT+=("${EXTRAS[@]}")

if [[ "$FAMILY" == debian ]] && (( ! DRY_RUN )); then
    log "Refreshing package lists"
    apt-get update -q
fi

log "Checking which packages exist on $PRETTY_NAME"
PKGS=()
for p in "${WANT[@]}"; do
    if available "$p"; then
        PKGS+=("$p")
    else
        printf '  - %s (not in your repositories, skipped)\n' "$p"
    fi
done
[[ ${#PKGS[@]} -gt 0 ]] || die "none of the packages were found. Are your repositories set up?"

case "$FAMILY" in
    arch)   CMD=(pacman -S --needed --noconfirm "${PKGS[@]}") ;;
    debian) CMD=(env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}") ;;
    fedora) CMD=(dnf install -y --setopt=install_weak_deps=False "${PKGS[@]}") ;;
    suse)   CMD=(zypper --non-interactive install --no-recommends "${PKGS[@]}") ;;
esac

log "Installing ${#PKGS[@]} packages (no recommended/weak dependencies)"
if (( DRY_RUN )); then
    printf '  [dry-run] %s\n' "${CMD[*]}"
else
    "${CMD[@]}"
fi

if (( WITH_DM )); then
    log "Enabling the SDDM login screen"
    if (( DRY_RUN )); then
        echo "  [dry-run] systemctl enable sddm.service"
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl enable sddm.service 2>/dev/null \
            || warn "could not enable sddm (another display manager may already be enabled)"
    fi
fi

log "Done."
echo "  Next steps:"
echo "    1. Reboot and pick 'Plasma' at the login screen."
echo "    2. As your normal user (not root), run: ./kdelite apply"
echo "    3. Optional, for low-RAM machines:   sudo ./zram-setup.sh"
