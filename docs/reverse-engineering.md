# Reverse Engineering Notes — Logi Options+ → MX Master 3S

Captured from the installed Options+ **2.5.926888** on this Mac (2026-07-24).

## Process architecture

| Component | Path / identity | Role |
|-----------|-----------------|------|
| Electron UI | `/Applications/logioptionsplus.app` | Settings UI only |
| Native agent | `logioptionsplus_agent` (LaunchAgent `com.logi.cp-dev-mgr`) | HID++, remaps, macros, focus |
| LogiVoice | `logioptionsplus_logivoice` | Voice features (unneeded) |
| Updater | `logioptionsplus_updater` | Auto-update |

IPC: Unix sockets `/tmp/logitech_kiros_agent-*`, TCP listen port (ephemeral).

Agent binary contains Logitech **`devio`** HID++ stack (`MacOSBus`, `MacOSDevice`, `IFeatureXXXX…`) over **IOHIDManager**.

## Device identity

- **Display name:** MX Master 3S  
- **modelId:** `2b034`  
- **Slot prefix:** `mx-master-3s-2b034`  
- **Depot package:** `/Library/Application Support/Logi/LogiOptionsPlus/depots/*/mx_master_3s/`  
- User device serial (this machine): `2331LZ52HFS8`  
- Connection types observed: **BLE_PRO**, Logi **Bolt** receiver `c547`

## Control IDs (Special Keys 0x1B04)

| CID | Decimal | Slot |
|-----|---------|------|
| 0x52 | 82 | Middle / wheel click |
| 0x53 | 83 | Back |
| 0x56 | 86 | Forward |
| 0xC3 | 195 | Gesture (thumb) |
| 0xC4 | 196 | Mode-shift (top) |

UI geometry: `core_metadata.json` in the device depot.

## HID++ features we implement

| ID | Name | Use |
|----|------|-----|
| 0x0000 | Root | GetFeature |
| 0x0001 | FeatureSet | Enumerate |
| 0x1B04 | ReprogControlsV4 / SpecialKeys | Divert buttons |
| 0x2110 / 0x2111 | SmartShift | MagSpeed ratchet |
| 0x2121 | HiResWheel | Hi-res / invert |
| 0x2150 | Thumbwheel | Divert / invert |
| 0x2201 / 0x2202 | Adjustable DPI | Sensor DPI |
| 0x1000 / 0x1004 | Battery | Level |

Protocol knowledge primarily from [Solaar](https://github.com/pwr-Solaar/Solaar) (GPL) and public HID++ 2.0 docs — not from decompiling the agent.

## Settings store

`~/Library/Application Support/LogiOptionsPlus/settings.db`  
Table `data.file` is a large JSON document: profiles, applications, battery cache, easy_switch hosts.

## Exclusive access

Only one process should open HID++ vendor reports. Stop official Options+ before running LogiOptions (see `teardown-options-plus.md`).
