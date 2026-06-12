#!/usr/bin/env python3
"""
render_manta.py — multi-view design mockup of the MANTA-1500 flying wing.

Rebuilds the geometry of cad/manta_wing.scad (same planform, airfoil,
sweep, taper, washout and blended-body math) and renders a glossy-white
hero view plus annotated top/front/side orthographic views and a spec
sheet.

    pip install numpy matplotlib
    python3 render_manta.py            ->  ../renders/manta_mockup.png
"""

import math
import os

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

# ---------------- planform (mirrors manta_wing.scad) ----------------
ROOT, TIP, HALF = 380.0, 220.0, 700.0
SWEEP_LE = 25.0          # deg
WASHOUT = 4.0            # deg, tip nose-down
BODY_W = 100.0           # center body width (z -50..+50)
HINGE_F, ELEV_Z0 = 0.72, 385.0
LAM = TIP / ROOT
SLOPE = math.tan(math.radians(SWEEP_LE)) - 0.25 * (ROOT - TIP) / HALF
SY_TIP = (0.09 * TIP) / (0.12 * ROOT)
CTR_SC = 470.0 / ROOT                       # centerline chord scale (TE deck)
CTR_ST = (0.16 * 420.0) / (0.12 * ROOT)     # centerline thickness scale
BLEND_HW = 120.0                            # body blend half-width
SLOT_X0, SLOT_X1 = 294.0, 318.0             # prop slot fore-aft opening
SLOT_HZ = 108.0                             # slot half-span
PROP_X, PROP_R = 306.0, 101.5               # 8x6 prop, fully recessed
MOT_Y = 8.0                                 # motor/prop axis height
MAC = 2 / 3 * ROOT * (1 + LAM + LAM**2) / (1 + LAM)
YMAC = (HALF / 3) * (1 + 2 * LAM) / (1 + LAM)
CG_LE = YMAC * math.tan(math.radians(SWEEP_LE)) + 0.25 * MAC - 0.08 * MAC
CG_X = CG_LE - 0.25 * ROOT

# ---------------- materials (glossy white) ----------------
C_WHITE, C_ELEV, C_GAP = "#f7f8fa", "#eceef2", "#9aa0a8"
C_GLASS, C_PROP = "#15181d", "#26282d"
AMB, KD, KS, SPEC_EXP = 0.52, 0.42, 0.34, 30
LIGHT = np.array([-0.50, 0.25, 0.83])       # plot coords: X chord, Y span, Z up
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# ---------------- NACA 2412 section (qc at origin) ----------------
def naca_loop(n=36, m=0.02, p=0.4, t=0.12):
    beta = np.linspace(0, math.pi, n)
    x = (1 - np.cos(beta)) / 2
    yc = np.where(x < p, m / p**2 * (2 * p * x - x**2),
                  m / (1 - p)**2 * ((1 - 2 * p) + 2 * p * x - x**2))
    yt = 5 * t * (0.2969 * np.sqrt(x) - 0.1260 * x - 0.3516 * x**2
                  + 0.2843 * x**3 - 0.1036 * x**4)
    xs = np.concatenate([x[::-1], x[1:]])
    ys = np.concatenate([(yc + yt)[::-1], (yc - yt)[1:]])
    return (xs - 0.25) * ROOT, ys * ROOT, xs

X0, Y0, FRAC = naca_loop()

def wing_station(zw):
    """wing section at local span zw (0..HALF): scale, twist, shear."""
    u = zw / HALF
    sx = 1 - (1 - LAM) * u
    sy = 1 - (1 - SY_TIP) * u
    a = math.radians(WASHOUT * u)
    return (sx * X0 * math.cos(a) - sy * Y0 * math.sin(a) + SLOPE * zw,
            sx * X0 * math.sin(a) + sy * Y0 * math.cos(a))

def body_station(zb):
    """blended body section at |zb| <= BLEND_HW: cosine point-morph
    between the local wing section and the fat centerline section."""
    w = (1 + math.cos(math.pi * zb / BLEND_HW)) / 2
    wx, wy = wing_station(max(0.0, abs(zb) - BODY_W / 2))
    return ((1 - w) * wx + w * CTR_SC * X0,
            (1 - w) * wy + w * CTR_ST * Y0)

