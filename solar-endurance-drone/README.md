# HELIOS-10 — solar-cycled, 1-hour autonomous quad with DJI O4 Air Unit Pro

A 10-inch, Li-Ion powered, 3D-printed endurance quadcopter designed around four goals:

| Goal | How this build delivers |
|---|---|
| **≥ 60 min flight time** | ~72 min calm hover / 60+ min real missions (math in §2) |
| **Best video quality** | DJI O4 Air Unit Pro (4K/120, 10-bit D-Log M) |
| **100% solar self-sufficient by day** | 200–400 W folding ground station recharges the packs between flights — full math in §4, including why on-board panels physically cannot do it |
| **Autonomous: waypoint paths + forced return at 10% battery** | ArduPilot + three independent safety layers (§7), code included |

```
solar-endurance-drone/
├── cad/helios10_frame.scad        ← 3D print files (parametric OpenSCAD → export STL)
├── ardupilot/helios10.param       ← flight controller config (10% RTL failsafe = layer 1)
└── software/
    ├── battery_rtl.lua            ← runs ON the FC, forces RTL at 10% (layer 2)
    ├── mission_guardian.py        ← Pi companion: uploads paths, guards battery (layer 3)
    └── mission_example.yaml       ← predetermined path format
```

**Headline numbers:** 1.6 kg all-up weight · ~154 W hover (10.4 g/W) · 216 Wh of Molicel 21700s · 380 mm wheelbase · 10×5 props.

---

## 1. Why this design is the efficient one

Multirotor endurance is won with **low disc loading** (big props, light craft) and **energy-dense cells**:

- **10" props on 880KV motors** instead of a racing 5": doubling disc area cuts induced power by ~30% for the same weight.
- **Li-Ion 21700 (Molicel P50B)** instead of LiPo: ~250 Wh/kg vs ~160 Wh/kg. The hover current is so low (~7 A total) that the cells' modest discharge rating never matters.
- **Printed hub + carbon-tube arms**: printing the *whole* frame in plastic would flex and resonate; printed pods + 16 mm carbon tubes give you a stiff frame, custom geometry, and cheap crash repairs.
- **Slow cruise beats hover**: at ~8 m/s a quad rides on translational lift and draws *less* than hover power, so a 60-min waypoint mission is easier than a 60-min hover.

## 2. The endurance math

**Weight budget (grams):**

| Group | g |
|---|---|
| Printed frame + 4 carbon tubes + hardware | 290 |
| 4 × 2814 880KV motors + 10×5×3 props | 255 |
| 4-in-1 ESC, FC, GPS, ELRS RX | 62 |
| DJI O4 Air Unit Pro + antennas + mounts | 38 |
| Raspberry Pi Zero 2 W + harness | 21 |
| Wiring, XT60, capacitor, straps | 55 |
| **Dry weight** | **~720** |
| 6S2P Molicel P50B pack (12 × 21700) | ~880 |
| **All-up weight (AUW)** | **~1,600** |

**Hover power (momentum theory):**

