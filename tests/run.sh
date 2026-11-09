#!/usr/bin/env bash
# Runs kdelite apply/revert against a throwaway $HOME with a stub
# kwriteconfig6, and checks that revert restores everything exactly.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/.config/autostart" "$T/xdg/autostart"

# Minimal INI writer/reader standing in for kwriteconfig6/kreadconfig6.
cat > "$T/bin/kwriteconfig6" <<'PY'
#!/usr/bin/env python3
import sys, configparser
a = sys.argv[1:]; f = a[a.index('--file')+1]; g = a[a.index('--group')+1]
k = a[a.index('--key')+1]; v = a[-1]
c = configparser.RawConfigParser(); c.optionxform = str; c.read(f)
if not c.has_section(g): c.add_section(g)
c.set(g, k, v)
with open(f, 'w') as fh: c.write(fh, space_around_delimiters=False)
PY
cat > "$T/bin/kreadconfig6" <<'PY'
#!/usr/bin/env python3
import sys, configparser
a = sys.argv[1:]; f = a[a.index('--file')+1]; g = a[a.index('--group')+1]
k = a[a.index('--key')+1]; d = a[a.index('--default')+1] if '--default' in a else ''
c = configparser.RawConfigParser(); c.optionxform = str; c.read(f)
print(c.get(g, k, fallback=d))
PY
chmod +x "$T/bin/"*

# Pre-existing user config that must survive the round trip.
printf '[Plugins]\nblurEnabled=true\n[Other]\nkeep=me\n' > "$T/home/.config/kwinrc"
printf '[Desktop Entry]\nName=KDE Connect\nExec=kdeconnectd\n' > "$T/home/.config/autostart/org.kde.kdeconnect.daemon.desktop"
touch "$T/xdg/autostart/org.kde.discover.notifier.desktop" "$T/xdg/autostart/kaccess.desktop"
before="$(cd "$T/home" && find . -type f -exec sha256sum {} + | sort)"

export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/data" \
       XDG_CONFIG_DIRS="$T/xdg" PATH="$T/bin:/usr/bin:/bin"
fail() { echo "FAIL: $*"; exit 1; }

"$ROOT/kdelite" apply --dry-run --aggressive --no-stop > "$T/dry.log"
[[ ! -e "$T/data/kdelite" ]] || fail "dry run wrote state"
[[ "$(cd "$T/home" && find . -type f -exec sha256sum {} + | sort)" == "$before" ]] || fail "dry run changed files"

"$ROOT/kdelite" apply --aggressive --no-stop > "$T/apply.log"
c="$XDG_CONFIG_HOME"
grep -q '^blurEnabled=false' "$c/kwinrc"                       || fail "blur not disabled"
grep -q '^keep=me' "$c/kwinrc"                                 || fail "existing key lost"
grep -q '^Indexing-Enabled=false' "$c/baloofilerc"             || fail "baloo not disabled"
grep -q '^AnimationDurationFactor=0' "$c/kdeglobals"           || fail "animations not off"
grep -A1 'Module-bluedevil' "$c/kded6rc" | grep -q 'autoload=false' || fail "aggressive kded"
grep -q '^Hidden=true' "$c/autostart/org.kde.discover.notifier.desktop" || fail "autostart not hidden"
grep -q '^Hidden=true' "$c/autostart/org.kde.kdeconnect.daemon.desktop" || fail "user autostart not hidden"
grep -q '^Exec=kdeconnectd' "$c/autostart/org.kde.kdeconnect.daemon.desktop" || fail "user autostart clobbered"
[[ ! -e "$c/autostart/org.kde.kalendarac.desktop" ]]           || fail "created override for missing app"
"$ROOT/kdelite" status > "$T/status.log"                       || fail "status failed"

"$ROOT/kdelite" revert > "$T/revert.log"
after="$(cd "$T/home" && find . -type f -exec sha256sum {} + | sort)"
[[ "$after" == "$before" ]] || { diff <(echo "$before") <(echo "$after"); fail "revert not exact"; }
echo "PASS"
