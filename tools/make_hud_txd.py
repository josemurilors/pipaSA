"""Copia um hud.txd e troca a textura de um blip (por padrao radar_light, blip sprite 56, sem uso em free roam)
pelo icone da pipa (64x64 BGRA cru gerado por prep_icon.ps1), gravada sem compressao (A8R8G8B8).

Uso: python tools/make_hud_txd.py <hud.txd origem> <icone.bgra> <hud.txd saida> [textura]
"""
import struct
import sys
from pathlib import Path


def patch(src, raw, tex="radar_light"):
    b = bytearray(src)
    t, size, ver = struct.unpack_from("<III", b, 0)
    assert t == 0x16, "nao e um TXD"
    o = 12
    _, s, _ = struct.unpack_from("<III", b, o)  # struct com a contagem
    o += 12 + s
    while o < 12 + size:
        t, s, _ = struct.unpack_from("<III", b, o)
        d = o + 24  # pula chunk 0x15 + cabecalho do struct
        if t == 0x15 and b[d + 8:d + 40].split(b"\0")[0].decode().lower() == tex.lower():
            head = bytearray(b[d:d + 88])
            w, h = struct.unpack_from("<HH", head, 80)
            assert len(raw) == w * h * 4, f"icone precisa ter {w}x{h}"
            struct.pack_into("<II", head, 72, 0x0500, 21)  # raster 8888, D3DFMT_A8R8G8B8
            head[84:88] = bytes((32, 1, 4, 1))              # depth, mips, tipo textura, flags = alpha
            st = bytes(head) + struct.pack("<I", len(raw)) + raw
            new = struct.pack("<III", 0x15, 12 + len(st) + 12, ver) + struct.pack("<III", 1, len(st), ver) + st \
                + struct.pack("<III", 3, 0, ver)
            b[o:o + 12 + s] = new
            struct.pack_into("<I", b, 4, len(b) - 12)
            return bytes(b)
        o += 12 + s
    raise SystemExit(f"textura {tex} nao encontrada")


if __name__ == "__main__":
    src, raw, out = (Path(a) for a in sys.argv[1:4])
    res = patch(src.read_bytes(), raw.read_bytes(), *sys.argv[4:5])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(res)
    print("ok", out, len(res))
