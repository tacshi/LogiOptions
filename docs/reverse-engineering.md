# Clean-room protocol and catalog research

This document records the boundary between factual compatibility research and
shipped LogiOptions code/assets.

## Sources and handling

- Logitech's
  [Options+ supported-device list](https://support.logi.com/hc/en-gb/articles/25528092585879-Supported-devices-Logi-Options)
  defines the current pointing-device scope.
- Logitech's
  [MX Master 4 setup documentation](https://support.logi.com/hc/en-hk/articles/28321445268247-Getting-Started-MX-Master-4)
  defines the advertised Haptic Sense behaviour.
- A leftover local `devices.json` catalog was used to enumerate factual model
  names and IDs. It is not copied into the repository or app bundle.
- Official device depots were inspected for protocol research and matching
  product renders. Depot archives were not installed or committed; only the
  selected device-render PNGs used by the UI are bundled.
- Public HID++ implementations, especially Solaar, were consulted for request
  framing and feature semantics. LogiOptions independently implements the
  protocol and does not vendor their source.

Do not commit Logitech binaries, encrypted depot archives, keys, raw catalogs,
settings databases, or serial numbers. Official product-render PNGs may be
added only when they map to a supported catalog model/colour and are referenced
by the UI. Sanitized protocol fixtures may contain only request/response bytes
needed by a unit test.

## Observed Options+ architecture

The previously installed Options+ build used an Electron settings UI, a native
device-management agent, voice components, and an updater. The agent owned
vendor HID reports through IOHID and maintained its own application/profile
database. Only one device manager can reliably own the HID++ report interface,
so Options+ must be stopped before LogiOptions controls the same hardware.

## Device identity

Stable identity priority in LogiOptions is:

1. HID++ unit ID
2. device or receiver-pairing serial
3. IORegistry interface identity
4. model + receiver slot only as a migration fallback

Exact Options+ catalog product IDs and known Options+ receiver IDs are checked
before any HID interface is opened. Direct Bluetooth/USB interfaces and all six
responsive receiver slots passing that allowlist are probed. Duplicate
interfaces with the same stable identity are collapsed. This keeps G-series
gaming devices untouched without maintaining a model-name blacklist.

The project registry contains model names, model IDs, expected controls, DPI
ranges, chassis keys, and known capabilities. Those entries are hints; runtime
HID++ probing remains authoritative for exposed and writable settings.

## Implemented protocol surfaces

| Feature | ID / register | Use |
|---|---:|---|
| Root / FeatureSet | `0x0000` / `0x0001` | HID++ 2 probing |
| Device info / name | `0x0003` / `0x0005` | stable identity and display |
| Battery | `0x1000`, `0x1004` | level and charging |
| Reprogrammable controls | `0x1B04` | controls, diversion, raw gesture movement |
| SmartShift | `0x2110`, `0x2111` | ratchet/free-spin settings |
| High-resolution wheel | `0x2121` | resolution, inversion, diversion |
| Thumb wheel | `0x2150` | scrolling or directional actions |
| Adjustable DPI | `0x2201`, `0x2202` | sensor resolution |
| Haptics | `0x19B0` | MX Master 4 level and selection waveform |
| Force sensing | `0x19C0` | MX Master 4 threshold |
| HID++ 1 battery | registers `0x07`, `0x0D` | safe legacy status |
| Receiver pairing info | register `0x2B5` | slot model and serial identity |

MX Master 4 request bytes used by tests are sanitized protocol fixtures. They
do not include any device serial, encryption material, package content, or
Logitech asset.

## Artwork

Device views use official Options+ product-render PNGs selected by exact model
ID and extended-model colour variant. MX Master 3 and MX Master 3S use their
full-resolution editor renders; other supported models use the corresponding
catalog thumbnail. If an official colour asset is unavailable, the UI falls
back to that model's official core render and only then to a neutral drawing.

## Verification

Compatibility means the model is in the official scope and its runtime HID++
features can be safely probed. It does not imply hardware validation.

- MX Master 3S (`2b034`, `2b043`): Verified
- MX Master 4 and all other registry entries: Compatible—untested

Promote a model to Verified only after its controls and every advertised feature
pass a physical-device test.
