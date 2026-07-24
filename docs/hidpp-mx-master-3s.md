# HID++ 2.0 — MX Master 3S feature notes

Byte order for multi-byte fields: **big-endian** unless noted.

## Reports

| Report ID | Size | Use |
|-----------|------|-----|
| 0x10 | 7 bytes | Short HID++ |
| 0x11 | 20 bytes | Long HID++ |

Layout (after report ID):

```
device_index: 1 byte   # 0xFF for direct BLE; 0x01+ for receiver slots
address:      1 byte   # (feature_index << 4) wait NO:
# Correct HID++ 2.0:
# byte0: device_index
# byte1: feature_index
# byte2: function_id (high nibble) | software_id (low nibble)
# byte3+: params
```

Actually Solaar packs request as:

- Short: `0x10 | device_index | (featureIndex << 8 | function | swId) | params…`  
- Long:  `0x11 | …` padded to 20 bytes  

Feature request address = `(feature_index << 8) | function | software_id` where software_id is low 4 bits of the third byte.

## Root 0x0000

- **fn 0x00 GetFeature(featureId: u16)** → `index: u8, type: u8, version: u8`  
  Index 0 means not present.

## FeatureSet 0x0001

- **fn 0x00 GetCount** → count (ROOT excluded; total features ≈ count+1)  
- **fn 0x10 GetFeatureId(index)** → featureId:u16, type, version  

## Battery Unified 0x1004

- **fn 0x00 get_status** → dischargeLevel (%), nextLevel, status flags  

## Adjustable DPI 0x2201

- **fn 0x10 getSensorDpi(sensor=0)** → sensor, dpi:u16, …  
- **fn 0x20 setSensorDpi(sensor, dpi:u16)**  

## Extended Adjustable DPI 0x2202

Prefer when present (MX Master 3S often has this).

- Similar get/set; supports more levels / default DPI lists.

## SmartShift 0x2110

- **fn 0x00 getRatchetSwitchSetting** → wheelMode, autoDivert, torque?  
- **fn 0x10 setRatchetSwitchSetting**  

0x2111 adds tunable torque.

## HiRes Wheel 0x2121

- **fn 0x10 getWheelMode**  
- **fn 0x20 setWheelMode** — multi / hires / invert / target bits  

## Thumbwheel 0x2150

- **fn 0x00 getThumbwheelInfo**  
- **fn 0x10 getThumbwheelStatus**  
- **fn 0x20 setThumbwheelReporting** — divert, invert, reporting  

## ReprogControls V4 0x1B04

- **fn 0x00 getControlsCount**  
- **fn 0x10 getCidInfo(index)** → cid, taskId, flags…  
- **fn 0x20 getCidReporting(cid)**  
- **fn 0x30 setCidReporting(cid, flags, remap)** — divert bit 0x01 (+ valid 0x02)  

Diverted presses arrive as HID++ notifications on the feature index.

## Transports on macOS

| Path | Notes |
|------|--------|
| Bolt USB | Vendor 0x046D, receiver product often 0xC547/C548; device via receiver index |
| BLE Pro | Direct HID device; device_index often 0xFF |

Probe tools under `tools/` list matching IOHID devices.

## Live probe result (this machine, Bolt C548)

```
HID++ OK  device_index=0x01  FeatureSet@1 v2
UNIFIED_BATTERY 0x1004 v3  → e.g. 15%
ADJUSTABLE_DPI  0x2201 v2  → e.g. 1000 dpi
SMART_SHIFT     0x2110 v0  → mode=2 thr=10
HIRES_WHEEL     0x2121 v1
THUMB_WHEEL     0x2150 v0
REPROG_CONTROLS_V4 0x1B04 v5
CHANGE_HOST     0x1814 v1
```

HID++ interface: usage page `FF00:0001` on the Bolt receiver.
