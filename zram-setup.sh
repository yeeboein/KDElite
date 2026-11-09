#!/usr/bin/env bash
# KDElite zram setup: compressed swap in RAM. On a 4 GB machine this
# typically lets you keep 1.5-2x more open before things slow down.
#
#   sudo ./zram-setup.sh [--dry-run]      set up zram + memory tuning
#   sudo ./zram-setup.sh --remove         undo
set -euo pipefail

ZRAM_CONF=/etc/systemd/zram-generator.conf
SYSCTL_CONF=/etc/sysctl.d/99-kdelite.conf
MARK="# Managed by KDElite"
DRY_RUN=0 REMOVE=0

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if (( DRY_RUN )); then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1 ;;
        --remove) REMOVE=1 ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done
(( DRY_RUN )) || [[ $EUID -eq 0 ]] || die "run as root (e.g. sudo $0), or use --dry-run"
command -v systemctl >/dev/null 2>&1 || die "systemd is required"

write_file() {  # write_file <path> <content>
    if (( DRY_RUN )); then
        printf '  [dry-run] write %s:\n' "$1"; printf '%s\n' "$2" | sed 's/^/      /'
        return
    fi
    if [[ -e "$1" ]] && ! grep -q "^$MARK" "$1"; then
        cp -a "$1" "$1.kdelite-backup"
        warn "existing $1 saved as $1.kdelite-backup"
    fi
    printf '%s\n' "$2" > "$1"
}

if (( REMOVE )); then
    log "Removing KDElite zram settings"
    for f in "$ZRAM_CONF" "$SYSCTL_CONF"; do
        if [[ -e "$f" ]] && grep -q "^$MARK" "$f"; then
            run rm -f "$f"
            [[ -e "$f.kdelite-backup" ]] && run mv "$f.kdelite-backup" "$f"
        fi
    done
    run systemctl daemon-reload
    run sysctl --system >/dev/null
    log "Removed. Reboot to switch zram off completely."
    exit 0
fi

# zram-generator ships with systemd on most distros as a separate package.
if [[ ! -x /usr/lib/systemd/system-generators/zram-generator ]] \
    && [[ ! -x /lib/systemd/system-generators/zram-generator ]]; then
    log "Installing zram-generator"
    if   command -v pacman  >/dev/null; then run pacman -S --needed --noconfirm zram-generator
    elif command -v apt-get >/dev/null; then run apt-get install -y systemd-zram-generator
    elif command -v dnf     >/dev/null; then run dnf install -y zram-generator
    elif command -v zypper  >/dev/null; then run zypper --non-interactive install zram-generator
    else die "install zram-generator with your package manager, then re-run"
    fi
fi

log "Configuring zram (half of RAM, max 8 GiB, zstd compression)"
write_file "$ZRAM_CONF" "$MARK
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100"

log "Tuning the kernel for zram"
write_file "$SYSCTL_CONF" "$MARK
# Swapping to compressed RAM is cheap, so prefer it over dropping file cache.
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125"

run systemctl daemon-reload
run systemctl start systemd-zram-setup@zram0.service || warn "zram will start after a reboot"
run sysctl --system >/dev/null
log "Done. Check with: zramctl   (or swapon --show)"
