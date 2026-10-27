"""Gera modloader/PipaSA/models/gta3.img/pipasa.ifp (bloco "PIPASA") e imagens de revisao.

Uso (Blender com o add-on DragonFF instalado):
  blender -b --factory-startup --python tools/blender_kite_anims.py -- <pasta do projeto> <pasta de previews>

As poses sao deltas (graus, Euler XYZ) sobre a pose IDLE_stance do ped.ifp do jogo, no espaco local de cada osso.
Eixos verificados no Blender (render do esqueleto): em bracos/coxas Z negativo = flexionar para frente, Z positivo = para tras;
Y abduz o braco direito (id 22) e aduz o esquerdo (id 32); X = torcao. Convencao do IFP: q_ifp = repouso_local @ base_blender.
"""
import math
import os
import subprocess
import sys

import bpy
from mathutils import Euler, Quaternion

ROOT, PREV = sys.argv[sys.argv.index("--") + 1:][:2]
sys.path.insert(0, os.path.join(ROOT, "tools"))
import ifp  # noqa: E402
import pose_lib as pl  # noqa: E402

GAME = os.environ.get("PIPASA_GAME", r"D:\Games\GTA San Andreas")  # pasta do GTA SA
L_UA, L_FA, R_UA, R_FA = 32, 33, 22, 23
SPINE, SPINE1, NECK, HEAD = 2, 3, 4, 5
L_TH, L_CALF, R_TH, R_CALF = 41, 42, 51, 52


def sym(ua_z, fa_z, abd=0, ua_x=0):
    """mesma flexao nos dois bracos; abd > 0 afasta os bracos do corpo (R usa +Y, L usa -Y)."""
    return {R_UA: (ua_x, abd, ua_z), L_UA: (ua_x, -abd, ua_z), R_FA: (0, 0, fa_z), L_FA: (0, 0, fa_z)}


def merge(*ds):
    out = {}
    for d in ds:
        for k, v in d.items():
            o = out.get(k, (0, 0, 0))
            out[k] = (o[0] + v[0], o[1] + v[1], o[2] + v[2])
    return out


LOOK_UP = {HEAD: (0, 0, 22), NECK: (0, 0, 8)}


def arms(r, l):
    """r / l = (flexao_ombro, abducao, flexao_cotovelo) para cada braco (abducao > 0 afasta do corpo)."""
    return {R_UA: (0, r[1], r[0]), R_FA: (0, 0, r[2]), L_UA: (0, -l[1], l[0]), L_FA: (0, 0, l[2])}


