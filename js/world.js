// World: map layout, building structures, harvestable resources, chests and the storm.
import { rand, randInt, pick, chance, clamp, dist, TAU } from "./utils.js";

export const WORLD_SIZE = 4000;     // square world in px
export const GRID = 64;             // build grid cell size

// Material properties for player-built structures.
export const MATERIALS = {
  wood:  { key: "wood",  hp: 150, color: "#c08a4a", edge: "#8a5e2c", buildTime: 0.0 },
  brick: { key: "brick", hp: 300, color: "#cf6a55", edge: "#9c4334", buildTime: 0.0 },
  metal: { key: "metal", hp: 500, color: "#b7c0cc", edge: "#7d8794", buildTime: 0.0 },
};

// Build piece shapes (all act as solid 1x1 cover in this top-down game).
export const PIECES = {
  wall:  { key: "wall",  cost: 10, hpMult: 1.0 },
  ramp:  { key: "ramp",  cost: 10, hpMult: 0.8 },
  floor: { key: "floor", cost: 10, hpMult: 0.9 },
  cone:  { key: "cone",  cost: 10, hpMult: 0.85 },
};

export class World {
  constructor() {
    this.size = WORLD_SIZE;
    this.structures = new Map();   // "gx,gy" -> structure
    this.resources = [];           // trees / rocks / metal
    this.chests = [];
    this.buildings = [];           // POI obstacle rectangles {x,y,w,h,color}
    this.bushes = [];              // cosmetic ground patches {x,y,r}

    this._generate();

    // Storm state
    this.stormCenter = { x: WORLD_SIZE / 2, y: WORLD_SIZE / 2 };
    this.stormRadius = WORLD_SIZE * 0.72;
    this.targetRadius = this.stormRadius;
    this.targetCenter = { ...this.stormCenter };
    this.phase = 0;
    this.phaseTime = 0;
    this.phaseDuration = 18;       // seconds to wait, then shrink
    this.shrinking = false;
    this.shrinkSpeed = 0;
    this.stormDamage = 1;          // dps, ramps up per phase
    this.maxPhases = 8;
  }

  key(gx, gy) { return gx + "," + gy; }
  cellAt(x, y) { return { gx: Math.floor(x / GRID), gy: Math.floor(y / GRID) }; }

  _generate() {
    const S = WORLD_SIZE;
    // Scatter named POI clusters of buildings.
    const poiCount = 7;
    for (let i = 0; i < poiCount; i++) {
      const cx = rand(S * 0.12, S * 0.88);
      const cy = rand(S * 0.12, S * 0.88);
      const blocks = randInt(2, 5);
      for (let b = 0; b < blocks; b++) {
        const w = rand(120, 260);
        const h = rand(120, 240);
        const x = clamp(cx + rand(-220, 220), 40, S - 40 - w);
        const y = clamp(cy + rand(-220, 220), 40, S - 40 - h);
        this.buildings.push({ x, y, w, h, color: pick(["#3a4a63", "#454b5e", "#4a3f55", "#3f5557"]) });
        // chest chance near a building
        if (chance(0.7)) {
          this.chests.push({
            x: x + rand(10, w - 10), y: y + rand(10, h - 10),
            opened: false, glow: rand(0, TAU),
          });
        }
      }
      // metal scrap near POIs
      for (let m = 0; m < randInt(1, 3); m++) {
        this.resources.push(this._mkResource("metal", cx + rand(-200, 200), cy + rand(-200, 200)));
      }
    }

    // Forests of trees + rock fields spread across the map.
    const trees = 240, rocks = 90;
    for (let i = 0; i < trees; i++) {
      this.resources.push(this._mkResource("wood", rand(60, S - 60), rand(60, S - 60)));
    }
    for (let i = 0; i < rocks; i++) {
      this.resources.push(this._mkResource("brick", rand(60, S - 60), rand(60, S - 60)));
    }
    // Filter resources that spawn inside buildings.
    this.resources = this.resources.filter(r => !this.buildings.some(b =>
      r.x > b.x - 10 && r.x < b.x + b.w + 10 && r.y > b.y - 10 && r.y < b.y + b.h + 10));

    // Free-standing floor chests scattered in the open.
    for (let i = 0; i < 18; i++) {
      this.chests.push({ x: rand(80, S - 80), y: rand(80, S - 80), opened: false, glow: rand(0, TAU) });
    }

    // Cosmetic bushes
    for (let i = 0; i < 120; i++) {
      this.bushes.push({ x: rand(0, S), y: rand(0, S), r: rand(18, 40) });
    }
  }

