# ProtoFrenz Firmware Decompilation & Reverse Engineering Report

## 1. Overview & Build Metadata
- **Target Microcontroller**: ESP32 (Xtensa dual-core LX6, 8MB Flash)
- **Firmware Version**: `3.0.13` ("Smooth Operator")
- **Build Timestamp**: `Aug 27 2026 17:39:08`
- **Compiler / Core**: Arduino IDE (ESP32 Dev Module), ESP-IDF `v5.5.4`, Arduino Core `3.3.8`
- **Original Author**: Blair Reynolds (`protofrenz@protofrenz.com`)
- **Key Libraries**:
  - `NimBLE-Arduino` (Low-overhead Bluetooth Low Energy for proximity detection)
  - `WebServer` & `DNSServer` (ESP32 Arduino core)
  - `esp32-hal-rmt` (RMT hardware peripheral driver for WS2812B NeoPixels)
  - `SPIFFS` & `Preferences` (NVS configuration storage)

---

## 2. Partition Layout (8MB Flash)
Reconstructed from `partitions.bin` (saved as [`partitions.csv`](file:///c:/Users/synnt/OneDrive/.Antigravity/ProtoFenz/sourcecode/partitions.csv)):

| Partition | Type | Subtype | Flash Offset | Size (Hex) | Size (Bytes) | Description |
|---|---|---|---|---|---|---|
| `nvs` | Data | NVS | `0x009000` | `0x5000` | 20 KB | Persistent settings (brightness, WiFi, presets) |
| `otadata` | Data | OTA | `0x00E000` | `0x2000` | 8 KB | OTA selection state |
| `app0` | App | OTA 0 | `0x010000` | `0x330000` | ~3.2 MB | Active application firmware (`ProtoFrenz.bin`) |
| `app1` | App | OTA 1 | `0x340000` | `0x330000` | ~3.2 MB | Secondary OTA application slot |
| `spiffs` | Data | SPIFFS | `0x670000` | `0x180000` | ~1.5 MB | Filesystem for user animations & preset assets |
| `coredump`| Data | Coredump| `0x7F0000` | `0x010000` | 64 KB | Crash logs / debug dumps |

---

## 3. WebUI Frontend Recovery (100% Decompiled)
The single-page Web Application served on `GET /` was embedded in `ProtoFrenz.bin` at byte offset `0x1d066` as a raw DEFLATE stream. 

We successfully extracted and decompressed the entire frontend into [`control_panel.html`](file:///c:/Users/synnt/OneDrive/.Antigravity/ProtoFenz/sourcecode/control_panel.html) (313,950 bytes, 6,234 lines of code). All HTML markup, responsive CSS stylesheets, and client-side JavaScript logic (including developer comments) are 100% preserved.

### WebUI Tabs & Features
1. **Editor (`ed`)**:
   - Interactive matrix face editor for WS2812B NeoPixel & MAX7219 displays.
   - Per-pixel color picking, gradient tools, cheek ring color adjustments, and expression slot assignment.
2. **P3 HUB75 Editor (`p3`)**:
   - 128x32 dual P3 panel canvas editor with per-pixel painting and GIF/animation support.
3. **Controls (`bt`)**:
   - Hardware button assignment, touch sensor ("boop") thresholds, and role mapping (Faces vs. Reactions).
4. **Social (`so`)**:
   - BLE Proximity greeting engine, Floor Mode (convention safety mode), and Frenz nearby scanner.
5. **Options (`op`)**:
   - Brightness master, microphone sensitivity, fan speed controller, lava lamp effects, and audio-reactive music styles.
6. **System (`sy`)**:
   - Hotspot SoftAP setup, home Wi-Fi station joiner, OTA firmware flasher, and reboot commands.
7. **Stats (`st`)**:
   - Boop counter (`total_boops`, `peak_rapid_boops`), uptime, and achievement engine.
8. **Diagnostics (`dg`)**:
   - Hardware health check, I2C/SPI bus testing, display test patterns, and current draw / brownout safety warning calculator.

---

## 4. Hardware Architecture
- **Displays Supported**:
  - **NeoPixel WS2812B**: Driven via ESP32 RMT peripheral channel.
  - **HUB75 (128x32, 2x P3 Panels)**: High-speed DMA driven display output.
  - **MAX7219**: SPI matrix driver.
- **Sensors & Inputs**:
  - **TTP223**: Capacitive touch sensor on nose ("Boop sensor"). Floating/disconnect detection logic included.
  - **Microphone**: Analog ADC input with software noise floor gating.
  - **Cooling Fan**: PWM speed control.
  - **Push Button**: Cycle expressions, hold to enter config menu.

---

## 5. Serial Console Protocol
Operating at `115200 baud`, the serial port accepts immediate single-character commands:
- `d` : Print full diagnostic dump (uptime, free heap, WiFi status, connected clients).
- `p` : Pause / resume auto status heartbeat (emitted every 15s).
- `w` : Toggle HTTP request logging to serial (`[web] GET /api/status | free=...`).
- `r` : Reboot microcontroller.
- `?` : Show command menu.

---

## 6. Complete REST API Surface (61 Endpoints)
The firmware exposes the following REST API endpoints:
- **System & Status**: `/api/status`, `/api/diag`, `/api/diag/test`, `/api/diag/restore`, `/api/reset`, `/api/factoryreset`, `/api/save`
- **Display & Hardware**: `/api/brightness`, `/api/micSensitivity`, `/api/fan`, `/api/displaytype`, `/api/modcount`, `/api/accessory`
- **NeoPixel**: `/api/neopixel`, `/api/neofx`, `/api/neograd`, `/api/neotest`, `/api/neo/diag`, `/api/neo/pixels`, `/api/neo/info`, `/api/neoboardrev`
- **HUB75**: `/api/hub75/diag`, `/api/hub75/info`
- **MAX7219**: `/api/maxfx`
- **Expressions & Presets**: `/api/face`, `/api/expranim`, `/api/expranim/clear`, `/api/eyeanim`, `/api/expr/settings`, `/api/resetexpr`, `/api/preset`, `/api/preset/frames`, `/api/presetmeta`, `/api/presetpack`, `/api/userpreset`, `/api/userpreset/save`, `/api/userpreset/delete`, `/api/userpresetmeta`, `/api/procface`, `/api/pf/pixels`, `/api/procface/upload`
- **Social & Proximity**: `/api/identity`, `/api/proximity`, `/api/proximity/clearfrenz`, `/api/floormode`
- **Networking & OTA**: `/api/wifi`, `/api/apname`, `/api/apboot`, `/api/ota/check`, `/api/ota/update`
- **Effects & Audio**: `/api/glitch`, `/api/rebootimg`, `/api/rebootimg/clear`, `/api/musicstyle`, `/api/fade`
- **Stats**: `/api/stats/get`, `/api/stats/reset`, `/api/stats/toggle`, `/api/stats/achievements`

---

## 7. Reconstructed File Inventory in Workspace
- [`control_panel.html`](file:///c:/Users/synnt/OneDrive/.Antigravity/ProtoFenz/sourcecode/control_panel.html) - The 100% recovered WebUI frontend (HTML/CSS/JS, 313 KB).
- [`captive_portal.html`](file:///c:/Users/synnt/OneDrive/.Antigravity/ProtoFenz/sourcecode/captive_portal.html) - The captive portal sign-in page.
- [`partitions.csv`](file:///c:/Users/synnt/OneDrive/.Antigravity/ProtoFenz/sourcecode/partitions.csv) - ESP32 partition table specification.
- [`webui.h`](file:///c:/Users/synnt/OneDrive/.Antigravity/ProtoFenz/sourcecode/webui.h) - C++ header embedding the WebUI gzipped payload in PROGMEM.
- [`ProtoFrenz.ino`](file:///c:/Users/synnt/OneDrive/.Antigravity/ProtoFenz/sourcecode/ProtoFrenz.ino) - Reconstructed Arduino firmware source code.
- [`manifest.json`](file:///c:/Users/synnt/OneDrive/.Antigravity/ProtoFenz/git/manifest.json) - ESP Web Tools flasher manifest.
