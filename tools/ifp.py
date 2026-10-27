"""Leitor/escritor minimo de IFP ANP3 (GTA SA). Quaternios int16/4096, tempo int16 em 1/60 s, translacao int16/1024."""
import struct


def _s(b):
    return b.split(b"\0")[0].decode("latin-1")


def read_ifp(data):
    assert data[:4] == b"ANP3", data[:4]
    name = _s(data[8:32])
    n = struct.unpack_from("<I", data, 32)[0]
    o = 36
    anims = {}
    for _ in range(n):
        an = _s(data[o:o + 24]); nb, size, unk = struct.unpack_from("<III", data, o + 24); o += 36
        end = o + nb * 36 + size  # dataSize conta so os quadros, nao os cabecalhos de osso
        bones = []
        for _ in range(nb):
            bn = _s(data[o:o + 24]); ft, nf, bid = struct.unpack_from("<III", data, o + 24); o += 36
            frames = []
            for _ in range(nf):
                if ft == 4:
                    x, y, z, w, t, tx, ty, tz = struct.unpack_from("<8h", data, o); o += 16
                    frames.append(((x / 4096, y / 4096, z / 4096, w / 4096), t / 60, (tx / 1024, ty / 1024, tz / 1024)))
                else:
                    x, y, z, w, t = struct.unpack_from("<5h", data, o); o += 10
                    frames.append(((x / 4096, y / 4096, z / 4096, w / 4096), t / 60, None))
            bones.append({"name": bn, "type": ft, "id": bid, "frames": frames})
        assert o == end, (an, o, end)
        anims[an] = {"unk": unk, "bones": bones}
    return name, anims


def write_ifp(name, anims):
    body = b""
    for an, a in anims.items():
        bd = b""
        for b in a["bones"]:
            bd += b["name"].encode().ljust(24, b"\0") + struct.pack("<III", b["type"], len(b["frames"]), b["id"])
            for q, t, p in b["frames"]:
                qi = [max(-32768, min(32767, round(c * 4096))) for c in q]
                bd += struct.pack("<4hh", *qi, round(t * 60))
                if b["type"] == 4:
                    bd += struct.pack("<3h", *[round(c * 1024) for c in p])
        body += an.encode().ljust(24, b"\0") + struct.pack("<III", len(a["bones"]), sum(len(b["frames"]) * (16 if b["type"] == 4 else 10) for b in a["bones"]), a.get("unk", 1)) + bd
    body = name.encode().ljust(24, b"\0") + struct.pack("<I", len(anims)) + body
    return b"ANP3" + struct.pack("<I", len(body)) + body
