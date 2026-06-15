// Generates the app icons as real PNGs without any image library.
// Draws a dark badge with a storm ring and a golden drop triangle.
import zlib from "node:zlib";
import fs from "node:fs";

const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return (buf) => {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = t[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
})();

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, "ascii");
  const body = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(CRC(body), 0);
  return Buffer.concat([len, body, crc]);
}

function makePng(size, draw) {
  const px = new Uint8Array(size * size * 4);
  draw((x, y, r, g, b, a = 255) => {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    const i = (y * size + x) * 4;
    px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a;
  }, size);

  // Filtered raw data (filter byte 0 per row).
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0;
    px.subarray(y * size * 4, (y + 1) * size * 4)
      .forEach((v, idx) => { raw[y * (size * 4 + 1) + 1 + idx] = v; });
  }
  const idat = zlib.deflateSync(raw, { level: 9 });

  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // color type RGBA
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;

  return Buffer.concat([sig, chunk("IHDR", ihdr), chunk("IDAT", idat), chunk("IEND", Buffer.alloc(0))]);
}

function draw(set, S) {
  const cx = S / 2, cy = S / 2;
  const lerp = (a, b, t) => a + (b - a) * t;
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      // Rounded badge background with vertical gradient.
      const margin = S * 0.06, radius = S * 0.22;
      const inX = x > margin && x < S - margin;
      const inY = y > margin && y < S - margin;
      const corner = (px, py) =>
        Math.hypot(x - px, y - py) <= radius;
      let inside = inX && inY;
      // carve rounded corners
      if (x < margin + radius && y < margin + radius && !corner(margin + radius, margin + radius)) inside = false;
      if (x > S - margin - radius && y < margin + radius && !corner(S - margin - radius, margin + radius)) inside = false;
      if (x < margin + radius && y > S - margin - radius && !corner(margin + radius, S - margin - radius)) inside = false;
      if (x > S - margin - radius && y > S - margin - radius && !corner(S - margin - radius, S - margin - radius)) inside = false;
      if (!inside) { set(x, y, 0, 0, 0, 0); continue; }

      const t = y / S;
      let r = Math.round(lerp(18, 9, t));
      let g = Math.round(lerp(30, 16, t));
      let b = Math.round(lerp(70, 36, t));

      // Storm ring.
      const d = Math.hypot(x - cx, y - cy);
      const ringR = S * 0.32, ringW = S * 0.035;
      if (Math.abs(d - ringR) < ringW) {
        const k = 1 - Math.abs(d - ringR) / ringW;
        r = Math.round(lerp(r, 168, k)); g = Math.round(lerp(g, 120, k)); b = Math.round(lerp(b, 245, k));
      }

      // Golden drop triangle in the center.
      const triH = S * 0.30, triW = S * 0.22;
      const topY = cy - triH * 0.5;
      const ty = (y - topY) / triH;
      if (ty >= 0 && ty <= 1) {
        const halfW = lerp(0, triW * 0.5, ty);
        if (Math.abs(x - cx) < halfW) {
          r = Math.round(lerp(255, 230, ty)); g = Math.round(lerp(220, 150, ty)); b = Math.round(lerp(90, 40, ty));
        }
      }
      set(x, y, r, g, b, 255);
    }
  }
}

for (const size of [192, 512, 180]) {
  const png = makePng(size, draw);
  fs.writeFileSync(new URL(`../icons/icon-${size}.png`, import.meta.url), png);
  console.log(`wrote icons/icon-${size}.png (${png.length} bytes)`);
}
