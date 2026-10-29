#!/usr/bin/env python3
"""Generate firmware/src/faces_default.h — Proot's own face set.

Eyes are 16x8, noses 8x8, mouths 40x8, drawn for the panel where the nose sits on
the right. Encoding (shared by firmware, web UI and iOS app): row-major, MSB = left
pixel; eye = 2 bytes/row, nose = 1 byte/row, mouth = 5 bytes/row.
"""
import json
import math
import os

EYES = {
    "Classic": """
        .#####..........
        ##########......
        #############...
        .##############.
        ...#############
        .....###########
        ........########
        ...........####.""",
    "Soft": """
        ....######......
        ..###########...
        .##############.
        ################
        ################
        .##############.
        ...##########...
        ......####......""",
    "Happy": """
        ......####......
        ....########....
        ...###....###...
        ..##........##..
        .##..........##.
        ##............##
        #..............#
        ................""",
    "Angry": """
        ###.............
        ########........
        #############...
        ################
        .###############
        ..#############.
        ....##########..
        .......#####....""",
    "Sad": """
        ............####
        .......#########
        ..##############
        ################
        ###############.
        .#############..
        ..##########....
        ....#####.......""",
    "Wide": """
        .....######.....
        ...###....###...
        ..##........##..
        .##....##....##.
        .##....##....##.
        ..##........##..
        ...###....###...
        .....######.....""",
    "Heart": """
        ...###....###...
        ..#####..#####..
        .##############.
        .##############.
        ..############..
        ....########....
        ......####......
        .......##.......""",
    "Dead": """
        ..##........##..
        ...##......##...
        ....##....##....
        ......####......
        ......####......
        ....##....##....
        ...##......##...
        ..##........##..""",
    "Closed": """
        ................
        ................
        ................
        ################
        ################
        ................
        ................
        ................""",
    "Sleepy": """
        ................
        ................
        ................
        ################
        ################
        .##############.
        ...##########...
        .....######.....""",
    "Star": """
        .......##.......
        ......####......
        .##############.
        ...##########...
        ....########....
        ...####..####...
        ..###......###..
        ................""",
    "Dizzy": """
        ....########....
        ..##........##..
        .#...######...#.
        #...#......#...#
        #...#..##..#...#
        .#...#....#...#.
        ..##..####...##.
        ....##.....##...""",
    "Dot": """
        ................
        ......####......
        .....######.....
        ....########....
        ....########....
        .....######.....
        ......####......
        ................""",
    "Squint": """
        .##.............
        ...####.........
        .......#####....
        ...........#####
        .......#####....
        ...####.........
        .##.............
        ................""",
    "Lens": """
        ....########....
        ..############..
        .######..######.
        #####......#####
        #####......#####
        .######..######.
        ..############..
        ....########....""",
    "Shades": """
        ################
        ################
        .######..######.
        .######..######.
        ..####....####..
        ................
        ................
        ................""",
}

NOSES = {
    "Classic": """
        ........
        #####...
        ....###.
        ......##
        ........
        ........
        ........
        ........""",
    "Chevron": """
        ........
        ##......
        .###....
        ...###..
        .###....
        ##......
        ........
        ........""",
    "Heart": """
        ........
        .##.##..
        #######.
        #######.
        .#####..
        ..###...
        ...#....
        ........""",
    "Dot": """
        ........
        ........
        ..###...
        .#####..
        .#####..
        ..###...
        ........
        ........""",
    "Triangle": """
        ........
        ........
        #######.
        .#####..
        ..###...
        ...#....
        ........
        ........""",
    "None": """
        ........
        ........
        ........
        ........
        ........
        ........
        ........
        ........""",
}


def blank(w=40, h=8):
    return [[0] * w for _ in range(h)]


def line(g, x0, y0, x1, y1):
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(steps + 1):
        x = round(x0 + (x1 - x0) * i / steps)
        y = round(y0 + (y1 - y0) * i / steps)
        if 0 <= x < len(g[0]) and 0 <= y < len(g):
            g[y][x] = 1


def poly(points, thick=1):
    g = blank()
    for (a, b) in zip(points, points[1:]):
        for t in range(thick):
            line(g, a[0], a[1] + t, b[0], b[1] + t)
    return g


