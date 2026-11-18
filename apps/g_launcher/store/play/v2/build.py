"""Build the G Launcher Play slides (v2) as 1080x1920 PNGs, per language.

Each slide is one HTML page at 540x960 CSS px, rendered by headless Chrome at
2x. One line of copy per slide; the distro's own wallpaper carries the rest.

    python3 build.py <assets_dir> <fonts_dir> <out_dir>
"""
import pathlib
import subprocess
import sys

ASSETS, FONTS, OUT = (pathlib.Path(p).resolve() for p in sys.argv[1:4])

COPY = {
    "en": dict(free="Free", desktops="desktops", icons="Icon packs", setup="Pick your desktop",
               step="Step 2 of 5", next="Next", browser="Browser", mail="Mail", files="Files",
               camera="Camera", photos="Photos", music="Music", maps="Maps", calendar="Calendar",
               weather="Weather", notes="Notes", settings="Settings", clock="Clock",
               date="Tuesday, November 10", bar="Tue 10 Nov  21:42", cloudy="Partly cloudy",
               day="TUESDAY", line="Line", bold="Bold"),
    "es": dict(free="Gratis", desktops="escritorios", icons="Packs de iconos", setup="Elige tu escritorio",
               step="Paso 2 de 5", next="Siguiente", browser="Navegador", mail="Correo", files="Archivos",
               camera="Cámara", photos="Fotos", music="Música", maps="Mapas", calendar="Calendario",
               weather="Clima", notes="Notas", settings="Ajustes", clock="Reloj",
               date="martes, 10 de noviembre", bar="mar 10 nov  21:42", cloudy="Parcialmente nublado",
               day="MARTES", line="Line", bold="Bold"),
    "pt": dict(free="Grátis", desktops="desktops", icons="Pacotes de ícones", setup="Escolha seu desktop",
               step="Etapa 2 de 5", next="Próximo", browser="Navegador", mail="E-mail", files="Arquivos",
               camera="Câmera", photos="Fotos", music="Música", maps="Mapas", calendar="Calendário",
               weather="Clima", notes="Notas", settings="Configurações", clock="Relógio",
               date="terça-feira, 10 de novembro", bar="ter 10 nov  21:42", cloudy="Parcialmente nublado",
               day="TERÇA", line="Line", bold="Bold"),
}

# Stroke glyphs on a 24 grid, shared by every icon style.
G = {
    "terminal": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 10l3 2.5L7 15M12.5 15H17"/>',
    "browser": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18"/>',
    "mail": '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3.5 7l8.5 6 8.5-6"/>',
    "files": '<path d="M4 7a2 2 0 012-2h4l2 2h6a2 2 0 012 2v8a2 2 0 01-2 2H6a2 2 0 01-2-2z"/>',
    "camera": '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7l1.5-3h5L16 7"/><circle cx="12" cy="13.5" r="3.2"/>',
    "photos": '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M4 18l5-5 3.5 3.5L16 13l4 4"/>',
    "music": '<path d="M9 18V6l10-2v12"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="16.5" cy="16" r="2.5"/>',
    "maps": '<path d="M9 4L3 6.5v13L9 17l6 2.5 6-2.5v-13L15 6.5z"/><path d="M9 4v13M15 6.5v13"/>',
    "calendar": '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 10h16M8 3v4M16 3v4"/>',
    "weather": '<path d="M7 18a4 4 0 010-8 5.5 5.5 0 0110.6 1.5A3.3 3.3 0 0117 18z"/>',
    "notes": '<path d="M6 3h9l4 4v14H6z"/><path d="M9 11h7M9 15h7"/>',
    "settings": '<circle cx="12" cy="12" r="3"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1"/>',
    "clock": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
}
TINT = {"browser": "#3b82f6", "mail": "#f6b93b", "files": "#7a8a99", "terminal": "#2b2b33",
        "music": "#f97316", "calendar": "#ef4444", "camera": "#0ea5a4", "photos": "#a855f7",
        "maps": "#22c55e", "weather": "#38bdf8", "notes": "#eab308", "settings": "#64748b",
        "clock": "#111827"}


