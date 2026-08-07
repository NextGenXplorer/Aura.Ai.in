"""Renders the AURA app logo to assets/branding/aura_logo.png (1024x1024).

Recreates the brand mark: a dark rounded-square backdrop with a glowing
white/lavender robot head (also a chat bubble), cyan->purple gradient eyes,
side "headphone" bumps, a vertical trio of antenna dots, and a speech-bubble
tail. Used as the single source for flutter_launcher_icons.
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
CX = S // 2

BG = (11, 11, 20, 255)          # near-black backdrop
LAV = (232, 228, 245, 255)      # head lavender/white
EAR = (169, 199, 255, 255)      # side bump light blue
DOT = (74, 150, 255, 255)       # antenna blue
EYE_TOP = (78, 197, 248)        # cyan
EYE_BOT = (138, 107, 224)       # purple


def rrect(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def gradient_pill(w, h, top, bot, radius):
    """A rounded-rect (pill) filled with a vertical gradient, RGBA."""
    grad = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = grad.load()
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    grad.putalpha(mask)
    return grad


def glow(shape_img, blur, color):
    """Return a blurred coloured copy of the alpha of shape_img for a glow."""
    a = shape_img.split()[-1]
    g = Image.new("RGBA", shape_img.size, (0, 0, 0, 0))
    solid = Image.new("RGBA", shape_img.size, color + (255,))
    g = Image.composite(solid, g, a)
    return g.filter(ImageFilter.GaussianBlur(blur))


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Backdrop rounded square (launcher will mask further).
rrect(draw, [0, 0, S - 1, S - 1], radius=232, fill=BG)

# ── Glows layer (behind everything) ─────────────────────────────────────────
glow_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow_layer)
# Head glow (purple/blue)
gd.ellipse([210, 315, 814, 735], fill=(120, 110, 220, 255))
glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(55))
img = Image.alpha_composite(img, glow_layer)
draw = ImageDraw.Draw(img)

# ── Side "ears" / headphone bumps ───────────────────────────────────────────
ear_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
egd = ImageDraw.Draw(ear_glow)
egd.rounded_rectangle([196, 470, 262, 585], radius=33, fill=EAR)
egd.rounded_rectangle([762, 470, 828, 585], radius=33, fill=EAR)
img = Image.alpha_composite(img, ear_glow.filter(ImageFilter.GaussianBlur(18)))
draw = ImageDraw.Draw(img)
rrect(draw, [200, 474, 258, 581], radius=29, fill=EAR)
rrect(draw, [766, 474, 824, 581], radius=29, fill=EAR)

# ── Antenna dots (top -> down, growing) ─────────────────────────────────────
dots = [((CX, 178), 13), ((CX, 233), 18), ((CX, 292), 23)]
dot_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dgd = ImageDraw.Draw(dot_glow)
for (x, y), r in dots:
    dgd.ellipse([x - r, y - r, x + r, y + r], fill=DOT)
img = Image.alpha_composite(img, dot_glow.filter(ImageFilter.GaussianBlur(10)))
draw = ImageDraw.Draw(img)
for (x, y), r in dots:
    draw.ellipse([x - r, y - r, x + r, y + r], fill=DOT)

# ── Speech-bubble tail (bottom of head) ─────────────────────────────────────
draw.polygon([(430, 660), (398, 762), (496, 690)], fill=LAV)

# ── Robot head ring (head is a thick rounded ring = chat bubble) ────────────
# Outer head
rrect(draw, [236, 330, 788, 720], radius=190, fill=LAV)
# Inner cutout -> dark, leaving a thick ring
rrect(draw, [292, 386, 732, 664], radius=150, fill=BG)

# ── Eyes (cyan -> purple gradient pills) ────────────────────────────────────
ew, eh = 40, 78
left = gradient_pill(ew, eh, EYE_TOP, EYE_BOT, radius=20)
right = gradient_pill(ew, eh, EYE_TOP, EYE_BOT, radius=20)
eye_y = 486
# glow behind eyes
eye_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
eye_glow.alpha_composite(glow(left, 14, EYE_TOP), (442, eye_y))
eye_glow.alpha_composite(glow(right, 14, EYE_TOP), (542, eye_y))
img = Image.alpha_composite(img, eye_glow)
img.alpha_composite(left, (442, eye_y))
img.alpha_composite(right, (542, eye_y))

# Save
import os
os.makedirs("assets/branding", exist_ok=True)
img.save("assets/branding/aura_logo.png")
print("Wrote assets/branding/aura_logo.png", img.size)
