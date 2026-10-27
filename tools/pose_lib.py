import bpy, sys, math, os
from mathutils import Quaternion, Vector, Matrix
TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import ifp

def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="bl_ext.user_default.dragonff")
    bpy.ops.import_scene.dff(filepath=os.path.join(TOOLS, "..", "work", "player.dff"))  # extraido do seu gta3.img (ver README)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    return arm

def bones_by_id(arm):
    return {pb.bone.get("bone_id"): pb for pb in arm.pose.bones}

def rest_local_q(pb):
    b = pb.bone
    if b.parent:
        m = b.parent.matrix_local.inverted() @ b.matrix_local
    else:
        m = b.matrix_local
    return m.to_quaternion()

def sample(frames, t):
    """frames: [(q,t,p)] -> quaternion (x,y,z,w) interpolado em t (loop simples)"""
    if t <= frames[0][1]: return frames[0][0]
    for a, b in zip(frames, frames[1:]):
        if a[1] <= t <= b[1]:
            u = (t - a[1]) / max(b[1] - a[1], 1e-6)
            qa = Quaternion((a[0][3], a[0][0], a[0][1], a[0][2])); qb = Quaternion((b[0][3], b[0][0], b[0][1], b[0][2]))
            q = qa.slerp(qb, u); return (q.x, q.y, q.z, q.w)
    return frames[-1][0]

def apply_pose(arm, bones, quats, variant="A"):
    """quats: {bone_id: (x,y,z,w) rotacao local GTA}"""
    for bid, pb in bones.items():
        pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = Quaternion((1, 0, 0, 0)); pb.location = (0, 0, 0)
    for bid, (x, y, z, w) in quats.items():
        pb = bones.get(bid)
        if not pb: continue
        q = Quaternion((w, x, y, z))
        if variant in ("B", "D"): q = q.conjugated()
        r = rest_local_q(pb)
        pb.rotation_quaternion = (r.inverted() @ q) if variant in ("A", "B") else (q @ r.inverted())
    bpy.context.view_layer.update()

def render(path, view="front", size=(420, 520)):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "OBJECT"
    for o in bpy.data.objects:
        if o.type == "MESH": o.color = (0.9, 0.7, 0.5, 1)
    cam = bpy.data.objects.get("Cam")
    if not cam:
        cd = bpy.data.cameras.new("Cam"); cd.type = "ORTHO"; cd.ortho_scale = 2.6
        cam = bpy.data.objects.new("Cam", cd); sc.collection.objects.link(cam); sc.camera = cam
    if view == "front":   # olhando de frente (+X), cima = +Z
        cam.location = (6, 0, 0.35); cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    else:                 # lado (+Y)
        cam.location = (0, -6, 0.35); cam.rotation_euler = (math.radians(90), 0, 0)
    sc.render.filepath = path; sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)

def draw_skeleton(arm):
    """desenha o esqueleto posado como curvas coloridas (a malha do player.dff e quase vazia)"""
    for o in [o for o in bpy.data.objects if o.name.startswith("SK_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    groups = {"SK_C": (0.1, 0.7, 0.1, 1), "SK_L": (0.9, 0.1, 0.1, 1), "SK_R": (0.1, 0.2, 0.95, 1)}
    cur = {}
    for k, col in groups.items():
        cd = bpy.data.curves.new(k, "CURVE"); cd.dimensions = "3D"; cd.bevel_depth = 0.025
        ob = bpy.data.objects.new(k, cd); ob.color = col; bpy.context.scene.collection.objects.link(ob); cur[k] = cd
    for pb in arm.pose.bones:
        if not pb.parent: continue
        bid = pb.bone.get("bone_id")
        k = "SK_L" if bid in (31, 32, 33, 34, 35, 36, 41, 42, 43, 44) else "SK_R" if bid in (21, 22, 23, 24, 25, 26, 51, 52, 53, 54) else "SK_C"
        if bid in (31, 21): continue  # clavicula sai do pescoco; desenhada pelo UpperArm
        a = arm.matrix_world @ pb.parent.head if bid not in (32, 22) else arm.matrix_world @ pb.parent.head
        b = arm.matrix_world @ pb.head
        sp = cur[k].splines.new("POLY"); sp.points.add(1)
        sp.points[0].co = (*a, 1); sp.points[1].co = (*b, 1)
    # cabeca: ponto extra acima de Head
    ids = {p.bone.get("bone_id"): p for p in arm.pose.bones}
    nose = bpy.data.curves.new("SK_N", "CURVE"); nose.dimensions = "3D"; nose.bevel_depth = 0.03
    no = bpy.data.objects.new("SK_N", nose); no.color = (1.0, 0.55, 0.0, 1); bpy.context.scene.collection.objects.link(no)
    hh = arm.matrix_world @ ids[5].head; jj = arm.matrix_world @ ids[8].head; fwd = (jj - hh)
    fwd.z = 0; fwd.normalize(); tip = hh + fwd * 0.3
    sp = nose.splines.new("POLY"); sp.points.add(1); sp.points[0].co = (*hh, 1); sp.points[1].co = (*tip, 1)
    h = ids[5]
    sp = cur["SK_C"].splines.new("POLY"); sp.points.add(1)
    a = arm.matrix_world @ h.head; sp.points[0].co = (*a, 1); sp.points[1].co = (a.x, a.y, a.z + 0.25, 1)
