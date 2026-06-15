// Player and Bot characters.
import { clamp, rand, randInt, pick, chance, dist, angleTo, angleDiff, TAU } from "./utils.js";
import { rollWeapon, makeWeapon } from "./weapons.js";

const BOT_NAMES = [
  "Raptor", "Vex", "Nova", "Blitz", "Echo", "Ghost", "Ryu", "Specter", "Onyx", "Frost",
  "Zara", "Kilo", "Maverick", "Pixel", "Talon", "Rogue", "Hex", "Drift", "Cobra", "Sable",
  "Jett", "Nyx", "Volt", "Ember", "Slate", "Wren", "Bolt", "Pico", "Ash", "Lux",
];

export class Character {
  constructor(x, y) {
    this.x = x; this.y = y;
    this.r = 16;
    this.angle = 0;
    this.maxHp = 100; this.hp = 100;
    this.maxShield = 100; this.shield = 0;
    this.baseSpeed = 235;
    this.alive = true;
    this.slots = [null, null, null, null, null];
    this.slot = 0;
    this.mats = { wood: 0, brick: 0, metal: 0 };
    this.ammo = { light: 0, medium: 0, heavy: 0, shells: 0 };
    this.fireCooldown = 0;
    this.reloadTimer = 0;
    this.hitFlash = 0;
    this.kills = 0;
  }

  get weapon() { return this.slots[this.slot]; }

  takeDamage(dmg) {
    this.hitFlash = 0.12;
    if (this.shield > 0) {
      const absorbed = Math.min(this.shield, dmg);
      this.shield -= absorbed;
      dmg -= absorbed;
    }
    this.hp -= dmg;
    if (this.hp <= 0) { this.hp = 0; this.alive = false; }
    return !this.alive;
  }

  heal(amount) { this.hp = clamp(this.hp + amount, 0, this.maxHp); }
  addShield(amount) { this.shield = clamp(this.shield + amount, 0, this.maxShield); }

  giveWeapon(weapon) {
    // Place in first empty slot, else replace current.
    let idx = this.slots.findIndex(s => s === null);
    if (idx === -1) idx = this.slot;
    this.slots[idx] = weapon;
    return idx;
  }

  addAmmo(type, n) { this.ammo[type] = (this.ammo[type] || 0) + n; }

  startReload() {
    const w = this.weapon;
    if (!w || w.ammoInMag >= w.magSize) return false;
    if ((this.ammo[w.ammoType] || 0) <= 0) return false;
    if (this.reloadTimer > 0) return false;
    this.reloadTimer = w.reloadTime;
    return true;
  }

  finishReloadIfDone(dt) {
    if (this.reloadTimer > 0) {
      this.reloadTimer -= dt;
      if (this.reloadTimer <= 0) {
        const w = this.weapon;
        if (w) {
          const need = w.magSize - w.ammoInMag;
          const take = Math.min(need, this.ammo[w.ammoType] || 0);
          w.ammoInMag += take;
          this.ammo[w.ammoType] -= take;
        }
      }
    }
  }
}

export class Player extends Character {
  constructor(x, y) {
    super(x, y);
    this.isPlayer = true;
    this.name = "You";
    // Start with a basic pistol so the player isn't helpless on drop.
    this.slots[0] = makeWeapon("pistol", "common");
    this.addAmmo("light", 60);
    this.addAmmo("medium", 30);
    this.mats.wood = 100;
  }
}

const STATE = { WANDER: 0, LOOT: 1, FIGHT: 2, FLEE: 3 };

export class Bot extends Character {
  constructor(x, y) {
    super(x, y);
    this.isPlayer = false;
    this.name = pick(BOT_NAMES);
    this.state = STATE.WANDER;
    this.target = null;            // enemy character
    this.wanderAngle = rand(0, TAU);
    this.decisionTimer = 0;
    this.skill = rand(0.35, 0.95);  // affects accuracy + reaction
    this.reaction = 0;
    this.buildCooldown = 0;
    this.lootTarget = null;
    this.baseSpeed = rand(210, 250);

    // Loadout
    const w = rollWeapon();
    this.slots[0] = w;
    this.addAmmo(w.ammoType, 200);
    if (chance(0.5)) {
      const w2 = rollWeapon();
      this.slots[1] = w2;
      this.addAmmo(w2.ammoType, 200);
    }
    this.shield = pick([0, 0, 25, 50]);
    this.mats.wood = randInt(50, 200);
  }

