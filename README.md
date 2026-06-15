# Storm Royale 3D 🌀

A **3D battle royale** that runs entirely in the browser — no install, no build step, **one HTML
file**. Designed for iPhone (touch controls), but works on desktop too. Drop in, fight bots, build
walls for cover, and survive the shrinking storm to win a **Victory Royale**.

The whole game is `index.html`. The only dependency is Three.js, loaded from a CDN. Just open it.

## Play on your iPhone

The game is just `index.html`. Any way you can open that file (over the internet) works:

1. **Shareable link (no setup):** open the game through githack, which serves the file from GitHub
   as a real web page. See the link your assistant gave you, or build one as
   `https://raw.githack.com/<user>/<repo>/<commit>/index.html`.
2. **Any static host:** drop `index.html` on Netlify, Vercel, Cloudflare Pages, or GitHub Pages.
3. **Local network:** run `python3 -m http.server` in this folder and open
   `http://<computer-ip>:8000` from your phone on the same Wi-Fi.

> Note: because it loads Three.js from a CDN, it needs an internet connection (so opening the file
> straight off disk with no network won't load the engine).

Tip: in Safari use **Share → Add to Home Screen** to play full-screen.

## Controls

**iPhone / touch**

| Control | Action |
| --- | --- |
| **Left side** | Drag to move (a floating joystick appears) |
| **Right side** | Drag to look / turn the camera |
| 🔫 **Fire** | Hold — it **auto-aims** at the nearest enemy in front of you |
| 🧱 **Build** | Tap to drop a wall in front of you for cover |
| ➕ **Heal** | Use a shield potion |
| ⤴︎ **Jump** | Jump |

**Desktop:** WASD/arrows to move, click the screen to capture the mouse and look, hold click to
fire, `B` build, `E` heal, `Space` jump.

Stay inside the circle, eliminate everyone else, and be the **last one standing**.

## Design notes

- **Aim assist:** firing locks onto the nearest enemy within range and a frontal cone (with a
  line-of-sight check), so you don't need pixel-perfect aim on a touchscreen.
- **Survivability:** you start with 100 HP + 50 shield, heal and shield up from chests, and enemy
  fire is modest and falls off with distance — engagements are winnable, not instant death.
- **One-tap building:** tap Build to place a wall; you carry plenty of wood and chests refill it.
- It's a single-player battle royale against 14 AI bots; the storm shrinks in phases.
- Everything (and all the tuning — health, damage, bot skill, storm timing) lives in `index.html`.
