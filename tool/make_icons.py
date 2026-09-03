"""Generate the Foldboard icon set from the app palette.

Mark: two rounded nodes joined by an arrow — the board's only two primitives.
Drawn at 4x and downsampled so the strokes stay clean at 16 px.
"""

from PIL import Image, ImageDraw
import os

BG = (17, 19, 16, 255)  # AppPalette.dark.background #111310
ACCENT = (182, 243, 107, 255)  # AppPalette.dark.accent #B6F36B
DIM = (109, 146, 64, 255)  # accent at ~60% over the background

SS = 4  # supersampling factor
WEB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web")
os.makedirs(os.path.join(WEB, "icons"), exist_ok=True)


def _target(name):
    """Manifest icons live in web/icons; the rest sit at the web root."""
    return os.path.join(WEB, "icons", name) if name.startswith("Icon-") or name.startswith("apple-") else os.path.join(WEB, name)



def draw_mark(d, box, scale):
    """Two nodes + arrow inside `box` (l, t, r, b). `scale` = px per unit."""
    l, t, r, b = box
    w = r - l
    stroke = max(1, round(w * 0.062))
    node_w = w * 0.42
    node_h = w * 0.30
    radius = w * 0.075

    # Upper-left node: outline (the source).
    a = (l, t, l + node_w, t + node_h)
    d.rounded_rectangle(a, radius=radius, outline=ACCENT, width=stroke)

    # Lower-right node: filled (the destination).
    c = (r - node_w, b - node_h, r, b)
    d.rounded_rectangle(c, radius=radius, fill=ACCENT)

    # Elbow arrow from the source's bottom edge to the target's left edge.
    x0 = l + node_w / 2
    y0 = t + node_h
    x1 = r - node_w
    y1 = b - node_h / 2
    bend = w * 0.10
    d.line(
        [(x0, y0), (x0, y1 - bend), (x0 + bend, y1), (x1 - w * 0.055, y1)],
        fill=DIM,
        width=stroke,
        joint="curve",
    )
    # Arrow head pointing at the filled node.
    head = w * 0.075
    tip = (x1, y1)
    d.polygon(
        [tip, (x1 - head, y1 - head * 0.62), (x1 - head, y1 + head * 0.62)],
        fill=DIM,
    )


def render(size, *, inset, rounded, bg=BG):
    """`inset` is the fraction of the canvas left as padding around the mark."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=s * 0.22, fill=bg)
    else:
        d.rectangle((0, 0, s, s), fill=bg)
    pad = s * inset
    draw_mark(d, (pad, pad, s - pad, s - pad), s)
    return img.resize((size, size), Image.LANCZOS)


targets = [
    ("favicon.png", 64, 0.16, True),
    ("Icon-192.png", 192, 0.20, True),
    ("Icon-512.png", 512, 0.20, True),
    ("Icon-maskable-192.png", 192, 0.29, False),
    ("Icon-maskable-512.png", 512, 0.29, False),
    ("apple-touch-icon.png", 180, 0.20, False),
    ("og-image.png", None, None, None),  # handled below
]

for name, size, inset, rounded in targets:
    if name == "og-image.png":
        continue
    render(size, inset=inset, rounded=rounded).save(_target(name))
    print("wrote", name, size)

# Social preview: 1200x630 wordmark on the app background.
og = Image.new("RGBA", (1200, 630), BG)
mark = render(220, inset=0.06, rounded=False, bg=(0, 0, 0, 0))
# The lockup is centered as a whole: mark + gap + the wider subtitle.
og.alpha_composite(mark, (172, 205))
d = ImageDraw.Draw(og)
try:
    from PIL import ImageFont

    title = ImageFont.truetype("segoeuib.ttf", 82)
    body = ImageFont.truetype("segoeui.ttf", 30)
except Exception:  # pragma: no cover - font availability differs per machine
    title = body = None
d.text((448, 218), "Foldboard", font=title, fill=(242, 244, 238, 255))
d.text(
    (448, 337),
    "Plans of any scale. One bounded context at a time.",
    font=body,
    fill=(170, 176, 164, 255),
)
og.convert("RGB").save(_target("og-image.png"), quality=92)
print("wrote og-image.png")
