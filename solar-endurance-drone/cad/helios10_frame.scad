// ============================================================
//  HELIOS-10  —  10" long-endurance quad frame (3D printed)
//  Parametric OpenSCAD source. Open in OpenSCAD (free,
//  openscad.org), set `part` below, press F6, export STL.
//
//  Design: printed center hub + printed motor pods joined by
//  4x 16mm OD / 14mm ID carbon fiber tubes (buy, don't print —
//  printed arms flex and resonate; tubes are light and stiff).
//
//  PRINT SETTINGS (per part guidance at bottom of header):
//   material : PETG-CF / PA-CF strongly preferred.
//              Plain PETG OK. PLA only for fit-test prints.
//   walls    : 4+ perimeters
//   infill   : 40% gyroid (60% for motor pods)
//   layer    : 0.2 mm
//   TPU      : cam_bumper + leg feet (optional)
//
//  PARTS TO PRINT (set `part`, F6, export):
//   "bottom_plate" x1   "top_plate"  x1   "motor_pod" x4
//   "tube_leg"     x4   "cam_mount"  x1   "o4_cradle" x1
//   "gps_mast"     x1   "solar_deck" x1 (optional)
//   "layout"            = visual check of everything
//
//  After F6, the console echoes the CARBON TUBE CUT LENGTH.
// ============================================================

part = "layout";   // <-- change me, then F6 + export STL

/* ------------------- main parameters ------------------- */
wheelbase    = 380;     // motor-to-motor diagonal, mm (10" props)
tube_od      = 16.0;    // carbon tube outer diameter
tube_fit     = 0.25;    // socket clearance for glue/clamp fit
plate_t      = 4.0;     // bottom plate thickness
top_t        = 3.0;     // top plate thickness
hub_r        = 58;      // center hub radius
socket_len   = 40;      // tube engagement in hub
socket_wall  = 3.2;     // wall around tube
standoff_sq  = 90;      // M3 standoffs: on cardinal axes, +/-45mm
m3           = 3.4;     // M3 clearance hole
m2           = 2.4;     // M2 clearance hole

// motor pod
pod_engage   = 35;      // tube engagement in pod
pod_top_d    = 32;      // motor platform diameter
slot_r_min   = 9;       // motor bolt slots cover 16x16..19x19
slot_r_max   = 14;      //   4-hole patterns (M3)

// camera (DJI O4 Air Unit Pro camera — MEASURE YOURS and set)
cam_w        = 21.8;    // camera body width incl. clearance
cam_tilt     = 20;      // uptilt degrees (15-25 for cruising)

// O4 air unit cradle
o4_w         = 33.5;    // unit width  (verify against your unit)
o4_l         = 39;      // unit length (verify)

// landing legs
leg_h        = 80;      // ground clearance for belly stack + antennas

// solar deck (optional perch-charge / avionics-offset panel)
solar_l      = 160;     // fits a small ~5-10W semi-flex panel
solar_w      = 120;
deck_standoff= 40;      // M3 standoff height above top plate

/* ------------------- derived ------------------- */
arm_r0   = 34;                          // tube starts here (hub side)
arm_r1   = wheelbase/2 - 6;             // tube ends 6mm before motor axis
tube_len = arm_r1 - arm_r0;             // cut length
tube_id  = tube_od + tube_fit;

echo(str(">>> CUT 4 CARBON TUBES TO: ", tube_len, " mm  (16mm OD x 14mm ID)"));
echo(str(">>> Frame wheelbase: ", wheelbase, " mm — for 10 inch props"));

$fs = 0.4; $fa = 3;

/* ================= helper modules ================= */

module rring(r, h) { cylinder(r=r, h=h); }

// 4 holes on cardinal axes (standoff pattern)
module standoff_holes(d=m3) {
    for (a=[0,90,180,270]) rotate([0,0,a])
        translate([standoff_sq/2,0,-1]) cylinder(d=d, h=20);
}

// FC stack patterns: 30.5 / 25.5 (M3) and 20 (M2.5)
module stack_holes() {
    for (p=[[30.5,m3],[25.5,m3],[20,2.9]])
        for (x=[-1,1], y=[-1,1])
            translate([x*p[0]/2, y*p[0]/2, -1]) cylinder(d=p[1], h=20);
}

// horizontal tube socket along +X starting at x=x0
module tube_socket(x0, len, pinch=true) {
    difference() {
        translate([x0,0,0]) rotate([0,90,0])
            cylinder(d=tube_id + 2*socket_wall, h=len);
        translate([x0-1,0,0]) rotate([0,90,0])
            cylinder(d=tube_id, h=len+2);
        if (pinch) {
            // pinch slit + 2 cross bolts to clamp the tube
            translate([x0+len/2, 0, tube_id/2+socket_wall/2])
                cube([len*0.7, 1.6, socket_wall+2], center=true);
            for (dx=[-len*0.22, len*0.22])
                translate([x0+len/2+dx, 0, 0]) rotate([90,0,0])
                    cylinder(d=m3, h=40, center=true);
        }
    }
}