# ---------------- mesh (stored in PLOT coords: X, span, up) ----------------
faces, basecols, normals = [], [], []

def add_face(pts_model, color):
    p = np.asarray(pts_model, float)[:, [0, 2, 1]]      # model -> plot
    n = np.cross(p[1] - p[0], p[2] - p[0])
    nn = np.linalg.norm(n)
    faces.append(p)
    basecols.append(np.array(matplotlib.colors.to_rgb(color)))
    normals.append(n / nn if nn > 0 else np.array([0, 0, 1.0]))

def in_slot(pts):
    """True if a quad lies inside the prop-slot cutout."""
    return all(SLOT_X0 < p[0] < SLOT_X1 and abs(p[2]) < SLOT_HZ for p in pts)

def loft(stations, zs, color_fn, skip=None):
    for k in range(len(zs) - 1):
        xa, ya = stations[k]; xb, yb = stations[k + 1]
        zm = (zs[k] + zs[k + 1]) / 2
        for i in range(len(xa) - 1):
            quad = [(xa[i], ya[i], zs[k]), (xa[i+1], ya[i+1], zs[k]),
                    (xb[i+1], yb[i+1], zs[k+1]), (xb[i], yb[i], zs[k+1])]
            if skip and skip(quad):
                continue
            add_face(quad, color_fn(zm, (FRAC[i] + FRAC[i + 1]) / 2))

def wing_color(zm, f):
    zl = abs(zm) - BODY_W / 2
    if zl > ELEV_Z0 and HINGE_F - 0.014 < f <= HINGE_F:
        return C_GAP
    if zl > ELEV_Z0 and f > HINGE_F:
        return C_ELEV
    return C_WHITE

def build():
    # wing halves — the blended body covers |z| <= 120 (zw 0..70)
    for side in (+1, -1):
        zw = np.concatenate([np.linspace(70, ELEV_Z0, 10),
                             np.linspace(ELEV_Z0, HALF, 14)[1:]])
        secs = [wing_station(z) for z in zw]
        zs = side * (zw + BODY_W / 2)
        loft(secs, zs, wing_color)
        xt, yt = secs[-1]
        add_face(np.column_stack([xt, yt, np.full_like(xt, zs[-1])]), C_WHITE)
    # blended body + TE deck, with the prop slot cut out of the skin
    zb = np.linspace(-BLEND_HW, BLEND_HW, 31)
    loft([body_station(z) for z in zb], zb, lambda zm, f: C_WHITE,
         skip=in_slot)
    # slot interior walls (dark, suggest depth)
    add_face([(SLOT_X0, -5, -SLOT_HZ), (SLOT_X0, 13, -SLOT_HZ),
              (SLOT_X0, 13, SLOT_HZ), (SLOT_X0, -5, SLOT_HZ)], "#565b62")
    add_face([(SLOT_X1, -4, -62), (SLOT_X1, 11, -62),
              (SLOT_X1, 11, 62), (SLOT_X1, -4, 62)], "#494e55")
    # hub spinner inside the slot
    th = np.linspace(0, 2 * math.pi, 26)
    sxs, srs = [PROP_X, PROP_X + 6, PROP_X + 12], [8.5, 6.5, 2.5]
    srings = [np.column_stack([np.full_like(th, x), MOT_Y + r * np.cos(th),
                               r * np.sin(th)]) for x, r in zip(sxs, srs)]
    for a, b in zip(srings, srings[1:]):
        for i in range(len(th) - 1):
            add_face([a[i], a[i+1], b[i+1], b[i]], C_PROP)
    # camera lens dome at the nose aperture
    u, v = np.meshgrid(np.linspace(0, math.pi, 12),
                       np.linspace(0, 2 * math.pi, 22))
    lx = -100 + 5.5 * np.cos(u)
    ly = 3 + 6.0 * np.sin(u) * np.cos(v)
    lz = 6.0 * np.sin(u) * np.sin(v)
    for i in range(u.shape[0] - 1):
        for j in range(u.shape[1] - 1):
            add_face([(lx[i,j],ly[i,j],lz[i,j]), (lx[i+1,j],ly[i+1,j],lz[i+1,j]),
                      (lx[i+1,j+1],ly[i+1,j+1],lz[i+1,j+1]),
                      (lx[i,j+1],ly[i,j+1],lz[i,j+1])], C_GLASS)
    # raked winglets
    poly = np.array([[0,0],[TIP*0.80,0],[TIP*0.98,35],[TIP*0.78,95],
                     [TIP*0.45,105],[TIP*0.16,40]])
    xof = SLOPE * HALF - 0.25 * TIP + 12
    for side in (+1, -1):
        z = side * (HALF + BODY_W / 2)
        for dz in (-1.25, 1.25):
            add_face([(xof+p[0], 4+p[1], z+dz) for p in poly], C_WHITE)
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            add_face([(xof+a[0],4+a[1],z-1.25), (xof+b[0],4+b[1],z-1.25),
                      (xof+b[0],4+b[1],z+1.25), (xof+a[0],4+a[1],z+1.25)],
                     C_WHITE)

