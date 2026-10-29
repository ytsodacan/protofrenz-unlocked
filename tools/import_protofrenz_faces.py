#!/usr/bin/env python3
"""Import the built-in ProtoFrenz face presets for local builds.

Reads the official ProtoFrenz v3.0.13 firmware image (downloaded from the public
protofrenz/protofrenz-firmware release, or a local file via --bin) and writes
firmware/src/faces_vendor.h. That file is git-ignored: the art belongs to
ProtoFrenz, so it stays on your machine. The firmware uses it instead of the
default face set whenever it exists, so your old preset numbers keep working.

    python3 tools/import_protofrenz_faces.py [--bin path/to/ProtoFrenz.bin]
"""
import argparse
import os
import struct
import urllib.request

RELEASE_URL = "https://github.com/protofrenz/protofrenz-firmware/releases/download/v3.0.13/ProtoFrenz.bin"

# Table locations in the v3.0.13 image (found by disassembling /api/presetpack).
EYES = (0x3F431080, 52)
NOSES = (0x3F430FC0, 24)
MOUTHS = (0x3F4313C0, 33)
DROM_LO, DROM_HI = 0x3F400000, 0x3F800000


def load_drom(image):
    assert image[0] == 0xE9, "not an ESP32 app image"
    off = 24
    for _ in range(image[1]):
        addr, size = struct.unpack("<II", image[off:off + 8])
        if DROM_LO <= addr < DROM_HI:
            return addr, image[off + 8:off + 8 + size]
        off += 8 + size
    raise SystemExit("no DROM segment in image")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", help="local ProtoFrenz.bin (default: download v3.0.13)")
    args = ap.parse_args()

    if args.bin:
        image = open(args.bin, "rb").read()
    else:
        print(f"downloading {RELEASE_URL}")
        image = urllib.request.urlopen(RELEASE_URL).read()
    if b"3.0.13" not in image:
        raise SystemExit("this importer only knows the v3.0.13 table layout")

    base, drom = load_drom(image)

    def u64(addr):
        return struct.unpack("<Q", drom[addr - base:addr - base + 8])[0]

    def byte(v, i):
        return (v >> (8 * i)) & 0xFF

    def rev(b):
        return int(f"{b:08b}"[::-1], 2)

    # Orientation matches the original editor's pfDecodePresetBytes(); output is
    # Proot's canonical row-major MSB-left encoding.
    def eye(i):
        t0, t1 = u64(EYES[0] + 16 * i), u64(EYES[0] + 16 * i + 8)
        out = []
        for r in range(8):
            out += [rev(byte(t1, r)), rev(byte(t0, r))]
        return out

    def nose(i):
        v = u64(NOSES[0] + 8 * i)
        return [byte(v, r) for r in range(8)]

    def mouth(i):
        tiles = [u64(MOUTHS[0] + 40 * i + 8 * s) for s in range(5)]
        return [byte(t, 7 - r) for r in range(8) for t in tiles]

    def emit(name, rows, nbytes, label):
        lines = [f"static const uint8_t {name}[][{nbytes}] PROGMEM = {{"]
        lines += ["  {" + ",".join(f"0x{b:02x}" for b in row) + "}," for row in rows]
        lines.append("};")
        names = ",".join(f'"{label} {i + 1}"' for i in range(len(rows)))
        lines.append(f"static const char* const {name}_NAMES[] = {{{names}}};")
        lines.append(f"static const uint8_t {name}_COUNT = {len(rows)};")
        return "\n".join(lines)

    out = os.path.join(os.path.dirname(__file__), "..", "firmware", "src", "faces_vendor.h")
    with open(out, "w") as f:
        f.write("// Imported from ProtoFrenz v3.0.13 by tools/import_protofrenz_faces.py.\n")
        f.write("// Local use only: git-ignored, do not commit or redistribute.\n")
        f.write("#pragma once\n#include <Arduino.h>\n\n")
        f.write(emit("FACE_EYES", [eye(i) for i in range(EYES[1])], 16, "Eye") + "\n\n")
        f.write(emit("FACE_NOSES", [nose(i) for i in range(NOSES[1])], 8, "Nose") + "\n\n")
        f.write(emit("FACE_MOUTHS", [mouth(i) for i in range(MOUTHS[1])], 40, "Mouth") + "\n")
    print(f"wrote {os.path.normpath(out)}: {EYES[1]} eyes, {NOSES[1]} noses, {MOUTHS[1]} mouths")


if __name__ == "__main__":
    main()
