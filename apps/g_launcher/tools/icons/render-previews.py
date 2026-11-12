#!/usr/bin/env python3
"""Render a store preview.png for tinted vector icon packs.

The phone draws line and bold previews live, but only with the geometry it has
loaded, which is whichever family is being worn. A family you are not wearing
needs a picture of its own, so each pack ships a preview.png: ten well-known
apps in the pack's colour, five across and two down, on transparent.

    python3 tools/icons/render-previews.py tools/icons/out/*-bold tools/icons/out/*-line

Run through tools/icons/py.sh, which provides cairosvg and Pillow in a venv.
A pack without a tint, or whose base is not built under the same out dir, is
skipped with a note rather than failing the batch.
"""
from __future__ import annotations

import io
import json
import sys
from pathlib import Path

import cairosvg
from PIL import Image

# Apps nearly every phone has, in the order the card shows them.
APPS = [
    "com.whatsapp",
    "com.instagram.android",
    "com.android.chrome",
    "com.google.android.youtube",
    "com.spotify.music",
    "org.telegram.messenger",
    "com.google.android.gm",
    "com.google.android.apps.maps",
    "com.google.android.GoogleCamera",
    "com.android.settings",
]
# Fallbacks for slots whose first choice a set does not draw.
SPARES = [
    "com.twitter.android",
    "com.facebook.katana",
    "com.netflix.mediaclient",
    "com.google.android.calendar",
    "com.google.android.apps.photos",
    "com.android.vending",
    "com.google.android.dialer",
    "com.google.android.apps.messaging",
]

CELL, GAP, COLS, ROWS = 96, 36, 5, 2


def load(pack_dir: Path) -> dict:
    return json.loads((pack_dir / "pack.json").read_text())


def glyph_svg(paths: list[str], box: float, stroke: float, tint: str) -> str:
    body = "".join(f'<path d="{d}"/>' for d in paths)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {box} {box}" '
        f'width="{CELL}" height="{CELL}" fill="none" stroke="{tint}" '
        f'stroke-width="{stroke}" stroke-linecap="round" '
        f'stroke-linejoin="round">{body}</svg>'
    )


def render(pack_dir: Path) -> str:
    pack = load(pack_dir)
    tint = pack.get("tint")
    base_id = pack.get("extends")
    if not tint or not base_id:
        return f"skip {pack_dir.name}: no tint or base"
    base_dir = pack_dir.parent / base_id
    if not (base_dir / "pack.json").exists():
        return f"skip {pack_dir.name}: base {base_id} is not built in {pack_dir.parent}"
    base = load(base_dir)
    icons, glyphs = base.get("icons", {}), base.get("glyphs", {})
    box, stroke = base.get("viewBox", 48), base.get("strokeWidth", 1)

    chosen = [p for p in APPS + SPARES if isinstance(icons.get(p), str) and icons[p] in glyphs]
    chosen = chosen[: COLS * ROWS]
    if not chosen:
        return f"skip {pack_dir.name}: none of the preview apps are drawn"

    w = COLS * CELL + (COLS - 1) * GAP
    h = ROWS * CELL + (ROWS - 1) * GAP
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for i, pkg in enumerate(chosen):
        png = cairosvg.svg2png(bytestring=glyph_svg(glyphs[icons[pkg]], box, stroke, tint).encode())
        cell = Image.open(io.BytesIO(png)).convert("RGBA")
        sheet.alpha_composite(cell, ((i % COLS) * (CELL + GAP), (i // COLS) * (CELL + GAP)))
    sheet.save(pack_dir / "preview.png", optimize=True)
    return f"ok   {pack_dir.name}: {len(chosen)} apps, {(pack_dir / 'preview.png').stat().st_size} B"


if __name__ == "__main__":
    dirs = [Path(a) for a in sys.argv[1:] if Path(a, "pack.json").exists()]
    if not dirs:
        sys.exit("render-previews: pass one or more built pack directories")
    for d in dirs:
        print(render(d))