def svg(name, size, stroke="#fff", width=1.6):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{stroke}" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round">{G[name]}</svg>')


def tile(name, size, radius, bg=None):
    """A filled app icon: coloured plate with a white glyph."""
    return (f'<div class="tile" style="width:{size}px;height:{size}px;border-radius:{radius}px;'
            f'background:{bg or TINT[name]}">{svg(name, round(size * 0.55), width=1.8)}</div>')


def img(name):
    return (ASSETS / f"{name}.webp").as_uri()


def head_size(text):
    n = len(text)
    return 104 if n <= 7 else 84 if n <= 10 else 66 if n <= 13 else 58 if n <= 16 else 48


def headline(text, top, pill=None, pill_bg="#e95420"):
    size = head_size(text)
    out = (f'<div class="head" style="top:{top}px"><div style="font-size:{size}px;line-height:{size}px;'
           f'letter-spacing:{-size * 0.03:.1f}px">{text}</div>')
    if pill:
        out += f'<div class="pill" style="background:{pill_bg}">{pill}</div>'
    return out + "</div>"


def backdrop(name, bright=0.5):
    return f'<img class="backdrop" src="{img(name)}" style="filter:blur(34px) brightness({bright}) saturate(1.25)">'


def phone(inner, wallpaper=None, top=268, bg="#000", edge="#05060a"):
    """The device. top=268 rises from the bottom edge, top=-150 hangs from the top."""
    wp = f'<img class="wp" src="{img(wallpaper)}">' if wallpaper else ""
    return f'<div class="phone" style="top:{top}px;background:{bg};border-color:{edge}">{wp}{inner}</div>'


def kali(t):
    rows = [("kali@kali", "21:42"), ("uptime", "3h 12m"), ("cpu", "12%"), ("ram", "3.1 / 8.0 GB")]
    read = "".join(f'<div class="row"><span{" style=color:#4aa3ff" if i == 0 else ""}>{a}</span><b>{b}</b></div>'
                   for i, (a, b) in enumerate(rows))
    names = ["terminal", "browser", "mail", "files", "camera", "photos", "music", "maps"]
    grid = "".join(f'<div class="app">{svg(n, 44, width=1.5)}<span>{t.get(n, "Terminal")}</span></div>' for n in names)
    inner = f'''
<div class="kread">{read}<div class="kbar"><i></i></div></div>
<div class="grid4" style="top:668px;color:#e8f3ff">{grid}</div>
<div class="kpanel"><svg width="22" height="22" viewBox="0 0 24 24" fill="#4aa3ff"><rect x="3" y="3" width="7.5" height="7.5" rx="1"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="1"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="1"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1"/></svg>
{svg("terminal", 22)}{svg("browser", 22)}<div style="flex:1"></div><div class="ws">1</div><div style="font-size:14px;font-weight:500">21:42</div></div>'''
    return backdrop("kali-nova") + phone(inner, "kali-nova", top=-150, edge="#03070d") + headline("Kali Linux", 814)


def ubuntu(t):
    dock = "".join(tile(n, 44, 12) for n in ["browser", "mail", "files", "terminal", "music", "calendar"])
    inner = f'''
<div class="ubar">{t["bar"]}</div>
<div class="udock">{dock}</div>
<div style="position:absolute;left:96px;top:96px"><div style="font-size:84px;line-height:88px;font-weight:300;letter-spacing:-2px">21:42</div>
<div style="font-size:17px;opacity:.9;margin-top:4px">{t["date"]}</div></div>'''
    return backdrop("ubuntu", 0.62) + headline("Ubuntu", 64, t["free"]) + phone(inner, "ubuntu", edge="#0d0509")


