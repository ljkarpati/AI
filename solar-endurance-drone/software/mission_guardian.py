#!/usr/bin/env python3
"""
HELIOS-10 mission guardian
==========================
Runs on the Raspberry Pi Zero 2 W (wired to the flight controller's
MAVLink UART) or on a laptop over telemetry/Wi-Fi/SITL.

What it does
------------
1. Uploads a predetermined waypoint path from a YAML file.
2. Pre-flight gates: GPS 3D fix, battery nearly full, link healthy.
3. Starts the mission (AUTO mode) and watches it.
4. BATTERY GUARDIAN: at <=10% remaining it FORCES Return-To-Launch,
   at <=5% it forces LAND. It cross-checks the autopilot's reported
   percentage against a Li-Ion voltage curve and trusts whichever
   is LOWER — a mis-set capacity can't lie to it.
5. `ai_decision_hook()` is your extension point for smarter
   behaviors (re-tasking, object avoidance, perch-to-charge logic).

This is the THIRD safety layer. Layers one and two run on the
flight controller itself and work even if the Pi dies:
  layer 1: ArduPilot battery failsafe   (ardupilot/helios10.param)
  layer 2: onboard Lua guardian         (software/battery_rtl.lua)

Install on the Pi:
    pip install pymavlink pyyaml

Usage:
    # full mission from the Pi (FC on serial):
    python3 mission_guardian.py --conn /dev/serial0 --baud 921600 \
        --mission mission_example.yaml

    # just guard the battery while YOU fly manually:
    python3 mission_guardian.py --conn /dev/serial0 --baud 921600 \
        --monitor-only

    # SITL simulation test (do this first!):
    python3 mission_guardian.py --conn udp:127.0.0.1:14550 \
        --mission mission_example.yaml

BENCH-TEST WITH PROPS OFF BEFORE ANY REAL FLIGHT.
"""

import argparse
import math
import sys
import time

import yaml
from pymavlink import mavutil

# ---------------- ArduCopter flight modes ----------------
MODES = {"STABILIZE": 0, "ALT_HOLD": 2, "AUTO": 3, "GUIDED": 4,
         "LOITER": 5, "RTL": 6, "LAND": 9, "SMART_RTL": 21}
MODE_NAMES = {v: k for k, v in MODES.items()}
SAFE_MODES = {MODES["RTL"], MODES["LAND"], MODES["SMART_RTL"]}

# Li-Ion (e.g. Molicel 21700) per-cell voltage -> % remaining,
# light-load curve. Deliberately conservative.
LIION_CURVE = [(4.20, 100), (4.05, 90), (3.95, 80), (3.86, 70),
               (3.78, 60), (3.71, 50), (3.64, 40), (3.57, 30),
               (3.47, 20), (3.30, 10), (3.10, 5), (2.80, 0)]


def voltage_to_pct(pack_v, cells):
    """Map per-cell voltage to % via linear interpolation."""
    v = pack_v / cells
    if v >= LIION_CURVE[0][0]:
        return 100.0
    for (v_hi, p_hi), (v_lo, p_lo) in zip(LIION_CURVE, LIION_CURVE[1:]):
        if v >= v_lo:
            f = (v - v_lo) / (v_hi - v_lo)
            return p_lo + f * (p_hi - p_lo)
    return 0.0


def haversine_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


# ======================================================================
#  YOUR AI HOOK
# ======================================================================
def ai_decision_hook(state):
    """
    Called every loop with the live telemetry dict:
      state = {mode, armed, pct, voltage, current_a, alt_m,
               lat, lon, dist_home_m, wp_seq, t}
    Return None to do nothing, or one of "RTL", "LAND", "LOITER"
    to override the flight mode. Plug your own logic in here —
    e.g. wind estimation, geofence margins, perch-site selection,
    or a vision model running on a bigger companion computer.
    """
    return None
# ======================================================================


