// ============================================================
//  MANTA-1500 — 3D-printed flying wing (tailless), 1.5 m span
//  ~3.5 h cruise on the same 6S2P pack as HELIOS-10, and the
//  best canvas in the fleet for the onboard solar option.
//
//  STABILITY comes from 25 deg sweep + 4 deg washout (the tip
//  flies nose-down relative to the root) + correct CG. This
//  file computes the balance point and echoes it on F6 — the
//  body also gets two CG dimples molded into its belly.
//
//  !!! BEFORE PRINTING, verify in the preview that the wingtip
//  trailing edge sits HIGHER than the root trailing edge
//  (tip twisted nose-DOWN). If it is reversed, set
//  washout_dir = -washout_dir below. A wing with wash-IN is
//  unflyable. !!!
//
//  Materials: wing/elevons/winglets in LW-PLA (1-2 perimeters,
//  2% gyroid, ~245C, tune flow first). Body + motor mount in
//  PETG, 3 walls 30% infill.
//
//  PARTS: body(1) hatch(1) winglet(x2 mirrored)
//         wing segments: part="wing_seg"; seg=1..4; side=+-1 (8)
//         elevon: side=+-1 (2)
//
//  BUY (echoed on F6): 2x O10 OD carbon tube (spars),
//  O5 carbon rod (aft pins), see cut list in console.
// ============================================================

part = "layout";
seg  = 1;        // 1 (root) .. 4 (tip)
side = 1;        // 1 = right, -1 = left

/* ---------------- planform ---------------- */
root       = 380;     // root chord, mm
tip        = 220;     // tip chord
half       = 700;     // half-span per side (total = 2*700 + 100 body)
sweep_le   = 25;      // leading-edge sweep, deg
washout    = 4;       // tip nose-down twist, deg
washout_dir= -1;      // flip if preview shows tip nose-UP (see header!)
sm         = 0.08;    // static margin (8% MAC) for first flights
body_w     = 100;     // center body width
seg_len    = 175;     // 4 segments per half
hinge_frac = 0.72;    // elevon hinge at 72% chord, z 350..700
elev_start = 350;

spar_d = 10.4;  pin_d = 5.4;  m3 = 3.4;
cam_tilt = 8;

/* ---------------- derived geometry ---------------- */
lam        = tip/root;
// shear slope so the LE sweep is sweep_le while scaling about
// the quarter-chord (origin): x_le(z) = slope*z - 0.25*c(z)
slope      = tan(sweep_le) - 0.25*(root-tip)/half;
mac        = 2/3*root*(1+lam+lam*lam)/(1+lam);
ymac       = (half/3)*(1+2*lam)/(1+lam);
np_le      = ymac*tan(sweep_le) + 0.25*mac;   // neutral pt, from root LE
cg_le      = np_le - sm*mac;                  // balance point, from root LE
cg_x       = cg_le - 0.25*root;               // in model coords (origin = root qc)
tipscale_c = tip/root;                        // chord taper
tipscale_t = (0.09*tip)/(0.12*root);          // 12% root -> 9% tip thickness

echo(str(">>> BALANCE POINT (CG): ", cg_le, " mm behind the root leading edge"));
echo(str(">>> neutral point ", np_le, " mm; MAC ", mac, " mm — never balance behind ", np_le-0.04*mac, " mm"));
echo(str(">>> CUT LIST: 2x O10 carbon tube x", 530+body_w/2+10, " mm (spars), 2x O5 rod x", 400, " mm (aft pins)"));
echo(">>> CHECK PREVIEW: wingtip trailing edge must be HIGHER than root (washout).");

$fs=0.5; $fa=4;

/* ---------------- NACA airfoil ---------------- */
function nc(x,m,p) = x<p ? m/pow(p,2)*(2*p*x-x*x)
                         : m/pow(1-p,2)*((1-2*p)+2*p*x-x*x);