def desktops(t):
    def card(name, left, top, rot, w=250, h=540):
        return (f'<div class="card" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px;'
                f'transform:rotate({rot}deg)"><img src="{img(name)}"></div>')
    fan = (card("milky", -148, 470, -14) + card("pocket", 438, 470, 14) + card("ubuntu", -10, 420, -7)
           + card("plasma-tree", 300, 420, 7) + card("kali-ferro", 135, 390, 0, 270, 584))
    return (f'<div class="head" style="top:64px"><div style="font-size:210px;line-height:190px;letter-spacing:-8px">15</div>'
            f'<div style="font-size:56px;line-height:64px;letter-spacing:-1.5px">{t["desktops"]}</div></div>{fan}')


def plasma(t):
    apps = "".join(tile(n, 34, 8) for n in ["browser", "files", "terminal", "music"])
    inner = f'''
<div class="ppanel"><div class="kick"></div>{apps}<div style="flex:1"></div>
<div style="text-align:right;font-size:12px;line-height:15px"><b style="font-weight:500">21:42</b><br><span style="opacity:.8">10/11</span></div></div>'''
    return (backdrop("plasma-tree", 0.55) + phone(inner, "plasma-tree", top=-150, edge="#04050c")
            + headline("KDE Plasma", 800, t["free"], "#1d99f3"))


def pocket(t):
    names = ["mail", "calendar", "photos", "camera", "maps", "weather", "clock", "notes", "music", "files", "browser", "settings"]
    grid = "".join(f'<div class="app">{tile(n, 62, 16)}<span>{t.get(n, n)}</span></div>' for n in names)
    inner = f'''
<div class="widgets"><div class="glass"><div style="font-size:13px;opacity:.85">San Diego</div><div style="font-size:50px;line-height:56px;font-weight:300">18°</div><div style="font-size:12px;opacity:.85;margin-top:22px">{t["cloudy"]}</div></div>
<div class="glass"><div style="font-size:12px;font-weight:700;color:#ffb4c8">{t["day"]}</div><div style="font-size:50px;line-height:56px;font-weight:300">10</div></div></div>
<div class="grid4" style="top:262px;font-size:12px">{grid}</div>'''
    return backdrop("pocket", 0.7) + headline("Pocket", 64) + phone(inner, "pocket", edge="#120a1c")


def terminal(t):
    apps = [t["browser"], t["calendar"], t["camera"], t["clock"], t["files"], t["mail"], t["maps"],
            t["music"], t["notes"], t["photos"], t["settings"], t["weather"]]
    cols = "".join(f"<span>{a.lower()}</span>" for a in apps)
    inner = f'''
<div class="tty"><div style="color:#2f9e55">G Launcher tty1</div>
<div><b>user@phone</b>:~$ ls apps</div><div class="cols">{cols}</div>
<div><b>user@phone</b>:~$ battery</div><div>[<i class="batt"></i>] 78%</div>
<div><b>user@phone</b>:~$ open {t["camera"].lower()}<i class="caret"></i></div></div>'''
    glow = '<div style="position:absolute;inset:0;background:radial-gradient(60% 45% at 50% 38%,#0f3d22 0%,#030705 70%)"></div>'
    return glow + phone(inner, None, top=-150, bg="#020403", edge="#16301f") + headline("Terminal", 800, t["free"], "#1f8f4a")


def icons(t):
    names = ["browser", "mail", "camera", "music", "files", "maps", "photos", "calendar"]
    line = "".join(f'<div class="ic" style="background:#151a24;border:1px solid #2a3344">{svg(n, 60, "#8fd0ff", 1.5)}</div>' for n in names[:4])
    bold = "".join(f'<div class="ic" style="background:#e95420;border-radius:50%">{svg(n, 58, width=1.9)}</div>' for n in names[4:])
    col = "".join(f'<div class="ic" style="background:{TINT[n]}">{svg(n, 60, width=1.8)}</div>' for n in ["weather", "notes", "terminal", "clock"])
    rows = f'<div class="icrow" style="top:330px;left:-40px">{line}{line}</div><div class="icrow" style="top:500px;left:-125px">{bold}{bold}</div><div class="icrow" style="top:670px;left:-40px">{col}{col}</div><div class="icrow" style="top:840px;left:-125px">{line}{line}</div>'
    return '<div style="position:absolute;inset:0;background:#0b0d13"></div>' + headline(t["icons"], 96) + rows


