// Touch input: two floating virtual joysticks (move + aim/fire) and action buttons.
// Falls back to keyboard + mouse on desktop for easy testing.

export class Input {
  constructor() {
    this.move = { x: 0, y: 0, active: false };
    this.aim = { x: 0, y: 0, active: false, mag: 0 };
    this.firing = false;

    // Edge-triggered button events consumed by the game each frame.
    this.buildToggle = false;
    this.reload = false;
    this.placeBuild = false;
    this.selectPiece = null;
    this.harvesting = false;

    this._leftId = null;
    this._rightId = null;
    this._knobs = {};

    this._setupSticks();
    this._setupButtons();
    this._setupKeyboard();
  }

  _makeKnob(zone, color) {
    const base = document.createElement("div");
    base.className = "stick-base";
    const knob = document.createElement("div");
    knob.className = "stick-knob";
    base.style.display = "none";
    knob.style.display = "none";
    zone.appendChild(base);
    zone.appendChild(knob);
    return { base, knob, origin: { x: 0, y: 0 } };
  }

  _setupSticks() {
    const left = document.getElementById("stick-left");
    const right = document.getElementById("stick-right");
    this._knobs.left = this._makeKnob(left);
    this._knobs.right = this._makeKnob(right);

    const RADIUS = 60;

    const start = (zone, which, t) => {
      const k = this._knobs[which];
      k.origin = { x: t.clientX, y: t.clientY };
      k.base.style.display = k.knob.style.display = "block";
      k.base.style.left = k.knob.style.left = t.clientX + "px";
      k.base.style.top = k.knob.style.top = t.clientY + "px";
      if (which === "left") { this.move.active = true; }
      else { this.aim.active = true; this.firing = true; }
    };

    const moveStick = (which, t) => {
      const k = this._knobs[which];
      let dx = t.clientX - k.origin.x;
      let dy = t.clientY - k.origin.y;
      const len = Math.hypot(dx, dy) || 1;
      const clamped = Math.min(len, RADIUS);
      const nx = (dx / len), ny = (dy / len);
      k.knob.style.left = (k.origin.x + nx * clamped) + "px";
      k.knob.style.top = (k.origin.y + ny * clamped) + "px";
      const mag = clamped / RADIUS;
      if (which === "left") {
        const dead = 0.18;
        if (mag < dead) { this.move.x = 0; this.move.y = 0; }
        else { this.move.x = nx * mag; this.move.y = ny * mag; }
      } else {
        this.aim.x = nx; this.aim.y = ny; this.aim.mag = mag;
      }
    };

    const end = (which) => {
      const k = this._knobs[which];
      k.base.style.display = k.knob.style.display = "none";
      if (which === "left") { this.move.x = 0; this.move.y = 0; this.move.active = false; this._leftId = null; }
      else {
        this.aim.active = false; this.firing = false; this.aim.mag = 0;
        if (this.buildMode) this.placeBuild = true; // tap on right stick places a build piece
        this._rightId = null;
      }
    };

    document.addEventListener("touchstart", (e) => {
      for (const t of e.changedTouches) {
        // Ignore touches that land on HUD controls so buttons don't also drive a stick.
        if (t.target && t.target.closest && t.target.closest("button, #inventory, #actions, #build-bar")) continue;
        const leftZone = document.getElementById("stick-left");
        const rightZone = document.getElementById("stick-right");
        const onLeft = this._inZone(leftZone, t);
        const onRight = this._inZone(rightZone, t);
        if (onLeft && this._leftId === null) { this._leftId = t.identifier; start(leftZone, "left", t); }
        else if (onRight && this._rightId === null) { this._rightId = t.identifier; start(rightZone, "right", t); }
      }
    }, { passive: true });

    document.addEventListener("touchmove", (e) => {
      for (const t of e.changedTouches) {
        if (t.identifier === this._leftId) moveStick("left", t);
        else if (t.identifier === this._rightId) moveStick("right", t);
      }
    }, { passive: true });

    const onEnd = (e) => {
      for (const t of e.changedTouches) {
        if (t.identifier === this._leftId) end("left");
        else if (t.identifier === this._rightId) end("right");
      }
    };
    document.addEventListener("touchend", onEnd, { passive: true });
    document.addEventListener("touchcancel", onEnd, { passive: true });
  }