class Guardian:
    def __init__(self, args):
        self.args = args
        self.home = None
        self.low_hits = 0          # consecutive low-battery samples
        self.crit_hits = 0
        self.was_armed = False

        print(f"[conn] {args.conn} ...")
        if args.conn.startswith(("udp", "tcp")):
            self.m = mavutil.mavlink_connection(args.conn)
        else:
            self.m = mavutil.mavlink_connection(args.conn, baud=args.baud)
        self.m.wait_heartbeat()
        print(f"[conn] heartbeat from sys {self.m.target_system} "
              f"comp {self.m.target_component}")
        # ask for telemetry at 4 Hz
        self.m.mav.request_data_stream_send(
            self.m.target_system, self.m.target_component,
            mavutil.mavlink.MAV_DATA_STREAM_ALL, 4, 1)

    # ---------------- low-level helpers ----------------
    def set_mode(self, mode_id, label):
        self.m.mav.command_long_send(
            self.m.target_system, self.m.target_component,
            mavutil.mavlink.MAV_CMD_DO_SET_MODE, 0,
            mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
            mode_id, 0, 0, 0, 0, 0)
        print(f"[mode] requested {label}")

    def force_mode(self, mode_id, label, tries=5):
        """Command a mode and verify the autopilot actually switched."""
        for i in range(tries):
            self.set_mode(mode_id, label)
            t0 = time.time()
            while time.time() - t0 < 2.0:
                hb = self.m.recv_match(type="HEARTBEAT", blocking=True,
                                       timeout=2)
                if hb and hb.custom_mode == mode_id:
                    print(f"[mode] {label} CONFIRMED")
                    return True
        print(f"[mode] FAILED to enter {label} after {tries} tries")
        return False

    def arm(self):
        self.m.mav.command_long_send(
            self.m.target_system, self.m.target_component,
            mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0,
            1, 0, 0, 0, 0, 0, 0)
        ack = self.m.recv_match(type="COMMAND_ACK", blocking=True, timeout=5)
        ok = ack and ack.result == mavutil.mavlink.MAV_RESULT_ACCEPTED
        print(f"[arm] {'ARMED' if ok else 'REFUSED (check prearm msgs)'}")
        return ok

    # ---------------- mission upload ----------------
    def build_items(self, plan):
        """YAML plan -> list of MISSION_ITEM_INT tuples."""
        FR = mavutil.mavlink.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT
        items = []

        def add(frame, cmd, p1=0, p2=0, p3=0, p4=0, x=0, y=0, z=0.0):
            items.append((frame, cmd, p1, p2, p3, p4,
                          int(x * 1e7), int(y * 1e7), float(z)))

        wps = plan["waypoints"]
        # item 0 = home placeholder (autopilot replaces it)
        add(0, mavutil.mavlink.MAV_CMD_NAV_WAYPOINT)
        # takeoff
        add(FR, mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
            z=plan.get("takeoff_alt", 30))
        # cruise speed (ground speed, m/s)
        if "cruise_speed" in plan:
            add(0, mavutil.mavlink.MAV_CMD_DO_CHANGE_SPEED,
                p1=1, p2=plan["cruise_speed"])
        for wp in wps:
            add(FR, mavutil.mavlink.MAV_CMD_NAV_WAYPOINT,
                p1=wp.get("hold", 0), x=wp["lat"], y=wp["lon"],
                z=wp["alt"])
        if plan.get("rtl_at_end", True):
            add(0, mavutil.mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH)
        return items

    def upload(self, items):
        m = self.m
        m.mav.mission_clear_all_send(m.target_system, m.target_component)
        m.recv_match(type="MISSION_ACK", blocking=True, timeout=3)

        m.mav.mission_count_send(m.target_system, m.target_component,
                                 len(items))
        deadline = time.time() + 30
        while time.time() < deadline:
            req = m.recv_match(type=["MISSION_REQUEST",
                                     "MISSION_REQUEST_INT"],
                               blocking=True, timeout=5)
            if req is None:
                continue
            fr, cmd, p1, p2, p3, p4, x, y, z = items[req.seq]
            m.mav.mission_item_int_send(
                m.target_system, m.target_component, req.seq, fr, cmd,
                0, 1, p1, p2, p3, p4, x, y, z)
            if req.seq == len(items) - 1:
                ack = m.recv_match(type="MISSION_ACK", blocking=True,
                                   timeout=5)
                ok = ack and ack.type == 0
                print(f"[mission] upload {'OK' if ok else 'REJECTED'} "
                      f"({len(items)} items)")
                return ok
        print("[mission] upload timed out")
        return False

    # ---------------- telemetry ----------------
    def read_state(self):
        s = {"mode": None, "armed": None, "pct": None, "voltage": None,
             "current_a": None, "alt_m": None, "lat": None, "lon": None,
             "dist_home_m": None, "wp_seq": None, "t": time.time()}
        t0 = time.time()
        while time.time() - t0 < 1.0:
            msg = self.m.recv_match(blocking=True, timeout=1)
            if msg is None:
                break
            k = msg.get_type()
            if k == "HEARTBEAT":
                s["mode"] = msg.custom_mode
                s["armed"] = bool(msg.base_mode &
                                  mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED)
            elif k == "SYS_STATUS":
                if msg.voltage_battery != 0xFFFF:
                    s["voltage"] = msg.voltage_battery / 1000.0
                if msg.current_battery != -1:
                    s["current_a"] = msg.current_battery / 100.0
                rep = msg.battery_remaining          # -1 = unknown
                vp = (voltage_to_pct(s["voltage"], self.args.cells)
                      if s["voltage"] else None)
                cands = [p for p in (rep if rep >= 0 else None, vp)
                         if p is not None]
                if cands:
                    s["pct"] = min(cands)            # trust the worst case
            elif k == "GLOBAL_POSITION_INT":
                s["lat"] = msg.lat / 1e7
                s["lon"] = msg.lon / 1e7
                s["alt_m"] = msg.relative_alt / 1000.0
                if self.home is None and s["armed"]:
                    self.home = (s["lat"], s["lon"])
                if self.home and s["lat"]:
                    s["dist_home_m"] = haversine_m(*self.home,
                                                   s["lat"], s["lon"])
            elif k == "MISSION_CURRENT":
                s["wp_seq"] = msg.seq
            elif k == "STATUSTEXT":
                print(f"[fc] {msg.text}")
        return s

    def wait_gps_and_battery(self):
        print("[preflight] waiting for 3D GPS fix + battery check ...")
        while True:
            gps = self.m.recv_match(type="GPS_RAW_INT", blocking=True,
                                    timeout=5)
            syss = self.m.recv_match(type="SYS_STATUS", blocking=True,
                                     timeout=5)
            fix = gps.fix_type if gps else 0
            v = syss.voltage_battery / 1000.0 if syss else 0
            pct = voltage_to_pct(v, self.args.cells) if v else 0
            print(f"[preflight] fix={fix} sats={gps.satellites_visible if gps else '?'} "
                  f"batt={v:.1f}V ({pct:.0f}%)")
            if fix >= 3 and pct >= self.args.min_start_pct:
                return True
            if fix >= 3 and pct < self.args.min_start_pct:
                print(f"[preflight] ABORT: battery {pct:.0f}% < "
                      f"--min-start-pct {self.args.min_start_pct}% "
                      f"(a 1 h mission needs a full pack)")
                return False
            time.sleep(2)

    # ---------------- the guardian loop ----------------
    def monitor(self):
        a = self.args
        print(f"[guardian] RTL at <= {a.rtl_pct}%  |  LAND at <= {a.land_pct}%")
        while True:
            s = self.read_state()
            if s["mode"] is None:
                continue
            mode_name = MODE_NAMES.get(s["mode"], str(s["mode"]))
            if s["pct"] is not None:
                print(f"[{time.strftime('%H:%M:%S')}] {mode_name:9s} "
                      f"batt {s['pct']:5.1f}% {s['voltage'] or 0:5.1f}V "
                      f"{s['current_a'] or 0:5.1f}A  alt {s['alt_m'] or 0:5.1f}m "
                      f"home {s['dist_home_m'] or 0:6.0f}m  wp {s['wp_seq']}")

            if s["armed"]:
                self.was_armed = True
            if self.was_armed and s["armed"] is False:
                print("[guardian] disarmed — flight over.")
                return

            if not s["armed"] or s["pct"] is None:
                continue

            # debounce: need 3 consecutive low samples (~3 s)
            self.low_hits = self.low_hits + 1 if s["pct"] <= a.rtl_pct else 0
            self.crit_hits = self.crit_hits + 1 if s["pct"] <= a.land_pct else 0

            override = ai_decision_hook(s)
            if override in MODES and s["mode"] != MODES[override]:
                self.force_mode(MODES[override], f"{override} (ai hook)")

            if self.crit_hits >= 3 and s["mode"] != MODES["LAND"]:
                print(f"[guardian] *** {s['pct']:.0f}% CRITICAL -> LAND ***")
                self.force_mode(MODES["LAND"], "LAND")
            elif self.low_hits >= 3 and s["mode"] not in SAFE_MODES:
                print(f"[guardian] *** {s['pct']:.0f}% <= {a.rtl_pct}% "
                      f"-> RETURN TO LAUNCH ***")
                self.force_mode(MODES["RTL"], "RTL")

    # ---------------- top level ----------------
    def run(self):
        if self.args.mission and not self.args.monitor_only:
            with open(self.args.mission) as f:
                plan = yaml.safe_load(f)
            items = self.build_items(plan)
            print(f"[mission] {len(plan['waypoints'])} waypoints, "
                  f"takeoff {plan.get('takeoff_alt', 30)} m, "
                  f"cruise {plan.get('cruise_speed', 'default')} m/s")
            if not self.upload(items):
                sys.exit(1)
            if self.args.upload_only:
                print("[mission] upload-only requested — done.")
                return
            if not self.wait_gps_and_battery():
                sys.exit(1)
            if not self.force_mode(MODES["AUTO"], "AUTO"):
                sys.exit(1)
            if not self.arm():
                sys.exit(1)
            print("[mission] LAUNCHED — guardian active.")
        else:
            print("[guardian] monitor-only: you fly, I watch the battery.")
        self.monitor()


def main():
    p = argparse.ArgumentParser(description="HELIOS-10 mission guardian")
    p.add_argument("--conn", default="udp:127.0.0.1:14550",
                   help="serial dev (/dev/serial0) or udp:host:port")
    p.add_argument("--baud", type=int, default=921600)
    p.add_argument("--mission", help="YAML mission file")
    p.add_argument("--cells", type=int, default=6, help="Li-Ion series cells")
    p.add_argument("--rtl-pct", type=float, default=10.0)
    p.add_argument("--land-pct", type=float, default=5.0)
    p.add_argument("--min-start-pct", type=float, default=95.0)
    p.add_argument("--monitor-only", action="store_true")
    p.add_argument("--upload-only", action="store_true")
    args = p.parse_args()

    try:
        Guardian(args).run()
    except KeyboardInterrupt:
        print("\n[exit] ctrl-c — the FLIGHT CONTROLLER failsafes (layers "
              "1+2) are still active. Take manual control on the radio.")


if __name__ == "__main__":
    main()