# Maos sempre separadas (checadas pela distancia das maos na revisao): nada de "maos juntas rezando".
POSES = {
    # --- CJ segurando a pipa: mao direita no carretel (na altura da cintura, a frente), esquerda guia a linha mais alta e afastada
    "HOLD": merge(arms((-22, 12, -70), (-62, 26, -28)), LOOK_UP, {SPINE1: (0, 0, 6)}),
    "TUG1": merge(arms((-18, 12, -82), (-52, 26, -42)), LOOK_UP, {SPINE1: (0, 0, 11)}),
    "HOLD2": merge(arms((-24, 12, -66), (-68, 28, -22)), LOOK_UP, {SPINE1: (0, -3, 6)}),
    "TUG2": merge(arms((-16, 12, -86), (-48, 24, -48)), LOOK_UP, {SPINE1: (0, 0, 13)}),
    # --- puxar linha "mao sobre mao": uma mao estica para a frente, a outra recolhe ao peito; alterna
    "PULL_A": merge(arms((-28, 14, -118), (-74, 20, -22)), {HEAD: (0, 0, 22), SPINE1: (0, 0, 18), L_TH: (0, 0, -14), R_TH: (0, 0, 8), L_CALF: (0, 0, 18)}),
    "PULL_B": merge(arms((-74, 20, -22), (-28, 14, -118)), {HEAD: (0, 0, 22), SPINE1: (0, 0, 18), L_TH: (0, 0, -14), R_TH: (0, 0, 8), L_CALF: (0, 0, 18)}),
    # --- dar linha: bracos a frente e abertos, tronco um pouco a frente
    "GIVE_A": merge(arms((-80, 24, -18), (-70, 26, -26)), {HEAD: (0, 0, 18), SPINE1: (0, 0, -6), R_TH: (0, 0, -8)}),
    "GIVE_B": merge(arms((-92, 26, -10), (-84, 28, -14)), {HEAD: (0, 0, 22), SPINE1: (0, 0, -9), R_TH: (0, 0, -10)}),
    # --- chicote: ergue por cima da cabeca (bracos em V) e estala para a frente
    "WHIP_0": merge(arms((-22, 12, -70), (-62, 26, -28)), LOOK_UP, {SPINE1: (0, 0, 6)}),
    "WHIP_UP": merge(arms((-160, 30, -25), (-165, 32, -25)), {HEAD: (0, 0, 26), SPINE1: (0, 0, 20), L_TH: (0, 0, 6)}),
    "WHIP_SNAP": merge(arms((-45, 22, -25), (-35, 24, -30)), {HEAD: (0, 0, 8), SPINE1: (0, 0, -22), L_TH: (0, 0, -16), R_TH: (0, 0, 8)}),
    # --- comemorar / perder
    "CHEER_A": merge(arms((-155, 28, -15), (-155, 28, -15)), {HEAD: (0, 0, 20), SPINE1: (0, 0, 10)}),
    "CHEER_B": merge(arms((-135, 40, -35), (-135, 40, -35)), {HEAD: (0, 0, 14), SPINE1: (0, 0, 4)}),
    "LOSE": merge(arms((6, 6, -22), (6, 6, -22)), {HEAD: (0, 0, -26), NECK: (0, 0, -10), SPINE1: (0, 0, -14), SPINE: (0, 0, -6)}),
    # --- pedestre A: direita no carretel (cintura), esquerda estica a linha para o alto
    "PED_A0": merge(arms((-18, 10, -66), (-118, 20, -18)), LOOK_UP, {HEAD: (0, 0, 8), SPINE1: (0, 0, 5)}),
    "PED_A1": merge(arms((-22, 10, -78), (-126, 18, -10)), LOOK_UP, {HEAD: (0, 0, 10), SPINE1: (0, 3, 7)}),
    "PED_A2": merge(arms((-16, 10, -60), (-112, 22, -24)), LOOK_UP, {HEAD: (0, 0, 6), SPINE1: (0, -3, 4)}),
    # --- pedestre B: espelhado
    "PED_B0": merge(arms((-118, 20, -18), (-18, 10, -66)), LOOK_UP, {HEAD: (0, 0, 8), SPINE1: (0, 0, 5)}),
    "PED_B1": merge(arms((-126, 18, -10), (-22, 10, -78)), LOOK_UP, {HEAD: (0, 0, 10), SPINE1: (0, -3, 7)}),
    "PED_B2": merge(arms((-112, 22, -24), (-16, 10, -60)), LOOK_UP, {HEAD: (0, 0, 6), SPINE1: (0, 3, 4)}),
    # --- pedestre C: calmo; uma mao no carretel baixo, a outra segura a linha a frente (maos afastadas)
    "PED_C0": merge(arms((-14, 10, -62), (-72, 26, -30)), {HEAD: (0, 0, 30), NECK: (0, 0, 8), SPINE1: (0, 0, 7)}),
    "PED_C1": merge(arms((-16, 10, -70), (-78, 28, -26)), {HEAD: (0, 0, 34), NECK: (0, 0, 10), SPINE1: (0, 0, 9)}),
}
# Medido no Blender (posicao da cabeca e do queixo): em Spine/Spine1/Neck/Head, Z POSITIVO = inclinar/baixar para a frente
# e Z negativo = inclinar para tras/olhar para cima (o oposto dos bracos e coxas). As poses acima foram escritas pensando
# "positivo = para cima/tras", entao o sinal desses ossos e invertido aqui.
for _p in POSES.values():
    for _b in (SPINE, SPINE1, NECK, HEAD):
        if _b in _p:
            x, y, z = _p[_b]
            _p[_b] = (x, y, -z)

# nome: (duracao, loop, [(tempo, pose)])
ANIMS = {
    "kite_fly_loop": (3.2, [(0, "HOLD"), (0.8, "TUG1"), (1.6, "HOLD2"), (2.4, "TUG2"), (3.2, "HOLD")]),
    "kite_pull": (0.8, [(0, "PULL_A"), (0.4, "PULL_B"), (0.8, "PULL_A")]),
    "kite_give": (0.8, [(0, "GIVE_A"), (0.4, "GIVE_B"), (0.8, "GIVE_A")]),
    "kite_whip": (1.0, [(0, "WHIP_0"), (0.35, "WHIP_UP"), (0.55, "WHIP_SNAP"), (1.0, "HOLD")]),
    "kite_cheer": (1.2, [(0, "CHEER_A"), (0.6, "CHEER_B"), (1.2, "CHEER_A")]),
    "kite_lose": (2.0, [(0, "LOSE"), (1.0, "LOSE"), (2.0, "LOSE")]),
    "kite_ped_a": (4.0, [(0, "PED_A0"), (1.0, "PED_A1"), (2.0, "PED_A0"), (3.0, "PED_A2"), (4.0, "PED_A0")]),
    "kite_ped_b": (4.4, [(0, "PED_B0"), (1.1, "PED_B1"), (2.2, "PED_B0"), (3.3, "PED_B2"), (4.4, "PED_B0")]),
    "kite_ped_c": (5.0, [(0, "PED_C0"), (2.5, "PED_C1"), (5.0, "PED_C0")]),
}
STEP = 0.1