  _mkResource(type, x, y) {
    const hp = type === "metal" ? 100 : type === "brick" ? 80 : 55;
    const r = type === "wood" ? 18 : type === "brick" ? 22 : 20;
    return { type, x, y, r, hp, maxHp: hp, shake: 0 };
  }

  // ---- Structures (player/bot builds) ----
  canBuildAt(gx, gy) {
    if (gx < 0 || gy < 0 || gx * GRID >= this.size || gy * GRID >= this.size) return false;
    return !this.structures.has(this.key(gx, gy));
  }

  build(gx, gy, piece, material) {
    if (!this.canBuildAt(gx, gy)) return false;
    const mat = MATERIALS[material];
    const pc = PIECES[piece];
    const maxHp = Math.round(mat.hp * pc.hpMult);
    this.structures.set(this.key(gx, gy), {
      gx, gy, piece, material, hp: maxHp, maxHp,
      x: gx * GRID, y: gy * GRID, build: 0.0,
    });
    return true;
  }

  damageStructure(struct, dmg) {
    struct.hp -= dmg;
    if (struct.hp <= 0) {
      this.structures.delete(this.key(struct.gx, struct.gy));
      return true; // destroyed
    }
    return false;
  }

  structAt(x, y) {
    const { gx, gy } = this.cellAt(x, y);
    return this.structures.get(this.key(gx, gy));
  }

  // ---- Storm update ----
  updateStorm(dt) {
    if (this.shrinking) {
      const dr = this.shrinkSpeed * dt;
      this.stormRadius = Math.max(this.targetRadius, this.stormRadius - dr);
      // ease center toward target
      this.stormCenter.x += (this.targetCenter.x - this.stormCenter.x) * Math.min(1, dt * 0.4);
      this.stormCenter.y += (this.targetCenter.y - this.stormCenter.y) * Math.min(1, dt * 0.4);
      if (this.stormRadius <= this.targetRadius + 0.5) {
        this.shrinking = false;
        this.phaseTime = 0;
      }
    } else {
      this.phaseTime += dt;
      if (this.phaseTime >= this.phaseDuration && this.phase < this.maxPhases) {
        this._nextPhase();
      }
    }
  }

  _nextPhase() {
    this.phase++;
    const shrinkFactor = 0.62;
    const prev = this.stormRadius;
    this.targetRadius = Math.max(120, prev * shrinkFactor);
    // New center drifts toward a random point inside the current circle.
    const a = rand(0, TAU);
    const maxOff = (prev - this.targetRadius) * 0.7;
    this.targetCenter = {
      x: clamp(this.stormCenter.x + Math.cos(a) * rand(0, maxOff), this.targetRadius, this.size - this.targetRadius),
      y: clamp(this.stormCenter.y + Math.sin(a) * rand(0, maxOff), this.targetRadius, this.size - this.targetRadius),
    };
    const shrinkDuration = 12;
    this.shrinkSpeed = (prev - this.targetRadius) / shrinkDuration;
    this.shrinking = true;
    this.stormDamage = 1 + this.phase * 1.5;
  }

  outsideStorm(x, y) {
    return dist(x, y, this.stormCenter.x, this.stormCenter.y) > this.stormRadius;
  }

  stormStatus() {
    if (this.phase >= this.maxPhases) return { text: "FINAL", danger: true };
    if (this.shrinking) return { text: "SHRINKING", danger: true };
    const left = Math.max(0, this.phaseDuration - this.phaseTime);
    return { text: Math.ceil(left) + "s", danger: left < 6 };
  }
}
