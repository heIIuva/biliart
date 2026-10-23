"""Convert an OBJ (v/vt/vn triangles or fans) to a binary glTF for the Open Cloud Model upload.

Roblox's glTF importer mirrors Z, so Z is pre-mirrored here (positions, normals, winding);
UVs are kept as in the OBJ. Usage: python3 obj_to_glb.py in.obj out.glb
"""
import json, struct, sys

src, dst = sys.argv[1], sys.argv[2]
v, vt, vn, verts, index, idx = [], [], [], [], [], {}
for line in open(src):
    p = line.split()
    if not p:
        continue
    if p[0] == "v":
        v.append(tuple(map(float, p[1:4])))
    elif p[0] == "vt":
        vt.append(tuple(map(float, p[1:3])))
    elif p[0] == "vn":
        vn.append(tuple(map(float, p[1:4])))
    elif p[0] == "f":
        corners = []
        for c in p[1:]:
            if c not in idx:
                a, b, n = (int(x) - 1 for x in c.split("/"))
                idx[c] = len(verts)
                x, y, z = v[a]
                nx, ny, nz = vn[n]
                verts.append(((x, y, -z), vt[b], (nx, ny, -nz)))
            corners.append(idx[c])
        for i in range(1, len(corners) - 1):
            index += [corners[0], corners[i + 1], corners[i]]

pos = b"".join(struct.pack("<3f", *p) for p, _, _ in verts)
nor = b"".join(struct.pack("<3f", *n) for _, _, n in verts)
uv = b"".join(struct.pack("<2f", *t) for _, t, _ in verts)
ind = struct.pack(f"<{len(index)}I", *index)
blob = pos + nor + uv + ind
views, off = [], 0
for chunk, target in ((pos, 34962), (nor, 34962), (uv, 34962), (ind, 34963)):
    views.append({"buffer": 0, "byteOffset": off, "byteLength": len(chunk), "target": target})
    off += len(chunk)
n = len(verts)
gltf = {
    "asset": {"version": "2.0"},
    "scene": 0,
    "scenes": [{"nodes": [0]}],
    "nodes": [{"mesh": 0, "name": "BallMesh"}],
    "meshes": [{"name": "BallMesh", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3}]}],
    "buffers": [{"byteLength": len(blob)}],
    "bufferViews": views,
    "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3",
         "min": [min(p[0][i] for p in verts) for i in range(3)], "max": [max(p[0][i] for p in verts) for i in range(3)]},
        {"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"},
        {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC2"},
        {"bufferView": 3, "componentType": 5125, "count": len(index), "type": "SCALAR"},
    ],
}
js = json.dumps(gltf).encode()
js += b" " * (-len(js) % 4)
blob += b"\0" * (-len(blob) % 4)
with open(dst, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(blob), 0x004E4942) + blob)
print(f"{n} vertices, {len(index) // 3} triangles -> {dst}")