def prop_overlay():
    """transparent prop disc + two slender blades, inside the slot."""
    cx, cy, r = PROP_X, MOT_Y, PROP_R
    th = np.linspace(0, 2 * math.pi, 80)
    disc = np.column_stack([np.full_like(th, cx), th * 0 + cy + r*np.cos(th),
                            r * np.sin(th)])[:, :]
    blades = []
    for ang in (math.radians(65), math.radians(245)):
        rr = np.linspace(13, r, 12)
        w = 6.5 * (1 - 0.5 * rr / r)
        up = [(cx, cy + ri*math.cos(ang) - wi*math.sin(ang),
               ri*math.sin(ang) + wi*math.cos(ang)) for ri, wi in zip(rr, w)]
        dn = [(cx, cy + ri*math.cos(ang) + wi*math.sin(ang),
               ri*math.sin(ang) - wi*math.cos(ang)) for ri, wi in zip(rr, w)]
        blades.append(np.asarray(up + dn[::-1])[:, [0, 2, 1]])
    return disc[:, [0, 2, 1]], blades

build()
DISC, BLADES = prop_overlay()

# ---------------- rendering ----------------
def shaded_colors(elev, azim):
    e, a = math.radians(elev), math.radians(azim)
    V = np.array([math.cos(e)*math.cos(a), math.cos(e)*math.sin(a), math.sin(e)])
    H = (LIGHT + V); H /= np.linalg.norm(H)
    out = []
    for c, n in zip(basecols, normals):
        d = abs(float(n @ LIGHT)); s = abs(float(n @ H)) ** SPEC_EXP
        out.append(tuple(np.clip(c * (AMB + KD * d) + KS * s, 0, 1)))
    return out

def draw(ax, persp, elev, azim, zoom=1.0, xlim=(-150, 500), shadow=False):
    if shadow:  # soft ground shadow under the hero craft
        t = np.linspace(0, 2 * math.pi, 60)
        sh = np.column_stack([200 + 280*np.cos(t), -30 + 700*np.sin(t),
                              np.full_like(t, -172)])
        ax.add_collection3d(Poly3DCollection([sh], facecolors="#3a4048",
                                             alpha=0.10, edgecolors="none"))
    pc = Poly3DCollection(faces, facecolors=shaded_colors(elev, azim),
                          edgecolors="none", zsort="average")
    ax.add_collection3d(pc)
    ax.add_collection3d(Poly3DCollection([DISC], facecolors="#3c4754",
                                         alpha=0.10, edgecolors="#5c6670",
                                         linewidths=0.8))
    ax.add_collection3d(Poly3DCollection(BLADES, facecolors=C_PROP,
                                         alpha=0.85, edgecolors="none"))
    ax.set_proj_type("persp" if persp else "ortho")
    ax.view_init(elev=elev, azim=azim)
    ax.set_xlim(*xlim); ax.set_ylim(-790, 790); ax.set_zlim(-180, 240)
    ax.set_box_aspect((xlim[1] - xlim[0], 1580, 420), zoom=zoom)
    ax.set_axis_off()
    ax.set_facecolor("#e9edf2")

fig = plt.figure(figsize=(19, 10.5), dpi=115)
fig.patch.set_facecolor("#f2f4f7")
gs = fig.add_gridspec(4, 3, width_ratios=[1.12, 1.12, 1.05],
                      height_ratios=[1.0, 0.74, 0.74, 1.0],
                      left=0.004, right=0.996, top=0.872, bottom=0.012,
                      wspace=0.02, hspace=0.14)

