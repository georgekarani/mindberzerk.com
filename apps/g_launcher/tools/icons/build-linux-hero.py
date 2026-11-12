#!/usr/bin/env python3
"""Build a HERO pack from a desktop Linux icon theme (Papirus, Numix Circle).

A desktop theme names icons after desktop apps, not Android packages, so each
package is mapped in two ways, explicit first:

  1. linux-aliases.json, the hand-checked names for apps whose Linux name
     differs from their Android one (Gmail is `gmail`, Settings is
     `preferences-system`);
  2. the Arcticons drawing name for the package (out/index.json), which desktop
     themes overwhelmingly share (`whatsapp`, `telegram`, `spotify`).

Mapping is scoped to a package list (default packages.txt plus every alias),
because a hero pack is one PNG per drawing and the whole Arcticons index would
be thousands of files on every phone that installs it.

    python3 tools/icons/build-linux-hero.py \
      --theme ~/Downloads/iconpacks/papirus-icon-theme-master/Papirus/64x64/apps \
      --id papirus-icon-theme --name "Papirus Icon Theme" \
      --license GPL-3.0 \
      --attribution "Papirus Development Team, GPL-3.0, github.com/PapirusDevelopmentTeam/papirus-icon-theme" \
      --merge-live heropacks/papirus-icon-theme/12

--merge-live keeps every icon an already published version of the pack maps,
downloaded from the CDN, so hand-picked art survives a rebuild.

GPL themes ship FREE, never sold: the licence lets anyone who receives them
share them, so a price would be a price for nothing.

Run through tools/icons/py.sh, which provides cairosvg and Pillow in a venv.
"""
from __future__ import annotations

import argparse
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

import cairosvg
from PIL import Image

HERE = Path(__file__).resolve().parent
CDN = "https://cdn.mindberzerk.com/g-launcher"
PREVIEW_APPS = [
    "com.whatsapp",
    "com.android.chrome",
    "com.google.android.youtube",
    "org.telegram.messenger",
    "com.google.android.gm",
    "com.android.settings",
]


def norm(name: str) -> str:
    """Case and punctuation folded, so `Org.Gnome.Calendar` meets `org_gnome_calendar`."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


def read_svg(path: Path, depth: int = 0) -> str | None:
    """The SVG text, following the plain-text links GitHub zips leave for symlinks."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    if text.lstrip().startswith("<"):
        return text
    target = text.strip()
    if depth > 4 or not target or "\n" in target or len(target) > 200:
        return None
    return read_svg(path.parent / target, depth + 1)


def theme_names(theme_dir: Path) -> dict[str, Path]:
    """Folded icon name -> file, for every SVG in the theme's apps directory."""
    out: dict[str, Path] = {}
    for f in sorted(theme_dir.glob("*.svg")):
        out.setdefault(norm(f.stem), f)
    return out


def packages(path: Path) -> list[str]:
    lines = path.read_text().splitlines()
    return [l.strip() for l in lines if l.strip() and not l.startswith("#")]


def arcticons_names(index_path: Path) -> dict[str, str]:
    data = json.loads(index_path.read_text())
    slugs = data.get("slugs", [])
    return {pkg: slugs[i] for pkg, i in data.get("map", {}).items() if i < len(slugs)}


def render(svg: str, size: int) -> bytes:
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=size, output_height=size)
    img = Image.open(io.BytesIO(png)).convert("RGBA")
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme", required=True, help="the theme's apps directory of SVGs")
    ap.add_argument("--id", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--license", required=True)
    ap.add_argument("--attribution", required=True)
    ap.add_argument("--packages", default=str(HERE / "packages.txt"))
    ap.add_argument("--aliases", default=str(HERE / "linux-aliases.json"))
    ap.add_argument("--index", default=str(HERE / "out" / "index.json"))
    ap.add_argument("--size", type=int, default=192)
    ap.add_argument(
        "--all",
        action="store_true",
        help="map every package the Arcticons index knows, not just the package list",
    )
    ap.add_argument("--merge-live", help="published path to keep, e.g. heropacks/<id>/<version>")
    ap.add_argument("--out", default=str(HERE / "out"))
    a = ap.parse_args()

    theme_dir = Path(a.theme).expanduser()
    if not theme_dir.is_dir():
        sys.exit(f"build-linux-hero: no such directory {theme_dir}")
    names = theme_names(theme_dir)
    aliases = {k: v for k, v in json.loads(Path(a.aliases).read_text()).items() if not k.startswith("_")}
    by_drawing = arcticons_names(Path(a.index))
    listed = list(by_drawing) if a.all else packages(Path(a.packages))
    scope = list(dict.fromkeys(list(aliases) + listed))

    out_dir = Path(a.out) / a.id
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in out_dir.iterdir():
        f.unlink()

    icons: dict[str, str] = {}
    files: set[str] = set()
    how = {"alias": 0, "drawing": 0, "kept": 0}

    # Hand-picked art from the live pack first: it was chosen by eye.
    if a.merge_live:
        base = f"{CDN}/{a.merge_live.strip('/')}"
        live = json.loads(fetch(f"{base}/pack.json"))
        for pkg, fname in live.get("icons", {}).items():
            if fname not in files:
                (out_dir / fname).write_bytes(fetch(f"{base}/{fname}"))
                files.add(fname)
            icons[pkg] = fname
            how["kept"] += 1

    for pkg in scope:
        if pkg in icons:
            continue
        candidates = [("alias", n) for n in aliases.get(pkg, [])]
        if pkg in by_drawing:
            d = by_drawing[pkg]
            candidates += [("drawing", d), ("drawing", d.replace("_", "-"))]
        for kind, cand in candidates:
            src = names.get(norm(cand))
            if src is None:
                continue
            svg = read_svg(src)
            if svg is None:
                continue
            fname = f"{norm(src.stem)}.png"
            if fname not in files:
                try:
                    (out_dir / fname).write_bytes(render(svg, a.size))
                except Exception as e:  # a single bad drawing must not sink the pack
                    print(f"  skip {src.name}: {e}")
                    continue
                files.add(fname)
            icons[pkg] = fname
            how[kind] += 1
            break

    pack = {
        "id": a.id,
        "name": a.name,
        "masked": False,
        "license": a.license,
        "attribution": a.attribution,
        "icons": dict(sorted(icons.items())),
    }
    (out_dir / "pack.json").write_text(json.dumps(pack, separators=(",", ":")))

    # The store picture: six well-known apps, three across, as the panel draws it.
    shown = [icons[p] for p in PREVIEW_APPS if p in icons][:6]
    if shown:
        cell, gap = 128, 24
        sheet = Image.new("RGBA", (3 * cell + 2 * gap, 2 * cell + gap), (0, 0, 0, 0))
        for i, fname in enumerate(shown):
            img = Image.open(out_dir / fname).convert("RGBA").resize((cell, cell), Image.LANCZOS)
            sheet.alpha_composite(img, ((i % 3) * (cell + gap), (i // 3) * (cell + gap)))
        sheet.save(out_dir / "preview.png", optimize=True)

    size = sum(f.stat().st_size for f in out_dir.iterdir())
    print(f"wrote {out_dir}")
    print(f"  packages  {len(icons)}  (kept {how['kept']}, alias {how['alias']}, drawing name {how['drawing']})")
    print(f"  drawings  {len(files)}")
    print(f"  size      {size // 1024} KB")
    popular = [p for p in PREVIEW_APPS if p not in icons]
    if popular:
        print(f"  missing   {', '.join(popular)}")


if __name__ == "__main__":
    main()
