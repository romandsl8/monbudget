#!/usr/bin/env python3
"""
Génère l'icône Mon Budget (PNG 1024 x 1024 sans transparence) en trois variantes :
claire, sombre et teintée. Lancé automatiquement par GitHub Actions avant la compilation.

Aucune dépendance : Python 3 standard uniquement (champs de distance + anti-crénelage).

Usage :
    python3 scripts/make_icon.py
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "MonBudget", "Resources", "Assets.xcassets", "AppIcon.appiconset")

SIZE = 1024

# --- Géométrie (repère 1024, y vers le bas) : un portefeuille et sa pièce -----
BODY_C, BODY_HALF, BODY_R = (512.0, 590.0), (300.0, 215.0), 80.0       # corps du portefeuille
CARD_C, CARD_HALF, CARD_R = (480.0, 340.0), (230.0, 34.0), 30.0        # carte qui dépasse
FLAP_C, FLAP_HALF, FLAP_R = (742.0, 590.0), (130.0, 78.0), 44.0        # rabat (découpe)
DOT_C, DOT_R = (722.0, 590.0), 30.0                                    # bouton du rabat

PALETTES = {
    "light": {"bg1": (60, 214, 160), "bg2": (16, 120, 140), "glyph1": (255, 255, 255), "glyph2": (232, 250, 244)},
    "dark": {"bg1": (14, 44, 46), "bg2": (10, 26, 40), "glyph1": (120, 235, 190), "glyph2": (70, 190, 200)},
    "tinted": {"bg1": (0, 0, 0), "bg2": (0, 0, 0), "glyph1": (255, 255, 255), "glyph2": (200, 200, 200)},
}


def sd_round_box(px, py, c, half, r):
    qx = abs(px - c[0]) - half[0] + r
    qy = abs(py - c[1]) - half[1] + r
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - r


def coverage(d):
    return max(0.0, min(1.0, 0.5 - d))


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(c1[i], c2[i], t) for i in range(3))


def glyph_alpha(px, py):
    body = coverage(sd_round_box(px, py, BODY_C, BODY_HALF, BODY_R))
    flap = coverage(sd_round_box(px, py, FLAP_C, FLAP_HALF, FLAP_R))
    dot = coverage(math.hypot(px - DOT_C[0], py - DOT_C[1]) - DOT_R)
    card = coverage(sd_round_box(px, py, CARD_C, CARD_HALF, CARD_R))
    wallet = body * (1.0 - flap) + dot * body
    return max(0.0, min(1.0, max(wallet, card)))


def write_png(path, width, height, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def render_icon(variant):
    pal = PALETTES[variant]
    rows = []
    for y in range(SIZE):
        row = bytearray()
        py = y + 0.5
        for x in range(SIZE):
            px = x + 0.5
            bg = mix(pal["bg1"], pal["bg2"], (px + py) / (2 * SIZE))
            if variant != "tinted":
                glow = max(0.0, 1.0 - math.hypot(px - 260, py - 200) / 620.0) ** 2 * 0.22
                bg = mix(bg, (255, 255, 255), glow)
            a = glyph_alpha(px, py)
            g = mix(pal["glyph1"], pal["glyph2"], max(0.0, min(1.0, (py - 300) / 520.0)))
            c = mix(bg, g, a)
            row.extend(int(round(max(0, min(255, v)))) for v in c)
        rows.append(row)
    return rows


def main():
    outputs = {"light": "AppIcon.png", "dark": "AppIcon-Dark.png", "tinted": "AppIcon-Tinted.png"}
    for variant, name in outputs.items():
        path = os.path.join(ICON_DIR, name)
        print("Rendu", variant, "->", path)
        write_png(path, SIZE, SIZE, render_icon(variant))


if __name__ == "__main__":
    main()
