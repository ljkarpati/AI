#!/usr/bin/env python3
"""
render_manta.py — multi-view design mockup of the MANTA-1500 flying wing.

Rebuilds the exact geometry of cad/manta_wing.scad (same planform,
airfoil, sweep, taper and washout math) and renders a shaded
perspective view plus orthographic top/front/side views.

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
HINGE_F, ELEV_Z0 = 0.72, 350.0
LAM = TIP / ROOT
SLOPE = math.tan(math.radians(SWEEP_LE)) - 0.25 * (ROOT - TIP) / HALF
SY_TIP = (0.09 * TIP) / (0.12 * ROOT)          # thickness scale at tip
MAC = 2 / 3 * ROOT * (1 + LAM + LAM**2) / (1 + LAM)
YMAC = (HALF / 3) * (1 + 2 * LAM) / (1 + LAM)
CG_LE = YMAC * math.tan(math.radians(SWEEP_LE)) + 0.25 * MAC - 0.08 * MAC
CG_X = CG_LE - 0.25 * ROOT                      # model coords (origin = root qc)

# colors
C_WING, C_ELEV, C_GAP = "#c9cbcf", "#b2b5bb", "#3c3c40"
C_BODY, C_RISER = "#e8762b", "#d2641f"
C_DARK, C_PROP = "#2e2e33", "#222226"
LIGHT = np.array([-0.45, 0.30, 0.85])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# ---------------- NACA 2412 section (qc at origin) ----------------
def naca_loop(n=36, m=0.02, p=0.4, t=0.12):
    """closed loop of (x0, y0, f) — f = chord fraction, root frame."""
    beta = np.linspace(0, math.pi, n)
    x = (1 - np.cos(beta)) / 2
    yc = np.where(x < p, m / p**2 * (2 * p * x - x**2),
                  m / (1 - p)**2 * ((1 - 2 * p) + 2 * p * x - x**2))
    yt = 5 * t * (0.2969 * np.sqrt(x) - 0.1260 * x - 0.3516 * x**2
                  + 0.2843 * x**3 - 0.1036 * x**4)
    xs = np.concatenate([x[::-1], x[1:]])           # TE -> LE (upper) -> TE
    ys = np.concatenate([(yc + yt)[::-1], (yc - yt)[1:]])
    return (xs - 0.25) * ROOT, ys * ROOT, xs        # qc at x=0

X0, Y0, FRAC = naca_loop()

def station(zw):
    """section points at wing-local span zw (0..HALF): scale, twist, shear."""
    u = zw / HALF
    sx = 1 - (1 - LAM) * u
    sy = 1 - (1 - SY_TIP) * u
    a = math.radians(WASHOUT * u)                   # +CCW = LE down = washout
    x1 = sx * X0 * math.cos(a) - sy * Y0 * math.sin(a) + SLOPE * zw
    y1 = sx * X0 * math.sin(a) + sy * Y0 * math.cos(a)
    return x1, y1

# ---------------- mesh builders ----------------
faces, colors, shades = [], [], []

def add_face(pts, color, double_shade=True):
    p = np.asarray(pts, float)
    n = np.cross(p[1] - p[0], p[2] - p[0])
    nn = np.linalg.norm(n)
    s = 0.45 + 0.55 * abs(np.dot(n / nn, LIGHT)) if nn > 0 else 0.8
    faces.append(p)
    colors.append(color)
    shades.append(s)

def add_box(x0, x1, y0, y1, z0, z1, color):
    v = np.array([[x0,y0,z0],[x1,y0,z0],[x1,y1,z0],[x0,y1,z0],
                  [x0,y0,z1],[x1,y0,z1],[x1,y1,z1],[x0,y1,z1]])
    for q in ([0,1,2,3],[4,5,6,7],[0,1,5,4],[2,3,7,6],[1,2,6,5],[0,3,7,4]):
        add_face(v[q], color)

def wing_half(side):
    """side=+1 right (model z +50..+750), -1 left."""
    zw = np.concatenate([np.linspace(0, ELEV_Z0, 10),
                         np.linspace(ELEV_Z0, HALF, 16)[1:]])
    secs = [station(z) for z in zw]
    for k in range(len(zw) - 1):
        xa, ya = secs[k]; xb, yb = secs[k + 1]
        za = side * (zw[k] + BODY_W / 2); zb = side * (zw[k + 1] + BODY_W / 2)
        zmid = (zw[k] + zw[k + 1]) / 2
        for i in range(len(xa) - 1):
            f = (FRAC[i] + FRAC[i + 1]) / 2
            if zmid > ELEV_Z0 and HINGE_F - 0.018 < f <= HINGE_F:
                c = C_GAP                     # hinge gap line
            elif zmid > ELEV_Z0 and f > HINGE_F:
                c = C_ELEV                    # elevon surface
            else:
                c = C_WING
            add_face([(xa[i], ya[i], za), (xa[i+1], ya[i+1], za),
                      (xb[i+1], yb[i+1], zb), (xb[i], yb[i], zb)], c)
    # tip cap
    xt, yt = secs[-1]
    add_face(np.column_stack([xt, yt, np.full_like(xt, side * (HALF + BODY_W/2))]),
             C_WING)

def body():
    xa, ya = station(0)
    for s in (-1, 1):  # side caps
        add_face(np.column_stack([xa, ya, np.full_like(xa, s * BODY_W / 2)]), C_BODY)
    for i in range(len(xa) - 1):  # skin
        add_face([(xa[i], ya[i], -BODY_W/2), (xa[i+1], ya[i+1], -BODY_W/2),
                  (xa[i+1], ya[i+1], BODY_W/2), (xa[i], ya[i], BODY_W/2)], C_BODY)
    add_box(-57, 93, 20, 33, -25, 25, C_RISER)        # battery hatch riser
    add_box(-95, -66, 14, 29, -13, 13, C_DARK)        # O4 camera shelf
    add_box(-92, -69, 17, 26, -10, 10, "#111114")     # lens aperture
    for zz in (-16, 12):                              # motor arms
        add_box(255, 341, -3, 11, zz, zz + 4, C_BODY)
    add_box(335, 340, -14, 22, -19, 19, C_BODY)       # motor plate
    add_box(341, 364, -8, 16, -12, 12, C_DARK)        # motor can

def winglet(side):
    poly = np.array([[0,0],[187,0],[165,110],[77,120],[26,30]], float)
    xof = SLOPE * HALF - 0.25 * TIP + 15
    z = side * (HALF + BODY_W / 2)
    for dz in (-1.5, 1.5):
        add_face([(xof + p[0], 4 + p[1], z + dz) for p in poly], C_BODY)
    for i in range(len(poly)):                        # edge band
        a, b = poly[i], poly[(i + 1) % len(poly)]
        add_face([(xof+a[0], 4+a[1], z-1.5), (xof+b[0], 4+b[1], z-1.5),
                  (xof+b[0], 4+b[1], z+1.5), (xof+a[0], 4+a[1], z+1.5)], C_BODY)

def prop():
    cx, cy, r = 352.0, 4.0, 114.0
    th = np.linspace(0, 2 * math.pi, 72)
    ring = np.column_stack([np.full_like(th, cx), cy + r * np.cos(th),
                            r * np.sin(th)])
    for ang in (math.radians(70), math.radians(250)):  # two blades
        rr = np.linspace(16, r, 10)
        w = 11 * (1 - 0.55 * (rr / r))                 # blade taper
        up = [(cx, cy + ri * math.cos(ang) - wi * math.sin(ang),
               ri * math.sin(ang) + wi * math.cos(ang)) for ri, wi in zip(rr, w)]
        dn = [(cx, cy + ri * math.cos(ang) + wi * math.sin(ang),
               ri * math.sin(ang) - wi * math.cos(ang)) for ri, wi in zip(rr, w)]
        add_face(up + dn[::-1], C_PROP)
    add_box(346, 358, cy - 8, cy + 8, -8, 8, C_PROP)   # spinner
    return ring

# ---------------- build ----------------
wing_half(+1); wing_half(-1); body(); winglet(+1); winglet(-1)
ring = prop()

def draw(ax, persp, elev, azim, zoom=1.0, xlim=(-140, 480)):
    pc = Poly3DCollection(
        [f[:, [0, 2, 1]] for f in faces],              # plot: X=x, Y=span, Z=up
        facecolors=[tuple(np.clip(np.array(matplotlib.colors.to_rgb(c)) * s, 0, 1))
                    for c, s in zip(colors, shades)],
        edgecolors="none", zsort="average")
    ax.add_collection3d(pc)
    ax.plot(ring[:, 0], ring[:, 2], ring[:, 1], color="#55555a", lw=1.0, alpha=0.7)
    ax.set_proj_type("persp" if persp else "ortho")
    ax.view_init(elev=elev, azim=azim)
    ax.set_xlim(*xlim); ax.set_ylim(-790, 790); ax.set_zlim(-180, 240)
    ax.set_box_aspect((xlim[1] - xlim[0], 1580, 420), zoom=zoom)
    ax.set_axis_off()

fig = plt.figure(figsize=(19, 10.5), dpi=115)
fig.patch.set_facecolor("white")
gs = fig.add_gridspec(3, 3, width_ratios=[1.12, 1.12, 1.05],
                      left=0.0, right=0.995, top=0.875, bottom=0.03,
                      wspace=0.02, hspace=0.12)

ax_hero = fig.add_subplot(gs[:, :2], projection="3d")
draw(ax_hero, persp=True, elev=22, azim=-145, zoom=1.75)

ax_top = fig.add_subplot(gs[0, 2], projection="3d")
draw(ax_top, persp=False, elev=89.9, azim=179.9, zoom=1.45, xlim=(-160, 700))
# top-view annotations (span runs horizontally; screen-left = +span)
ax_top.plot([560, 560], [-750, 750], [60, 60], color="#777", lw=1)
ax_top.text(645, 0, 60, "span 1,500 mm", fontsize=8, color="#444",
            ha="center", va="center")
ax_top.scatter([CG_X], [0], [80], marker="x", s=60, color="#cc0000",
               depthshade=False)
ax_top.text(CG_X, -370, 80, f"CG {CG_LE:.0f} mm aft of nose",
            fontsize=8, color="#cc0000", ha="center")
ax_top.text(400, 540, 70, "elevon", fontsize=8, color="#333", ha="center")
ax_top.text(460, 260, 70, "pusher prop", fontsize=8, color="#333", ha="center")
ax_top.text(-110, 230, 70, "O4 cam", fontsize=8, color="#333", ha="center")
ax_top.text(330, -660, 70, "winglet", fontsize=8, color="#333", ha="center")
ax_top.set_title("top — 25° sweep, elevons outboard", fontsize=9.5, pad=1)

ax_front = fig.add_subplot(gs[1, 2], projection="3d")
draw(ax_front, persp=False, elev=3, azim=179.9, zoom=2.8)
ax_front.set_title("front — 4° washout (tips ride nose-down)", fontsize=9.5, pad=1)

ax_side = fig.add_subplot(gs[2, 2], projection="3d")
draw(ax_side, persp=False, elev=3, azim=89.9, zoom=2.8)
ax_side.set_title("side — cam shelf · battery hatch · pusher", fontsize=9.5, pad=1)

fig.text(0.015, 0.075,
         "PRINT:  8 wing segments + 2 elevons + 2 winglets (LW-PLA) · body + hatch (PETG)\n"
         "BUY:  2× Ø10 carbon spar · Ø5 pin rod · 2814 900KV pusher + 9×6 · 40 A ESC ·"
         " 2× 9 g servos · DJI O4 Pro · 6S2P Li-Ion",
         fontsize=9, color="#555", ha="left", va="bottom", linespacing=1.6)

fig.suptitle("MANTA-1500 — 3D-printed flying wing (design mockup)",
             fontsize=17, fontweight="bold", y=0.975)
fig.text(0.5, 0.915,
         "1.5 m span · NACA 2412→2409 · 25° sweep + 4° washout · LW-PLA wing,"
         " PETG body (orange) · DJI O4 Air Unit Pro nose cam · 2814 pusher ·"
         f" 6S2P Li-Ion · ~3.5 h cruise · CG {CG_LE:.0f} mm aft of nose (marked)",
         ha="center", fontsize=10, color="#333")

out = os.path.join(os.path.dirname(__file__) or ".", "..", "renders")
os.makedirs(out, exist_ok=True)
path = os.path.abspath(os.path.join(out, "manta_mockup.png"))
fig.savefig(path, facecolor="white")
print("wrote", path, "| faces:", len(faces), f"| CG {CG_LE:.1f} mm aft of nose")
