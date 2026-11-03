// Vector assets (logo, icons, glows, connector paths) rendered to PNG via sharp.
const sharp = require("sharp");

const ICONS = {
  cart: '<circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/>',
  chat: '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/><path d="M8 12h.01M12 12h.01M16 12h.01"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  exit: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
  truck: '<path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2"/><path d="M15 18H9"/><path d="M19 18h2a1 1 0 0 0 1-1v-3.65a1 1 0 0 0-.22-.624l-3.48-4.35A1 1 0 0 0 17.52 8H14"/><circle cx="17" cy="18" r="2"/><circle cx="7" cy="18" r="2"/>',
  ruler: '<path d="M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.41 2.41 0 0 1 0-3.4l2.6-2.6a2.41 2.41 0 0 1 3.4 0Z"/><path d="m14.5 12.5 2-2"/><path d="m11.5 9.5 2-2"/><path d="m8.5 6.5 2-2"/><path d="m17.5 15.5 2-2"/>',
  cash: '<rect width="20" height="12" x="2" y="6" rx="2"/><circle cx="12" cy="12" r="2"/><path d="M6 12h.01M18 12h.01"/>',
  sliders: '<path d="M21 4h-7M10 4H3M21 12h-9M8 12H3M21 20h-5M12 20H3M14 2v4M8 10v4M16 18v4"/>',
  shield: '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>',
  pin: '<path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/>',
  zap: '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>',
  package: '<path d="M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z"/><path d="M12 22V12"/><path d="m3.3 7 8.7 5 8.7-5"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
};

async function icon(name, color, px = 256, stroke = 2) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="0 0 24 24" fill="none" stroke="#${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`;
  return toData(svg);
}

async function toData(svg) {
  const buf = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + buf.toString("base64");
}

// Logo: rounded chat-bubble tile (cyan -> green) with a white cart and a check inside the basket.
async function logo(px = 1024) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="0 0 200 200">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#3CE7E2"/><stop offset="1" stop-color="#25D366"/>
    </linearGradient>
  </defs>
  <path d="M40 14 H160 A30 30 0 0 1 190 44 V128 A30 30 0 0 1 160 158 H82 L46 188 L50 158 H40 A30 30 0 0 1 10 128 V44 A30 30 0 0 1 40 14 Z" fill="url(#g)"/>
  <g fill="none" stroke="#070B1B" stroke-width="11" stroke-linecap="round" stroke-linejoin="round">
    <path d="M44 48 H60 L76 112 H142 L156 66 H66"/>
  </g>
  <circle cx="84" cy="134" r="8" fill="#070B1B"/>
  <circle cx="134" cy="134" r="8" fill="#070B1B"/>
  <path d="M92 86 L106 99 L132 74" fill="none" stroke="#F5F7FB" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
  return toData(svg);
}

// Soft ambient glows for a dark slide (full-bleed, transparent PNG).
async function glow(spots, w = 1920, h = 1080) {
  const defs = spots.map((s, i) =>
    `<radialGradient id="r${i}" cx="${s.x}" cy="${s.y}" r="${s.r}" gradientUnits="userSpaceOnUse">
       <stop offset="0" stop-color="#${s.c}" stop-opacity="${s.o}"/><stop offset="1" stop-color="#${s.c}" stop-opacity="0"/>
     </radialGradient>`).join("");
  const rects = spots.map((s, i) => `<rect width="${w}" height="${h}" fill="url(#r${i})"/>`).join("");
  // faint dot grid for texture
  let dots = "";
  for (let y = 40; y < h; y += 48) for (let x = 40; x < w; x += 48) dots += `<circle cx="${x}" cy="${y}" r="1.3"/>`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><defs>${defs}</defs>${rects}<g fill="#F5F7FB" fill-opacity="0.05">${dots}</g></svg>`;
  return toData(svg);
}

// Generic glowing gradient path. pts in inches relative to box origin; ppi pixels per inch.
async function pathImage({ w, h, d, colors, width = 6, ppi = 150, dash = null }) {
  const W = Math.round(w * ppi), H = Math.round(h * ppi);
  const stops = colors.map((c, i) => `<stop offset="${i / (colors.length - 1)}" stop-color="#${c}"/>`).join("");
  const dashAttr = dash ? `stroke-dasharray="${dash}"` : "";
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${w * 100} ${h * 100}">
   <defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="0">${stops}</linearGradient>
   <filter id="b" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="6"/></filter></defs>
   <path d="${d}" fill="none" stroke="url(#lg)" stroke-width="${width * 3}" stroke-opacity="0.35" stroke-linecap="round" filter="url(#b)"/>
   <path d="${d}" fill="none" stroke="url(#lg)" stroke-width="${width}" stroke-linecap="round" ${dashAttr}/>
  </svg>`;
  return toData(svg);
}

module.exports = { icon, logo, glow, pathImage };