function nt(x,t) = 5*t*(0.2969*sqrt(x)-0.1260*x-0.3516*pow(x,2)
                        +0.2843*pow(x,3)-0.1036*pow(x,4));
function af(c,m,p,t,n=28) =
  let(xs=[for(i=[0:n]) (1-cos(180*i/n))/2])
  concat([for(i=[n:-1:0]) let(x=xs[i]) c*[x, nc(x,m,p)+nt(x,t)]],
         [for(i=[1:n])    let(x=xs[i]) c*[x, nc(x,m,p)-nt(x,t)]]);

/* ---------------- half wing (right, spans +Z) ---------------- */
// Root NACA 2412 scaled to ~NACA 2409 at the tip; twist about
// the quarter-chord; shear matrix adds sweep. Origin = root qc.
module wing_form() {
    multmatrix([[1,0,slope,0],[0,1,0,0],[0,0,1,0]])
        linear_extrude(height=half, scale=[tipscale_c, tipscale_t],
                       twist=washout_dir*washout, slices=70)
            translate([-0.25*root, 0]) polygon(af(root, 0.02, 0.4, 0.12));
}

// straight hole along (x0 + xslope*z, y0, z) — for spars/pins
module angled_hole(x0, y0, xslope, d, z0, z1) {
    hull() {
        translate([x0+xslope*z0, y0, z0]) sphere(d=d);
        translate([x0+xslope*z1, y0, z1]) sphere(d=d);
    }
}

// elevon hinge x-position at span z
function hinge_x(z) = slope*z + (hinge_frac-0.25)*(root-(root-tip)*z/half);
hinge_ang = atan((hinge_x(half)-hinge_x(elev_start))/(half-elev_start));

module elevon_cutter(gap) {
    translate([hinge_x(elev_start)+gap, 0, elev_start+gap])
        rotate([0, -hinge_ang, 0])     // align cut with hinge line
            translate([0, -60, -20]) cube([root, 120, half]);
}

module wing_half() {
    difference() {
        wing_form();
        angled_hole(0, 5, slope, spar_d, -20, 530);          // O10 spar
        angled_hole((0.65-0.25)*root, 4, 0.377, pin_d, -20, 400); // O5 pin
        elevon_cutter(0);                                     // elevon + 1.2 gap
        // elevon servo pocket (bottom skin, segment 3, ~45% chord)
        translate([slope*420 + 0.20*(root-(root-tip)*420/half) - 12, -26, 405])
            cube([24, 24, 30]);
        // winglet tab slots in the tip face
        for (f=[0.32, 0.62])
            translate([slope*half + (f-0.25)*tip - 7, -2.5, half-10])
                cube([14, 5, 11]);
    }
}

module elevon() {
    intersection() {
        difference() {
            wing_form();
            // horn slot
            translate([hinge_x(430)+8, -10, 425]) cube([16, 10, 3]);
        }
        elevon_cutter(1.2);
    }
}

module wing_seg(n) {
    intersection() {
        wing_half();
        translate([-root, -60, (n-1)*seg_len]) cube([3*root, 120, seg_len]);
    }
}

