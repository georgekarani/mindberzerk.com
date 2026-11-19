"""Build the G Recovery Play slides: phone (1080x1920) and tablet (1600x2560).

Each slide is one HTML page rendered by headless Chrome at 2x. One short line
of copy per slide; the app screen, drawn full bleed, carries the rest.

    python3 build.py <out_dir>
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).parent.resolve()
IMG = ROOT / "assets"
ICONS = ROOT / "node_modules/lucide-static/icons"
OUT = pathlib.Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)

ACCENT = "#D93D00"
ACCENT_TEXT = "#FF7A45"


def icon(name, size=22, color="currentColor", width=1.8):
    """Inline Lucide icon at a given size and stroke."""
    svg = (ICONS / f"{name}.svg").read_text()
    svg = re.sub(r"<!--.*?-->", "", svg, flags=re.S)
    svg = re.sub(r'width="24"', f'width="{size}"', svg, count=1)
    svg = re.sub(r'height="24"', f'height="{size}"', svg, count=1)
    svg = svg.replace('stroke="currentColor"', f'stroke="{color}"')
    svg = re.sub(r'stroke-width="[\d.]+"', f'stroke-width="{width}"', svg)
    return svg


def img(name):
    return (IMG / f"{name}.jpg").as_uri()


def photo(name, extra=""):
    return f'<div class="ph" style="background-image:url({img(name)});{extra}"></div>'


# ── App chrome ────────────────────────────────────────────────────────────

def status_bar():
    return ('<div class="status"><span>9:41</span><span class="sicons">'
            f'{icon("wifi", 15, "#fff", 2.2)}{icon("battery", 17, "#fff", 2)}</span></div>')


def tab_bar(active):
    items = [("house", "Home"), ("sparkles", "Clean up"), ("smartphone", "Device"),
             ("ellipsis", "More")]
    cells = "".join(
        f'<div class="tab{" on" if label == active else ""}">'
        f'{icon(name, 22, ACCENT if label == active else "#8E8E93", 1.9)}<span>{label}</span></div>'
        for name, label in items)
    return f'<div class="tabbar">{cells}</div>'


def nav(back=None, title=None, actions=()):
    left = (f'<div class="back">{icon("chevron-left", 24, "#fff", 2.2)}<span>{back}</span></div>'
            if back else "<div></div>")
    acts = "".join(f'<div class="navbtn">{icon(a, 19, "#fff", 2)}</div>' for a in actions)
    mid = f'<div class="navtitle">{title}</div>' if title else ""
    return f'<div class="nav">{left}{mid}<div class="acts">{acts}</div></div>'


def large(title, sub=None):
    s = f'<div class="sub">{sub}</div>' if sub else ""
    return f'<div class="large">{title}</div>{s}'


# ── Screens ───────────────────────────────────────────────────────────────

def screen_restore(wide):
    cats = [("image", "Photos", True), ("video", "Video", False), ("circle-dashed", "Statuses", False),
            ("message-circle", "Messages", False), ("file-text", "Docs", False)]
    chips = "".join(
        f'<div class="cat{" on" if on else ""}">{icon(i, 22, "#fff" if on else "#8E8E93", 1.8)}'
        f'<span>{l}</span></div>' for i, l, on in cats)
    soon = "".join(photo(n, "height:120px;border-radius:14px") for n in ["k22", "k7", "k16"])
    return f"""
    {status_bar()}
    {nav("Recovery", None, ["radar", "search"])}
    {large("Can come back")}
    <div class="cats">{chips}</div>
    <div class="pad">
      <div class="hero" style="height:{'420' if wide else '330'}px">
        {photo("k23", "position:absolute;inset:0")}
        <div class="pill tl">Deleted 3 days ago</div>
      </div>
      <div class="h2">14 photos can come back</div>
      <div class="foot">48.6 MB, leaves in 26 days</div>
      <div class="cta">Review and restore</div>
      <div class="h3">Leaving soon</div>
      <div class="row3">{soon}</div>
    </div>
    {tab_bar("Home")}"""


def screen_grid(wide):
    cols = 4 if wide else 3
    names = ["k21", "k13", "k3", "k9", "chelsea", "k20", "k6", "k1", "coffee", "k19", "k10",
             "k24", "k14", "k8", "wikkie", "k11", "k16", "k22", "k7", "k23"]
    tiles = "".join(
        f'<div class="tile">{photo(n, "position:absolute;inset:0")}'
        + ('<div class="dur">0:24</div>' if n in ("k14", "k10") else "")
        + "</div>" for n in names[: cols * 5])
    return f"""
    {status_bar()}
    {nav("Recovery", None, ["ellipsis"])}
    {large("Photos", "41 items, 126 MB")}
    <div class="ghead"><span>Deleted yesterday</span><span class="fig">18, 52 MB</span></div>
    <div class="grid" style="grid-template-columns:repeat({cols},1fr)">{tiles}</div>
    <div class="scrub"><div class="bubble">Last week</div><div class="thumb"></div></div>
    {tab_bar("Home")}"""


def screen_player(wide):
    bars = "".join(
        f'<i style="height:{h}px;background:{ACCENT if n < 22 else "#3A3A3C"}"></i>'
        for n, h in enumerate([18, 30, 44, 26, 52, 38, 60, 34, 22, 48, 64, 40, 28, 56, 36, 20, 46,
                               58, 30, 42, 24, 50, 34, 62, 44, 28, 40, 54, 26, 36, 48, 22, 32, 44,
                               20, 30]))
    return f"""
    {status_bar()}
    <div class="nav">{icon("chevron-left", 24, "#fff", 2.2)}<div class="navtitle">Voice note</div><div></div></div>
    <div class="cover">{icon("audio-lines", 64, "#8E8E93", 1.6)}</div>
    <div class="ptitle">Voice note, Tuesday</div>
    <div class="wave">{bars}</div>
    <div class="ctrl">
      <div class="track"><div style="width:38%"></div></div>
      <div class="times"><span>0:21</span><span>-0:34</span></div>
      <div class="btns">{icon("volume-2", 24, "#fff")}{icon("rotate-ccw", 24, "#fff")}
        <div class="bigplay">{icon("pause", 30, "#fff", 2.4)}</div>
        {icon("rotate-cw", 24, "#fff")}<span class="speed">1.5x</span></div>
    </div>"""


def screen_shrink(wide):
    rows = [("monitor", "Screenshots", "5.6 MB"), ("image", "Photos", "150 MB"),
            ("video", "Video", "22.5 MB")]
    group = "".join(f'<div class="lrow">{icon(i, 22, "#8E8E93")}<span class="lt">{t}</span>'
                    f'<span class="ld">{d}</span></div>' for i, t, d in rows)
    return f"""
    {status_bar()}
    {nav("Clean up", None, [])}
    {large("Make smaller")}
    <div class="pad">
      <div class="hero shrink" style="height:{'400' if wide else '300'}px">
        {photo("k13", "position:absolute;inset:0")}
        <div class="corner c1"></div><div class="corner c2"></div>
        <div class="corner c3"></div><div class="corner c4"></div>
        <div class="pill bc">3.6 MB</div>
      </div>
      <div class="h2">178 MB could get smaller</div>
      <div class="h3 muted">Choose</div>
      <div class="group">{group}</div>
    </div>
    {tab_bar("Clean up")}"""


def screen_messages(wide):
    msgs = [("in", "Running late, save me a seat"), ("in", "Actually, forget the movie"),
            ("del", "This message was deleted"), ("in", "Call me when you are free"),
            ("out", "On my way"), ("in", "Bring the charger please")]
    out = []
    for kind, text in msgs:
        if kind == "del":
            out.append(f'<div class="b in kept">{text}<span class="tag">Kept</span></div>')
        else:
            out.append(f'<div class="b {kind}">{text}</div>')
    return f"""
    {status_bar()}
    <div class="nav"><div class="back">{icon("chevron-left", 24, "#fff", 2.2)}</div>
      <div class="who"><div class="av">A</div><span>Alex</span></div><div></div></div>
    <div class="day">Today</div>
    <div class="chat">{"".join(out)}</div>"""


def ring(pct, label, value):
    r = 34
    c = 2 * 3.14159 * r
    return (f'<div class="ring"><svg width="84" height="84"><circle cx="42" cy="42" r="{r}" '
            f'stroke="#2C2C2E" stroke-width="8" fill="none"/><circle cx="42" cy="42" r="{r}" '
            f'stroke="{ACCENT}" stroke-width="8" fill="none" stroke-linecap="round" '
            f'stroke-dasharray="{c * pct:.1f} {c:.1f}" transform="rotate(-90 42 42)"/></svg>'
            f'<b>{value}</b><span>{label}</span></div>')


def screen_device(wide):
    cores = "".join(
        f'<i style="background:rgba(217,61,0,{a})"></i>'
        for a in [0.95, 0.7, 0.85, 0.4, 0.6, 0.3, 0.9, 0.5])
    rows = [("cpu", "CPU", "8 cores"), ("battery", "Battery", "94%"),
            ("memory-stick", "Memory", "8 GB"), ("monitor", "Display", "120 Hz")]
    group = "".join(f'<div class="lrow">{icon(i, 22, "#8E8E93")}<span class="lt">{t}</span>'
                    f'<span class="ld">{d}</span></div>' for i, t, d in rows)
    return f"""
    {status_bar()}
    {nav(None, None, [])}
    {large("Your phone", "Octa-core, 8 GB, Android 16")}
    <div class="pad">
      <div class="die"><div class="cores">{cores}</div><div class="dielabel">3.2 GHz</div></div>
      <div class="rings">{ring(0.51, "Storage", "51%")}{ring(0.94, "Battery", "94%")}{ring(1, "Protection", "100%")}</div>
      <div class="group">{group}</div>
    </div>
    {tab_bar("Device")}"""


def screen_server(wide):
    rows = [("Back up on its own", True), ("Wi-Fi only", True), ("While charging", True)]
    group = "".join(f'<div class="lrow"><span class="lt">{t}</span><span class="sw{" on" if on else ""}"><i></i></span></div>'
                    for t, on in rows)
    strip = "".join(photo(n, "height:86px;border-radius:12px") for n in ["k24", "k3", "chelsea", "k21"])
    return f"""
    {status_bar()}
    {nav("More", None, [])}
    {large("Home server", "Next run tonight, 2:00")}
    <div class="pad">
      <div class="srv">
        <div class="srvicon">{icon("hard-drive", 34, "#fff", 1.8)}</div>
        <div class="srvline"><span class="dot"></span><span class="dot"></span><span class="dot on"></span></div>
        <div class="srvicon ph2">{icon("smartphone", 30, "#fff", 1.8)}</div>
      </div>
      <div class="h2 center">2,418 photos backed up</div>
      <div class="row4">{strip}</div>
      <div class="h3 muted">When</div>
      <div class="group">{group}</div>
    </div>
    {tab_bar("More")}"""


def screen_home(wide):
    tools = [("shrink", "Make smaller", "178 MB to shrink"), ("copy", "Similar photos", "67 sets"),
             ("message-circle", "Message archive", "17 kept"), ("server", "Home server", "Nightly")]
    grid = "".join(f'<div class="tool"><div class="ti">{icon(i, 22, "#fff", 1.9)}</div>'
                   f'<b>{t}</b><span>{d}</span></div>' for i, t, d in tools)
    stack = "".join(
        f'<div class="print" style="transform:rotate({r}deg) translate({x}px,{y}px)">{photo(n, "position:absolute;inset:0")}</div>'
        for n, r, x, y in [("k9", -10, -18, 6), ("k22", 6, 10, -4), ("k23", -2, 0, 0)])
    return f"""
    {status_bar()}
    <div class="nav"><div></div><div class="acts"><div class="navbtn">{icon("search", 19, "#fff", 2)}</div></div></div>
    {large("Recovery")}
    <div class="pad">
      <div class="dash">
        <div class="pill tl">{icon("shield", 13, "#fff", 2.2)} Protected</div>
        <div class="stack">{stack}</div>
        <div class="dashtext"><b>14 photos can come back</b><span>Watching trash, chats and statuses</span></div>
      </div>
      <div class="rings card">{ring(0.51, "Storage", "51%")}{ring(0.94, "Battery", "94%")}{ring(1, "Protection", "100%")}</div>
      <div class="h3">Tools</div>
      <div class="tools">{grid}</div>
    </div>
    {tab_bar("Home")}"""


SLIDES = [
    ("01-Restore", "Bring back <em>deleted</em> photos", screen_restore),
    ("02-Grid", "Every deleted file, <em>sorted</em>", screen_grid),
    ("03-Play", "Play it <em>before</em> you decide", screen_player),
    ("04-Shrink", "Same photos, <em>less space</em>", screen_shrink),
    ("05-Messages", "Keep messages they <em>unsend</em>", screen_messages),
    ("06-Device", "Know your <em>phone</em>", screen_device),
    ("07-Backup", "Back up to <em>your own</em> server", screen_server),
    ("08-Home", "Recovery, cleanup, <em>one app</em>", screen_home),
]

CSS = (ROOT / "slide.css").read_text()


def page(head, body, form):
    """One slide. Phone: 540x960 CSS, tablet: 800x1280 CSS."""
    if form == "phone":
        w, h, sw, sh, scale, top = 540, 960, 390, 844, 1.16, 248
    elif form == "fold":
        w, h, sw, sh, scale, top = 960, 1080, 600, 1000, 1.15, 240
    else:
        w, h, sw, sh, scale, top = 800, 1280, 600, 1000, 1.2, 270
    left = (w - sw * scale) / 2
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}
    body{{width:{w}px;height:{h}px}}
    .screen{{width:{sw}px;height:{sh}px;left:{left}px;top:{top}px;transform:scale({scale})}}
    </style></head><body class="{form}">
    <div class="glow"></div>
    <div class="headline">{head}</div>
    <div class="screen">{body}</div>
    </body></html>"""


def render(name, html, form):
    w, h = {"phone": (540, 960), "fold": (960, 1080), "tablet": (800, 1280)}[form]
    src = OUT / f"{form}-{name}.html"
    src.write_text(html)
    png = OUT / f"{form}-{name}.png"
    subprocess.run(
        ["google-chrome", "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
         f"--window-size={w},{h}", "--force-device-scale-factor=2",
         f"--screenshot={png}", src.as_uri()],
        check=True, capture_output=True)
    src.unlink()
    return png


if __name__ == "__main__":
    for name, head, fn in SLIDES:
        for form in sys.argv[2:] or ("phone", "tablet", "fold"):
            print(render(name, page(head, fn(form != "phone"), form), form))
