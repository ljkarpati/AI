// Entry point: wires menus, HUD helpers, input and the game together.
import { Game } from "./game.js";
import { Input } from "./input.js";

// Tiny HUD helper used by the game to update DOM cheaply.
const hud = {
  _cache: {},
  el(id) { return this._cache[id] || (this._cache[id] = document.getElementById(id)); },
  set(id, val) { const e = this.el(id); if (e && e.textContent != val) e.textContent = val; },
  fill(id, frac) { const e = this.el(id); if (e) e.style.width = (Math.max(0, Math.min(1, frac)) * 100) + "%"; },
  showResult(victory, place, kills) {
    const r = document.getElementById("result");
    const title = document.getElementById("result-title");
    title.textContent = victory ? "VICTORY ROYALE 👑" : "ELIMINATED";
    title.className = victory ? "victory" : "defeat";
    document.getElementById("result-sub").textContent = victory
      ? "You are the last one standing!"
      : "You placed well. Drop in again?";
    document.getElementById("res-place").textContent = "#" + place;
    document.getElementById("res-kills").textContent = kills;
    document.getElementById("hud").classList.add("hidden");
    r.classList.remove("hidden");
  },
};

const canvas = document.getElementById("game");
const input = new Input();
const game = new Game(canvas, input, hud);

function show(id) { document.getElementById(id).classList.remove("hidden"); }
function hide(id) { document.getElementById(id).classList.add("hidden"); }

function startMatch() {
  hide("menu"); hide("howto"); hide("result");
  game.start();
}

document.getElementById("btn-play").addEventListener("click", startMatch);
document.getElementById("btn-again").addEventListener("click", startMatch);
document.getElementById("btn-howto").addEventListener("click", () => { hide("menu"); show("howto"); });
document.getElementById("btn-back").addEventListener("click", () => { hide("howto"); show("menu"); });

// Prevent iOS double-tap zoom / scroll bounce on the game UI.
document.addEventListener("gesturestart", (e) => e.preventDefault());
document.addEventListener("dblclick", (e) => e.preventDefault(), { passive: false });
document.body.addEventListener("touchmove", (e) => { if (e.target.closest("#hud, #game")) e.preventDefault(); }, { passive: false });

// Register service worker for offline / installable PWA (best-effort).
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  });
}
