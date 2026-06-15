// Core game: loop, physics, combat, loot, storm, rendering and HUD.
import { World, GRID, MATERIALS, PIECES, WORLD_SIZE } from "./world.js";
import { Player, Bot } from "./entities.js";
import { rollWeapon } from "./weapons.js";
import {
  clamp, rand, randInt, pick, chance, dist, dist2, angleTo, TAU,
  resolveCircleRect, circleRectHit,
} from "./utils.js";

const PICKUP_R = 34;
const HARVEST_RANGE = 50;
const TOTAL_PLAYERS = 50;   // including the player

export class Game {
  constructor(canvas, input, hud) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.input = input;
    this.hud = hud;
    this.mini = document.getElementById("minimap");
    this.miniCtx = this.mini.getContext("2d");

    this.state = "menu";
    this.zoom = 1;
    this.camera = { x: 0, y: 0 };
    this._raf = null;
    this._last = 0;

    this.buildMode = false;
    this.currentPiece = "wall";

    this._resize();
    window.addEventListener("resize", () => this._resize());
  }

  _resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
    this.cssW = window.innerWidth;
    this.cssH = window.innerHeight;
    this.canvas.width = Math.floor(this.cssW * dpr);
    this.canvas.height = Math.floor(this.cssH * dpr);
    this.dpr = dpr;
    // Show roughly a 1050px-wide slice of the world, clamped for sanity.
    this.zoom = clamp(this.cssW / 1050, 0.5, 1.1);
    const md = Math.min(this.mini.clientWidth, this.mini.clientHeight) || 92;
    this.mini.width = md * dpr; this.mini.height = md * dpr;
  }

  start() {
    this.world = new World();
    // Spawn the player somewhere inside the initial safe zone.
    const sp = this._randSpawn();
    this.player = new Player(sp.x, sp.y);

    this.bots = [];
    for (let i = 0; i < TOTAL_PLAYERS - 1; i++) {
      const p = this._randSpawn();
      this.bots.push(new Bot(p.x, p.y));
    }

    this.bullets = [];
    this.loot = [];
    this.particles = [];
    this.floats = [];

    this.buildMode = false;
    this.currentPiece = "wall";
    this.kills = 0;
    this.startTime = performance.now();
    this.invDirty = true;

    this.state = "playing";
    document.getElementById("hud").classList.remove("hidden");
    document.getElementById("build-bar").classList.add("hidden");
    this._buildInventoryDom();

    this._last = performance.now();
    if (this._raf) cancelAnimationFrame(this._raf);
    this._loop = this._loop.bind(this);
    this._raf = requestAnimationFrame(this._loop);
  }

  _randSpawn() {
    const c = WORLD_SIZE / 2;
    const a = rand(0, TAU);
    const rr = rand(0, WORLD_SIZE * 0.34);
    return { x: c + Math.cos(a) * rr, y: c + Math.sin(a) * rr };
  }

  _loop(t) {
    const dt = Math.min(0.05, (t - this._last) / 1000);
    this._last = t;
    if (this.state === "playing") {
      this.update(dt);
      this.render();
    }
    this._raf = requestAnimationFrame(this._loop);
  }

  // ---------------- UPDATE ----------------
  update(dt) {
    const input = this.input;
    const player = this.player;

    // Desktop keyboard/mouse polling (no-op on touch devices that ignore it).
    const sx = this.cssW / 2, sy = this.cssH / 2;
    input.buildMode = this.buildMode;
    input.pollKeyboard(sx, sy);

    // Handle edge-triggered buttons.
    const ev = input.consume();
    if (ev.buildToggle) this._toggleBuild();
    if (ev.selectPiece) { this.currentPiece = ev.selectPiece; this._refreshBuildBar(); }
    if (ev.reload && player.alive) player.startReload();
    if (ev.placeBuild && this.buildMode && player.alive) this._placeBuild();

    if (player.alive) {
      // Movement
      this._moveCharacter(player, input.move.x, input.move.y, dt);
      // Aim
      if (input.aim.active && input.aim.mag > 0.1) {
        player.angle = Math.atan2(input.aim.y, input.aim.x);
      }
      // Fire (only when not in build mode)
      if (!this.buildMode && input.firing && input.aim.active) {
        this._tryFire(player, dt);
      }
      player.fireCooldown -= dt;
      player.finishReloadIfDone(dt);
      if (player.hitFlash > 0) player.hitFlash -= dt;

      // Harvesting
      if (input.harvesting) this._harvest(player, dt);
      this._harvestCd = (this._harvestCd || 0) - dt;

      // Auto chest open + loot pickup
      this._checkChests(player);
      this._pickupLoot(player);
    }

    // Bots
    const everyone = [player, ...this.bots];
    for (const bot of this.bots) {
      if (!bot.alive) continue;
      bot.think(dt, this.world, everyone);
      this._moveCharacter(bot, bot.intentX || 0, bot.intentY || 0, dt);
      bot.fireCooldown -= dt;
      bot.finishReloadIfDone(dt);
      if (bot.hitFlash > 0) bot.hitFlash -= dt;
      if (bot.wantFire) this._tryFire(bot, dt);
      else if (bot.weapon && bot.weapon.ammoInMag <= 0) bot.startReload();
      bot._chestTick = (bot._chestTick || 0) - dt;
      if (bot._chestTick <= 0) { this._checkChests(bot); bot._chestTick = 0.3; }
    }

    this._updateBullets(dt);
    this._updateParticles(dt);
    this._updateFloats(dt);

    // Storm
    this.world.updateStorm(dt);
    this._stormTick = (this._stormTick || 0) + dt;
    if (this._stormTick >= 0.5) {
      const d = this._stormTick;
      this._stormTick = 0;
      for (const ch of everyone) {
        if (ch.alive && this.world.outsideStorm(ch.x, ch.y)) {
          const died = ch.takeDamage(this.world.stormDamage * d);
          if (died) this._onDeath(ch, null);
        }
      }
    }

    this._updateCamera(dt);
    this._checkEndState();
    this._updateHud();
  }

  _toggleBuild() {
    this.buildMode = !this.buildMode;
    document.getElementById("btn-build").classList.toggle("on", this.buildMode);
    document.getElementById("build-bar").classList.toggle("hidden", !this.buildMode);
    this._refreshBuildBar();
  }

  _refreshBuildBar() {
    document.querySelectorAll(".build-piece").forEach(b =>
      b.classList.toggle("active", b.dataset.piece === this.currentPiece));
  }

  _chooseMaterial(p) {
    if (p.mats.wood >= 10) return "wood";
    if (p.mats.brick >= 10) return "brick";
    if (p.mats.metal >= 10) return "metal";
    return null;
  }

  _placeBuild() {
    const p = this.player;
    const mat = this._chooseMaterial(p);
    if (!mat) { this._float(p.x, p.y - 30, "No mats!", "#ff6b6b"); return; }
    const tx = p.x + Math.cos(p.angle) * GRID;
    const ty = p.y + Math.sin(p.angle) * GRID;
    const { gx, gy } = this.world.cellAt(tx, ty);
    if (this.world.build(gx, gy, this.currentPiece, mat)) {
      p.mats[mat] -= PIECES[this.currentPiece].cost;
      this.invDirty = true;
      for (let i = 0; i < 6; i++) this._particle(tx + rand(-20, 20), ty + rand(-20, 20), MATERIALS[mat].color);
    }
  }

  _tryFire(ch, dt) {
    const w = ch.weapon;
    if (!w) return;
    if (ch.reloadTimer > 0) return;
    if (ch.fireCooldown > 0) return;
    if (w.ammoInMag <= 0) { ch.startReload(); return; }
    if (!w.auto && ch._triggerHeld && ch.isPlayer) {
      // semi-auto: require release between shots for the player
    }
    ch.fireCooldown = 1 / w.fireRate;
    w.ammoInMag--;
    if (ch.isPlayer) this.invDirty = true;

    const accuracy = ch.isPlayer ? 1 : (0.4 + ch.skill * 0.6);
    for (let i = 0; i < w.pellets; i++) {
      const spread = w.spread * (ch.isPlayer ? 1 : (1.6 - ch.skill)) ;
      const a = ch.angle + rand(-spread, spread) + (1 - accuracy) * rand(-0.08, 0.08);
      const muzzle = ch.r + 6;
      this.bullets.push({
        x: ch.x + Math.cos(a) * muzzle,
        y: ch.y + Math.sin(a) * muzzle,
        vx: Math.cos(a) * w.speed,
        vy: Math.sin(a) * w.speed,
        dmg: w.damage,
        range: w.range,
        traveled: 0,
        owner: ch,
        player: ch.isPlayer,
      });
    }
    // Muzzle flash + recoil particles
    this._particle(ch.x + Math.cos(ch.angle) * 20, ch.y + Math.sin(ch.angle) * 20, "#ffd27f", 60, 0.12);
  }

  _updateBullets(dt) {
    const w = this.world;
    const everyone = [this.player, ...this.bots];
    for (let i = this.bullets.length - 1; i >= 0; i--) {
      const b = this.bullets[i];
      const step = Math.hypot(b.vx, b.vy) * dt;
      const nx = b.x + b.vx * dt;
      const ny = b.y + b.vy * dt;
      b.traveled += step;
      let hit = false;

      // World bounds / range
      if (b.traveled > b.range || nx < 0 || ny < 0 || nx > WORLD_SIZE || ny > WORLD_SIZE) {
        this.bullets.splice(i, 1); continue;
      }

      // Structures
      const s = w.structAt(nx, ny);
      if (s) {
        const destroyed = w.damageStructure(s, b.dmg);
        this._particle(nx, ny, MATERIALS[s.material].color, 80);
        if (destroyed) for (let k = 0; k < 8; k++) this._particle(s.x + GRID / 2, s.y + GRID / 2, MATERIALS[s.material].color);
        this.bullets.splice(i, 1); continue;
      }

      // Resources block + take damage
      for (const r of w.resources) {
        if (r.hp <= 0) continue;
        if (dist2(nx, ny, r.x, r.y) < (r.r + 2) * (r.r + 2)) {
          r.hp -= b.dmg * 0.6; r.shake = 0.15;
          this._particle(nx, ny, r.type === "wood" ? "#7a5a2e" : "#9aa0a6", 70);
          hit = true; break;
        }
      }
      if (hit) { this.bullets.splice(i, 1); continue; }

      // Buildings (POI walls)
      for (const bd of w.buildings) {
        if (nx > bd.x && nx < bd.x + bd.w && ny > bd.y && ny < bd.y + bd.h) {
          this._particle(nx, ny, "#2c3850", 60); hit = true; break;
        }
      }
      if (hit) { this.bullets.splice(i, 1); continue; }

      // Characters
      for (const ch of everyone) {
        if (!ch.alive || ch === b.owner) continue;
        if (dist2(nx, ny, ch.x, ch.y) < ch.r * ch.r) {
          const died = ch.takeDamage(b.dmg);
          this._float(ch.x, ch.y - ch.r - 8, Math.round(b.dmg), b.player ? "#ffd166" : "#ff8a8a");
          for (let k = 0; k < 4; k++) this._particle(ch.x, ch.y, "#ff5555", 90);
          if (died) {
            this._onDeath(ch, b.owner);
          }
          hit = true; break;
        }
      }
      if (hit) { this.bullets.splice(i, 1); continue; }

      b.x = nx; b.y = ny;
    }
  }

  _harvest(ch, dt) {
    if (this._harvestCd > 0) return;
    const w = this.world;
    const hx = ch.x + Math.cos(ch.angle) * HARVEST_RANGE * 0.6;
    const hy = ch.y + Math.sin(ch.angle) * HARVEST_RANGE * 0.6;
    // Resource first
    let best = null, bd = HARVEST_RANGE * HARVEST_RANGE;
    for (const r of w.resources) {
      if (r.hp <= 0) continue;
      const d = dist2(hx, hy, r.x, r.y);
      if (d < bd + r.r * r.r) { bd = d; best = r; }
    }
    if (best) {
      this._harvestCd = 0.35;
      best.hp -= 34; best.shake = 0.2;
      const matType = best.type; // wood/brick/metal
      const gain = randInt(6, 10);
      ch.mats[matType] = (ch.mats[matType] || 0) + gain;
      if (ch.isPlayer) { this.invDirty = true; this._float(best.x, best.y - best.r, "+" + gain, MATERIALS[matType].color); }
      for (let k = 0; k < 5; k++) this._particle(best.x, best.y, MATERIALS[matType].color);
      if (best.hp <= 0) { best.dead = true; w.resources = w.resources.filter(rr => !rr.dead); }
      return;
    }
    // Otherwise hit a structure in front (enemy builds).
    const s = w.structAt(hx, hy);
    if (s) {
      this._harvestCd = 0.35;
      const destroyed = w.damageStructure(s, 50);
      ch.mats[s.material] = (ch.mats[s.material] || 0) + 3;
      if (ch.isPlayer) this.invDirty = true;
      for (let k = 0; k < 5; k++) this._particle(s.x + GRID / 2, s.y + GRID / 2, MATERIALS[s.material].color);
    }
  }

  _checkChests(ch) {
    for (const c of this.world.chests) {
      if (c.opened) continue;
      if (dist2(ch.x, ch.y, c.x, c.y) < 38 * 38) {
        c.opened = true;
        this._spawnChestLoot(c, ch.isPlayer);
        if (ch.isPlayer) {
          // Auto-grab from chest after a short beat handled by pickup.
        }
      }
    }
  }

  _spawnChestLoot(c, forPlayer) {
    const items = [];
    items.push({ kind: "weapon", weapon: rollWeapon(0.2) });
    if (chance(0.8)) items.push({ kind: "ammo", ammoType: pick(["light", "medium", "heavy", "shells"]), n: randInt(14, 30) });
    if (chance(0.55)) items.push({ kind: "shield", n: pick([25, 50]) });
    if (chance(0.4)) items.push({ kind: "heal", n: pick([25, 50]) });
    for (const it of items) {
      const a = rand(0, TAU), d = rand(14, 34);
      this.loot.push({ ...it, x: c.x + Math.cos(a) * d, y: c.y + Math.sin(a) * d, bob: rand(0, TAU) });
    }
    for (let k = 0; k < 12; k++) this._particle(c.x, c.y, "#ffd166", 120);
  }

  _pickupLoot(p) {
    for (let i = this.loot.length - 1; i >= 0; i--) {
      const it = this.loot[i];
      if (dist2(p.x, p.y, it.x, it.y) > PICKUP_R * PICKUP_R) continue;
      let taken = true, msg = "", col = "#fff";
      if (it.kind === "weapon") {
        const idx = p.giveWeapon(it.weapon);
        p.addAmmo(it.weapon.ammoType, randInt(8, 18));
        msg = it.weapon.rarity[0].toUpperCase() + it.weapon.rarity.slice(1) + " " + it.weapon.name;
        col = it.weapon.rarityColor;
      } else if (it.kind === "ammo") {
        p.addAmmo(it.ammoType, it.n); msg = "+" + it.n + " ammo"; col = "#ffe6a0";
      } else if (it.kind === "shield") {
        if (p.shield >= p.maxShield) { taken = false; }
        else { p.addShield(it.n); msg = "+" + it.n + " shield"; col = "#7be0ff"; }
      } else if (it.kind === "heal") {
        if (p.hp >= p.maxHp) { taken = false; }
        else { p.heal(it.n); msg = "+" + it.n + " hp"; col = "#87f07f"; }
      } else if (it.kind === "mat") {
        p.mats[it.matType] += it.n; msg = "+" + it.n; col = MATERIALS[it.matType].color;
      }
      if (taken) {
        this.loot.splice(i, 1);
        if (p.isPlayer) { this.invDirty = true; this._float(p.x, p.y - 28, msg, col); }
      }
    }
  }

  _onDeath(ch, killer) {
    ch.alive = false;
    // Drop loot
    this._dropLoot(ch);
    for (let k = 0; k < 16; k++) this._particle(ch.x, ch.y, "#ff7766", 130);
    if (killer && killer.isPlayer) {
      this.kills++;
      this._float(this.player.x, this.player.y - 40, "Eliminated " + ch.name + "!", "#ffd166");
    }
    if (killer) killer.kills = (killer.kills || 0) + 1;
  }

  _dropLoot(ch) {
    // Best weapon
    const best = ch.slots.filter(Boolean).sort((a, b) => b.damage - a.damage)[0];
    if (best) this.loot.push({ kind: "weapon", weapon: best, x: ch.x + rand(-12, 12), y: ch.y + rand(-12, 12), bob: rand(0, TAU) });
    // Mats
    for (const m of ["wood", "brick", "metal"]) {
      if (ch.mats[m] > 0) this.loot.push({ kind: "mat", matType: m, n: Math.min(ch.mats[m], 60), x: ch.x + rand(-18, 18), y: ch.y + rand(-18, 18), bob: rand(0, TAU) });
    }
    // Ammo bundle
    this.loot.push({ kind: "ammo", ammoType: pick(["light", "medium", "heavy"]), n: randInt(10, 24), x: ch.x + rand(-16, 16), y: ch.y + rand(-16, 16), bob: rand(0, TAU) });
  }

  // ----- movement & collision -----
  _moveCharacter(ch, ix, iy, dt) {
    let nx = ch.x + ix * ch.baseSpeed * dt;
    let ny = ch.y + iy * ch.baseSpeed * dt;
    nx = clamp(nx, ch.r, WORLD_SIZE - ch.r);
    ny = clamp(ny, ch.r, WORLD_SIZE - ch.r);

    const w = this.world;
    // Collide vs nearby structures (grid cells around new pos)
    const { gx, gy } = w.cellAt(nx, ny);
    for (let cy = gy - 1; cy <= gy + 1; cy++) {
      for (let cx = gx - 1; cx <= gx + 1; cx++) {
        const s = w.structures.get(w.key(cx, cy));
        if (!s) continue;
        const res = resolveCircleRect(nx, ny, ch.r, s.x, s.y, GRID, GRID);
        if (res) { nx = res.x; ny = res.y; }
      }
    }
    // Collide vs POI buildings
    for (const bd of w.buildings) {
      if (circleRectHit(nx, ny, ch.r, bd.x, bd.y, bd.w, bd.h)) {
        const res = resolveCircleRect(nx, ny, ch.r, bd.x, bd.y, bd.w, bd.h);
        if (res) { nx = res.x; ny = res.y; }
      }
    }
    // Collide vs resources (circle-circle)
    for (const r of w.resources) {
      if (r.hp <= 0) continue;
      const rr = ch.r + r.r;
      if (dist2(nx, ny, r.x, r.y) < rr * rr) {
        const a = angleTo(r.x, r.y, nx, ny);
        nx = r.x + Math.cos(a) * rr;
        ny = r.y + Math.sin(a) * rr;
      }
    }
    ch.x = clamp(nx, ch.r, WORLD_SIZE - ch.r);
    ch.y = clamp(ny, ch.r, WORLD_SIZE - ch.r);
  }

  _updateCamera(dt) {
    const p = this.player;
    const tx = p.x, ty = p.y;
    this.camera.x += (tx - this.camera.x) * Math.min(1, dt * 8);
    this.camera.y += (ty - this.camera.y) * Math.min(1, dt * 8);
  }

  _checkEndState() {
    const aliveBots = this.bots.filter(b => b.alive).length;
    this.aliveCount = aliveBots + (this.player.alive ? 1 : 0);
    if (!this.player.alive && this.state === "playing") {
      this._end(false, this.aliveCount + 1);
    } else if (this.player.alive && aliveBots === 0 && this.state === "playing") {
      this._end(true, 1);
    }
  }

  _end(victory, place) {
    this.state = "over";
    this.hud.showResult(victory, place, this.kills);
  }

  // ----- particles / floats -----
  _particle(x, y, color, speed = 100, life = 0.4) {
    const a = rand(0, TAU), s = rand(speed * 0.3, speed);
    this.particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life, max: life, color, size: rand(2, 4) });
  }
  _updateParticles(dt) {
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.9; p.vy *= 0.9;
      p.life -= dt; if (p.life <= 0) this.particles.splice(i, 1);
    }
  }
  _float(x, y, text, color) { this.floats.push({ x, y, text: String(text), color, life: 0.9, vy: -34 }); }
  _updateFloats(dt) {
    for (let i = this.floats.length - 1; i >= 0; i--) {
      const f = this.floats[i];
      f.y += f.vy * dt; f.life -= dt;
      if (f.life <= 0) this.floats.splice(i, 1);
    }
  }

  // ---------------- RENDER ----------------
  render() {
    const ctx = this.ctx;
    const w = this.world;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.clearRect(0, 0, this.cssW, this.cssH);

    // Camera transform
    ctx.save();
    ctx.translate(this.cssW / 2, this.cssH / 2);
    ctx.scale(this.zoom, this.zoom);
    ctx.translate(-this.camera.x, -this.camera.y);

    const viewW = this.cssW / this.zoom, viewH = this.cssH / this.zoom;
    const vx = this.camera.x - viewW / 2, vy = this.camera.y - viewH / 2;
    const inView = (x, y, pad = 60) => x > vx - pad && x < vx + viewW + pad && y > vy - pad && y < vy + viewH + pad;

    this._drawGround(ctx, vx, vy, viewW, viewH);

    // Bushes
    ctx.fillStyle = "rgba(40,90,55,0.5)";
    for (const b of w.bushes) { if (!inView(b.x, b.y)) continue; ctx.beginPath(); ctx.arc(b.x, b.y, b.r, 0, TAU); ctx.fill(); }

    // POI buildings
    for (const bd of w.buildings) {
      if (!inView(bd.x + bd.w / 2, bd.y + bd.h / 2, 200)) continue;
      ctx.fillStyle = bd.color;
      ctx.fillRect(bd.x, bd.y, bd.w, bd.h);
      ctx.strokeStyle = "rgba(0,0,0,0.4)"; ctx.lineWidth = 4; ctx.strokeRect(bd.x, bd.y, bd.w, bd.h);
      ctx.fillStyle = "rgba(255,255,255,0.05)"; ctx.fillRect(bd.x + 8, bd.y + 8, bd.w - 16, bd.h - 16);
    }

    // Resources
    for (const r of w.resources) {
      if (r.hp <= 0 || !inView(r.x, r.y)) continue;
      const sh = r.shake > 0 ? Math.sin(performance.now() * 0.05) * 2 : 0;
      r.shake = Math.max(0, r.shake - 0.016);
      if (r.type === "wood") {
        ctx.fillStyle = "#2f7d44"; ctx.beginPath(); ctx.arc(r.x + sh, r.y, r.r + 6, 0, TAU); ctx.fill();
        ctx.fillStyle = "#256238"; ctx.beginPath(); ctx.arc(r.x + sh, r.y - 4, r.r, 0, TAU); ctx.fill();
        ctx.fillStyle = "#6b4423"; ctx.fillRect(r.x - 3 + sh, r.y, 6, r.r);
      } else {
        ctx.fillStyle = r.type === "brick" ? "#8a8f98" : "#a9b4c2";
        ctx.beginPath(); ctx.arc(r.x + sh, r.y, r.r, 0, TAU); ctx.fill();
        ctx.fillStyle = "rgba(255,255,255,0.12)"; ctx.beginPath(); ctx.arc(r.x - 4 + sh, r.y - 4, r.r * 0.5, 0, TAU); ctx.fill();
      }
    }

    // Loot on ground
    for (const it of this.loot) {
      if (!inView(it.x, it.y)) continue;
      it.bob += 0.06;
      const yo = Math.sin(it.bob) * 3;
      this._drawLootItem(ctx, it, yo);
    }

    // Chests (unopened)
    for (const c of w.chests) {
      if (c.opened || !inView(c.x, c.y)) continue;
      c.glow += 0.05;
      const g = 0.5 + Math.sin(c.glow) * 0.3;
      ctx.fillStyle = `rgba(255,209,102,${0.25 * g})`;
      ctx.beginPath(); ctx.arc(c.x, c.y, 22, 0, TAU); ctx.fill();
      ctx.fillStyle = "#b9852a"; ctx.fillRect(c.x - 12, c.y - 8, 24, 16);
      ctx.fillStyle = "#e0b04a"; ctx.fillRect(c.x - 12, c.y - 8, 24, 5);
      ctx.strokeStyle = "#6b4d18"; ctx.lineWidth = 2; ctx.strokeRect(c.x - 12, c.y - 8, 24, 16);
    }

    // Structures
    for (const s of w.structures.values()) {
      if (!inView(s.x + GRID / 2, s.y + GRID / 2)) continue;
      this._drawStructure(ctx, s);
    }

    // Build preview
    if (this.buildMode && this.player.alive) {
      const p = this.player;
      const tx = p.x + Math.cos(p.angle) * GRID, ty = p.y + Math.sin(p.angle) * GRID;
      const { gx, gy } = w.cellAt(tx, ty);
      const ok = w.canBuildAt(gx, gy) && this._chooseMaterial(p);
      ctx.globalAlpha = 0.5;
      ctx.fillStyle = ok ? "#7be0ff" : "#ff6b6b";
      ctx.fillRect(gx * GRID, gy * GRID, GRID, GRID);
      ctx.globalAlpha = 1;
      ctx.strokeStyle = ok ? "#fff" : "#ff9090"; ctx.lineWidth = 2;
      ctx.strokeRect(gx * GRID, gy * GRID, GRID, GRID);
    }

    // Bots
    for (const b of this.bots) { if (b.alive && inView(b.x, b.y)) this._drawCharacter(ctx, b, false); }
    // Player
    if (this.player.alive) this._drawCharacter(ctx, this.player, true);

    // Bullets
    ctx.lineCap = "round";
    for (const b of this.bullets) {
      if (!inView(b.x, b.y, 30)) continue;
      ctx.strokeStyle = b.player ? "#fff2b0" : "#ffb0b0";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(b.x, b.y);
      ctx.lineTo(b.x - b.vx * 0.012, b.y - b.vy * 0.012);
      ctx.stroke();
    }

    // Particles
    for (const p of this.particles) {
      ctx.globalAlpha = Math.max(0, p.life / p.max);
      ctx.fillStyle = p.color;
      ctx.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
    }
    ctx.globalAlpha = 1;

    // Floating text
    ctx.textAlign = "center"; ctx.font = "bold 15px -apple-system, sans-serif";
    for (const f of this.floats) {
      ctx.globalAlpha = Math.min(1, f.life * 1.6);
      ctx.fillStyle = "#000"; ctx.fillText(f.text, f.x + 1, f.y + 1);
      ctx.fillStyle = f.color; ctx.fillText(f.text, f.x, f.y);
    }
    ctx.globalAlpha = 1;

    this._drawStorm(ctx);
    ctx.restore();

    this._drawMinimap();
  }

  _drawGround(ctx, vx, vy, vw, vh) {
    // Base grass + subtle grid.
    ctx.fillStyle = "#1c3d28";
    ctx.fillRect(vx - 60, vy - 60, vw + 120, vh + 120);
    ctx.strokeStyle = "rgba(255,255,255,0.03)"; ctx.lineWidth = 1;
    const step = 128;
    const x0 = Math.floor((vx) / step) * step;
    const y0 = Math.floor((vy) / step) * step;
    ctx.beginPath();
    for (let x = x0; x < vx + vw + step; x += step) { ctx.moveTo(x, vy - 60); ctx.lineTo(x, vy + vh + 60); }
    for (let y = y0; y < vy + vh + step; y += step) { ctx.moveTo(vx - 60, y); ctx.lineTo(vx + vw + 60, y); }
    ctx.stroke();
    // World border
    ctx.strokeStyle = "rgba(0,0,0,0.6)"; ctx.lineWidth = 8;
    ctx.strokeRect(0, 0, WORLD_SIZE, WORLD_SIZE);
  }

  _drawStructure(ctx, s) {
    const m = MATERIALS[s.material];
    ctx.fillStyle = m.color;
    ctx.fillRect(s.x, s.y, GRID, GRID);
    ctx.strokeStyle = m.edge; ctx.lineWidth = 3;
    ctx.strokeRect(s.x + 1.5, s.y + 1.5, GRID - 3, GRID - 3);
    // Piece motif
    ctx.strokeStyle = "rgba(0,0,0,0.25)"; ctx.lineWidth = 2;
    ctx.beginPath();
    if (s.piece === "ramp") { ctx.moveTo(s.x, s.y + GRID); ctx.lineTo(s.x + GRID, s.y); }
    else if (s.piece === "cone") { ctx.moveTo(s.x + GRID / 2, s.y); ctx.lineTo(s.x, s.y + GRID); ctx.lineTo(s.x + GRID, s.y + GRID); }
    else if (s.piece === "floor") { ctx.moveTo(s.x, s.y + GRID / 2); ctx.lineTo(s.x + GRID, s.y + GRID / 2); }
    else { ctx.moveTo(s.x + GRID / 2, s.y); ctx.lineTo(s.x + GRID / 2, s.y + GRID); }
    ctx.stroke();
    // Damage overlay
    const f = s.hp / s.maxHp;
    if (f < 1) {
      ctx.fillStyle = `rgba(0,0,0,${0.5 * (1 - f)})`;
      ctx.fillRect(s.x, s.y, GRID, GRID);
    }
  }

  _drawLootItem(ctx, it, yo) {
    const x = it.x, y = it.y + yo;
    if (it.kind === "weapon") {
      ctx.fillStyle = "rgba(0,0,0,0.35)"; ctx.beginPath(); ctx.ellipse(it.x, it.y + 8, 14, 5, 0, 0, TAU); ctx.fill();
      ctx.fillStyle = it.weapon.rarityColor;
      ctx.fillRect(x - 13, y - 9, 26, 18);
      ctx.fillStyle = "rgba(0,0,0,0.55)"; ctx.fillRect(x - 9, y - 3, 18, 4);
      ctx.fillStyle = "#222"; ctx.fillRect(x - 11, y + 3, 8, 4);
    } else {
      const col = it.kind === "ammo" ? "#e0b85a" : it.kind === "shield" ? "#4cc9f0" : it.kind === "heal" ? "#6bd968" : "#c08a4a";
      ctx.fillStyle = "rgba(0,0,0,0.3)"; ctx.beginPath(); ctx.ellipse(it.x, it.y + 7, 10, 4, 0, 0, TAU); ctx.fill();
      ctx.fillStyle = col;
      if (it.kind === "shield" || it.kind === "heal") {
        ctx.fillRect(x - 6, y - 9, 12, 18); ctx.fillStyle = "rgba(255,255,255,0.5)"; ctx.fillRect(x - 6, y - 9, 12, 4);
      } else {
        ctx.beginPath(); ctx.arc(x, y, 8, 0, TAU); ctx.fill();
      }
    }
  }

  _drawCharacter(ctx, ch, isPlayer) {
    const x = ch.x, y = ch.y;
    // Shadow
    ctx.fillStyle = "rgba(0,0,0,0.3)";
    ctx.beginPath(); ctx.ellipse(x, y + ch.r * 0.7, ch.r, ch.r * 0.45, 0, 0, TAU); ctx.fill();

    // Body
    const base = isPlayer ? "#4cc9f0" : "#e0584f";
    ctx.fillStyle = ch.hitFlash > 0 ? "#ffffff" : base;
    ctx.beginPath(); ctx.arc(x, y, ch.r, 0, TAU); ctx.fill();
    ctx.strokeStyle = "rgba(0,0,0,0.4)"; ctx.lineWidth = 2; ctx.stroke();

    // Direction / weapon
    const gx = x + Math.cos(ch.angle) * (ch.r + 10);
    const gy = y + Math.sin(ch.angle) * (ch.r + 10);
    ctx.strokeStyle = "#2a2f3a"; ctx.lineWidth = 5; ctx.lineCap = "round";
    ctx.beginPath(); ctx.moveTo(x + Math.cos(ch.angle) * ch.r, y + Math.sin(ch.angle) * ch.r); ctx.lineTo(gx, gy); ctx.stroke();

    // Name + health for bots (small)
    if (!isPlayer) {
      const total = (ch.hp + ch.shield) / (ch.maxHp + ch.maxShield);
      ctx.fillStyle = "rgba(0,0,0,0.5)"; ctx.fillRect(x - 18, y - ch.r - 14, 36, 5);
      ctx.fillStyle = "#6bd968"; ctx.fillRect(x - 18, y - ch.r - 14, 36 * (ch.hp / ch.maxHp), 5);
      if (ch.shield > 0) { ctx.fillStyle = "#4cc9f0"; ctx.fillRect(x - 18, y - ch.r - 18, 36 * (ch.shield / ch.maxShield), 3); }
    } else {
      // Player ring
      ctx.strokeStyle = "rgba(255,255,255,0.5)"; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(x, y, ch.r + 4, 0, TAU); ctx.stroke();
    }
  }

  _drawStorm(ctx) {
    const w = this.world;
    const c = w.stormCenter;
    // Purple overlay outside the circle using even-odd fill.
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, WORLD_SIZE, WORLD_SIZE);
    ctx.arc(c.x, c.y, w.stormRadius, 0, TAU, true);
    ctx.fillStyle = "rgba(120, 50, 200, 0.28)";
    ctx.fill("evenodd");
    ctx.restore();
    // Circle edge
    ctx.strokeStyle = "rgba(220, 180, 255, 0.9)"; ctx.lineWidth = 4;
    ctx.beginPath(); ctx.arc(c.x, c.y, w.stormRadius, 0, TAU); ctx.stroke();
    // Next circle
    if (w.shrinking || w.phase < w.maxPhases) {
      ctx.strokeStyle = "rgba(255,255,255,0.45)"; ctx.lineWidth = 2; ctx.setLineDash([10, 10]);
      ctx.beginPath(); ctx.arc(w.targetCenter.x, w.targetCenter.y, w.targetRadius, 0, TAU); ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  _drawMinimap() {
    const ctx = this.miniCtx;
    const W = this.mini.width, H = this.mini.height;
    const s = W / WORLD_SIZE;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = "#16331f"; ctx.fillRect(0, 0, W, H);
    // POIs
    ctx.fillStyle = "rgba(160,170,200,0.5)";
    for (const b of this.world.buildings) ctx.fillRect(b.x * s, b.y * s, Math.max(2, b.w * s), Math.max(2, b.h * s));
    // Storm
    const c = this.world.stormCenter;
    ctx.strokeStyle = "#d9b3ff"; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(c.x * s, c.y * s, this.world.stormRadius * s, 0, TAU); ctx.stroke();
    ctx.strokeStyle = "rgba(255,255,255,0.6)"; ctx.lineWidth = 1; ctx.setLineDash([3, 3]);
    ctx.beginPath(); ctx.arc(this.world.targetCenter.x * s, this.world.targetCenter.y * s, this.world.targetRadius * s, 0, TAU); ctx.stroke();
    ctx.setLineDash([]);
    // Player
    const p = this.player;
    ctx.fillStyle = "#fff";
    ctx.save();
    ctx.translate(p.x * s, p.y * s); ctx.rotate(p.angle);
    ctx.beginPath(); ctx.moveTo(6, 0); ctx.lineTo(-4, -4); ctx.lineTo(-4, 4); ctx.closePath(); ctx.fill();
    ctx.restore();
  }

  // ---------------- HUD ----------------
  _updateHud() {
    const p = this.player;
    const h = this.hud;
    h.set("alive-count", this.aliveCount);
    h.set("kill-count", this.kills);
    const st = this.world.stormStatus();
    h.set("storm-text", st.text);
    document.getElementById("storm-stat").classList.toggle("danger", st.danger);

    h.fill("health-fill", p.hp / p.maxHp);
    h.set("health-label", Math.ceil(p.hp));
    h.fill("shield-fill", p.shield / p.maxShield);
    h.set("shield-label", Math.ceil(p.shield));

    document.querySelector("#mat-wood .mat-count").textContent = p.mats.wood;
    document.querySelector("#mat-brick .mat-count").textContent = p.mats.brick;
    document.querySelector("#mat-metal .mat-count").textContent = p.mats.metal;

    if (p.hitFlash > 0.08) document.getElementById("hud").classList.add("hurt");
    else document.getElementById("hud").classList.remove("hurt");

    if (this.invDirty) { this._buildInventoryDom(); this.invDirty = false; }
    else this._updateInventoryAmmo();
  }

  _buildInventoryDom() {
    const inv = document.getElementById("inventory");
    inv.innerHTML = "";
    this.player.slots.forEach((w, i) => {
      const slot = document.createElement("div");
      slot.className = "slot" + (i === this.player.slot ? " active" : "") + (w ? "" : " empty");
      if (w) {
        slot.innerHTML = `<div class="rarity" style="background:${w.rarityColor}"></div>` +
          `<span>${w.icon}</span><span class="ammo">${w.ammoInMag}/${this.player.ammo[w.ammoType] || 0}</span>`;
      } else {
        slot.innerHTML = `<span style="opacity:.4">${i + 1}</span>`;
      }
      slot.addEventListener("touchstart", (e) => { e.preventDefault(); this._selectSlot(i); }, { passive: false });
      slot.addEventListener("mousedown", () => this._selectSlot(i));
      inv.appendChild(slot);
    });
  }

  _updateInventoryAmmo() {
    const slots = document.querySelectorAll("#inventory .slot");
    this.player.slots.forEach((w, i) => {
      const el = slots[i]; if (!el) return;
      const ammoEl = el.querySelector(".ammo");
      if (w && ammoEl) ammoEl.textContent = `${w.ammoInMag}/${this.player.ammo[w.ammoType] || 0}`;
      el.classList.toggle("active", i === this.player.slot);
    });
  }

  _selectSlot(i) {
    if (!this.player.slots[i]) return;
    this.player.slot = i;
    this.invDirty = true;
  }
}