def setup(t):
    opts = [("Ubuntu", "#e95420", True), ("KDE Plasma", "#1d99f3", False), ("Kali Linux", "#367bf0", False),
            ("Linux Mint", "#6fbd45", False), ("Arch Linux", "#1793d1", False), ("Terminal", "#22c55e", False)]
    rows = "".join(f'<div class="opt{" on" if on else ""}"><i style="background:{c}"></i><span>{n}</span><u></u></div>' for n, c, on in opts)
    inner = f'''<div style="position:absolute;inset:0;background:#1a0812"></div>
<div class="steps"><i class="on"></i><i class="on"></i><i></i><i></i><i></i></div>
<div style="position:absolute;left:26px;top:74px;font-size:13px;opacity:.7">{t["step"]}</div>
<div class="opts">{rows}</div>'''
    return backdrop("ubuntu", 0.42) + headline(t["setup"], 84) + phone(inner, None, edge="#0d0509")


SLIDES = [("01-Kali", kali), ("02-Ubuntu", ubuntu), ("03-Desktops", desktops), ("04-Plasma", plasma),
          ("05-Pocket", pocket), ("06-Terminal", terminal), ("07-Icons", icons), ("08-Setup", setup)]

CSS = f'''
@font-face{{font-family:U;font-weight:300;src:url("{(FONTS / "Ubuntu-Light.ttf").as_uri()}")}}
@font-face{{font-family:U;font-weight:400;src:url("{(FONTS / "Ubuntu-Regular.ttf").as_uri()}")}}
@font-face{{font-family:U;font-weight:500;src:url("{(FONTS / "Ubuntu-Medium.ttf").as_uri()}")}}
@font-face{{font-family:U;font-weight:700;src:url("{(FONTS / "Ubuntu-Bold.ttf").as_uri()}")}}
@font-face{{font-family:UM;font-weight:400;src:url("{(FONTS / "UbuntuMono-Regular.ttf").as_uri()}")}}
@font-face{{font-family:UM;font-weight:700;src:url("{(FONTS / "UbuntuMono-Bold.ttf").as_uri()}")}}
*{{box-sizing:border-box}}html,body{{margin:0}}
body{{width:540px;height:960px;position:relative;overflow:hidden;background:#0b0c10;color:#fff;font-family:U,sans-serif}}
.backdrop{{position:absolute;left:-80px;top:-120px;width:700px;height:1200px;object-fit:cover}}
.head{{position:absolute;left:0;right:0;display:flex;flex-direction:column;align-items:center;gap:14px;font-weight:700;text-align:center}}
.pill{{padding:6px 18px;border-radius:999px;font-size:20px;font-weight:500}}
.phone{{position:absolute;left:55px;width:430px;height:930px;border:7px solid;border-radius:48px;overflow:hidden;box-shadow:0 40px 90px rgba(0,0,0,.6)}}
.wp{{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}}
.tile{{display:flex;align-items:center;justify-content:center;flex:none}}
.grid4{{position:absolute;left:22px;right:22px;display:grid;grid-template-columns:repeat(4,1fr);gap:26px 8px;font-size:12px;text-align:center}}
.app{{display:flex;flex-direction:column;align-items:center;gap:8px}}
.kread{{position:absolute;left:22px;right:22px;top:500px;padding:14px 16px;background:rgba(4,14,24,.72);border:1px solid rgba(90,170,255,.35);border-radius:6px;font-family:UM,monospace;font-size:13px;line-height:22px;color:#9fd0ff}}
.kread .row{{display:flex;justify-content:space-between}}.kread b{{color:#fff;font-weight:400}}
.kbar{{height:4px;margin-top:8px;background:rgba(74,163,255,.25);border-radius:2px}}.kbar i{{display:block;width:39%;height:4px;background:#4aa3ff;border-radius:2px}}
.kpanel{{position:absolute;left:0;right:0;bottom:0;height:46px;padding:0 16px;background:rgba(6,12,20,.92);border-top:1px solid rgba(90,170,255,.3);display:flex;align-items:center;gap:18px}}
.ws{{width:24px;height:24px;border:1px solid #4aa3ff;border-radius:3px;font-size:13px;line-height:22px;text-align:center;color:#4aa3ff}}
.ubar{{position:absolute;left:0;right:0;top:0;height:34px;background:rgba(0,0,0,.28);display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:500;white-space:pre}}
.udock{{position:absolute;left:0;top:34px;bottom:0;width:62px;background:rgba(20,8,16,.72);display:flex;flex-direction:column;align-items:center;gap:12px;padding-top:14px}}
.card{{position:absolute;border-radius:30px;overflow:hidden;border:5px solid #000;box-shadow:0 30px 60px rgba(0,0,0,.6)}}.card img{{width:100%;height:100%;object-fit:cover}}
.ppanel{{position:absolute;left:10px;right:10px;bottom:10px;height:52px;padding:0 12px;border-radius:12px;background:rgba(27,30,38,.88);border:1px solid rgba(255,255,255,.14);display:flex;align-items:center;gap:10px}}
.kick{{width:34px;height:34px;border-radius:50%;background:linear-gradient(135deg,#31c6f7,#1d6fd6);flex:none}}
.widgets{{position:absolute;left:22px;right:22px;top:44px;display:grid;grid-template-columns:1fr 1fr;gap:16px}}
.glass{{height:176px;padding:16px;border-radius:26px;background:rgba(255,255,255,.2);border:1px solid rgba(255,255,255,.3)}}
.tty{{position:absolute;left:24px;right:24px;top:300px;font-family:UM,monospace;font-size:17px;line-height:30px;color:#39d353}}
.tty b{{color:#7ee787;font-weight:700}}.cols{{display:grid;grid-template-columns:1fr 1fr;color:#b6f5c5;margin:2px 0 14px}}
.batt{{display:inline-block;width:150px;height:12px;background:linear-gradient(90deg,#39d353 78%,#123d22 78%)}}
.caret{{display:inline-block;width:10px;height:19px;background:#39d353;margin-left:3px;vertical-align:-3px}}
.icrow{{position:absolute;display:flex;gap:30px}}.ic{{width:140px;height:140px;border-radius:34px;display:flex;align-items:center;justify-content:center;flex:none}}
.steps{{position:absolute;left:26px;right:26px;top:46px;display:flex;gap:6px}}.steps i{{flex:1;height:3px;border-radius:2px;background:rgba(255,255,255,.2)}}.steps i.on{{background:#e95420}}
.opts{{position:absolute;left:22px;right:22px;top:112px;display:flex;flex-direction:column;gap:12px}}
.opt{{height:68px;padding:0 18px;border-radius:12px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);display:flex;align-items:center;gap:16px;font-size:19px;font-weight:500}}
.opt i{{width:30px;height:30px;border-radius:8px}}.opt span{{flex:1}}.opt u{{width:20px;height:20px;border-radius:50%;border:2px solid rgba(255,255,255,.4)}}
.opt.on{{border-color:#e95420;background:rgba(233,84,32,.16)}}.opt.on u{{border-color:#e95420;background:radial-gradient(#e95420 45%,transparent 50%)}}
'''

for lang, t in COPY.items():
    (OUT / lang).mkdir(parents=True, exist_ok=True)
    for name, fn in SLIDES:
        page = OUT / f"_{lang}-{name}.html"
        page.write_text(f'<!doctype html><html lang="{lang}"><meta charset="utf-8"><style>{CSS}</style><body>{fn(t)}</body></html>')
        png = OUT / lang / f"{name}.png"
        subprocess.run(["google-chrome", "--headless=new", "--no-sandbox", "--hide-scrollbars",
                        "--force-device-scale-factor=2", "--window-size=540,960",
                        "--allow-file-access-from-files", f"--screenshot={png}", page.as_uri()],
                       check=True, capture_output=True)
        page.unlink()
print("done")
