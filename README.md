# LogiOptions

**A lightweight, fully local replacement for Logi Options+ on macOS.**

Official Options+ is a large always-on stack (agents, updaters, cloud/AI surfaces, voice extras). LogiOptions keeps what you need for daily mouse work—DPI, MagSpeed, remaps, gestures, profiles—in a small Flutter UI and a single background daemon. No account, no marketplace, no cloud.

| | Official Options+ | LogiOptions |
|--|--|--|
| Footprint | Heavy multi-process agent suite | One UI + one HID++ daemon |
| Network / account | Cloud-oriented product surface | **100% local** |
| Device control | Proprietary agents | Open HID++ 2.0 (Bolt + BLE) |
| After UI quit | Agents often stay | Daemon can stay; Dock icon goes away with the window |
| Scope today | Full Logitech lineup | **MX Master 3S** first (`2b034`) |

---

## Why replace Options+

- **Lighter** — no parallel Options+ agents fighting for exclusive HID++ access  
- **Private** — settings live on disk under your home directory  
- **Controllable** — start/stop the daemon from Settings; optional login agent  
- **Familiar** — Options+-style device art and 4-way gesture button, without the bloat  

Stop official Options+ before using LogiOptions (they cannot share exclusive HID++):

```bash
./tools/stop_options_plus.sh
```

Restore it anytime after quitting our daemon:

```bash
# Settings → Stop background daemon, or:
pkill -x LogiOptionsDaemon
./tools/start_options_plus.sh
```

---

## Features (MX Master 3S)

- **Pointer** — DPI  
- **MagSpeed** — SmartShift, hi-res host scroll, invert, speed  
- **Thumb wheel** — diverted horizontal scroll, invert, speed  
- **Buttons** — remaps (mouse, key chords, system actions)  
- **Gesture (0xC3)** — 4-way + click (Mission Control, Spaces, App Exposé, …)  
- **Profiles** — global + per-app focus  
- **Battery** — level / charging  
- **Daemon lifecycle** — survives UI close; optional **start at login**; explicit **Stop**  

Transports: **Logi Bolt** (USB receiver) and **BLE Pro**.

---

## Quick start (debug)

```bash
./tools/stop_options_plus.sh

# Recommended: same Developer ID as release so Accessibility grants stick
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"

./scripts/mac-debug.sh
open dist/LogiOptions.app
```

Grant **Accessibility** to **LogiOptions** and **LogiOptionsDaemon**  
(System Settings → Privacy & Security → Accessibility).  
Input Monitoring is **not** required for normal use.

### Config & socket

| | |
|--|--|
| Settings | `~/Library/Application Support/LogiOptions/config.json` |
| Daemon socket | `/tmp/logioptions.sock` |
| Daemon logs | `/tmp/logioptions.daemon.out.log`, `/tmp/logioptions.daemon.err.log` |

---

## Release (signed + notarized DMG)

```bash
# One-time notarization profile (app-specific Apple ID password)
xcrun notarytool store-credentials LogiOptions \
  --apple-id you@example.com --team-id TEAMID --password 'xxxx-xxxx-xxxx-xxxx'

export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
gh auth login   # once — needed to publish GitHub Releases

./scripts/mac-release.sh              # version from app/pubspec.yaml → build, notarize, publish
./scripts/mac-release.sh 1.2.0        # explicit version → dist/LogiOptions-1.2.0.dmg + GitHub release
./scripts/mac-release.sh --no-notarize
./scripts/mac-release.sh --no-upload  # local DMG only (no GitHub)
./scripts/mac-release.sh --draft      # draft GitHub release
```

Outputs:

- `dist/LogiOptions.app`  
- `dist/LogiOptions-<version>.dmg`  
- GitHub Release `v<version>` on the `origin` remote (override with `GITHUB_REPO=owner/name`) with the DMG attached

---

## Architecture

```
┌─────────────────────┐     JSON-RPC      ┌──────────────────────┐
│  LogiOptions.app    │ ◄───────────────► │  LogiOptionsDaemon   │
│  (Flutter UI)       │  /tmp/…sock       │  (Swift, HID++)      │
└─────────────────────┘                   └──────────┬───────────┘
                                                     │ exclusive HID
                                                     ▼
                                              MX Master 3S
                                           (Bolt / BLE Pro)
```

- **UI** — configuration, device art, Settings (login agent / stop daemon)  
- **Daemon** — HID++, remaps, gestures, host scroll; can run without Dock icon  
- Closing the last window **quits the UI only**; remaps/scroll keep working if the daemon is still up  

---

## Project layout

```
docs/                          Reverse engineering, HID++ notes, Options+ teardown
tools/                         stop/start Options+, HID probe, run_daemon
scripts/mac-debug.sh           Debug build → dist/LogiOptions.app
scripts/mac-release.sh         Release build, sign, notarize, DMG
app/                           Flutter macOS UI
app/macos/LogiOptionsDaemon/   Swift daemon (embedded under Contents/Helpers/)
dist/                          Build products (gitignored)
```

## Docs

- [Reverse engineering](docs/reverse-engineering.md)  
- [HID++ MX Master 3S](docs/hidpp-mx-master-3s.md)  
- [Teardown Options+](docs/teardown-options-plus.md)  

---

## Status

Actively used as a day-to-day Options+ stand-in for **MX Master 3S**. Core pointer, scroll, remaps, gestures, profiles, and daemon lifecycle are in place. More Logitech models may follow the same HID++ path later.

---

## License

App code: license TBD. HID++ knowledge reimplemented from community documentation and patterns similar to Solaar/logiops (we do **not** vendor their GPL source). **Not affiliated with Logitech.**
