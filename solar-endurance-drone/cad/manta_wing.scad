// ============================================================
//  MANTA-1500 — 3D-printed flying wing (tailless), 1.5 m span
//  ~3.2 h cruise on the same 6S2P pack as HELIOS-10, and the
//  best canvas in the fleet for the onboard solar option.
//  The prop is fully recessed in a trailing-edge slot — one
//  continuous wing, nothing hanging outside the planform.
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
//  PARTS: body(1) fairing(x2 mirrored) hatch(1) winglet(x2)
//         wing segments: part="wing_seg"; seg=1..4; side=+-1 (8)
//         elevon halves: part="elevon"; seg=1..2; side=+-1 (4)
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
body_w     = 100;     // center body piece width (blend continues to 120)
wing_z0    = 70;      // wing segments start here (fairings cover 0..70)
seg_len    = (700-70)/4;   // 4 segments per half = 157.5 mm
hinge_frac = 0.72;    // elevon hinge at 72% chord
elev_start = 385;     // elevon spans segments 3-4 (z 385..700)

spar_d = 10.4;  pin_d = 5.4;  m3 = 3.4;

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

// elevon prints in two halves per side (tape-hinge both, share one horn)
module elevon(n) {
    intersection() {
        difference() {
            wing_form();
            // horn slot
            translate([hinge_x(430)+8, -10, 425]) cube([16, 10, 3]);
        }
        elevon_cutter(1.2);
        translate([-root, -60, elev_start + (n-1)*(700-elev_start)/2])
            cube([3*root, 120, (700-elev_start)/2]);
    }
}

module wing_seg(n) {
    intersection() {
        wing_half();
        translate([-root, -60, wing_z0 + (n-1)*seg_len])
            cube([3*root, 120, seg_len]);
    }
}

/* ------- center body (blended, recessed slot pusher) ------- */
// ONE CONTINUOUS WING: the root section point-morphs into a fat
// 470 mm centerline section across z = +-120, extending the
// trailing edge into a solid deck — and the propeller spins
// INSIDE a spanwise slot cut through that deck. Nothing hangs
// outside the planform; the slot also shields the blades on
// belly landings. Use a FIXED 8x6 prop (Ø204 mm) — a folding
// prop can snag in the slot. The slot costs ~5% propulsive
// efficiency vs an open pusher: endurance ~3.2 h.
//
// Printing: the blend region is wider than the body part, so it
// splits into body (|z|<=50) + 2 mirrored "fairing" pieces
// (50..120) + 4 wing segments per side starting at z=120.
ctr_sc   = 470/root;                  // centerline chord scale (TE deck)
ctr_st   = (0.16*420)/(0.12*root);    // centerline thickness scale
blend_hw = 120;                       // blend half-width
slot_x0  = 294;  slot_x1 = 318;       // fore-aft slot opening
slot_hz  = 108;                       // slot half-span (prop tip 102 + gap)
prop_x   = 306;                       // prop plane (echoed for reference)
mot_y    = 8;                         // motor/prop axis height

base_pts = af(root, 0.02, 0.4, 0.12);
// wing section points at local span zw (same math as wing_form)
function wsec_pts(zw) =
    let(u=zw/half, sx=1-(1-tipscale_c)*u, sy=1-(1-tipscale_t)*u, a=washout*u)
    [for (p=base_pts) [sx*p[0]*cos(a) - sy*p[1]*sin(a) + slope*zw,
                       sx*p[0]*sin(a) + sy*p[1]*cos(a)]];
// blended body section at |z| <= blend_hw (cosine point-morph)
function bsec_pts(z) =
    let(w=(1+cos(180*z/blend_hw))/2,
        ws=wsec_pts(max(0, abs(z)-body_w/2)))
    [for (i=[0:len(ws)-1]) [(1-w)*ws[i][0] + w*ctr_sc*base_pts[i][0],
                            (1-w)*ws[i][1] + w*ctr_st*base_pts[i][1]]];

module body_slice(z) {
    translate([0,0,z]) linear_extrude(height=0.6, center=true)
        polygon(bsec_pts(z));
}
module blend_loft() {
    zs = [for (i=[0:16]) -blend_hw + i*(2*blend_hw/16)];
    for (i=[0:len(zs)-2]) hull() { body_slice(zs[i]); body_slice(zs[i+1]); }
}

module slot_cut() {     // the prop slot through the TE deck
    translate([slot_x0, -45, -slot_hz])
        cube([slot_x1-slot_x0, 95, 2*slot_hz]);
}

