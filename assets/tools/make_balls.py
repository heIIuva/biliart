"""Generate the pool ball set for HU HU POOL.

One UV-sphere mesh (pole along local X) + one equirectangular texture per ball.
Texture and mesh share the same direction<->UV mapping:
    u = (atan2(dy, dz) + pi) / (2 pi)      seam at -Z
    v = (asin(dx) + pi/2) / pi             (OBJ convention: v=0 at bottom of image)
At rest (identity rotation) the number circle sits on top (+Y) and the stripe band
wraps around the X axis, so it is visible from the top-down table camera.
Glyph "up" = local -Z = sim +Y = screen up in the table camera.
"""
import math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 1024, 512
SS = 3                     # supersampling per axis
BAND_LAT = math.radians(37)
CIRCLE = math.radians(27)  # angular radius of the white number disc
CUE_DOT = math.radians(7)
OUT = sys.argv[1] if len(sys.argv) > 1 else "."

WHITE = np.array([246, 243, 232]) / 255
COLORS = {
    1: (250, 196, 22), 2: (24, 62, 196), 3: (214, 32, 36), 4: (104, 40, 158),
    5: (242, 112, 24), 6: (18, 128, 64), 7: (128, 26, 36), 8: (16, 16, 18),
}
CUE_RED = np.array([205, 30, 36]) / 255
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

def directions(w, h, ss):
    cols = (np.arange(w * ss) + 0.5) / (w * ss)
    rows = (np.arange(h * ss) + 0.5) / (h * ss)
    u, r = np.meshgrid(cols, rows)
    v = 1.0 - r
    lat = v * math.pi - math.pi / 2
    lon = u * 2 * math.pi - math.pi
    dx = np.sin(lat)
    c = np.cos(lat)
    dy = c * np.sin(lon)
    dz = c * np.cos(lon)
    return np.stack([dx, dy, dz], -1)

def glyph_bitmap(text, size=600):
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(size * (0.62 if len(text) == 1 else 0.52)))
    if len(text) == 2:  # tighten two-digit numbers a little
        x0 = 0
        widths = [d.textlength(ch, font=font) for ch in text]
        total = sum(widths) - size * 0.03
        x = (size - total) / 2
        for ch, wd in zip(text, widths):
            bb = d.textbbox((0, 0), ch, font=font)
            d.text((x, size / 2 - (bb[1] + bb[3]) / 2), ch, font=font, fill=255)
            x += wd - size * 0.03
    else:
        bb = d.textbbox((0, 0), text, font=font)
        d.text(((size - (bb[0] + bb[2])) / 2, (size - (bb[1] + bb[3])) / 2), text, font=font, fill=255)
    if text in ("6", "9"):  # underline so 6/9 read correctly when rolling
        bb = img.getbbox()
        y = bb[3] + size * 0.05
        d.rectangle([size * 0.36, y, size * 0.64, y + size * 0.055], fill=255)
    return np.asarray(img, dtype=np.float32) / 255

def sample_glyph(bmp, x, y, half):
    """x,y in tangent-plane units, glyph square spans [-half, half]."""
    n = bmp.shape[0]
    px = (x / half * 0.5 + 0.5) * (n - 1)
    py = (0.5 - y / half * 0.5) * (n - 1)
    inside = (px >= 0) & (px <= n - 1) & (py >= 0) & (py <= n - 1)
    px = np.clip(px, 0, n - 1); py = np.clip(py, 0, n - 1)
    x0 = np.floor(px).astype(int); y0 = np.floor(py).astype(int)
    x1 = np.minimum(x0 + 1, n - 1); y1 = np.minimum(y0 + 1, n - 1)
    fx = px - x0; fy = py - y0
    val = (bmp[y0, x0] * (1 - fx) * (1 - fy) + bmp[y0, x1] * fx * (1 - fy)
           + bmp[y1, x0] * (1 - fx) * fy + bmp[y1, x1] * fx * fy)
    return np.where(inside, val, 0.0)

def cap_mask(d, center, ang, soft):
    cosd = d @ np.array(center, dtype=float)
    a = np.arccos(np.clip(cosd, -1, 1))
    return np.clip((ang - a) / soft + 0.5, 0, 1)