/* ---------------- center body ---------------- */
// Straight prism of the root section, z = -body_w/2..+body_w/2.
// Bays: battery over the CG, O4 + FC behind it, pusher motor
// mount cantilevered off the trailing edge.
module body() {
    difference() {
        union() {
            translate([0,0,-body_w/2]) linear_extrude(height=body_w)
                translate([-0.25*root, 0]) polygon(af(root, 0.02, 0.4, 0.12));
            // motor mount: 2 arms + plate, prop plane 50mm aft of TE
            for (z=[-16, 12]) translate([0.75*root-30, -3, z])
                cube([root*0.25+80-(0.75*root-30)+50, 14, 4]);
            translate([0.75*root+46, -3+7, 0]) rotate([0,90,0]) hull() {
                translate([0,-16,0]) cylinder(d=8, h=4);
                translate([0, 16,0]) cylinder(d=8, h=4);
                translate([16,0,0]) cylinder(d=8, h=4);
                translate([-16,0,0]) cylinder(d=8, h=4);
            }
        }
        // main cavity (leave 2.6 walls + thick LE)
        translate([-0.25*root+24, -13, -body_w/2+2.6])
            cube([0.70*root-24, 30, body_w-5.2]);
        // hatch opening on top
        translate([-0.25*root+30, 5, -28]) cube([170, 40, 56]);
        // spar channels into both wing roots (meet at center)
        for (s=[0,1]) mirror([0,0,s])
            angled_hole(0, 5, slope, spar_d, 0, body_w/2+1);
        for (s=[0,1]) mirror([0,0,s])
            angled_hole((0.65-0.25)*root, 4, 0.377, pin_d, 0, body_w/2+1);
        // motor bolt slots 16x16..19x19 + shaft hole
        translate([0.75*root+45, 4, 0]) rotate([0,90,0]) {
            translate([0,0,-1]) cylinder(d=10, h=8);
            for (a=[45,135,225,315]) rotate([0,0,a]) hull() {
                translate([8,0,-1])    cylinder(d=m3, h=8);
                translate([13.5,0,-1]) cylinder(d=m3, h=8);
            }
        }
        // hatch screws
        for (x=[-0.25*root+38, -0.25*root+188]) translate([x, 18, 0])
            rotate([-90,0,0]) cylinder(d=m3, h=30);
        // CG dimples on the belly — balance HERE
        for (z=[-30, 30]) translate([cg_x, -0.06*root, z]) sphere(d=5);
        // cooling inlets (O4 bay) + rear outlet
        for (z=[-1,1]) translate([0.45*root, 0, z*body_w/2])
            rotate([z*90,0,0]) cylinder(d=12, h=8, center=true);
    }
}

// lid: flat plate + raised battery box (pack sits proud of the
// section) + O4 camera shelf peeking over the leading edge
module hatch() {
    difference() {
        union() {
            translate([0,0,0])  cube([168, 54, 2.4]);
            translate([2,2,-3]) cube([164, 50, 3.2]);          // lip
            translate([8,4,2.4]) cube([150, 46, 12]);          // battery riser
            translate([0,15,2.4]) rotate([0, 0, 0])
                translate([-26,0,0]) rotate([0,-cam_tilt,0])
                    cube([28, 24, 16]);                        // cam shelf
        }
        translate([10,6,0]) cube([146, 42, 16]);               // riser hollow
        translate([-24, 16.1, 4]) rotate([0,-cam_tilt,0])
            cube([30, 21.8, 20]);   // cam pocket — set to your O4 cam width
        for (x=[8, 158]) translate([x, 27, -4]) cylinder(d=m3, h=10);
    }
}

/* ---------------- winglet ---------------- */
module winglet() {
    difference() {
        union() {
            linear_extrude(height=2.5)
                polygon([[0,0],[tip*0.85,0],[tip*0.75,110],[tip*0.35,120],[tip*0.12,30]]);
            for (f=[0.32,0.62]) translate([f*tip*0.85-6, -8, 0])
                cube([12, 9, 2.5]);                            // tabs
        }
    }
}

/* ---------------- layout / selector ---------------- */
module layout() {
    color("orange") body();
    color("gray")   translate([0,0, body_w/2]) wing_half();
    color("gray")   mirror([0,0,1]) translate([0,0, body_w/2]) wing_half();
    color("orange") translate([slope*half, 30, body_w/2+half]) rotate([90,0,0]) winglet();
}

if (part=="layout") layout();
else if (part=="wing_seg") mirror([0,0,side<0?1:0]) wing_seg(seg);
else if (part=="elevon")   mirror([0,0,side<0?1:0]) elevon();
else if (part=="body")     body();
else if (part=="hatch")    hatch();
else if (part=="winglet")  winglet();