ax_hero = fig.add_subplot(gs[:, :2], projection="3d")
draw(ax_hero, persp=True, elev=23, azim=-141, zoom=1.30, shadow=True)

ax_top = fig.add_subplot(gs[0, 2], projection="3d")
draw(ax_top, persp=False, elev=89.9, azim=179.9, zoom=1.45, xlim=(-170, 710))
ax_top.plot([572, 572], [-750, 750], [60, 60], color="#8a929c", lw=1)
ax_top.text(655, 0, 60, "span 1,500 mm", fontsize=8, color="#555",
            ha="center", va="center")
ax_top.scatter([CG_X], [0], [85], marker="x", s=60, color="#cc2222",
               depthshade=False)
ax_top.text(CG_X, -380, 85, f"CG {CG_LE:.0f} mm aft of nose",
            fontsize=8, color="#cc2222", ha="center")
ax_top.text(395, 545, 70, "elevon", fontsize=8, color="#555", ha="center")
ax_top.text(415, 245, 70, "recessed\nprop slot", fontsize=8, color="#555",
            ha="center")
ax_top.text(-115, 220, 70, "O4 cam", fontsize=8, color="#555", ha="center")
ax_top.text(330, -660, 70, "winglet", fontsize=8, color="#555", ha="center")
ax_top.set_title("top — 25° sweep, elevons outboard", fontsize=9.5,
                 color="#333", pad=1)

ax_front = fig.add_subplot(gs[1, 2], projection="3d")
draw(ax_front, persp=False, elev=3, azim=179.9, zoom=2.5)
ax_front.set_title("front — 4° washout (tips ride nose-down)",
                   fontsize=9.5, color="#333", pad=1)

ax_side = fig.add_subplot(gs[2, 2], projection="3d")
draw(ax_side, persp=False, elev=3, azim=89.9, zoom=2.5)
ax_side.set_title("side — one continuous profile, prop hidden in the slot",
                  fontsize=9.5, color="#333", pad=1)

# ---------------- spec sheet ----------------
ax_spec = fig.add_subplot(gs[3, 2]); ax_spec.set_axis_off()
specs = (
    " MANTA-1500  ·  SPECIFICATIONS\n"
    " ───────────────────────────────────────\n"
    " span / area          1,500 mm · 0.47 m²\n"
    " airfoil              NACA 2412 → 2409\n"
    " sweep / washout      25° / 4°\n"
    " all-up weight        1.80 kg (880 g pack)\n"
    " wing loading         3.8 kg/m²\n"
    " stall / cruise       7.5 / 14–15 m/s\n"
    " cruise power         ~58 W\n"
    " endurance            ~3.2 h (6–8 h solar)\n"
    " range (still air)    ~160 km\n"
    " battery              6S2P Li-Ion · 216 Wh\n"
    " video                DJI O4 Air Unit Pro\n"
    " motor                2814 900KV · 8×6 in slot\n"
    " CG                   201 mm aft of nose\n"
    " autonomy             ArduPilot · RTL at 10%\n"
    " ───────────────────────────────────────\n"
    " gloss: sand 400 → white base → 2K clear"
)
ax_spec.text(0.05, 0.98, specs, family="monospace", fontsize=8.4,
             color="#2c3138", va="top", ha="left", linespacing=1.42,
             bbox=dict(boxstyle="round,pad=0.55", fc="white",
                       ec="#c8cdd5", lw=1))

fig.suptitle("MANTA-1500 — 3D-printed flying wing (design mockup)",
             fontsize=17, fontweight="bold", color="#23272d", y=0.972)
fig.text(0.5, 0.912,
         "one solid wing: prop fully recessed in a trailing-edge slot ·"
         " blended-wing body · gloss white · LW-PLA flying surfaces, PETG core ·"
         " DJI O4 Air Unit Pro behind the nose aperture · ~3.2 h cruise",
         ha="center", fontsize=10, color="#4a5058")

out = os.path.join(os.path.dirname(__file__) or ".", "..", "renders")
os.makedirs(out, exist_ok=True)
path = os.path.abspath(os.path.join(out, "manta_mockup.png"))
fig.savefig(path, facecolor=fig.get_facecolor())
print("wrote", path, "| faces:", len(faces), f"| CG {CG_LE:.1f} mm aft of nose")
