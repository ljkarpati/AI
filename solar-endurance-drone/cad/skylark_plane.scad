// ============================================================
//  SKYLARK-1600 — 3D-printed endurance plane (pod & boom)
//  1.6 m wing, ~3 h cruise on the same 6S2P pack as HELIOS-10.
//
//  Open in OpenSCAD, set `part`, F6, export STL.
//  Wing/tail print in LW-PLA (foaming, ~half weight — REQUIRED
//  to hit the weight budget). Pod, saddles, mounts in PETG.
//
//  Slicer for LW-PLA wing/tail parts:
//    1-2 perimeters, 2% gyroid infill, 0 top/bottom layers on
//    wing segments (the skin IS the part), 0.25 layers, ~245 C
//    (tune flow ~55-65% for your LW-PLA brand first!)
//  Pod/mount parts: PETG, 3 walls, 30% infill.
//
//  PARTS (qty):
//    pod(1) hatch(1) boom_servo_saddle(1) tail_mount(1)
//    wing segments: part="wing_seg"; seg=1..4; side=1 (right)
//                   and side=-1 (left)            (8 total)
//    aileron: seg 3..4 equivalent, side=±1        (2 total)
//    stab_half(×2 mirrored) elevator_half(×2) fin(1) rudder(1)
//
//  BUY (cut lengths echoed on F6):
//    1×  Ø10 OD ×750 mm carbon tube  (wing joiner spar)
//    2×  Ø8  OD ×550 mm carbon tube  (outer wing spars)
//    1×  Ø16 OD/14 ID ×600 mm carbon tube (tail boom — same
//        stock as the HELIOS-10 arms)
//    Ø5 ×1 m carbon rod (anti-rotation pins, tail joins)
// ============================================================

part = "layout";
seg  = 1;       // wing segment 1 (root) .. 4 (tip)
side = 1;       // 1 = right wing, -1 = left wing

/* ---------------- design parameters ---------------- */
chord      = 220;     // wing chord, mm
half_span  = 760;     // per side; total span = 2*760 + 80 pod
seg_len    = 190;     // 4 segments per side
ail_start  = 380;     // aileron spans z 380..760 (outer half)
hinge_frac = 0.75;    // aileron hinge at 75% chord
skin       = 1.0;     // n/a (slicer handles walls) — kept for ref

pod_l      = 270;  pod_w = 74;  pod_h = 88;
boom_d     = 16.3;    // 16 mm boom + fit
spar1_d    = 10.4;    // inner spar hole (Ø10 tube)
spar2_d    = 8.4;     // outer spar hole (Ø8 tube)
pin_d      = 5.4;     // Ø5 anti-rotation rod
m3         = 3.4;  m4 = 4.4;

stab_chord = 115;  stab_half_span = 230;  // NACA0008 tail
fin_chord  = 130;  fin_height = 150;

cam_tilt   = 10;      // O4 camera shelf angle on the hatch

/* ---------------- NACA airfoil generator ---------------- */
function nc(x,m,p) = x<p ? m/pow(p,2)*(2*p*x-x*x)
                         : m/pow(1-p,2)*((1-2*p)+2*p*x-x*x);
function nt(x,t) = 5*t*(0.2969*sqrt(x)-0.1260*x-0.3516*pow(x,2)
                        +0.2843*pow(x,3)-0.1036*pow(x,4));
function af(c,m,p,t,n=28) =
  let(xs=[for(i=[0:n]) (1-cos(180*i/n))/2])
  concat([for(i=[n:-1:0]) let(x=xs[i]) c*[x, nc(x,m,p)+nt(x,t)]],
         [for(i=[1:n])    let(x=xs[i]) c*[x, nc(x,m,p)-nt(x,t)]]);

echo(">>> CUT LIST: 1x O10x750 joiner | 2x O8x550 outer spar | 1x O16x600 boom | O5 rod pins");
echo(str(">>> Balance point (CG): 60-66 mm behind the wing leading edge."));
echo(">>> LW-PLA for all wing/tail parts. Verify airfoil preview before printing.");

$fs=0.5; $fa=4;

/* ================= WING ================= */
// NACA 2412, constant chord. Spans +Z. Root at z=0.
module wing_solid() {
    linear_extrude(height=half_span)
        polygon(af(chord, 0.02, 0.4, 0.12));
}

// straight holes along the span for spars/pins
module wing_holes() {
    // inner Ø10 joiner: z 0..360 (the other 360 lives in the
    // opposite wing through the pod saddle)
    translate([0.30*chord, 1, -1]) cylinder(d=spar1_d, h=362);
    // outer Ø8 spar: z 300..760 (overlaps the joiner bay)
    translate([0.30*chord, 1, 300]) cylinder(d=spar2_d, h=462);
    // Ø5 anti-rotation pin at 65% chord, full span
    translate([0.65*chord, 0.5, -1]) cylinder(d=pin_d, h=half_span+2);
}