def ease(u):
    return 0.5 - 0.5 * math.cos(math.pi * u)


def delta_at(keys, t):
    for (ta, pa), (tb, pb) in zip(keys, keys[1:]):
        if ta <= t <= tb:
            u = ease((t - ta) / (tb - ta))
            A, B = POSES[pa], POSES[pb]
            out = {}
            for bid in set(A) | set(B):
                a, b = A.get(bid, (0, 0, 0)), B.get(bid, (0, 0, 0))
                out[bid] = tuple(a[i] + (b[i] - a[i]) * u for i in range(3))
            return out
    return POSES[keys[-1][1]]


def main():
    arm = pl.setup()
    bones = pl.bones_by_id(arm)
    _, vanilla = ifp.read_ifp(open(os.path.join(GAME, "anim", "ped.ifp"), "rb").read())
    base_anim = vanilla["IDLE_stance"]
    base_q = {b["id"]: b["frames"][0][0] for b in base_anim["bones"]}

    def basis(bid):
        x, y, z, w = base_q[bid]
        return pl.rest_local_q(bones[bid]).inverted() @ Quaternion((w, x, y, z))

    anims = {}
    for name, (length, keys) in ANIMS.items():
        times = [round(i * STEP, 4) for i in range(int(round(length / STEP)) + 1)]
        bones_out = []
        for vb in base_anim["bones"]:
            bid, frames = vb["id"], []
            prev = None
            for t in times:
                d = delta_at(keys, t).get(bid, (0, 0, 0))
                bq = basis(bid) @ Euler(tuple(math.radians(a) for a in d), "XYZ").to_quaternion()
                q = pl.rest_local_q(bones[bid]) @ bq
                if prev is not None and q.dot(prev) < 0:
                    q = -q
                prev = q
                frames.append(((q.x, q.y, q.z, q.w), t, vb["frames"][0][2]))
            bones_out.append({"name": vb["name"], "type": vb["type"], "id": bid, "frames": frames})
        anims[name] = {"unk": 1, "bones": bones_out}

    out = os.path.join(ROOT, "modloader", "PipaSA", "models", "gta3.img", "pipasa.ifp")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "wb").write(ifp.write_ifp("PIPASA", anims))
    print("IFP", out, os.path.getsize(out))

    # previews: cada animacao em varios instantes, vista de perfil e de frente
    os.makedirs(PREV, exist_ok=True)
    for name, (length, keys) in ANIMS.items():
        shots = []
        for i, (t, _) in enumerate(keys[:-1] if keys[-1][0] == length and len(keys) > 2 else keys):
            quats = {}
            for b in anims[name]["bones"]:
                idx = min(range(len(b["frames"])), key=lambda k: abs(b["frames"][k][1] - t))
                quats[b["id"]] = b["frames"][idx][0]
            pl.apply_pose(arm, bones, quats, "A")
            pl.draw_skeleton(arm)
            hr = arm.matrix_world @ bones[24].head; hl = arm.matrix_world @ bones[34].head; hd = arm.matrix_world @ bones[5].head
            jw = arm.matrix_world @ bones[8].head
            print(f"METRIC {name} t={t:.2f} cabeca_y={hd.y:+.3f} queixo_rel_z={jw.z - hd.z:+.3f} maos_afastadas={(hr - hl).length:.2f}m  altura_mao_R={hr.z - hd.z:+.2f} L={hl.z - hd.z:+.2f} (rel. cabeca)")
            for view in ("front", "side"):
                p = os.path.join(PREV, f"{name}_{i}_{view}.png")
                pl.render(p, view, (240, 340)); shots.append(p)
        n = len(shots) // 2
        row1 = [s for s in shots if s.endswith("front.png")]; row2 = [s for s in shots if s.endswith("side.png")]
        subprocess.run(["magick"] + row1 + ["+append", os.path.join(PREV, "_r1.png")], check=True)
        subprocess.run(["magick"] + row2 + ["+append", os.path.join(PREV, "_r2.png")], check=True)
        subprocess.run(["magick", os.path.join(PREV, "_r1.png"), os.path.join(PREV, "_r2.png"), "-append", os.path.join(PREV, f"sheet_{name}.png")], check=True)
        for s in shots + [os.path.join(PREV, "_r1.png"), os.path.join(PREV, "_r2.png")]:
            os.remove(s)


main()
