"""Gera modloader/PipaSA/data/gta.dat: copia COMPLETA do gta.dat original + COLFILE e IDE do mod.
(o modloader faz diff contra o original: um gta.dat so com as linhas novas apagaria o resto do mapa)

Uso: python tools/make_gta_dat.py "<pasta do GTA SA>" <saida gta.dat>
"""
import sys
from pathlib import Path

game, out = Path(sys.argv[1]), Path(sys.argv[2])
t = (game / "data" / "gta.dat").read_bytes().decode("latin-1")
nl = "\r\n" if "\r\n" in t else "\n"
anchor = r"IDE DATA\MAPS\veh_mods\veh_mods.IDE"
i = t.index(anchor)
j = t.index(nl, i) + len(nl)
new = nl.join([r"COLFILE 0 MODELS\pipasa.col", r"IDE DATA\MAPS\PIPASA\PIPASA.IDE"]) + nl
out.parent.mkdir(parents=True, exist_ok=True)
out.write_bytes((t[:j] + new + t[j:]).encode("latin-1"))
print("ok", out)