/* ================= bottom plate (hub) ================= */
// Carries the FC stack underneath-center, sockets on diagonals.
module bottom_plate() {
    difference() {
        union() {
            // hub disc
            cylinder(r=hub_r, h=plate_t);
            // socket bases on the 4 diagonals
            for (a=[45,135,225,315]) rotate([0,0,a]) {
                translate([arm_r0,-((tube_id+2*socket_wall)/2),0])
                    cube([socket_len, tube_id+2*socket_wall, plate_t]);
                translate([0,0,plate_t]) translate([0,0,tube_id/2])
                    tube_socket(arm_r0, socket_len);
            }
        }
        stack_holes();
        standoff_holes();
        // lightening holes
        for (a=[0,90,180,270]) rotate([0,0,a+45])
            translate([hub_r*0.62,0,-1]) cylinder(d=16, h=plate_t+2);
        // battery strap slots (straps wrap whole hub)
        for (x=[-1,1]) translate([x*24,0,plate_t/2])
            cube([4,52,plate_t+2], center=true);
    }
}

/* ================= top plate ================= */
module top_plate() {
    difference() {
        cylinder(r=hub_r-3, h=top_t);
        standoff_holes();
        // GPS mast mount (rear pair)
        for (x=[-10,10]) translate([x,-46,-1]) cylinder(d=m3, h=10);
        // O4 cradle mount (rear-center pair)
        for (x=[-10,10]) translate([x,-28,-1]) cylinder(d=m3, h=10);
        // cam mount (front pair)
        for (x=[-14,14]) translate([x,46,-1]) cylinder(d=m3, h=10);
        // battery strap slots
        for (x=[-1,1]) translate([x*24,0,top_t/2])
            cube([4,52,top_t+2], center=true);
        // lightening
        for (a=[45,135,225,315]) rotate([0,0,a])
            translate([hub_r*0.55,0,-1]) cylinder(d=20, h=top_t+2);
    }
}

/* ================= motor pod ================= */
// Slides over tube end; slotted holes fit 16x16..19x19 M3 motor
// bolt patterns (covers 2806.5 / 2812 / 2814 / 3110 motors).
module motor_pod() {
    body_d = tube_id + 2*socket_wall;
    difference() {
        union() {
            rotate([0,90,0]) cylinder(d=body_d, h=pod_engage+6);
            // motor platform on top of the tube axis
            translate([pod_engage/2+3, 0, body_d/2-1])
                cylinder(d=pod_top_d, h=5);
        }
        // tube bore (blind: stops 5mm before end)
        rotate([0,90,0]) translate([0,0,-1]) cylinder(d=tube_id, h=pod_engage+1);
        // pinch slit + cross bolts (also mount the landing legs)
        translate([pod_engage/2, 0, -body_d/2])
            cube([pod_engage*0.7, 1.6, body_d], center=true);
        for (dx=[-8, 8])
            translate([pod_engage/2+dx, 0, -2]) rotate([90,0,0])
                cylinder(d=m3, h=60, center=true);
        // motor bolt slots: 4 radial slots, M3, r 9..14
        translate([pod_engage/2+3, 0, body_d/2-2])
            for (a=[45,135,225,315]) rotate([0,0,a]) hull() {
                translate([slot_r_min,0,0]) cylinder(d=m3, h=10);
                translate([slot_r_max,0,0]) cylinder(d=m3, h=10);
            }
        // motor shaft / wire clearance
        translate([pod_engage/2+3, 0, body_d/2-2]) cylinder(d=9, h=10);
    }
}

/* ================= landing leg ================= */
// Bolts to the motor pod cross-bolts. Print 4 (PETG; tip in TPU).
module tube_leg() {
    difference() {
        union() {
            hull() {                              // upper attach blade
                translate([-8,0,0])  cylinder(d=12, h=6);
                translate([ 8,0,0])  cylinder(d=12, h=6);
            }
            hull() {                              // tapering leg
                translate([0,0,0])      cylinder(d=14, h=4);
                translate([0,18,-leg_h]) cylinder(d=10, h=8);
            }
        }
        for (x=[-8,8]) translate([x,0,-1]) cylinder(d=m3, h=10);
        // TPU foot snap hole
        translate([0,18,-leg_h-1]) cylinder(d=5, h=6);
    }
}

/* ================= camera mount ================= */
// U-bracket, tilted. Side-screw the O4 cam with M2s through
// the cheek slots (slots forgive hole-position differences).
module cam_mount() {
    base_l = cam_w + 12;
    difference() {
        union() {
            translate([-base_l/2,-14,0]) cube([base_l, 24, 4]); // base
            rotate([cam_tilt,0,0]) translate([0,0,0]) {
                for (s=[-1,1]) translate([s*(cam_w/2+3)-3*(s>0?1:0) - (s<0?0:0),0,0])
                    translate([s*(cam_w/2)+ (s<0?-6:0),-10,0])
                        cube([6, 22, 26]);                       // cheeks
            }
        }
        // mount holes to top plate front pair (28mm spacing)
        for (x=[-14,14]) translate([x,6,-1]) cylinder(d=m3, h=8);
        // cam side slots (M2), through both cheeks
        rotate([cam_tilt,0,0]) for (z=[10,18]) hull() {
            translate([-cam_w/2-8, -4, z]) rotate([0,90,0]) cylinder(d=m2, h=cam_w+16);
            translate([-cam_w/2-8,  4, z]) rotate([0,90,0]) cylinder(d=m2, h=cam_w+16);
        }
    }
}