// aileron = trailing 25% of chord over the outer half, 1.2 mm gaps
module aileron_block(grow=0) {
    translate([hinge_frac*chord + (grow>0?-1:1)*1.2, -30,
               ail_start + (grow>0?1.2:-(grow>0?0:0))])
        cube([chord, 60, half_span]);
}

module wing_half() {
    difference() {
        wing_solid();
        wing_holes();
        // aileron cutout (gap included)
        translate([hinge_frac*chord-1.2, -30, ail_start-1.2])
            cube([chord, 60, half_span]);
        // aileron servo pocket, bottom skin, segment 3
        translate([0.42*chord, -25, 410]) cube([24, 26, 30]);
        translate([0.42*chord+6, -25, 416]) cube([12, 27.5, 18]); // lid lip
    }
}

module aileron() {
    intersection() {
        difference() { wing_solid(); // reuse outer surface
            // horn slot
            translate([hinge_frac*chord+8, -12, 425]) cube([14, 12, 2]);
        }
        translate([hinge_frac*chord, -30, ail_start])
            cube([chord, 60, half_span - ail_start]);
    }
}

// one printable segment; print standing up (span = printer Z)
module wing_seg(n) {
    intersection() {
        wing_half();
        translate([-20, -40, (n-1)*seg_len])
            cube([chord+40, 80, seg_len]);
    }
}

/* ================= POD (fuselage) ================= */
// Hull-of-spheres shell. Nose face is the motor firewall
// (16x16..19x19 M3 slots). Boom socket at the rear, wing
// saddle + O10 joiner channel on top.
module pod_form(sh=0) {
    hull() {
        translate([0, 0, pod_h*0.45])  sphere(r=pod_w/2-sh);          // nose
        translate([pod_l*0.45, 0, pod_h*0.55]) sphere(r=pod_w/2-sh);
        translate([pod_l*0.80, 0, pod_h*0.55]) sphere(r=pod_w/2.6-sh);
        translate([pod_l, 0, pod_h*0.55])      sphere(r=11-(sh>0?2:0));
    }
}
module pod() {
    difference() {
        union() {
            difference() {
                pod_form(0);
                pod_form(2.6);                       // 2.6 mm wall
                // flatten the nose -> firewall face
                translate([-pod_w, -pod_w, -pod_w]) cube([pod_w-15, 2*pod_w, 3*pod_w]);
            }
            // firewall disc (solid PETG ring behind the cut)
            translate([-15, 0, pod_h*0.45]) rotate([0,90,0])
                cylinder(d=54, h=6);
            // wing saddle block on top, rear half
            translate([pod_l*0.42, -pod_w/2*0.8, pod_h*0.78])
                cube([90, pod_w*0.8, 26]);
            // boom socket boss
            translate([pod_l-58, 0, pod_h*0.55]) rotate([0,90,0])
                cylinder(d=boom_d+6, h=60);
        }
        // motor shaft + M3 slots in firewall (fits 16x16..19x19)
        translate([-17, 0, pod_h*0.45]) rotate([0,90,0]) {
            cylinder(d=10, h=12);
            for (a=[45,135,225,315]) rotate([a,0,0]) hull() {
                translate([0, 8, -1])   cylinder(d=m3, h=14);
                translate([0, 13.5,-1]) cylinder(d=m3, h=14);
            }
        }
        // hatch opening (front-top, battery/electronics access)
        translate([8, -24, pod_h*0.62]) cube([150, 48, 60]);
        // wing saddle: airfoil bed + O10 joiner channel + M4 bolts
        translate([pod_l*0.42+45-0.30*chord, 0, pod_h*0.78+26-6])
            rotate([90,0,0]) translate([0,0,-50])
            linear_extrude(100) scale([1,1.6]) polygon(af(chord,0.02,0.4,0.12));
        translate([pod_l*0.42+45, -60, pod_h*0.78+14]) rotate([-90,0,0])
            cylinder(d=spar1_d, h=120);
        for (dx=[-28, 28])
            translate([pod_l*0.42+45+dx, 0, pod_h*0.5]) cylinder(d=m4, h=60);
        // boom bore + pinch bolt
        translate([pod_l-60, 0, pod_h*0.55]) rotate([0,90,0])
            cylinder(d=boom_d, h=70);
        translate([pod_l-30, 0, pod_h*0.55+boom_d/2+2]) cylinder(d=m3, h=12, center=true);
        // cooling: nose-side inlets, rear outlet (O4 runs hot)
        for (y=[-1,1]) translate([30, y*pod_w/2, pod_h*0.5])
            rotate([90,0,0]) cylinder(d=14, h=8, center=true);
    }
}