def zigzag(period, top, bottom, start=0, thick=1):
    pts, x, up = [], start, False
    while x <= 39 + period:
        pts.append((x, top if up else bottom))
        x += period // 2
        up = not up
    return poly(pts, thick)


def curve(fn, thick=2):
    pts = [(x, round(fn(x))) for x in range(40)]
    return poly(pts, thick)


MOUTHS = {
    "Wave": zigzag(10, 2, 5, thick=2),
    "Fang": poly([(0, 1), (3, 3), (6, 5), (10, 2), (14, 5), (19, 2), (24, 5), (29, 2), (34, 5), (39, 2)], 2),
    "Smile": curve(lambda x: 1 + 4.5 * math.sin(math.pi * x / 39)),
    "Grin": poly([(0, 1), (5, 5), (12, 6), (20, 6), (28, 6), (35, 5), (39, 1)], 2),
    "Flat": poly([(0, 1), (2, 4), (39, 4)], 2),
    "Frown": curve(lambda x: 6 - 4.5 * math.sin(math.pi * x / 39)),
    "Owo": poly([(0, 2), (6, 6), (12, 2), (18, 6), (24, 2)], 2),
    "Open": None,
    "Teeth": zigzag(6, 2, 6),
    "Talk": zigzag(14, 1, 6, thick=2),
    "Wobble": curve(lambda x: 3.5 + 2.5 * math.sin(x / 2.2)),
    "Smirk": poly([(0, 2), (8, 5), (26, 5), (34, 3), (39, 0)], 2),
}


def open_mouth():
    g = blank()
    for x in range(4, 36):
        h = round(3 * math.sin(math.pi * (x - 4) / 31))
        g[3 - min(h, 3) // 2][x] = 1
        g[4 + h][x] = 1
    for y in range(1, 8):
        g[y][4] = g[y][35] = 1 if 2 <= y <= 5 else 0
    return g


MOUTHS["Open"] = open_mouth()


def parse(art, w):
    rows = [r.strip() for r in art.strip("\n").splitlines()]
    assert len(rows) == 8, f"need 8 rows, got {len(rows)}"
    for r in rows:
        assert len(r) == w, f"row '{r}' is {len(r)} wide, need {w}"
    return [[1 if c == "#" else 0 for c in r] for r in rows]


def pack(grid):
    out = []
    for row in grid:
        for i in range(0, len(row), 8):
            b = 0
            for bit in row[i:i + 8]:
                b = (b << 1) | bit
            out.append(b)
    return out


def emit(name, items, nbytes):
    lines = [f"static const uint8_t {name}[][{nbytes}] PROGMEM = {{"]
    for label, data in items:
        lines.append("  {" + ",".join(f"0x{b:02x}" for b in data) + "},  // " + label)
    lines.append("};")
    names = ",".join(f'"{label}"' for label, _ in items)
    lines.append(f"static const char* const {name}_NAMES[] = {{{names}}};")
    lines.append(f"static const uint8_t {name}_COUNT = {len(items)};")
    return "\n".join(lines)


def main():
    eyes = [(k, pack(parse(v, 16))) for k, v in EYES.items()]
    noses = [(k, pack(parse(v, 8))) for k, v in NOSES.items()]
    mouths = [(k, pack(v)) for k, v in MOUTHS.items()]
    out = os.path.join(os.path.dirname(__file__), "..", "firmware", "src", "faces_default.h")
    with open(out, "w") as f:
        f.write("// Generated by tools/gen_default_faces.py. Do not edit.\n#pragma once\n#include <Arduino.h>\n\n")
        f.write(emit("FACE_EYES", eyes, 16) + "\n\n")
        f.write(emit("FACE_NOSES", noses, 8) + "\n\n")
        f.write(emit("FACE_MOUTHS", mouths, 40) + "\n")
    demo = os.path.join(os.path.dirname(__file__), "..", "app", "Proot", "Resources", "DemoFaces.json")
    os.makedirs(os.path.dirname(demo), exist_ok=True)
    as_hex = lambda items: [{"n": k, "b": bytes(v).hex()} for k, v in items]
    with open(demo, "w") as f:
        json.dump({"eyes": as_hex(eyes), "noses": as_hex(noses), "mouths": as_hex(mouths)}, f)
    print(f"wrote {len(eyes)} eyes, {len(noses)} noses, {len(mouths)} mouths -> {os.path.normpath(out)}, DemoFaces.json")


if __name__ == "__main__":
    main()
