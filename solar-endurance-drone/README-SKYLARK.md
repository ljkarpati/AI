# SKYLARK-1600 — 3D-printed endurance plane (~3 h cruise)

A 1.6 m pod-and-boom airplane that flies on the **same 6S2P pack, charger, solar
station, radio, goggles and autonomy software as HELIOS-10** — but a wing makes
lift instead of burning watts for it, so the same 216 Wh lasts **~3 hours and
~150 km** instead of ~72 minutes.

CAD: `cad/skylark_plane.scad` · Params: `ardupilot/skylark-plane.param` ·
Software: shared (`software/`, auto-detects plane)

## 1. The math

**Weight budget:** printed airframe in LW-PLA + spars ~860 g, motor/ESC/servos
~140 g, O4 Pro + FC + GPS + RX + Pi ~99 g, wiring ~50 g → dry **~1.17 kg**;
plus the 880 g pack → **AUW ≈ 2.05 kg**.

**Wing:** 1.6 m × 0.22 m = 0.35 m² (NACA 2412) → wing loading 5.9 kg/m²,
stall ≈ 8.8 m/s, cruise 14 m/s.

**Cruise power:**
- Lift/drag for a clean printed cruiser ≈ 10 → drag = 20.1 N ÷ 10 = 2.0 N
- Aero power = 2.0 N × 14 m/s = 28 W
- ÷ 0.65 prop eff ÷ 0.85 motor+ESC = **51 W** + 10 W avionics = **~61 W total**

**Endurance: 184 Wh usable ÷ 61 W ≈ 3.0 h. Range ≈ 150 km still air.**
(The quad needs 154 W to hover; the plane cruises on 61 W — that's the whole story.)

## 2. Extra parts to buy (on top of the HELIOS-10 shared electronics)

Shared with the quad: DJI O4 Pro, Matek H743-SLIM, M10Q GPS, ELRS RX, Pi Zero 2 W,
6S2P pack(s), charger, radio, goggles, solar ground station, Remote ID module.

| Part | Qty | ~$ |
|---|---|---|
| 2814 900KV motor (tractor) | 1 | 36 |
| 10×6 folding prop + spinner (folds = no drag in glides) | 1 | 15 |
| 40 A ESC with 5 V BEC | 1 | 30 |
| 9–12 g metal-gear servos (2 aileron, elevator, rudder) | 4 | 32 |
| Carbon: Ø10×750 joiner, 2× Ø8×550 spars, Ø16/14×600 boom (same stock as the quad arms), Ø5 rod | — | 40 |
| LW-PLA (wing/tail) 2 spools + PETG (pod/mounts) | — | 80 |
| Matek ASPD-4525 airspeed sensor (optional, sharpens efficiency) | 1 | 28 |
| Hinge tape, kevlar belly tape, CA + epoxy | — | 20 |
| **Plane-specific subtotal** | | **~280** |

## 3. Onboard solar — on a wing it finally pays

The quad's top deck fits ~0.015 m² of cells. This wing offers **~0.18 m² of flat,
sun-facing surface** — a different game:

- 12 × SunPower Maxeon C60 cells (125 mm, ~23%) laminated along the wing: 0.184 m²
  × 1000 W/m² × 0.225 × 0.8 (lamination/temp/incidence) ≈ **33 W at midday**
- System weight ≈ +300 g (cells ~95 g, lamination ~80 g, boost-MPPT ~90 g, wiring)
  → AUW 2.35 kg → cruise rises to ~73 W (power scales with weight^1.5)
- Net midday draw: 73 − 33 = **40 W → ~4.6 h endurance, +55% over battery-only**
- Still not in-flight perpetual (needs 73 W average all day) — but on the ground
  it perch-charges the pack with no ground station at all.

**Solar option kit (~$220):** 12× C60 cells ($50), EVA + clear laminate ($25),
Genasun GVB-8 boost MPPT with 25.2 V lithium output ($130), bypass diode every
4 cells + wiring ($15). Cells in series along the span, MPPT output Y'd into the
pack lead. The CC/CV boost MPPT is what makes feeding a 6S pack from a ~7 V cell
string safe — do not wire cells to the battery directly.

## 4. Printing & assembly

LW-PLA for wing and tail surfaces (1–2 perimeters, 2% gyroid infill, ~245 °C —
**tune flow on a test cube first**, LW-PLA foams differently per brand). PETG for
pod, hatch, tail mount, saddles. Print wing segments standing up (span vertical).

1. `pod` + `hatch`: battery + FC + Pi live inside; O4 unit in the pod with the
   camera on the hatch shelf; motor bolts to the nose firewall (16×16–19×19 slots).
2. Wing: 4 segments per side over the spar tubes, CA/epoxy at each joint;
   ailerons hinge with tape; one 9 g servo per side in the printed pockets.
   The Ø10 joiner tube crosses the pod saddle — wings slide on at the field.
3. Tail: boom into the pod socket (pinch bolt), `tail_mount` on the rear, stab
   halves pinned + glued, fin on top; elevator/rudder servos on the
   `boom_servo_saddle` mid-boom, short pushrods.
4. **Balance 60–66 mm behind the wing leading edge** (battery position is your
   trim weight). Kevlar tape on the belly — it lands on it.

## 5. Flying it autonomously

Same three safety layers as the quad — same files. Plane specifics:

- Load `ardupilot/skylark-plane.param`; in `battery_rtl.lua` set `VEHICLE = "plane"`.
- `mission_guardian.py` auto-detects a plane from the heartbeat: takeoff items get
  a climb-out pitch, and the critical-battery action becomes RTL (a plane can't
  hover-land; add a `DO_LAND_START` landing sequence in Mission Planner when
  you're ready for fully hands-off landings).
- Launch: arm in AUTO, the motor stays quiet until the throw (TKOFF_THR_MINACC) —
  give it a firm level toss and it climbs out and flies the YAML mission.
- RTL behavior: circles home at 60 m until you take over and glide it in.

First flights: FBWA mode, no mission, trim it, then Autotune, then missions.
