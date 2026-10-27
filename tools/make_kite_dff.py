"""Gera DFFs RenderWare minimos: pipa (losango + varetas, sem rabiola) e lacos da rabiola (animados por script), sem textura.

Uso: python tools/make_kite_dff.py <pasta do mod modloader>
Gera models/gta3.img/*.dff|txd, data/maps/pipasa/PipaSA.ide (data/gta.dat e uma copia COMPLETA do gta.dat original + 1 linha IDE: o modloader faz diff, um gta.dat so com a linha apaga o resto do mapa).
"""
import math
import struct
import sys
from pathlib import Path

VER = 0x1803FFFF  # RW 3.6.0.3 (GTA SA)
COLORS = {"red": (220, 40, 40), "blue": (40, 90, 220), "yellow": (240, 200, 30), "green": (40, 190, 80)}
FIRST_ID = 19100
BOWS = {"red": (220, 40, 40), "yellow": (240, 200, 30), "blue": (40, 90, 220)}  # lacos da rabiola
BOW_FIRST_ID = 19104
REEL_ID = 19107  # carretel (cilindro com eixo em X), preso a mao do personagem por script


def chunk(t, data):
    return struct.pack("<III", t, len(data), VER) + data


def pad_str(s):
    b = s.encode() + b"\0"
    return b + b"\0" * (-len(b) % 4)


def quad(x0, z0, x1, z1, y=0.0):
    return [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]