- Disc area: 4 × π × (0.127 m)² = **0.203 m²**
- Thrust = 1.6 kg × 9.81 = 15.7 N
- Ideal induced power: P = T^1.5 / √(2ρA) = 15.7^1.5 / √(2 × 1.225 × 0.203) ≈ **88 W**
- ÷ 0.72 prop figure of merit ≈ 123 W shaft → ÷ 0.85 motor+ESC efficiency ≈ **144 W electrical**
- + avionics: O4 Pro ~6 W + Pi Zero 2 W ~1.5 W + FC/GPS/RX ~2 W ≈ 10 W
- **Total hover ≈ 154 W → 10.4 g/W** (consistent with well-built 10" Li-Ion cruisers)

**Endurance:**

- Pack: 6S2P × 5.0 Ah = 21.6 V × 10 Ah = **216 Wh**; usable to 3.0 V/cell ≈ 85% → **184 Wh**
- 184 Wh ÷ 154 W = **72 min hover** → budget **60–65 min real missions** (wind, climbs, cold). ✔ Goal met with margin.

> Want more? Swapping to 12" props (480KV motors, 450 mm wheelbase) pushes past 90 min — the SCAD file is parametric (`wheelbase`, prop sizes) for exactly that.

## 3. Parts to buy (BOM)

Prices are approximate USD — check current prices. Substitutions in *italics*.

### The aircraft

| Part | Qty | ~$ |
|---|---|---|
| DJI O4 Air Unit Pro | 1 | 229 |
| iFlight XING X2814 880KV motors *(or BrotherHobby 2812 900KV)* | 4 | 145 |
| iFlight BLITZ E55 4-in-1 ESC, BLHeli_32 *(any 45–60 A 4-in-1)* | 1 | 70 |
| Matek H743-SLIM flight controller (runs ArduPilot) | 1 | 110 |
| Matek M10Q-5883 GPS + compass | 1 | 32 |
| RadioMaster RP1/XR1 ExpressLRS receiver | 1 | 20 |
| Raspberry Pi Zero 2 W (companion computer) | 1 | 18 |
| **Battery:** prebuilt 6S2P 21700 Li-Ion pack, Molicel P50B/P45B (Auline, Vapcell…) — **buy 2** for the solar rotation | 2 | 300 |
| HQProp 10×5×3 props *(or Gemfan 1050)* + spares | 8 | 35 |
| Carbon tube 16 mm OD × 14 mm ID × 500 mm (cut 4 arms) | 2 | 28 |
| M3/M2 hardware kit, 35 mm standoffs, XT60, 12 AWG wire, 1000 µF low-ESR cap, battery straps | — | 45 |
| 1 kg PETG-CF (or PA-CF) + small TPU spool | — | 45 |
| Remote ID broadcast module (e.g. BlueMark DroneBeacon) — legally required in US/EU for >249 g | 1 | 60 |
| **Aircraft subtotal** | | **~1,140** |

### Ground gear (skip what you own)

| Part | ~$ |
|---|---|
| DJI Goggles N3 *(or Goggles 3 for the premium screen, ~$499)* | 229 |
| RadioMaster Pocket ELRS radio *(or Boxer/TX16S)* | 65 |
| HOTA D6 Pro charger (650 W on DC input — solar-friendly, Li-Ion profile) | 95 |

### The solar station (§4 for sizing)

| Part | ~$ |
|---|---|
| 200 W folding solar panel (Renogy / ALLPOWERS / EcoFlow class) — *400 W (~$500) for gapless ops* | 250 |
| Victron SmartSolar MPPT 75/15 charge controller | 60 |
| 12 V 20 Ah LiFePO4 buffer battery (optional but recommended — see §4) | 110 |
| XT60/MC4 cabling, inline wattmeter | 25 |

**Everything, all-in: roughly $1,900–2,300** depending on options. Cost cuts: standard O4 instead of Pro (−$100, less video quality), one pack instead of two (−$150, breaks the continuous solar cycle), skip the buffer battery (−$110).

## 4. Solar: the math you asked for

### 4a. Why panels ON the drone can't keep it airborne — proof

- Hover draw: **154 W** (§2).
- Best flexible cells: ~23% efficient × 1,000 W/m² peak sun × ~0.85 wiring/MPPT derate ≈ **195 W per m²**.
- Panel area needed to hover: 154 ÷ 195 ≈ **0.79 m²** — a sheet roughly 0.9 × 0.9 m, far bigger than the entire drone.
- Area actually available between the prop arcs on a 380 mm frame: ~0.015 m² → **~3 W, i.e. 2% of hover power**. Even an oversized deck shading the props is ~10 W = 6%.
- And it spirals: panel + structure adds mass → hover power rises → you need *more* panel. Only large fixed-wing aircraft (10+ m wingspan, e.g. Airbus Zephyr) close this loop.

**Conclusion: on a quad this size, in-flight solar sustain is physically impossible — no product fixes this, it's physics.** The included `solar_deck` print is an honest option: a ~5–10 W panel that offsets avionics draw and trickle-charges while parked, nothing more.

### 4b. The design that IS 100% self-sufficient in the day: fly ↔ recharge cycle

Recharge the packs from the sun between flights. Zero grid power, all day.

**Energy per flight:** 184 Wh out of the pack → ÷ 0.92 charger eff. ÷ 0.95 MPPT/wiring ≈ **210 Wh of solar input per recharge**.

**With the 200 W panel** (real-world ~150 W in good sun, re-aimed hourly):
- Recharge time: 210 ÷ 150 ≈ **1.4 h** (charge current ≈ 6 A ≈ 0.6C — gentle on the cells)
- A good solar day (~8 productive hours) harvests ≈ 1.2 kWh ≈ **5 full recharges ≈ 5 flight-hours/day**
- Cycle with 2 packs: fly A (60 min) while B charges (84 min) → ~40% airborne duty cycle

**With the 400 W panel** (~300 W real):
- Recharge time: 210 ÷ 300 ≈ **42 min — faster than a flight**
- Fly pack A for 60 min while B recharges in 42 → swap → **gapless coverage all daylight**, 100% solar

**Two ways to wire it:**

1. **Simple:** panel → HOTA D6 Pro DC input (set the charger's input-current limit so it doesn't drag the panel below its max-power point) → pack. Fewer parts, fine in steady sun.
2. **Robust (recommended):** panel → Victron MPPT → 12 V 20 Ah LiFePO4 buffer (256 Wh) → D6 Pro → pack. The buffer rides through clouds, lets the panel work at its max-power point all day, and can even top a pack after sunset.

Sanity margin: 5 flights × 210 Wh = 1.05 kWh vs ~1.2 kWh/day harvested → **~15% surplus**, so an average-decent day still closes the loop. Winter/overcast cuts harvest 50–80% — expect fewer flights, not zero.

## 5. 3D printing the frame

Open `cad/helios10_frame.scad` in [OpenSCAD](https://openscad.org) (free), set the `part` variable, press F6, export STL. The console prints the **carbon tube cut length** for your parameters.

| Part | Qty | Material | Infill |
|---|---|---|---|
| `bottom_plate` | 1 | PETG-CF / PA-CF | 40% |
| `top_plate` | 1 | PETG-CF | 40% |
| `motor_pod` | 4 | PETG-CF / PA-CF | 60% |
| `tube_leg` | 4 | PETG | 40% |
| `cam_mount`, `o4_cradle`, `gps_mast` | 1 ea | PETG | 40% |
| `solar_deck` (optional) | 1 | PETG | 25% |

4+ perimeters, 0.2 mm layers everywhere. **PLA only for fit-checks** — it creeps under load and softens in the sun (you're building a solar drone!). Before printing the lot, print one `motor_pod`, test-fit your tube and motor, and adjust `tube_fit` / `cam_w` / `o4_w` — measure your actual O4 Pro camera width and set `cam_w`.

Assembly: epoxy or clamp tubes into hub + pods (pinch bolts included in the design), motors on pods (slots fit 16×16–19×19 patterns), FC stack under the bottom plate, battery strapped on top, GPS on its mast at the rear, O4 in the open cradle — **never enclose the O4 Pro, it needs airflow**.

## 6. Wiring

| From | To |
|---|---|
| Pack XT60 → 1000 µF cap → 4-in-1 ESC | power; ESC current sensor → FC |
| FC UART2 | DJI O4 (OSD via MSP DisplayPort) |
| FC UART4 + I2C | M10Q GPS + compass |
| FC UART6 | ELRS receiver (CRSF) |
| FC UART7 | Pi Zero 2 W GPIO UART (MAVLink, 921600) |
| FC 5V BEC | Pi Zero 2 W (draws ~0.6 A) |
| Battery lead (3–6S OK) | O4 Pro power |

## 7. Autonomy: three independent safety layers

The "AI" here is the same layered autonomy commercial drones use: a GPS waypoint autopilot + scripted decision logic + an extension hook for smarter brains.

1. **Layer 1 — autopilot failsafe** (`ardupilot/helios10.param`): ArduPilot itself triggers RTL at 1,000 mAh remaining (= 10% of the 10 Ah pack) and LAND at 5%, with sag-compensated voltage backstops. Works with everything else dead.
2. **Layer 2 — onboard Lua** (`software/battery_rtl.lua`): drop onto the FC's SD card (`APM/scripts/`). Independently forces RTL ≤10% / LAND ≤5% and re-asserts every 15 s if overridden.
3. **Layer 3 — companion computer** (`software/mission_guardian.py` on the Pi): uploads your predetermined path, refuses to launch below 95% charge or without 3D GPS, watches the battery cross-checked against a Li-Ion voltage curve (trusts whichever reads *lower*), forces RTL/LAND, and exposes `ai_decision_hook()` — drop your own logic in there. For camera-based AI (tracking/detection) later, swap the Pi Zero for a Pi 5 + camera module; note the O4's video goes to your goggles, not the Pi.

```bash
# on the Pi
pip install pymavlink pyyaml
python3 mission_guardian.py --conn /dev/serial0 --baud 921600 --mission mission_example.yaml
# or guard the battery while you fly FPV manually:
python3 mission_guardian.py --conn /dev/serial0 --baud 921600 --monitor-only
```

Predetermined paths are plain YAML (`mission_example.yaml`): takeoff altitude, cruise speed, waypoint list with optional loiter holds, automatic RTL at the end. You can also draw missions in Mission Planner — the YAML route is what makes it scriptable.

**Setup order:** flash ArduPilot Copter (Matek-H743 target) → load `helios10.param` → calibrate accel/compass/RC/battery monitor → verify motor order with props OFF → bench-test all three failsafe layers with props OFF (set `BATT_LOW_MAH` temporarily high to watch each layer fire) → first hover in Stabilize → Autotune → then missions.

## 8. Read before flying (the boring part that keeps your $2k airborne)

- **Regulations:** at 1.6 kg you must register, broadcast Remote ID, and (US Part 107 / EU A2) keep the drone in **visual line of sight even when autonomous**, max 120 m AGL. The geofence in the param file (500 m radius, 120 m ceiling) is set for this — widen it only where legal.
- **Li-Ion safety:** charge to 4.2 V/cell with the Li-Ion profile, never below 2.8 V/cell, charge on a fireproof surface, store at ~3.7 V/cell. Buy welded packs unless you own a spot welder — never solder directly to 21700 cells.
- **Test the failsafes on the bench (props off) before trusting them in the air.** All three layers, every time you change firmware.
- Maiden flight: manual, calm day, log a full battery curve from 100%→landing to calibrate the % readout before any autonomous hour-long mission.
