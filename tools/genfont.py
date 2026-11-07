#!/usr/bin/env python3
"""Generate BMFont resources (.fnt + .png) for the Loom/DOOM watch app.

The Instinct 3 Solar firmware rejects every built-in Graphics.FONT_* constant
at run time, so we ship our own bitmap font as a Connect IQ font resource
(BMFont text format). Two sizes are generated from PIL's embedded bitmap font:
  - loom_small : 1x  (glyph cell 12x9, advance 6, cap height 7)
  - loom_big   : 2x  (glyph cell 24x18, advance 12, cap height 14)
"""
from PIL import Image, ImageDraw, ImageFont
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "resources", "fonts")
CHARS = [chr(c) for c in range(32, 127)]  # printable ASCII


def render_glyphs(scale):
    """Render each char into a fixed cell; return list of PIL images."""
    font = ImageFont.load_default()
    imgs = []
    # Canvas layout: draw at (4,4). Caps occupy rows 7..12, descenders to 15.
    # Glyph advance is 6 px, so crop cols 0..5 -> cell width == advance.
    crop_h = 9  # source rows 7..15 inclusive (descender included)
    crop_w = 6  # source cols 0..5 exactly one glyph advance
    for ch in CHARS:
        canvas = Image.new("L", (24, 24), 0)
        ImageDraw.Draw(canvas).text((4, 4), ch, font=font, fill=255)
        cell = canvas.crop((4, 7, 4 + crop_w, 7 + crop_h))  # 6x9, cap top at row 0
        if scale != 1:
            cell = cell.resize((crop_w * scale, crop_h * scale), Image.NEAREST)
        imgs.append(cell)
    return imgs


def build_font(name, scale):
    cells = render_glyphs(scale)
    cw, chh = cells[0].size
    adv = 6 * scale
    base = 6 * scale
    line_h = 10 * scale
    cols = max(1, 512 // (cw + 1))
    rows = (len(cells) + cols - 1) // cols
    atlas = Image.new("L", (cols * cw, rows * chh), 0)
    entries = []
    for idx, ch in enumerate(CHARS):
        gx = (idx % cols) * cw
        gy = (idx // cols) * chh
        atlas.paste(cells[idx], (gx, gy))
        code = ord(ch)
        entries.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 "
            "xadvance=%d page=0 chnl=15"
            % (code, gx, gy, cw, chh, adv)
        )
    png = os.path.join(OUT, name + ".png")
    atlas.save(png)
    fnt = os.path.join(OUT, name + ".fnt")
    with open(fnt, "w") as fh:
        fh.write(
            'info face="LoomMono" size=%d bold=0 italic=0 charset="" unicode=1 '
            'stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=0,0 outline=0\n'
            % line_h
        )
        fh.write(
            "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 "
            "alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0\n"
            % (line_h, base, atlas.size[0], atlas.size[1])
        )
        fh.write('page id=0 file="%s.png"\n' % name)
        fh.write("chars count=%d\n" % len(entries))
        fh.write("\n".join(entries) + "\n")
    print("%s: atlas %s, chars %d, cell %dx%d" % (name, atlas.size, len(cells), cw, chh))


os.makedirs(OUT, exist_ok=True)
build_font("loom_small", 1)
build_font("loom_big", 2)

with open(os.path.join(OUT, "fonts.xml"), "w") as fh:
    fh.write(
        "<fonts>\n"
        '    <font id="DoomSmall" filename="loom_small.fnt" antialias="false"/>\n'
        '    <font id="DoomBig" filename="loom_big.fnt" antialias="false"/>\n'
        "</fonts>\n"
    )
print("fonts.xml written")