def build_polys(kind="kite"):
    """(material, [verts]). pipa: mat 0 = corpo, 1 = varetas. laco: mat 0."""
    if kind == "reel":
        n, fr, cr, xf, xc = 14, 0.115, 0.075, 0.085, 0.07  # raio da aba, raio do nucleo (linha), meia-largura, meia-largura do nucleo
        pts = lambda r, x: [(x, r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]
        polys = []
        for sx in (-1, 1):  # abas de madeira: disco externo/interno + lateral
            polys.append((0, pts(fr, sx * xf)[::sx], (sx, 0, 0)))
            polys.append((0, pts(fr, sx * xc)[::-sx], (-sx, 0, 0)))
            a_, b_ = sorted((sx * xf, sx * xc))
            for i in range(n):
                j = (i + 1) % n
                (_, y0, z0), (_, y1, z1) = pts(fr, a_)[i], pts(fr, a_)[j]
                m = 2 * math.pi * (i + 0.5) / n
                polys.append((0, [(a_, y0, z0), (b_, y0, z0), (b_, y1, z1), (a_, y1, z1)], (0, math.cos(m), math.sin(m))))
        for i in range(n):  # nucleo enrolado de linha
            j = (i + 1) % n
            (_, y0, z0), (_, y1, z1) = pts(cr, 0)[i], pts(cr, 0)[j]
            m = 2 * math.pi * (i + 0.5) / n
            polys.append((1, [(-xc, y0, z0), (xc, y0, z0), (xc, y1, z1), (-xc, y1, z1)], (0, math.cos(m), math.sin(m))))
        return polys
    if kind == "bow":
        return [(0, [(-0.2, 0, 0.1), (0, 0, 0), (-0.2, 0, -0.1)]), (0, [(0.2, 0, 0.1), (0.2, 0, -0.1), (0, 0, 0)])]
    t, r, b, l, c = (0, 0, 0.8), (0.55, 0, 0.1), (0, 0, -0.9), (-0.55, 0, 0.1), (0, 0, 0.1)
    polys = [(0, [(p[0], 0, p[2]) for p in tri]) for tri in ((t, r, c), (r, b, c), (b, l, c), (l, t, c))]
    polys.append((1, quad(-0.02, -0.9, 0.02, 0.8, 0.01)))
    polys.append((1, quad(-0.55, 0.08, 0.55, 0.12, 0.01)))
    return polys


def geometry(polys, cols):
    verts, norms, tris = [], [], []  # tris: (a, b, c, mat)
    for mat, poly, *nrm in polys:
        for side, ny in ((0, -1.0), (1, 1.0)):  # frente e verso
            base = len(verts)
            pts = poly if side == 0 else poly[::-1]
            verts += pts
            norms += [tuple((1 if side == 0 else -1) * c for c in nrm[0])] * len(pts) if nrm else [(0.0, ny, 0.0)] * len(pts)
            for k in range(1, len(pts) - 1):
                tris.append((base, base + k, base + k + 1, mat))
    xs, ys, zs = zip(*verts)
    cx, cy, cz = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2
    rad = max(((x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2) ** 0.5 for x, y, z in verts) + 0.05

    body = struct.pack("<IIII", 0x72, len(tris), len(verts), 1)  # pos|normals|light|modulate
    for a, b, c, m in tris:
        body += struct.pack("<HHHH", b, a, m, c)
    body += struct.pack("<ffffII", cx, cy, cz, rad, 1, 1)
    body += b"".join(struct.pack("<fff", *v) for v in verts)
    body += b"".join(struct.pack("<fff", *n) for n in norms)

    def mat(c):
        s = struct.pack("<I4BIIfff", 0, *c, 1, 0, 1.0, 1.0, 1.0)
        return chunk(7, chunk(1, s) + chunk(3, b""))

    mlist = chunk(8, chunk(1, struct.pack(f"<I{len(cols)}i", len(cols), *([-1] * len(cols)))) + b"".join(mat(c) for c in cols))
    meshes = b""
    for m in range(len(cols)):
        idx = [i for t in tris if t[3] == m for i in t[:3]]
        meshes += struct.pack("<II", len(idx), m) + struct.pack(f"<{len(idx)}I", *idx)
    binmesh = chunk(0x50E, struct.pack("<III", 0, len(cols), 3 * len(tris)) + meshes)
    return chunk(0x0F, chunk(1, body) + mlist + chunk(3, binmesh))


def dff(rgb, kind="kite"):
    frame = struct.pack("<9f3fii", 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, -1, 0x00020003)
    flist = chunk(0x0E, chunk(1, struct.pack("<I", 1) + frame) + chunk(3, chunk(0x253F2FE, pad_str("kite"))))
    glist = chunk(0x1A, chunk(1, struct.pack("<I", 1)) + geometry(build_polys(kind), {"kite": [(*rgb, 255), (60, 40, 20, 255)], "bow": [(*rgb, 255)], "reel": [(130, 85, 45, 255), (235, 235, 235, 255)]}[kind]))
    atomic = chunk(0x14, chunk(1, struct.pack("<IIII", 0, 0, 5, 0)) + chunk(3, b""))
    return chunk(0x10, chunk(1, struct.pack("<III", 1, 0, 0)) + flist + glist + atomic + chunk(3, b""))


def col1(name):
    """COL1 minimo (1 esfera): CObject precisa de colisao, sem ela createObject derruba o jogo."""
    sphere = struct.pack("<f3fBBBB", 0.4, 0, 0, 0.1, 0, 0, 0, 0)
    body = name.encode().ljust(22, bytes(1)) + struct.pack("<H", 0)
    body += struct.pack("<f3f3f3f", 1.3, 0, 0, -0.2, -0.6, -0.1, -1.0, 0.6, 0.1, 0.9)
    body += struct.pack("<I", 1) + sphere + struct.pack("<IIII", 0, 0, 0, 0)  # esferas, desconhecido, caixas, vertices, faces
    return b"COLL" + struct.pack("<I", len(body)) + body


def empty_txd():
    """TXD valido sem texturas: o IDE precisa de um txd proprio (o 'generic' nao e um slot de objeto em gta3.img)."""
    return chunk(0x16, chunk(1, struct.pack("<HH", 0, 0)) + chunk(3, b""))


if __name__ == "__main__":
    root = Path(sys.argv[1])
    img = root / "models" / "gta3.img"
    ide_dir = root / "data" / "maps" / "pipasa"
    img.mkdir(parents=True, exist_ok=True)
    ide_dir.mkdir(parents=True, exist_ok=True)
    (img / "pipasa_kite.txd").write_bytes(empty_txd())
    ide = ["objs"]
    for i, (name, rgb) in enumerate(COLORS.items()):
        (img / f"pipasa_kite_{name}.dff").write_bytes(dff(rgb))
        ide.append(f"{FIRST_ID + i}, pipasa_kite_{name}, pipasa_kite, 299.0, 0")
    for i, (name, rgb) in enumerate(BOWS.items()):
        (img / f"pipasa_bow_{name}.dff").write_bytes(dff(rgb, "bow"))
        ide.append(f"{BOW_FIRST_ID + i}, pipasa_bow_{name}, pipasa_kite, 299.0, 0")
    (img / "pipasa_reel.dff").write_bytes(dff((0, 0, 0), "reel"))
    ide.append(f"{REEL_ID}, pipasa_reel, pipasa_kite, 299.0, 0")
    ide.append("end")
    cols = b"".join(col1(f"pipasa_kite_{n}") for n in COLORS) + b"".join(col1(f"pipasa_bow_{n}") for n in BOWS) + col1("pipasa_reel")
    (root / "models" / "pipasa.col").write_bytes(cols)
    (ide_dir / "PipaSA.ide").write_text("\n".join(ide) + "\n")
    print("ok", root)
