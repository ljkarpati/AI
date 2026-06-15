// Small math / helper utilities used across the game.

export const TAU = Math.PI * 2;

export const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const rand = (lo, hi) => lo + Math.random() * (hi - lo);
export const randInt = (lo, hi) => Math.floor(rand(lo, hi + 1));
export const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
export const chance = (p) => Math.random() < p;

export const dist2 = (ax, ay, bx, by) => {
  const dx = ax - bx, dy = ay - by;
  return dx * dx + dy * dy;
};
export const dist = (ax, ay, bx, by) => Math.sqrt(dist2(ax, ay, bx, by));

export const angleTo = (ax, ay, bx, by) => Math.atan2(by - ay, bx - ax);

// Shortest signed difference between two angles.
export const angleDiff = (a, b) => {
  let d = (b - a) % TAU;
  if (d > Math.PI) d -= TAU;
  if (d < -Math.PI) d += TAU;
  return d;
};

// Circle vs axis-aligned rectangle collision test.
export function circleRectHit(cx, cy, r, rx, ry, rw, rh) {
  const nx = clamp(cx, rx, rx + rw);
  const ny = clamp(cy, ry, ry + rh);
  return dist2(cx, cy, nx, ny) < r * r;
}

// Resolve a circle out of an axis-aligned rectangle (returns adjusted {x,y}).
export function resolveCircleRect(cx, cy, r, rx, ry, rw, rh) {
  const nx = clamp(cx, rx, rx + rw);
  const ny = clamp(cy, ry, ry + rh);
  const dx = cx - nx, dy = cy - ny;
  const d2 = dx * dx + dy * dy;
  if (d2 >= r * r || d2 === 0) {
    // Center inside the rect (d2===0) — push along smallest axis.
    if (d2 === 0) {
      const left = cx - rx, right = rx + rw - cx, top = cy - ry, bottom = ry + rh - cy;
      const m = Math.min(left, right, top, bottom);
      if (m === left) return { x: rx - r, y: cy };
      if (m === right) return { x: rx + rw + r, y: cy };
      if (m === top) return { x: cx, y: ry - r };
      return { x: cx, y: ry + rh + r };
    }
    return null;
  }
  const d = Math.sqrt(d2) || 1;
  const push = (r - d) / d;
  return { x: cx + dx * push, y: cy + dy * push };
}

export function now() { return performance.now(); }
