# KDElite

A version of KDE Plasma for Linux that doesn't use as much RAM.

KDElite is not a fork of Plasma. A fork would fall behind on security fixes
within weeks. Instead it takes the real KDE Plasma from your distribution and:

1. **Installs only the core** of Plasma: no PIM suite, Akonadi database,
   Discover, KDE Connect, games or office apps.
2. **Switches off the memory-hungry background parts** of an existing Plasma
   install, with a backup so you can undo it in one command.
3. **Optionally sets up zram**: compressed swap in RAM, the most effective
   fix for machines with 4 GB or less.

## Quick start

```bash
git clone https://github.com/yeeboein/KDElite.git
cd KDElite

# Fresh system or no Plasma yet: install the minimal desktop (needs root)
sudo ./install-minimal.sh

# Then log into Plasma and, as your normal user (NOT sudo):
./kdelite status          # see how much RAM KDE uses now
./kdelite apply           # slim it down
# log out and back in
./kdelite status          # compare
```

Undo everything with `./kdelite revert`.

Every command takes `--dry-run`, which shows exactly what would change
without touching anything.

## What `kdelite apply` turns off

| Component | Why it uses RAM | What you lose |
|---|---|---|
| **Baloo** file indexer | Indexes the contents of every file in your home folder, all the time | Full-text file search in Dolphin and the launcher (searching by file *name* still works) |
| **Akonadi** (stopped) | PIM storage with its own database server | Nothing, unless you use KMail/KOrganizer. They start it again when opened |
| **KWin effects**: blur, translucency, wobbly windows, animations, ... | Extra GPU/compositor buffers and shaders | Eye candy. Windows open and close instantly |
| **Splash screen** | Loaded on every login | The logo animation at login |
| **kded modules**: browser-integration reminder, Samba watcher, online accounts, donation popup, RGB keyboard, ... | Each one loads into the KDE background daemon | Nags and features most people never use |
| **KRunner plugins**: file-content search, software-center search, browser tabs/history | The software-center plugin loads the whole app catalog into memory | Searching for uninstalled apps from the launcher |
| **Autostart**: Discover update notifier, KDE Connect, Welcome Center, calendar reminders | Separate processes running all session long | Update popups (update with your package manager instead), phone pairing |

### `kdelite apply --aggressive`

Also turns off these. Skip this if you need any of them:

- Bluetooth (`bluedevil`), printer manager, Wacom tablet support
- Low-disk-space warnings, accent color from wallpaper, automatic timezone,
  plug-in sounds and popups for devices
- Accessibility daemon (`kaccess`). **Don't use this if you rely on sticky
  keys, a screen reader, etc.**
- Legacy tray icons (`xembedsniproxy`, used by old X11 and Wine apps) and the
  GTK global menu proxy
- "Recent files" and "frequent apps" tracking
- Session restore: login starts an empty desktop instead of reopening apps
- On X11 sessions only: the compositor

## What `install-minimal.sh` installs

Plasma desktop and window manager, network and sound applets, display
settings, power management, the Breeze theme (including for GTK apps), the
Konsole terminal, the Dolphin file manager and the SDDM login screen. It uses
`--no-install-recommends` (or the equivalent) so nothing extra comes along.

Supported: **Arch** (and Manjaro, EndeavourOS, CachyOS), **Debian/Ubuntu**
(and Mint, Pop!_OS, KDE neon), **Fedora**, **openSUSE**. The installer checks
which package names your release actually has and skips missing ones.

| Option | Effect |
|---|---|
| `--no-dm` | Skip SDDM (for example, if you already use another login screen) |
| `--bluetooth` | Add Bluetooth support |
| `--extras` | Add Kate (text editor), Gwenview (images) and Ark (archives) |

## zram (recommended for 8 GB of RAM or less)

```bash
sudo ./zram-setup.sh            # set up
sudo ./zram-setup.sh --remove   # undo
```

This creates a compressed swap device in RAM, sized at half your memory and
capped at 8 GiB, using zstd compression. It also tunes the kernel to prefer
it. Data in zram usually compresses to about a third of its size, so the
system can hold much more before it slows down. Fedora already enables zram
by default; this script still applies the kernel tuning there.

## More tips

- **Widgets cost memory.** Every Plasma widget runs inside `plasmashell`.
  Remove the ones you don't use, especially weather, system monitor graphs
  and media players.
- **Use a static wallpaper**, not a slideshow or animated plugin.
- **Your browser is probably the biggest RAM user.** Turn on tab sleeping /
  memory saver in your browser's settings.
- Run `./kdelite status` to see which process is actually using the memory.

## How it works and how undo works

`kdelite` only changes files under `~/.config` (and, with `--aggressive`,
masks two systemd *user* units). It edits them with KDE's own
`kwriteconfig5`/`kwriteconfig6`, so it works on Plasma 5 and Plasma 6.
Before changing a file it copies it to
`~/.local/share/kdelite/backup-<date>/`. `kdelite revert` copies the
originals back, deletes files that didn't exist before, unmasks the units
and turns file indexing back on if it was on before.

Nothing outside your home folder is changed except by `install-minimal.sh`
and `zram-setup.sh`, which you run with `sudo`.

## Tests

```bash
tests/run.sh
```

Runs `apply --aggressive` and then `revert` in a throwaway home folder, and
checks that every file comes back byte-for-byte identical.