// flat lid with lip, O4 camera shelf at the front (tilted)
module hatch() {
    difference() {
        union() {
            translate([0,-23,0]) cube([148, 46, 2.4]);
            translate([2,-21,-3]) cube([144, 42, 3.2]);     // lip
            translate([6, -12, 2.4]) rotate([0, -cam_tilt, 0])
                cube([26, 24, 16]);                          // cam shelf
        }
        translate([10, 0, 2]) rotate([0, -cam_tilt, 0])
            translate([4, -10.9, 4]) cube([30, 21.8, 20]);   // cam pocket (set width = your O4 cam)
        translate([140, 0, -4]) cylinder(d=m3, h=10);        // rear screw
    }
}

/* ================= TAIL ================= */
module stab_half() {            // NACA 0008, print 2, join with O5 pins
    difference() {
        linear_extrude(height=stab_half_span)
            polygon(af(stab_chord, 0, 0.3, 0.08));
        // elevator cut (trailing 30%)
        translate([0.70*stab_chord-1.2, -20, -1]) cube([stab_chord,40,stab_half_span+2]);
        for (x=[0.25, 0.55]) translate([x*stab_chord, 0, -1])
            cylinder(d=pin_d, h=80);                          // root join pins
    }
}
module elevator_half() {
    intersection() {
        linear_extrude(height=stab_half_span)
            polygon(af(stab_chord, 0, 0.3, 0.08));
        translate([0.70*stab_chord, -20, 0]) cube([stab_chord,40,stab_half_span]);
    }
}
module fin() {
    difference() {
        linear_extrude(height=fin_height, scale=0.6)
            polygon(af(fin_chord, 0, 0.3, 0.09));
        translate([0.70*fin_chord-1.2, -20, 25]) cube([fin_chord,40,fin_height]);
        translate([0.25*fin_chord, 0, -1]) cylinder(d=pin_d, h=40);
    }
}
module rudder() {
    intersection() {
        linear_extrude(height=fin_height, scale=0.6)
            polygon(af(fin_chord, 0, 0.3, 0.09));
        translate([0.70*fin_chord, -20, 25]) cube([fin_chord,40,fin_height]);
    }
}
// clamps on the boom end; stab slides through, fin pins on top
module tail_mount() {
    difference() {
        union() {
            rotate([0,90,0]) cylinder(d=boom_d+7, h=60);
            translate([0,-stab_chord/2+10,-3]) cube([60, stab_chord, 14]); // stab bed
        }
        rotate([0,90,0]) translate([0,0,-1]) cylinder(d=boom_d, h=62);
        translate([30, 0, boom_d/2+5]) cylinder(d=m3, h=12);   // pinch
        for (x=[0.25,0.55]) translate([14+x*0, -stab_chord/2+10+x*stab_chord, 0])
            translate([30,0,-4]) cylinder(d=pin_d, h=30);       // stab+fin pins
    }
}
// dual 9g servo saddle, clamps mid-boom (elevator + rudder)
module boom_servo_saddle() {
    difference() {
        union() {
            rotate([0,90,0]) cylinder(d=boom_d+7, h=58);
            translate([0,-16,boom_d/2]) cube([58, 32, 16]);
        }
        rotate([0,90,0]) translate([0,0,-1]) cylinder(d=boom_d, h=60);
        for (x=[5, 31]) translate([x, -12, boom_d/2+3]) cube([23.5, 12.5, 16]);
        translate([29, 0, -boom_d/2-4]) cylinder(d=m3, h=10);  // pinch
    }
}

/* ================= layout / selector ================= */
module layout() {
    color("orange") translate([-60, 0, -70]) pod();
    color("gray") for (s=[-1,1]) mirror([0,0,s<0?1:0])
        translate([0,0,40]) wing_half();
    color("orange") translate([320, 0, -25]) rotate([0,0,180]) tail_mount();
}

if (part=="layout") layout();
else if (part=="wing_seg")      mirror([0,0,side<0?1:0]) wing_seg(seg);
else if (part=="aileron")       mirror([0,0,side<0?1:0]) aileron();
else if (part=="pod")           pod();
else if (part=="hatch")         hatch();
else if (part=="stab_half")     stab_half();
else if (part=="elevator_half") elevator_half();
else if (part=="fin")           fin();
else if (part=="rudder")        rudder();
else if (part=="tail_mount")    tail_mount();
else if (part=="boom_servo_saddle") boom_servo_saddle();
