# MANTA-1500 — 3D-printed flying wing (~3.5 h cruise, best solar platform)

A 1.5 m tailless flying wing: no fuselage, no tail, just lifting surface. Lowest
drag and the most sun-facing area in the fleet — same shared electronics, pack,
charger, solar station and autonomy stack as HELIOS-10 and SKYLARK.

CAD: `cad/manta_wing.scad` · Params: `ardupilot/manta-wing.param` ·
Software: shared (`software/`, auto-detects plane)

## 1. Why a wing flies longest

Everything that isn't wing is drag that makes no lift. Deleting the fuselage and
tail cuts wetted area massively. The price: a tailless aircraft must get its pitch
stability from **25° sweep + 4° washout** (the tips fly nose-down, acting like a
tail) and a **correct CG**. The SCAD computes the balance point from the planform
and molds **CG dimples into the belly** — balance there, always. Tail-heavy = crash;
slightly nose-heavy = lands a bit sooner. The file also echoes the neutral point:
never balance behind it.

## 2. The math

**Weight:** LW-PLA airframe + spars ~620 g, motor/prop/ESC/2 servos ~135 g,
electronics ~99 g, wiring ~45 g → dry ~0.9 kg; + 880 g pack → **AUW ≈ 1.78 kg**.

**Area:** 0.45 m² → wing loading 4.0 kg/m², stall ≈ 7.5 m/s, cruise 14–15 m/s.

**Cruise power:** L/D ≈ 11 (clean tailless) → drag 17.7/11 = 1.6 N × 14.5 m/s
= 23 W aero ÷ (0.62 prop × 0.85 motor) ≈ **43 W**, +~12% for the recessed-slot
prop (smaller 8" disc + slot-edge losses — the price of the clean silhouette)
≈ **48 W** + 10 W avionics = **~58 W**.

**Endurance: 184 Wh ÷ 58 W ≈ 3.2 h · range ≈ 160 km still air.**

## 3. Onboard solar — the closest this fleet gets to a solar airplane

The wing offers **~0.245 m² of usable cell area** (16× SunPower C60 in two
spanwise rows, clear of the elevons):

- Midday harvest: 0.245 m² × 1000 × 0.225 × 0.8 ≈ **44 W**
- Solar system ≈ +300 g → AUW ~2.10 kg → cruise ~70 W
- **Net midday draw: 70 − 44 ≈ 26 W → endurance stretches toward 6–8 h** in
  strong summer sun; true break-even at solar noon would need a flawless build
  in midsummer — physically *close* here, but design for assist, not perpetual flight.
- Parked nose-into-sun it recharges its own pack — a self-sufficient field unit
  even without the folding ground panel.

Same solar kit architecture as SKYLARK (cells → bypass diodes → Genasun GVB-8
boost MPPT 25.2 V → pack lead), just 16 cells (~$240 total).

## 4. Extra parts to buy (on top of the shared electronics)

| Part | Qty | ~$ |
|---|---|---|
| 2814 900KV motor (buried in the wing, ahead of the prop slot) | 1 | 36 |
| 8×6 fixed props (spin inside the TE slot — folding blades can snag) | 4 | 12 |
| 40 A ESC with 5 V BEC | 1 | 30 |
| 9–12 g metal-gear servos (elevons) | 2 | 16 |
| Carbon: 2× Ø10 spar tube, Ø5 rod (cut lengths echoed by the SCAD) | — | 30 |
| LW-PLA 2 spools + PETG for the body | — | 80 |
| Hinge tape, kevlar belly tape, CA + epoxy | — | 20 |
| **Wing-specific subtotal** | | **~225** |

## 5. Printing & assembly

- **Before printing anything**: open the SCAD, press F6, and check the preview —
  the wingtip trailing edge must sit **higher** than the root's (washout). If your
  OpenSCAD version twists the other way, flip `washout_dir`. A wing with wash-in
  is unflyable. The console also prints the CG location and spar cut lengths.
- Wing segments in LW-PLA standing up; body, fairings + hatch in PETG;
  winglets/elevons LW-PLA.
- Spars slide through the body's angled channels into both wing halves; Ø5 pins
  stop rotation; tape the root joints (field-removable). Elevons tape-hinge on
  the angled hinge line; servos in the segment-3 pockets.
- Battery sits inside the blended body over the CG dimples (it IS the trim
  weight); the O4 unit rides behind it, its camera looking out through the round
  nose aperture. The motor is buried in the wing and the prop spins **inside the
  trailing-edge slot** — nothing protrudes from the silhouette, and the deck
  shields the blades on belly landings (use fixed blades, never folding, in
  the slot).
- The blend region is wider than a print bed, so the center prints as three
  pieces: `body` plus two mirrored `fairing` segments — the spar tubes tie all
  of it together.
- Gloss white finish: wet-sand the LW-PLA at 400 grit, white filler-primer/base,
  then 2K clear coat — it also seals and stiffens the foamed plastic.

## 6. Flying it autonomously

Same three layers, shared software. Wing specifics:

- Load `ardupilot/manta-wing.param` (elevon mixing is in there);
  `battery_rtl.lua`: set `VEHICLE = "plane"`.
- Bench check in FBWA: nose up → both elevons up; roll right → right elevon up.
  Fix directions with SERVOx_REVERSED only.
- Hand launch with a pusher: grip the belly ahead of the prop, firm level throw —
  the motor only spools after the launch acceleration (extra delay is configured).
  Keep fingers away from the prop arc.
- Critical battery on a plane = RTL (it circles home at 60 m); land in FBWA on
  the kevlar belly strip, or add a DO_LAND_START sequence for full auto-landing.

First flights: CG on the dimples, calm evening air, FBWA, gentle trims — wings
are slippery and build speed fast in descents. Autotune once trimmed, then missions.
