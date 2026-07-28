# LogiOptions

A lightweight, fully local Logitech pointing-device settings app for macOS.

LogiOptions provides device settings, button and wheel assignments, gestures,
and application profiles through one Flutter UI and one native HID++ daemon. It
requires no Logitech account and has no cloud dependency.

The core goal is reliable configuration of every programmable button and wheel
reported by a supported mouse or trackball. Actions Ring is intentionally not
implemented.

## Device coverage

The project-owned registry covers the 63 mice and trackballs in Logitech's
[current Options+ supported-device list](https://support.logi.com/hc/en-gb/articles/25528092585879-Supported-devices-Logi-Options).
Discovery is not tied to MX Master 3S:

- all responsive slots on supported receivers and supported direct
  Bluetooth/USB HID++ interfaces are scanned;
- interfaces are deduplicated by stable unit ID, serial, or IORegistry identity;
- HID++ features are probed at runtime before a setting is exposed or written;
- connected and recently configured devices can be selected independently;
- HID++ 1.0 receiver devices are detected with safe, limited capability
  exposure; HID++ 2.0 devices use full runtime feature probing;
- supported models use the matching official Options+ product render and colour
  variant; a neutral fallback is reserved for missing catalog artwork.

MX Master 3S (`2b034` and `2b043`) is currently marked **Verified** after
local-hardware testing. MX Master 4 and all other models remain
**Compatible—untested** until their advertised controls pass real-hardware
validation.

### Hardware safety boundary

Discovery is a positive allowlist, not a product-name blacklist:

1. A direct interface must have an exact product ID from the official Options+
   mouse/trackball catalog, or be an exact supported receiver interface.
2. This check happens before LogiOptions opens the HID interface.
3. Devices behind a supported receiver must then report a model ID in the same
   catalog.
4. Display names are never used to decide compatibility.

Consequently, G502, G502 X, other G/LIGHTSPEED devices, and unknown future
gaming models are ignored without adding special cases for each model. They
remain available to G Hub.

## Features

- Multiple connected devices with separate configuration and recent-device
  history
- Capability-generated Buttons and Point & Scroll screens
- DPI, SmartShift, high-resolution wheel, inversion, and speed
- Thumb-wheel scrolling or paired directional actions
- Mouse actions, navigation, undo/redo, clipboard, tabs, zoom, screenshots,
  media, system actions, app/file/URL launch, shortcuts, and gestures
- Global and sparse per-application profiles with per-setting inheritance
- Searchable installed-application picker with native icons and Browse
- Config v1 → v3 migration that preserves existing MX Master 3S assignments
- Revision-checked typed RPC writes, structured errors, optimistic rollback,
  and debounced continuous controls
- Battery, connection, transport, and verification state
- Optional login agent and explicit daemon start/stop controls
- Official Options+ product renders with per-model colour variants and
  per-chassis control hotspots

MX Master 4 additionally exposes its sixth Haptic Sense control, haptic level,
power saving, and force threshold. The Haptic Sense control can use the same
action catalogue as every other programmable control.

Finder Back and Forward assignments use Finder history shortcuts, while other
applications retain auxiliary mouse navigation. Opening the app checks existing
Accessibility trust without repeatedly reopening System Settings.

The daemon checks Accessibility trust whenever it starts and reports a missing
grant again if permission was removed. It does not repeatedly open System
Settings after permission has already been granted.

## Quick start

Official Options+ and LogiOptions cannot share exclusive HID++ access. If
Options+ is still installed or left running:

```bash
./tools/stop_options_plus.sh
```

Build and open a debug app:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
./scripts/mac-debug.sh
open dist/LogiOptions.app
```

Grant Accessibility to `LogiOptions` and `LogiOptionsDaemon` in System Settings
→ Privacy & Security → Accessibility. Input Monitoring is not required for
normal use.

Building a new app does not replace an already running daemon. When testing an
upgrade, verify the process path first and transition once to the daemon
embedded in the new app; avoid repeatedly toggling an older daemon that predates
the hardware-safety allowlist.

| Runtime data | Location |
|---|---|
| Settings | `~/Library/Application Support/LogiOptions/config.json` |
| Daemon socket | `/tmp/logioptions.sock` |
| Daemon logs | `/tmp/logioptions.daemon.out.log`, `/tmp/logioptions.daemon.err.log` |

## Architecture

```text
┌──────────────────────────────┐       typed JSON-RPC
│ LogiOptions.app              │ ◄─────────────────────────┐
│ devices, profiles, settings  │   /tmp/logioptions.sock   │
└──────────────────────────────┘                            │
                                                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│ DeviceService                                                       │
│ discovery · stable identity · capabilities · events · live state    │
├────────────────────────┬───────────────────────┬────────────────────┤
│ HID++ 2 adapter        │ HID++ 1 / receiver   │ Fake test adapter  │
└────────────┬───────────┴───────────┬───────────┴────────────────────┘
             └───────────────────────┴────────────► mice / trackballs
```

`DeviceService` is the deep boundary: UI, RPC, configuration, and action code
do not know receiver slots or IOHID interface details. The same interface drives
the production adapters and deterministic tests.

## Development and validation

```bash
cd app/macos/LogiOptionsDaemon
swift test

cd ../../..
flutter analyze
flutter test
flutter build macos --release
```

The release helper can build, sign, notarize, package, and publish:

```bash
./scripts/mac-release.sh --no-upload
```

Project layout:

```text
app/                           Flutter macOS UI
app/macos/LogiOptionsDaemon/   Swift daemon and tests
docs/                          Protocol and clean-room research notes
tools/                         Options+ lifecycle and HID diagnostics
scripts/                       Debug and release packaging
```

## Clean-room policy

Installed Options+ catalogs and official downloadable depots are used to learn
factual device IDs, capabilities, control metadata, protocol behaviour, and to
source the device product renders requested by this project. The app bundles
only the selected product-render PNGs; Logitech executables, keys, raw catalogs,
and depot archives are not shipped. Protocol fixtures contain only sanitized
request/response bytes.

See [reverse-engineering notes](docs/reverse-engineering.md),
[HID++ notes](docs/hidpp-mx-master-3s.md), and
[Options+ teardown](docs/teardown-options-plus.md).

## Scope

This release targets Options+-supported mice and trackballs. Keyboards,
cameras, lights, presenters, Flow, pairing, Easy-Switch management, and firmware
updates are outside the current scope. Discovery uses the exact direct-product
and receiver IDs from the Options+ pointing-device catalog as a positive
allowlist before opening an HID interface. Logitech G/LIGHTSPEED gaming devices
therefore remain untouched without relying on a `G502`-specific name or product
blacklist.

Not affiliated with Logitech. App code license: TBD. HID++ knowledge was
independently reimplemented from public documentation, observable device
behaviour, and upstream protocol implementations; no third-party GPL source is
vendored.