module hatch_box() { translate([-0.25*root+40, 6, -22]) cube([190, 60, 44]); }

module body() {         // center piece, |z| <= 50
    difference() {
        intersection() {
            union() {
                blend_loft();
                // subtle blister over the buried motor bell
                hull() { translate([252, 12, 0]) sphere(r=20);
                         translate([285, 10, 0]) sphere(r=15); }
            }
            translate([-200, -100, -body_w/2]) cube([700, 200, body_w]);
        }
        // main cavity (battery over the CG, electronics behind)
        translate([-0.25*root+22, -12, -body_w/2+8])
            cube([0.62*root, 26, body_w-16]);
        // nose camera bay + lens aperture
        translate([-0.25*root-6, -8, -14]) cube([38, 18, 28]);
        translate([-0.25*root-12, 2, 0]) rotate([0,90,0]) cylinder(d=20, h=16);
        slot_cut();
        // motor cavity ahead of the slot; the motor face-bolts to the
        // slot's front wall from inside the slot (16x16..19x19 slots)
        translate([238, mot_y, 0]) rotate([0,90,0])
            cylinder(d=37, h=slot_x0-240);
        translate([slot_x0-10, mot_y, 0]) rotate([0,90,0]) {
            cylinder(d=10, h=24);
            for (a=[45,135,225,315]) rotate([0,0,a]) hull() {
                translate([8,0,0])    cylinder(d=m3, h=24);
                translate([13.5,0,0]) cylinder(d=m3, h=24);
            }
        }
        // cooling intake over the motor
        translate([250, 20, 0]) cylinder(d=9, h=26, center=true);
        // spar + pin channels into both wing roots
        for (s=[0,1]) mirror([0,0,s]) {
            angled_hole(0, 5, slope, spar_d, 0, body_w/2+1);
            angled_hole((0.65-0.25)*root, 4, 0.377, pin_d, 0, body_w/2+1);
        }
        hatch_box();
        for (x=[-0.25*root+52, -0.25*root+215]) translate([x, 12, 0])
            rotate([-90,0,0]) cylinder(d=m3, h=46);
        // CG dimples on the belly — balance HERE
        for (z=[-26, 26]) translate([cg_x, -0.07*root, z]) sphere(d=5);
    }
}

// blend fairing, one per side (z 50..120) — carries spar + slot end
module fairing() {
    difference() {
        intersection() {
            blend_loft();
            translate([-200, -100, body_w/2]) cube([700, 200, blend_hw-body_w/2]);
        }
        slot_cut();
        angled_hole(0, 5, slope, spar_d, 30, blend_hw+1);
        angled_hole((0.65-0.25)*root, 4, 0.377, pin_d, 30, blend_hw+1);
    }
}

// the lid IS the cut-out skin: identical curvature, flush fit.
// Slice with 0.3 mm XY compensation (or scale 99.5% in XZ).
module hatch() {
    difference() {
        intersection() { blend_loft(); hatch_box(); }
        translate([0,-3,0]) hatch_box();    // keep 3 mm of skin
    }
}

echo(str(">>> prop: FIXED 8x6 at x=", prop_x, " inside the slot — do not use folding blades"));

/* ---------------- winglet (raked) ---------------- */
module winglet() {
    union() {
        linear_extrude(height=2.5)
            polygon([[0,0],[tip*0.80,0],[tip*0.98,35],[tip*0.78,95],
                     [tip*0.45,105],[tip*0.16,40]]);
        for (f=[0.32,0.62]) translate([f*tip*0.80-6, -8, 0])
            cube([12, 9, 2.5]);                                // tabs
    }
}

/* ---------------- layout / selector ---------------- */
module layout() {
    color("white") body();
    for (s=[0,1]) color("white") mirror([0,0,s]) fairing();
    color("lightgray") translate([0,0, body_w/2]) wing_half();
    color("lightgray") mirror([0,0,1]) translate([0,0, body_w/2]) wing_half();
    color("white") translate([slope*half, 30, body_w/2+half]) rotate([90,0,0]) winglet();
}

if (part=="layout") layout();
else if (part=="wing_seg") mirror([0,0,side<0?1:0]) wing_seg(seg);
else if (part=="elevon")   mirror([0,0,side<0?1:0]) elevon(seg);
else if (part=="fairing")  mirror([0,0,side<0?1:0]) fairing();
else if (part=="body")     body();
else if (part=="hatch")    hatch();
else if (part=="winglet")  winglet();
