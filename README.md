# Storm Royale 🌀

A touch-first **battle royale** game that runs entirely in the browser — no install, no build step,
**one HTML file**. Designed for iPhone (touch controls), but works on desktop too. It captures the
Fortnite signatures in a fast 2D top-down format: drop in, loot weapons, **build** instant cover,
fight bots, and survive the shrinking storm to win a **Victory Royale**.

The whole game is `index.html` — pure HTML5 + Canvas with **zero dependencies**. Just open it.

## Play on your iPhone

The game is just `index.html`. Any way you can open that file works:

1. **GitHub Pages (recommended):** enable Pages for this repo (Settings → Pages → deploy from
   the `claude/fortnite-clone-iphone-1x1dba` branch), then open the page URL in Safari on your phone.
2. **Any static host:** drop `index.html` on Netlify, Vercel, Cloudflare Pages, etc.
3. **Local network:** run `python3 -m http.server` in this folder on a computer and open
   `http://<computer-ip>:8000` from your phone on the same Wi-Fi.
4. **Straight from the file:** you can even open `index.html` directly in a browser — it's
   self-contained and needs no server.

Tip: in Safari use **Share → Add to Home Screen** to play full-screen without browser chrome.

## How to play

**iPhone / touch**

| Control | Action |
| --- | --- |
| **Left stick** | Move (floating joystick — touch the left half of the screen) |
| **Right stick** | Aim & auto-fire (touch the right half) |
| 🧱 **Build** | Toggle build mode, pick a piece, then release the right stick to place it |
| ⛏️ **Harvest** | Hold to swing your pickaxe at trees, rocks and walls for materials |
| 🔄 **Reload** | Reload the current weapon |
| Inventory slots | Tap to switch weapons |

Stay inside the white circle, eliminate everyone else, and be the **last one standing**.

**Desktop**

WASD/arrows to move, mouse to aim, click to fire, `B` build, `R` reload, `Space` harvest,
`1`–`4` to choose a build piece.

## Features

- **Twin-stick touch controls** with floating joysticks that appear under your thumbs.
- **Building** — drop walls, ramps, floors and cones on a grid for instant cover, in wood, brick or
  metal (auto-selected by what you're carrying), each with different HP.
- **Harvesting** — gather materials from trees, rocks and metal with your pickaxe.
- **Loot & rarity** — 5 weapon types (pistol, AR, SMG, shotgun, sniper) across 5 rarities
  (common → legendary) with rolled stats. Open chests and grab floor loot for guns, ammo, shields
  and healing.
- **Shields & health** — shield potions absorb damage before HP.
- **The storm** — a safe circle that shrinks in phases and deals escalating damage outside.
- **Bots with AI** — opponents that wander, loot, take cover by building, fight and flee.
- **HUD & minimap** — players-alive counter, eliminations, storm timer, materials and inventory.
- **Add to Home Screen** for a full-screen, app-like experience on iPhone.

## Notes

- The world is 2D top-down, so "ramps/floors" act as cover pieces rather than changing elevation.
- Opponents are bots, not networked players — it's a single-player battle royale against AI.
- Everything lives in `index.html`; gameplay tuning (storm timing, damage, bot skill, loot rates)
  is in the inlined script near the `World`, `weapons` and `Bot` definitions.
