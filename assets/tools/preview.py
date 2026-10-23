import math, numpy as np
from PIL import Image
N = 220
def rot(ax, a):
    c, s = math.cos(a), math.sin(a)
    if ax == "x": return np.array([[1,0,0],[0,c,-s],[0,s,c]])
    if ax == "z": return np.array([[c,-s,0],[s,c,0],[0,0,1]])
def ball_img(tex, R):
    xs = (np.arange(N) + .5) / N * 2 - 1
    X, Yi = np.meshgrid(xs, -xs)  # screen x right, y up
    r2 = X**2 + Yi**2; inside = r2 < 1
    Zs = np.sqrt(np.clip(1 - r2, 0, 1))
    # camera above (+Y world) looking down, screen up = -Z, screen right = +X
    p = np.stack([X, Zs, -Yi], -1)
    d = p @ R  # world -> ball local (R maps local->world, so local = R^T world)
    u = (np.arctan2(d[...,1], d[...,2]) + math.pi) / (2*math.pi)
    v = (np.arcsin(np.clip(d[...,0], -1, 1)) + math.pi/2) / math.pi
    h, w = tex.shape[:2]
    col = tex[np.clip(((1-v)*h).astype(int),0,h-1), np.clip((u*w).astype(int),0,w-1)]
    L = np.array([-.4, .8, -.45]); L /= np.linalg.norm(L)
    nrm = np.stack([X, Zs, -Yi], -1)
    diff = np.clip(nrm @ L, 0, 1)[..., None]
    H = L + np.array([0,1,0]); H /= np.linalg.norm(H)
    spec = (np.clip(nrm @ H, 0, 1) ** 60)[..., None]
    out = col * (0.35 + 0.7 * diff) + spec * 0.6
    bg = np.array([0.12, 0.42, 0.26])
    a = np.clip((1 - np.sqrt(r2)) * N / 2, 0, 1)[..., None]
    return np.clip(out * a + bg * (1 - a), 0, 1)
tiles = []
rots = [np.eye(3), rot("x", 0.5) @ rot("z", 0.6)]
for R in rots:
    row = []
    for b in range(16):
        tex = np.asarray(Image.open(f"textures/ball_{b:02d}.png"), dtype=float) / 255
        row.append(ball_img(tex, R))
    tiles.append(np.concatenate(row[:8], 1)); tiles.append(np.concatenate(row[8:], 1))
sheet = np.concatenate(tiles, 0)
Image.fromarray((sheet*255).astype(np.uint8)).save("preview.png")
