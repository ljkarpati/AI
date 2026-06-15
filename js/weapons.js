// Weapon definitions and loot rarity data.

export const RARITY = {
  common:    { name: "Common",    color: "#9aa0a6" },
  uncommon:  { name: "Uncommon",  color: "#5fd35f" },
  rare:      { name: "Rare",      color: "#4c8bf5" },
  epic:      { name: "Epic",      color: "#b06bff" },
  legendary: { name: "Legendary", color: "#ffb13d" },
};

// damage is per shot; fireRate in shots/sec; spread in radians; speed px/s; range px.
export const WEAPONS = {
  pistol: {
    id: "pistol", name: "Pistol", icon: "🔫", auto: false,
    damage: 24, fireRate: 4.5, spread: 0.05, speed: 900, range: 520,
    mag: 16, reload: 1.1, pellets: 1, ammoType: "light",
  },
  ar: {
    id: "ar", name: "Assault Rifle", icon: "🔫", auto: true,
    damage: 30, fireRate: 7, spread: 0.07, speed: 1000, range: 640,
    mag: 30, reload: 2.2, pellets: 1, ammoType: "medium",
  },
  smg: {
    id: "smg", name: "SMG", icon: "🔫", auto: true,
    damage: 17, fireRate: 12, spread: 0.11, speed: 950, range: 460,
    mag: 35, reload: 1.8, pellets: 1, ammoType: "light",
  },
  shotgun: {
    id: "shotgun", name: "Shotgun", icon: "🔫", auto: false,
    damage: 9, fireRate: 1.3, spread: 0.34, speed: 800, range: 300,
    mag: 6, reload: 2.6, pellets: 9, ammoType: "shells",
  },
  sniper: {
    id: "sniper", name: "Sniper", icon: "🔫", auto: false,
    damage: 105, fireRate: 0.6, spread: 0.004, speed: 1600, range: 1100,
    mag: 5, reload: 3.0, pellets: 1, ammoType: "heavy",
  },
};

// Per-rarity multipliers applied to a base weapon to make loot feel varied.
export const RARITY_MULT = {
  common:    1.0,
  uncommon:  1.08,
  rare:      1.18,
  epic:      1.28,
  legendary: 1.4,
};

const RARITY_ORDER = ["common", "uncommon", "rare", "epic", "legendary"];

// Create a concrete weapon instance with rolled stats.
export function makeWeapon(baseId, rarity) {
  const base = WEAPONS[baseId];
  const mult = RARITY_MULT[rarity];
  return {
    base: baseId,
    name: base.name,
    icon: base.icon,
    auto: base.auto,
    rarity,
    rarityColor: RARITY[rarity].color,
    damage: Math.round(base.damage * mult),
    fireRate: base.fireRate,
    spread: base.spread,
    speed: base.speed,
    range: base.range,
    pellets: base.pellets,
    reloadTime: base.reload,
    ammoType: base.ammoType,
    magSize: base.mag,
    ammoInMag: base.mag,
  };
}

// Weighted random loot drop. Better rarities are rarer.
export function rollWeapon(luck = 0) {
  const ids = Object.keys(WEAPONS);
  const baseId = ids[Math.floor(Math.random() * ids.length)];
  const r = Math.random() - luck * 0.15;
  let rarity;
  if (r > 0.97) rarity = "legendary";
  else if (r > 0.88) rarity = "epic";
  else if (r > 0.68) rarity = "rare";
  else if (r > 0.40) rarity = "uncommon";
  else rarity = "common";
  return makeWeapon(baseId, rarity);
}

export function rarityRank(rarity) { return RARITY_ORDER.indexOf(rarity); }