  _inZone(zone, t) {
    const r = zone.getBoundingClientRect();
    return t.clientX >= r.left && t.clientX <= r.right && t.clientY >= r.top && t.clientY <= r.bottom;
  }

  _setupButtons() {
    const tap = (id, fn) => {
      const el = document.getElementById(id);
      if (!el) return;
      el.addEventListener("touchstart", (e) => { e.preventDefault(); fn(true, el); }, { passive: false });
      el.addEventListener("touchend", (e) => { e.preventDefault(); fn(false, el); }, { passive: false });
      el.addEventListener("mousedown", () => fn(true, el));
      el.addEventListener("mouseup", () => fn(false, el));
    };

    tap("btn-build", (down) => { if (down) this.buildToggle = true; });
    tap("btn-reload", (down) => { if (down) this.reload = true; });
    tap("btn-harvest", (down) => { this.harvesting = down; });

    document.querySelectorAll(".build-piece").forEach((btn) => {
      const sel = (e) => { e.preventDefault(); this.selectPiece = btn.dataset.piece; };
      btn.addEventListener("touchstart", sel, { passive: false });
      btn.addEventListener("mousedown", sel);
    });
  }

  // Desktop fallback: WASD move, mouse aim+click fire, B build, R reload, Space harvest.
  _setupKeyboard() {
    const keys = {};
    this._keys = keys;
    window.addEventListener("keydown", (e) => {
      keys[e.key.toLowerCase()] = true;
      if (e.key.toLowerCase() === "b") this.buildToggle = true;
      if (e.key.toLowerCase() === "r") this.reload = true;
      if ("1234".includes(e.key)) this.selectPiece = ["wall", "ramp", "floor", "cone"][+e.key - 1];
    });
    window.addEventListener("keyup", (e) => { keys[e.key.toLowerCase()] = false; });

    const canvas = document.getElementById("game");
    window.addEventListener("mousemove", (e) => { this._mouse = { x: e.clientX, y: e.clientY }; });
    canvas.addEventListener("mousedown", (e) => {
      if (e.target.closest("button")) return;
      this.firing = true; this._mouseDown = true;
      if (this.buildMode) this.placeBuild = true;
    });
    window.addEventListener("mouseup", () => { this.firing = false; this._mouseDown = false; });
  }

  // Pull keyboard movement into the move vector each frame (desktop only).
  pollKeyboard(playerScreenX, playerScreenY) {
    if (!this._keys) return;
    let x = 0, y = 0;
    if (this._keys["w"] || this._keys["arrowup"]) y -= 1;
    if (this._keys["s"] || this._keys["arrowdown"]) y += 1;
    if (this._keys["a"] || this._keys["arrowleft"]) x -= 1;
    if (this._keys["d"] || this._keys["arrowright"]) x += 1;
    if (x || y) {
      const l = Math.hypot(x, y);
      this.move.x = x / l; this.move.y = y / l; this.move.active = true;
    } else if (!this.move.active) {
      this.move.x = 0; this.move.y = 0;
    }
    this.harvesting = !!this._keys[" "];
    // Mouse aim relative to player position on screen.
    if (this._mouse && playerScreenX != null) {
      const dx = this._mouse.x - playerScreenX, dy = this._mouse.y - playerScreenY;
      const l = Math.hypot(dx, dy) || 1;
      this.aim.x = dx / l; this.aim.y = dy / l; this.aim.mag = 1; this.aim.active = true;
    }
  }

  // Called by the game after reading the edge-triggered flags.
  consume() {
    const out = {
      buildToggle: this.buildToggle,
      reload: this.reload,
      placeBuild: this.placeBuild,
      selectPiece: this.selectPiece,
    };
    this.buildToggle = false;
    this.reload = false;
    this.placeBuild = false;
    this.selectPiece = null;
    return out;
  }
}
