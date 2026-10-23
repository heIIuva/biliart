"""Cue mesh (lathe along +X, butt at x=-0.5, tip at x=+0.5, unit length) + texture.
UV: u = along length (0 butt .. 1 tip), v = around. Real cue 1.47 m: set MeshPart.Size to
(1.47, 0.029, 0.029) * StudsPerMeter, or anything with the same proportions."""
import math, numpy as np
from PIL import Image
L = 1.47
def radius(t):  # t 0..1 butt->tip, meters
    if t < 0.47: return 0.0145 - (0.0145 - 0.0108) * (t / 0.47)
    return 0.0108 - (0.0108 - 0.0064) * ((t - 0.47) / 0.53) ** 0.8
STEPS = [0, .005, .01, .03, .30, .31, .45, .46, .48, .55, .7, .85, .95, .985, .995, 1.0]
SEG = 24
vs, vts, vns, faces = [], [], [], []
for t in STEPS:
    r = radius(t) / L
    for i in range(SEG + 1):
        a = i / SEG * 2 * math.pi
        vs.append((t - 0.5, r * math.cos(a), r * math.sin(a)))
        vns.append((0, math.cos(a), math.sin(a)))
        vts.append((t, i / SEG))
row = SEG + 1
for j in range(len(STEPS) - 1):
    for i in range(SEG):
        a = j * row + i; b = a + 1; c = a + row; d = c + 1
        faces.append((a, b, c)); faces.append((b, d, c))
# end caps
for end, t, sgn in ((0, 0.0, -1), (len(STEPS) - 1, 1.0, 1)):
    ci = len(vs); vs.append((t - 0.5, 0, 0)); vns.append((sgn, 0, 0)); vts.append((t, 0.5))
    base = len(vs)
    for i in range(SEG):
        a = i / SEG * 2 * math.pi; r = radius(t) / L
        vs.append((t - 0.5, r * math.cos(a), r * math.sin(a))); vns.append((sgn, 0, 0)); vts.append((t, 0.5))
    for i in range(SEG):
        p, q = base + i, base + (i + 1) % SEG
        faces.append((ci, q, p) if sgn < 0 else (ci, p, q))
V = np.array(vs)
bad = 0
for f in faces:
    n = np.cross(V[f[1]] - V[f[0]], V[f[2]] - V[f[0]])
    cen = V[list(f)].mean(0); out = cen.copy()
    if abs(cen[1]) + abs(cen[2]) < 1e-9: out = np.array([cen[0], 0, 0])
    else: out = np.array([0, cen[1], cen[2]]) if abs(abs(cen[0]) - 0.5) > 1e-6 or np.dot(n, [1,0,0]) == 0 else np.array([np.sign(cen[0]), 0, 0])
    if np.dot(n, out) < 0: bad += 1
print("faces", len(faces), "inward", bad)
with open("cue/cue.obj", "w") as f:
    f.write("# HU HU POOL cue: unit length along X, tip at +X\n")
    for v in vs: f.write("v %.6f %.6f %.6f\n" % v)
    for t in vts: f.write("vt %.6f %.6f\n" % t)
    for n in vns: f.write("vn %.6f %.6f %.6f\n" % n)
    for t in faces: f.write("f " + " ".join(f"{k+1}/{k+1}/{k+1}" for k in t) + "\n")

W, H = 1024, 128
u = (np.arange(W) + .5) / W
v = (np.arange(H) + .5) / H
U, Vv = np.meshgrid(u, v)
rng = np.random.default_rng(7)
def c(*rgb): return np.array(rgb, float) / 255
img = np.zeros((H, W, 3))
maple = c(226, 196, 150); grain = np.sin(Vv * 6.283 * 9 + np.sin(U * 6.283 * 2.3) * 1.4 + np.sin(U * 6.283 * 7.1) * 0.5) * .5 + .5
maple_t = maple[None, None] * (0.95 + 0.05 * grain[..., None])
img[:] = maple_t
def band(a, b, col): 
    m = (U >= a) & (U < b); img[m] = col
band(0, .01, c(20, 20, 20))
band(.01, .03, c(212, 170, 60))
# wrap: black with fine red diagonal hatch
m = (U >= .03) & (U < .30)
hatch = ((np.floor(U * 600 + Vv * 40) + np.floor(U * 600 - Vv * 40)) % 2 == 0)
img[m] = np.where(hatch[m][:, None], c(28, 10, 12), c(64, 14, 18))
band(.30, .31, c(212, 170, 60))
# forearm: lacquered red with 4 black points tipped with gold veneer
m = (U >= .31) & (U < .45)
img[m] = maple_t[m]
f = (U - .31) / .14
for k in range(4):
    dv = np.abs(((Vv - (k + .5) / 4) + .5) % 1 - .5) * 4  # 0 at point centre .. 2
    pt = (dv < (1 - f) * 1.0) & m
    veneer = (dv < (1 - f) * 1.0 + .06) & m & ~pt
    img[veneer] = c(212, 170, 60)
    img[pt] = c(170, 22, 30)
band(.45, .46, c(212, 170, 60))
band(.46, .48, c(190, 190, 196))
band(.985, .995, c(240, 238, 228))
band(.995, 1.0, c(40, 90, 170))
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save("cue/cue.png")