  // Decide behaviour. `world`, list of enemies, and helper to find nearest chest.
  think(dt, world, enemies) {
    this.decisionTimer -= dt;
    this.buildCooldown -= dt;

    // Storm avoidance overrides everything.
    const outside = world.outsideStorm(this.x, this.y);
    const distToCenter = dist(this.x, this.y, world.stormCenter.x, world.stormCenter.y);
    const nearEdge = distToCenter > world.stormRadius * 0.82;

    // Find nearest visible enemy.
    let nearest = null, nd = Infinity;
    for (const e of enemies) {
      if (!e.alive || e === this) continue;
      const d = dist(this.x, this.y, e.x, e.y);
      if (d < nd) { nd = d; nearest = e; }
    }

    const fleeHp = this.hp + this.shield < 35;
    if (fleeHp && nearest && nd < 360) this.state = STATE.FLEE;
    else if (nearest && nd < 520) this.state = STATE.FIGHT;
    else if (this.decisionTimer <= 0) {
      this.state = chance(0.6) ? STATE.LOOT : STATE.WANDER;
      this.decisionTimer = rand(3, 7);
    }

    let moveX = 0, moveY = 0;

    if (outside || nearEdge) {
      // Head toward storm center.
      const a = angleTo(this.x, this.y, world.stormCenter.x, world.stormCenter.y);
      moveX = Math.cos(a); moveY = Math.sin(a);
      this.angle = a;
    } else if (this.state === STATE.FIGHT && nearest) {
      this.target = nearest;
      const a = angleTo(this.x, this.y, nearest.x, nearest.y);
      this.angle += angleDiff(this.angle, a) * Math.min(1, dt * (4 + this.skill * 6));
      const w = this.weapon;
      const ideal = w ? w.range * 0.55 : 300;
      // Strafe + maintain distance.
      const perp = a + Math.PI / 2;
      const strafe = Math.sin(performance.now() * 0.002 + this.skill * 10);
      if (nd > ideal + 40) { moveX = Math.cos(a); moveY = Math.sin(a); }
      else if (nd < ideal - 40) { moveX = -Math.cos(a); moveY = -Math.sin(a); }
      moveX += Math.cos(perp) * strafe * 0.6;
      moveY += Math.sin(perp) * strafe * 0.6;

      // Occasionally build a wall toward enemy when hit recently.
      if (this.buildCooldown <= 0 && this.hitFlash > 0 && this.mats.wood >= 10 && chance(0.5)) {
        this._buildCover(world, a);
        this.buildCooldown = rand(2, 4);
      }
    } else if (this.state === STATE.FLEE && nearest) {
      const a = angleTo(nearest.x, nearest.y, this.x, this.y);
      moveX = Math.cos(a); moveY = Math.sin(a);
      this.angle = angleTo(this.x, this.y, nearest.x, nearest.y);
      if (this.buildCooldown <= 0 && this.mats.wood >= 10) {
        this._buildCover(world, angleTo(this.x, this.y, nearest.x, nearest.y));
        this.buildCooldown = rand(1.5, 3);
      }
    } else if (this.state === STATE.LOOT) {
      if (!this.lootTarget || this.lootTarget.opened) {
        this.lootTarget = this._nearestChest(world);
      }
      if (this.lootTarget) {
        const a = angleTo(this.x, this.y, this.lootTarget.x, this.lootTarget.y);
        moveX = Math.cos(a); moveY = Math.sin(a);
        this.angle = a;
        if (dist(this.x, this.y, this.lootTarget.x, this.lootTarget.y) < 40) {
          this.state = STATE.WANDER; this.lootTarget = null;
        }
      } else { this.state = STATE.WANDER; }
    } else {
      // Wander
      this.wanderAngle += rand(-1, 1) * dt * 2;
      moveX = Math.cos(this.wanderAngle); moveY = Math.sin(this.wanderAngle);
      this.angle = this.wanderAngle;
    }

    const len = Math.hypot(moveX, moveY) || 1;
    this.intentX = moveX / len;
    this.intentY = moveY / len;

    // Decide whether to fire this frame.
    this.wantFire = false;
    if (this.state === STATE.FIGHT && nearest && this.weapon) {
      const w = this.weapon;
      if (nd < w.range) {
        const facing = Math.abs(angleDiff(this.angle, angleTo(this.x, this.y, nearest.x, nearest.y)));
        if (facing < 0.25) this.wantFire = true;
      }
    }
    this.fireTarget = nearest;
  }

  _nearestChest(world) {
    let best = null, bd = Infinity;
    for (const c of world.chests) {
      if (c.opened) continue;
      const d = dist(this.x, this.y, c.x, c.y);
      if (d < bd && d < 1100) { bd = d; best = c; }
    }
    return best;
  }

  _buildCover(world, towardAngle) {
    const bx = this.x + Math.cos(towardAngle) * 52;
    const by = this.y + Math.sin(towardAngle) * 52;
    const { gx, gy } = world.cellAt(bx, by);
    if (world.build(gx, gy, "wall", "wood")) this.mats.wood -= 10;
  }
}