# Number discs: (center, up) — viewer outside the ball, right = up x center
DISCS = [((0, 1, 0), (0, 0, -1)), ((0, -1, 0), (0, 0, -1))]

def render(ball_id, d):
    shape = d.shape[:2]
    img = np.zeros(shape + (3,))
    soft = 1.5 * math.pi / (H * SS)  # ~1.5 subpixel feather
    if ball_id == 0:
        img[:] = WHITE
        for c in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]:
            m = cap_mask(d, c, CUE_DOT, soft)[..., None]
            img = img * (1 - m) + CUE_RED * m
        return img
    col = np.array(COLORS[ball_id if ball_id <= 8 else ball_id - 8]) / 255
    if ball_id <= 8:
        img[:] = col
    else:
        lat = np.arcsin(np.clip(d[..., 0], -1, 1))
        m = np.clip((BAND_LAT - np.abs(lat)) / soft + 0.5, 0, 1)[..., None]
        img = WHITE * (1 - m) + col * m
    bmp = glyph_bitmap(str(ball_id))
    half = math.tan(CIRCLE) * 0.80
    for center, up in DISCS:
        c = np.array(center, float); up = np.array(up, float)
        right = np.cross(up, c)
        disc = cap_mask(d, center, CIRCLE, soft)[..., None]
        img = img * (1 - disc) + WHITE * disc
        cosd = d @ c
        front = cosd > 0.2
        p = d / np.where(front, cosd, 1)[..., None] - c
        gx = p @ right; gy = p @ up
        g = sample_glyph(bmp, gx, gy, half) * front
        ink = np.array([20, 20, 22]) / 255
        img = img * (1 - g[..., None]) + ink * g[..., None]
    return img

def downsample(img):
    h, w = img.shape[0] // SS, img.shape[1] // SS
    return img.reshape(h, SS, w, SS, 3).mean(axis=(1, 3))

def write_obj(path, seg=48, rings=32):
    """Unit-diameter UV sphere, pole on X, same UV mapping as the textures."""
    vs, vts, vns, faces = [], [], [], []
    for j in range(rings + 1):
        v = j / rings
        lat = v * math.pi - math.pi / 2
        for i in range(seg + 1):
            u = i / seg
            if j in (0, rings):
                u = (i + 0.5) / seg  # pole vertices: centre of each fan triangle
            lon = u * 2 * math.pi - math.pi
            dx = math.sin(lat); c = math.cos(lat)
            dy = c * math.sin(lon); dz = c * math.cos(lon)
            vs.append((dx * 0.5, dy * 0.5, dz * 0.5)); vns.append((dx, dy, dz)); vts.append((u, v))
    row = seg + 1
    for j in range(rings):
        for i in range(seg):
            a = j * row + i; b = a + 1; c2 = a + row; d2 = c2 + 1
            # winding: counter-clockwise seen from outside
            if j != 0:
                faces.append((a, c2, b))
            if j != rings - 1:
                faces.append((b, c2, d2))
    # check winding against normals
    with open(path, "w") as f:
        f.write("# HU HU POOL ball: unit diameter UV sphere, pole along X\n")
        for x, y, z in vs: f.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
        for u, v in vts: f.write(f"vt {u:.6f} {v:.6f}\n")
        for x, y, z in vns: f.write(f"vn {x:.6f} {y:.6f} {z:.6f}\n")
        for t in faces:
            f.write("f " + " ".join(f"{k+1}/{k+1}/{k+1}" for k in t) + "\n")
    return np.array(vs), faces

if __name__ == "__main__":
    vs, faces = write_obj(f"{OUT}/pool_ball.obj")
    # winding sanity: normals of faces should point outward
    bad = 0
    for t in faces:
        p0, p1, p2 = vs[t[0]], vs[t[1]], vs[t[2]]
        n = np.cross(p1 - p0, p2 - p0)
        if np.dot(n, p0 + p1 + p2) < 0: bad += 1
    print("faces", len(faces), "inward", bad)
    d = directions(W, H, SS)
    for bid in range(16):
        tex = downsample(render(bid, d))
        Image.fromarray((np.clip(tex, 0, 1) * 255 + 0.5).astype(np.uint8)).save(f"{OUT}/textures/ball_{bid:02d}.png")
        print("ball", bid)
