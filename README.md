# Storm Royale 🌀

A touch-first **battle royale** game built for iPhone (and any modern browser). It captures the
Fortnite signatures in a fast 2D top-down format: drop in, loot weapons, **build** instant cover,
fight 49 bots, and survive the shrinking storm to win a **Victory Royale**.

It's a pure HTML5 + Canvas web game with **no build step and no dependencies**, installable to your
iPhone Home Screen as a full-screen app (PWA) and playable offline.

> Why a web game and not a native iOS app? A native app requires Xcode on a Mac to compile and an
> Apple Developer account to install on a device. This web version runs instantly in mobile Safari,
> installs to the Home Screen, and plays full-screen — no Mac, Xcode, or App Store needed.

## Features

- **Twin-stick touch controls** — left stick moves, right stick aims and auto-fires. Floating
  joysticks appear wherever you place your thumbs.
- **Building** — drop walls, ramps, floors and cones on a grid for instant cover. Pick wood, brick
  or metal (auto-selected by what you're carrying); each has different HP.
- **Harvesting** — swing your pickaxe at trees, rocks and metal to gather materials.
- **Loot & rarity** — 5 weapon types (pistol, AR, SMG, shotgun, sniper) across 5 rarities
  (common → legendary) with rolled stats. Open chests and grab floor loot for guns, ammo, shields
  and healing.
- **Shields & health** — shield potions absorb damage before HP, just like the real thing.
- **The storm** — a safe circle that shrinks in phases and deals escalating damage outside.
- **Bots with AI** — 49 opponents that wander, loot, take cover by building, fight and flee.
- **HUD & minimap** — players-alive counter, eliminations, storm timer, materials, inventory slots
  and a live minimap.
- **Installable PWA** — add to Home Screen for a full-screen, offline-capable app.

## How to play

| Control | Action |
| --- | --- |
| **Left stick** | Move |
| **Right stick** | Aim & auto-fire (release in build mode to place a piece) |
| 🧱 **Build** | Toggle build mode, then pick a piece and tap the right stick to place it |
| ⛏️ **Harvest** | Hold to swing your pickaxe at trees, rocks and walls |
| 🔄 **Reload** | Reload the current weapon |
| Inventory slots | Tap to switch weapons |

Stay inside the white circle, eliminate everyone else, and be the **last one standing**.

**Desktop testing:** WASD to move, mouse to aim, click to fire, `B` build, `R` reload,
`Space` harvest, `1`–`4` to choose a build piece.

## Run it

It's static files — serve the folder over HTTP (ES modules require `http://`, not `file://`):

```bash
# from the project root
python3 -m http.server 8000
# then open http://localhost:8000 on your computer,
# or http://<your-computer-ip>:8000 in iPhone Safari on the same Wi-Fi
```

### Install on your iPhone

1. Open the URL in **Safari** on your iPhone.
2. Tap the **Share** button → **Add to Home Screen**.
3. Launch it from the Home Screen for a full-screen, no-browser-chrome experience.

For a public link, host the folder on any static host (GitHub Pages, Netlify, Vercel, Cloudflare
Pages) — no server code required.

## Project structure

```
index.html              Game shell, HUD markup, PWA meta tags
css/style.css           Full-screen mobile layout, HUD, joysticks
js/
  main.js               Entry point: menus, HUD helpers, wiring
  game.js               Core loop, physics, combat, loot, storm, rendering
  world.js              Map generation, build grid, resources, chests, storm
  entities.js           Player and Bot (with AI)
  weapons.js            Weapon stats and loot rarity rolls
  input.js              Touch joysticks + buttons (keyboard/mouse fallback)
  utils.js              Math and collision helpers
manifest.webmanifest    PWA manifest
sw.js                   Service worker (offline + installable)
icons/                  App icons (generated)
tools/gen-icons.mjs     Regenerates the PNG icons (node tools/gen-icons.mjs)
```

## Notes & limitations

- The world is 2D top-down, so "ramps/floors" act as cover pieces rather than changing elevation.
- Opponents are bots, not networked players — it's a single-player battle royale against AI.
- Tuning (storm timing, damage, bot skill, loot rates) lives at the top of `world.js`,
  `weapons.js` and `entities.js` if you want to adjust the feel.
