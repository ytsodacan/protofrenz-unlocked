# ProtoFrenz-Unlocked

Decompiled and reconstructed source code for the **ProtoFrenz** Protogen fursuit LED matrix / HUB75 / NeoPixel face controller firmware (v3.0.13 "Smooth Operator").

---

## Repository Contents

- **[`ProtoFrenz.ino`](ProtoFrenz.ino)**: The main ESP32 Arduino firmware source code implementing the WiFi SoftAP, captive portal DNS responder, REST API router (61 endpoints), serial console parser, and hardware state machine.
- **[`control_panel.html`](control_panel.html)**: The 100% recovered WebUI frontend (313 KB, 6,234 lines of vanilla HTML/CSS/JavaScript) featuring all 7 tabs:
  - **Editor**: WS2812B NeoPixel and MAX7219 matrix face painter, gradient builder, cheek rings.
  - **P3 Editor**: Dual P3 HUB75 128x32 canvas editor and animated reaction designer.
  - **Controls**: Hardware button assignment and TTP223 capacitive touch "boop" thresholds.
  - **Social**: Bluetooth Low Energy (NimBLE) proximity greeting beacon and "Floor Mode".
  - **Options**: Master brightness, microphone audio reactivity, and fan PWM speed control.
  - **System**: Hotspot SoftAP / Home Wi-Fi configuration and OTA flasher.
  - **Stats**: Boop counter, rapid boop peak tracker, and achievement celebration engine.
  - **Diagnostics**: Bus health diagnostics, test patterns, and brownout warning calculator.
- **[`captive_portal.html`](captive_portal.html)**: Captive portal sign-in screen HTML.
- **[`webui.h`](webui.h)**: C++ PROGMEM header containing the compressed WebUI payload for direct flashing.
- **[`partitions.csv`](partitions.csv)**: ESP-IDF partition table for 8MB Flash (`nvs`, `otadata`, `app0`, `app1`, `spiffs`, `coredump`).
- **[`DECOMPILATION_REPORT.md`](DECOMPILATION_REPORT.md)**: Full reverse engineering technical report detailing memory segments, Xtensa binary analysis, and REST API schemas.

---

## Build & Flashing

- **Target**: ESP32 Dev Module (Xtensa LX6 dual-core, 8MB Flash)
- **Toolchain**: Arduino IDE / Arduino CLI / ESP-IDF
- **Partition Scheme**: Custom (`partitions.csv` / 8MB with SPIFFS)
- **Dependencies**:
  - `WiFi` & `WebServer` & `DNSServer` (ESP32 core)
  - `NimBLE-Arduino`
  - `SPIFFS` & `Preferences`
