# MiniCraft 🎮⛏️

A tiny Minecraft-style voxel game that runs entirely in the browser — no install, no build step, one HTML file. Designed for iPhone (touch controls), but works on desktop too.

## Play on your iPhone

The game is just `index.html`. Any way you can open that file over HTTPS works:

1. **GitHub Pages (recommended):** enable Pages for this repo (Settings → Pages → deploy from branch), then open the page URL in Safari on your phone.
2. **Any static host:** drop `index.html` on Netlify, Vercel, etc.
3. **Local network:** run `python3 -m http.server` in this folder on a computer and open `http://<computer-ip>:8000` from your phone on the same Wi-Fi.

Tip: in Safari use **Share → Add to Home Screen** to play fullscreen without browser chrome.

## Controls

**iPhone / touch**
- Left half of screen: virtual joystick to move
- Right half: drag to look around
- Tap: mine the block under the crosshair (or place, if a block is selected in the hotbar)
- ▲ button: jump (hold to keep hopping / swim up)
- Hotbar (bottom): first slot ⛏️ = mine mode, other slots place that block
- ⟳ (top right): generate a fresh world

**Desktop**
- Click to capture the mouse, WASD/arrows to move, Space to jump
- Left click: mine • Right click: place • Keys 1–8: select hotbar slot

## Features

- Procedurally generated 128×128 voxel world: hills, mountains with snow caps, sandy beaches, water, and trees
- Mine and place blocks (grass, dirt, stone, sand, logs, planks, snow)
- Walking, jumping, swimming, gravity and proper block collision
- Procedural pixel-art textures (no asset files), per-face lighting and fog
- Your edits are saved automatically in the browser (localStorage), per world seed
- Only dependency is Three.js, loaded from a CDN
