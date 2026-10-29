# Proot

Open replacement firmware and an iOS app for the **ProtoFrenz HUB75 controller** (board V4, ESP32, two chained 64×32 P3 panels).

- **Faces**: 8 expressions built from eye, nose and mouth parts, with scrolling gradients, natural blinking, a mouth that moves with your voice, and boop reactions. Draw your own parts pixel by pixel.
- **Animations**: pick any GIF or image on your phone. It's resized on the phone and streamed to the visor.
- **Games** on the visor, played with your phone as the controller: Snake, Paddle Duel, Brick Breaker and Comet Dodge.
- **Live drawing**, **scrolling text** and a **panel test pattern**.
- **Bluetooth LE** by default, with Wi-Fi (the visor's own hotspot or your home network) for fast uploads and firmware updates.
- Fan, NeoPixel cheeks, boop sensor, button and microphone all supported. No boot splash: the face fades straight in.
- Your old ProtoFrenz settings (expression names, presets, colors, custom drawing, fan speed, name) are imported automatically on first boot.

There's no web page in the firmware. The app is the whole interface, which keeps the firmware small.

```
firmware/   PlatformIO project (ESP32 Arduino)
app/        SwiftUI iOS app (XcodeGen project.yml)
tools/      face generators / importer
legacy/     (git-ignored) the old decompiled files
```

## Installing the firmware

> Back up your current firmware first so you can always go back to stock:
> `esptool.py --baud 115200 read_flash 0 0x800000 protofrenz-backup.bin`

**Option A: build it yourself (recommended, includes the original ProtoFrenz faces)**

```bash
pip install platformio
python3 tools/import_protofrenz_faces.py      # downloads the official v3.0.13 image and extracts its face presets
cd firmware && pio run -t upload
```

`import_protofrenz_faces.py` writes `firmware/src/faces_vendor.h`, which is git-ignored. That art belongs to ProtoFrenz, so keep it out of the repo. Without it, the firmware uses Proot's own face set (`tools/gen_default_faces.py`).

**Option B: prebuilt.** Every push builds firmware in GitHub Actions (*Actions → Firmware → proot-firmware*):

- `proot-full.bin`: first install over USB: `esptool.py --chip esp32 write_flash 0x0 proot-full.bin`
- `proot-ota.bin`: later updates from the app (Settings → Update firmware, over Wi-Fi)

Writing `proot-full.bin` at 0x0 keeps your settings partition, so the ProtoFrenz settings import still works.

## Installing the iOS app (no Xcode needed)

GitHub Actions builds an unsigned `Proot.ipa` on every push (*Actions → iOS app → Proot-ipa*). Sideload it with [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io) using a free Apple ID. Free-account installs need re-signing every 7 days; a paid developer account removes that limit.

On first launch the app scans for nearby visors over Bluetooth and reconnects to the last one automatically. *Try the demo* explores the app without a visor.

To build locally instead (needs Xcode): `brew install xcodegen && cd app && xcodegen generate && open Proot.xcodeproj`.

## Hardware (ProtoFrenz V4)

Recovered from the board table in the stock v3.0.13 firmware:

| Function | GPIO |
|---|---|
| HUB75 R1 G1 B1 / R2 G2 B2 | 25 26 27 / 14 12 13 |
| HUB75 A B C D (E unused) | 23 19 5 17 |
| HUB75 CLK / LAT / OE | 16 / 4 / 15 |
| NeoPixel cheeks | 21 |
| Boop sensor (TTP223) | 36 |
| Button (to GND) | 39 |
| Microphone (MAX9814, analog) | 35 |
| Fan PWM (25 kHz) | 18 |

Panel order, mirroring, upside-down mounting and the HUB75 driver chip can all be changed in the app.

## Protocol

The app and visor exchange JSON messages plus a few binary messages, over either transport:

- **BLE**: service `7f3e0001-4a2b-4d7e-9c1a-70726f6f7401`; write to `…0002`, notifications on `…0003`. Each packet starts with a header byte: bit 7 = binary, bit 6 = first packet, bit 5 = last packet.
- **Wi-Fi**: WebSocket at `ws://192.168.4.1/ws` (or `proot.local`); firmware upload at `POST /api/ota`.

Commands (`{"cmd": …}`): `get`, `faces`, `expr`, `next`, `setExpr`, `custom`, `set`, `mode`, `text`, `anim`, `files`, `rm`, `upStart`/`upEnd`, `game`, `key`, `meter`, `applyWifi`, `save`, `reboot`, `factoryReset`, `resetStats`. Add `"id"` to get an `ack`.
Binary: `0x01` live frame `[fmt][w][h][pixels]` (fmt bit0 = RGB332, else RGB565 LE; bit7 = mirror), `0x02` upload chunk `[u32 offset][data]`.

Animations are stored as `.pfa`: `"PFA1"`, u16 width (64 or 128), u16 height (32), u16 frame count, u8 flags (bit0 mirror), u8 0, then each frame as a u16 delay in ms followed by RGB565 pixels.