/* ================= O4 air unit cradle ================= */
// Open tray + zip-tie slots; the O4 Pro runs hot — leave the
// finned side exposed to airflow, never enclose it.
module o4_cradle() {
    wall=2.4; floor_t=2.4; h=10;
    difference() {
        translate([-(o4_w/2+wall), -(o4_l/2+wall), 0])
            cube([o4_w+2*wall, o4_l+2*wall, h+floor_t]);
        translate([-o4_w/2, -o4_l/2, floor_t])
            cube([o4_w, o4_l, 20]);
        // zip-tie slots
        for (y=[-o4_l/4, o4_l/4]) for (x=[-1,1])
            translate([x*(o4_w/2+wall/2), y, floor_t+h/2])
                cube([wall+2, 3.5, 2], center=true);
        // vent slots in floor
        for (y=[-o4_l/3,0,o4_l/3])
            translate([0,y,floor_t/2]) cube([o4_w-8, 6, floor_t+2], center=true);
        // mount holes -> top plate rear pair (20mm spacing)
        for (x=[-10,10]) translate([x, 0, -1]) cylinder(d=m3, h=floor_t+2);
    }
}

/* ================= GPS mast ================= */
// Lifts the M10Q-5883 away from power wiring (compass noise).
module gps_mast() {
    difference() {
        union() {
            hull() for (x=[-10,10]) translate([x,0,0]) cylinder(d=14, h=5);
            translate([0,0,0]) cylinder(d=12, h=60);
            translate([0,0,60]) hull() {
                cylinder(d=12, h=2);
                translate([0,0,6]) cube([26,26,2], center=true); // platform
            }
        }
        for (x=[-10,10]) translate([x,0,-1]) cylinder(d=m3, h=8);
        translate([0,0,20]) rotate([90,0,0]) cylinder(d=6, h=20, center=true); // wire pass
    }
}

/* ================= solar deck (optional) ================= */
// Tray for a small semi-flex panel (~5-10 W). This does NOT
// fly the drone (see README math) — it offsets avionics draw
// and trickle-charges while perched. Mounts on 40mm M3
// standoffs over the top-plate standoff holes.
module solar_deck() {
    difference() {
        union() {
            translate([-solar_l/2,-solar_w/2,0]) cube([solar_l, solar_w, 2.2]);
            translate([-solar_l/2,-solar_w/2,0]) difference() { // rim
                cube([solar_l, solar_w, 5]);
                translate([1.6,1.6,-1]) cube([solar_l-3.2, solar_w-3.2, 8]);
            }
        }
        standoff_holes();
        // weight-saving hex field
        for (x=[-solar_l/2+22 : 22 : solar_l/2-20])
            for (y=[-solar_w/2+20 : 20 : solar_w/2-18])
                if (abs(x)>14 || abs(y)>14)   // keep webs near mounts
                    translate([x,y,-1]) cylinder(d=15, h=8, $fn=6);
        // zip-tie holes for panel leads
        for (x=[-1,1]) translate([x*(solar_l/2-8), 0, 1])
            cube([3,8,8], center=true);
    }
}

/* ================= layout / selector ================= */
module layout() {
    color("dimgray")  bottom_plate();
    color("dimgray")  translate([0,0,38]) top_plate();
    color("crimson")  for (a=[45,135,225,315]) rotate([0,0,a])
        translate([arm_r1-pod_engage, 0, plate_t+tube_id/2]) motor_pod();
    // tubes (visual only)
    color("black") for (a=[45,135,225,315]) rotate([0,0,a])
        translate([arm_r0,0,plate_t+tube_id/2]) rotate([0,90,0])
            cylinder(d=tube_od, h=tube_len);
    color("crimson") translate([0,46,41]) cam_mount();
    color("crimson") translate([0,-28,41]) o4_cradle();
    color("crimson") translate([0,-46,41]) gps_mast();
    color("orange")  translate([0,0,38+deck_standoff]) solar_deck();
}

if (part=="layout")            layout();
else if (part=="bottom_plate") bottom_plate();
else if (part=="top_plate")    top_plate();
else if (part=="motor_pod")    rotate([0,-90,0]) motor_pod(); // print on end face
else if (part=="tube_leg")     tube_leg();
else if (part=="cam_mount")    cam_mount();
else if (part=="o4_cradle")    o4_cradle();
else if (part=="gps_mast")     rotate([90,0,0]) gps_mast();   // print lying down
else if (part=="solar_deck")   solar_deck();
