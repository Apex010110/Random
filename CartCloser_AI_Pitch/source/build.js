// CartCloser AI — IGNITE XIII 3-slide animated pitch.
// Usage: node build.js final <out.pptx>     -> animated deck (native OOXML timing injected)
//        node build.js stages <out.pptx>    -> one slide per build stage (for preview video)
const pptxgen = require("pptxgenjs");
const JSZip = require("jszip");
const fs = require("fs");
const A = require("./assets");
const NOTES = require("./notes");

const COL = {
  ink: "070B1B", navy: "0D1631", navy2: "141E3D", cyan: "3CE7E2", green: "25D366",
  white: "F5F7FB", muted: "A9B3CC", dim: "6E7A99", coral: "FF6B70",
  waScreen: "0B141A", waIn: "1F2C34", waOut: "005C4B", waHead: "1A252D",
};
const FONT = "Inter";

// ---------------------------------------------------------------- animation spec
// trigger: "auto" (plays on slide entry, after transition) | "click"
// step: { g: group, fx, at: ms offset inside the click, dur }
const ANIM = {
  1: [
    { trigger: "auto", steps: [
      { g: "glow", fx: "fade", at: 0, dur: 600 },
      { g: "logo", fx: "zoom", at: 300, dur: 700 },
      { g: "name", fx: "up", at: 800, dur: 600 },
      { g: "tag1", fx: "up", at: 1250, dur: 600 },
      { g: "tag2", fx: "up", at: 1650, dur: 600 },
    ]},
    { trigger: "click", steps: [
      { g: "node1", fx: "zoom", at: 0, dur: 500 },
      { g: "path", fx: "wipeR", at: 400, dur: 2000 },
      { g: "node2", fx: "zoom", at: 1150, dur: 500 },
      { g: "node3", fx: "zoom", at: 2250, dur: 500 },
      { g: "node3", fx: "pulse", at: 2800, dur: 300 },
    ]},
    { trigger: "click", steps: [
      { g: "vision", fx: "up", at: 0, dur: 700 },
    ]},
  ],
  2: [
    { trigger: "click", steps: [
      { g: "row1", fx: "up", at: 0, dur: 500 },
    ]},
    { trigger: "click", steps: [
      { g: "conn1", fx: "wipeD", at: 0, dur: 400 },
      { g: "row2", fx: "up", at: 300, dur: 500 },
      { g: "chip", fx: "fade", at: 700, dur: 400 },
      { g: "bot1", fx: "up", at: 1000, dur: 450 },
      { g: "user1", fx: "up", at: 1900, dur: 450 },
      { g: "typing", fx: "fade", at: 2600, dur: 250 },
      { g: "typing", fx: "exit", at: 3600, dur: 200 },
      { g: "bot2", fx: "up", at: 3700, dur: 450 },
    ]},
    { trigger: "click", steps: [
      { g: "user2", fx: "up", at: 0, dur: 450 },
      { g: "bot3", fx: "up", at: 1000, dur: 500 },
    ]},
    { trigger: "click", steps: [
      { g: "conn2", fx: "wipeD", at: 0, dur: 400 },
      { g: "row3", fx: "up", at: 300, dur: 500 },
      { g: "confirm", fx: "zoom", at: 800, dur: 500 },
      { g: "confirm", fx: "pulse", at: 1350, dur: 300 },
    ]},
    { trigger: "click", steps: [
      { g: "merchant", fx: "fade", at: 0, dur: 500 },
      { g: "outcome", fx: "up", at: 400, dur: 700 },
    ]},
  ],
  3: [
    { trigger: "click", steps: [
      { g: "leftLabel", fx: "fade", at: 0, dur: 400 },
      { g: "q1", fx: "up", at: 200, dur: 450 },
      { g: "q2", fx: "up", at: 550, dur: 450 },
      { g: "q3", fx: "up", at: 900, dur: 450 },
    ]},
    { trigger: "click", steps: [
      { g: "linesL", fx: "wipeR", at: 0, dur: 700 },
      { g: "hub", fx: "zoom", at: 550, dur: 500 },
      { g: "linesR", fx: "wipeR", at: 1000, dur: 700 },
      { g: "rightLabel", fx: "fade", at: 1300, dur: 400 },
      { g: "a1", fx: "up", at: 1450, dur: 450 },
      { g: "a2", fx: "up", at: 1800, dur: 450 },
      { g: "a3", fx: "up", at: 2150, dur: 450 },
    ]},
    { trigger: "click", steps: [
      { g: "statement", fx: "up", at: 0, dur: 700 },
      { g: "v1", fx: "up", at: 600, dur: 450 },
      { g: "v2", fx: "up", at: 850, dur: 450 },
      { g: "v3", fx: "up", at: 1100, dur: 450 },
    ]},
  ],
};

// ---------------------------------------------------------------- element registry
function makeCtx(visible) {
  let n = 0;
  return {
    vis: (g) => g === "base" || !visible || visible.has(g),
    name: (g) => `${g}#${++n}`,
  };
}
function api(slide, ctx, pres) {
  const ok = (g) => ctx.vis(g);
  return {
    set background(v) { slide.background = v; },
    rect(g, o) { if (!ok(g)) return; slide.addShape(pres.shapes.RECTANGLE, { ...o, objectName: ctx.name(g) }); },
    rrect(g, o) { if (!ok(g)) return; slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { ...o, objectName: ctx.name(g) }); },
    oval(g, o) { if (!ok(g)) return; slide.addShape(pres.shapes.OVAL, { ...o, objectName: ctx.name(g) }); },
    line(g, o) { if (!ok(g)) return; slide.addShape(pres.shapes.LINE, { ...o, objectName: ctx.name(g) }); },
    text(g, t, o) { if (!ok(g)) return; slide.addText(t, { fontFace: FONT, margin: 0, isTextBox: true, ...o, objectName: ctx.name(g) }); },
    img(g, o) { if (!ok(g)) return; slide.addImage({ altText: "Decorative icon", ...o, objectName: ctx.name(g) }); },
  };
}
const glass = (t = 93) => ({ fill: { color: "FFFFFF", transparency: t }, line: { color: "FFFFFF", transparency: 84, width: 1 } });

// ---------------------------------------------------------------- assets
async function loadAssets() {
  const I = {};
  I.logo = await A.logo();
  for (const [k, n, c] of [
    ["cartCoral", "cart", COL.coral], ["chatCyan", "chat", COL.cyan], ["checkInk", "check", COL.ink],
    ["exitCoral", "exit", COL.coral], ["chatInk", "chat", COL.ink], ["checkGreen", "check", COL.green],
    ["truckCoral", "truck", COL.coral], ["rulerCoral", "ruler", COL.coral], ["cashCoral", "cash", COL.coral],
    ["sliders", "sliders", COL.cyan], ["zap", "zap", COL.cyan], ["pin", "pin", COL.cyan], ["package", "package", COL.cyan],
    ["checkWhite", "check", "FFFFFF"], ["linkGreen", "link", COL.green], ["shieldGreen", "shield", COL.green],
  ]) I[k] = await A.icon(n, c, 256, k === "checkInk" || k === "checkWhite" ? 3 : 2);
  I.glow1 = await A.glow([{ x: 1500, y: 520, r: 760, c: COL.cyan, o: 0.20 }, { x: 260, y: 1000, r: 700, c: COL.green, o: 0.10 }, { x: 1700, y: 1050, r: 500, c: COL.green, o: 0.12 }]);
  I.glow2 = await A.glow([{ x: 1640, y: 420, r: 700, c: COL.green, o: 0.16 }, { x: 120, y: 120, r: 700, c: COL.cyan, o: 0.10 }]);
  I.glow3 = await A.glow([{ x: 960, y: 520, r: 620, c: COL.cyan, o: 0.15 }, { x: 0, y: 520, r: 560, c: COL.coral, o: 0.08 }, { x: 1920, y: 520, r: 560, c: COL.green, o: 0.10 }]);
  // Slide 1 hero path (box x6.9 y1.6 w6.0 h4.6, units = in*100)
  I.heroPath = await A.pathImage({ w: 6.0, h: 4.6, d: "M85 325 C 175 325, 200 115, 305 115 S 430 300, 515 300", colors: [COL.coral, COL.cyan, COL.green], width: 4 });
  // Slide 3 convergence lines
  I.linesL = await A.pathImage({ w: 1.5, h: 2.0, d: "M0 14 C 80 14, 70 99, 150 99 M0 99 L150 99 M0 184 C 80 184, 70 99, 150 99", colors: [COL.coral, COL.cyan], width: 2.5 });
  I.linesR = await A.pathImage({ w: 1.1, h: 2.0, d: "M0 99 C 60 99, 50 14, 110 14 M0 99 L110 99 M0 99 C 60 99, 50 184, 110 184", colors: [COL.cyan, COL.green], width: 2.5 });
  return I;
}

// ---------------------------------------------------------------- slides
function slide1(s, I, pres) {
  s.background = { color: COL.ink };
  s.img("glow", { data: I.glow1, x: 0, y: 0, w: 13.333, h: 7.5, altText: "Ambient glow" });
  s.text("base", [{ text: "IGNITE XIII", options: { bold: true, color: COL.cyan, charSpacing: 3 } }, { text: "   ·   Logistics & E-Commerce  ·  Retail Tech", options: { color: COL.dim } }], { x: 0.9, y: 0.55, w: 8, h: 0.35, fontSize: 13 });

  s.img("logo", { data: I.logo, x: 0.9, y: 1.45, w: 1.55, h: 1.55, altText: "CartCloser AI logo: cart inside a chat bubble with a check mark" });
  s.text("name", [{ text: "CartCloser ", options: { color: COL.white } }, { text: "AI", options: { color: COL.cyan } }], { x: 0.85, y: 3.15, w: 6.3, h: 1.05, fontSize: 60, bold: true });
  s.text("tag1", "Turning abandoned carts", { x: 0.9, y: 4.3, w: 6.2, h: 0.5, fontSize: 27, color: COL.white });
  s.text("tag2", "into conversations.", { x: 0.9, y: 4.8, w: 6.2, h: 0.5, fontSize: 27, color: COL.green, bold: true });

  s.rrect("vision", { x: 0.9, y: 5.75, w: 5.7, h: 1.15, rectRadius: 0.16, ...glass(93) });
  s.text("vision", "OUR VISION", { x: 1.2, y: 5.92, w: 3, h: 0.28, fontSize: 12, bold: true, color: COL.cyan, charSpacing: 3 });
  s.text("vision", "Every online shopper gets the help they need to finish buying.", { x: 1.2, y: 6.2, w: 5.2, h: 0.6, fontSize: 18, color: COL.white });

  // hero journey
  s.img("path", { data: I.heroPath, x: 6.9, y: 1.6, w: 6.0, h: 4.6, altText: "Glowing path from cart to chat to confirmed order" });
  const node = (g, cx, cy, ring, fill, icon, label, labelAbove) => {
    const d = 1.45;
    s.oval(g, { x: cx - d / 2 - 0.12, y: cy - d / 2 - 0.12, w: d + 0.24, h: d + 0.24, fill: { color: ring, transparency: 85 }, line: { color: ring, transparency: 100 } });
    s.oval(g, { x: cx - d / 2, y: cy - d / 2, w: d, h: d, fill: { color: fill }, line: { color: ring, width: 2 } });
    s.img(g, { data: icon, x: cx - 0.36, y: cy - 0.36, w: 0.72, h: 0.72 });
    s.text(g, label, { x: cx - 1.3, y: labelAbove ? cy - d / 2 - 0.68 : cy + d / 2 + 0.25, w: 2.6, h: 0.4, fontSize: 17, bold: true, color: COL.white, align: "center" });
  };
  node("node1", 7.75, 4.85, COL.coral, COL.navy, I.cartCoral, "Cart left behind", false);
  node("node2", 9.95, 2.75, COL.cyan, COL.navy, I.chatCyan, "Helpful chat", true);
  node("node3", 12.05, 4.6, COL.green, COL.green, I.checkInk, "Order completed", false);
}

function slide2(s, I, pres) {
  s.background = { color: COL.ink };
  s.img("base", { data: I.glow2, x: 0, y: 0, w: 13.333, h: 7.5, altText: "Ambient glow" });
  s.text("base", "PRODUCT", { x: 0.8, y: 0.45, w: 3, h: 0.3, fontSize: 13, bold: true, color: COL.cyan, charSpacing: 3 });
  s.text("base", "From abandoned cart to completed order", { x: 0.8, y: 0.78, w: 7.5, h: 1.2, fontSize: 38, bold: true, color: COL.white, valign: "top" });

  const rows = [
    { g: "row1", n: "01", title: "Cart left behind", body: "Shopper exits checkout with a question still unanswered.", icon: I.exitCoral, c: COL.coral, fill: COL.navy },
    { g: "row2", n: "02", title: "AI starts a helpful chat", body: "Only after valid opt-in. Answers size, delivery and COD questions in Urdu or English.", icon: I.chatInk, c: COL.cyan, fill: COL.cyan },
    { g: "row3", n: "03", title: "Customer checks out", body: "Merchant-approved incentive if needed. One-tap checkout link or supported COD confirmation.", icon: I.checkInk, c: COL.green, fill: COL.green },
  ];
  const y0 = 2.38, gap = 1.25, d = 0.9;
  s.line("conn1", { x: 0.8 + d / 2, y: y0 + d, w: 0, h: gap - d, line: { color: COL.cyan, width: 2, dashType: "dash" } });
  s.line("conn2", { x: 0.8 + d / 2, y: y0 + gap + d, w: 0, h: gap - d, line: { color: COL.green, width: 2, dashType: "dash" } });
  rows.forEach((r, i) => {
    const y = y0 + i * gap;
    s.oval(r.g, { x: 0.8, y, w: d, h: d, fill: { color: r.fill }, line: { color: r.c, width: 2 } });
    s.img(r.g, { data: r.icon, x: 0.8 + 0.22, y: y + 0.22, w: 0.46, h: 0.46 });
    s.text(r.g, [{ text: r.n + "  ", options: { color: r.c } }, { text: r.title, options: { color: COL.white } }], { x: 2.0, y: y - 0.02, w: 6.3, h: 0.42, fontSize: 22, bold: true });
    s.text(r.g, r.body, { x: 2.0, y: y + 0.42, w: 6.3, h: 0.62, fontSize: 16, color: COL.muted, valign: "top" });
  });

  s.rrect("merchant", { x: 0.8, y: 6.08, w: 5.0, h: 0.52, rectRadius: 0.26, ...glass(92) });
  s.img("merchant", { data: I.sliders, x: 1.0, y: 6.19, w: 0.3, h: 0.3 });
  s.text("merchant", "Merchant controls messaging + discounts", { x: 1.45, y: 6.08, w: 4.3, h: 0.52, fontSize: 15, color: COL.white, valign: "middle" });
  s.text("outcome", [{ text: "Helpful answers. ", options: { color: COL.white } }, { text: "Less friction. ", options: { color: COL.cyan } }, { text: "More completed orders.", options: { color: COL.green } }], { x: 0.8, y: 6.72, w: 7.8, h: 0.45, fontSize: 20, bold: true });

  // ---- phone mockup
  const PX = 8.75, PY = 0.42, PW = 3.8, PH = 6.38;
  s.rrect("base", { x: PX, y: PY, w: PW, h: PH, rectRadius: 0.48, fill: { color: "151D33" }, line: { color: "3A4766", width: 1.5 }, shadow: { type: "outer", color: "000000", blur: 30, offset: 8, angle: 90, opacity: 0.55 } });
  const SX = PX + 0.12, SY = PY + 0.12, SW = PW - 0.24, SH = PH - 0.24;
  s.rrect("base", { x: SX, y: SY, w: SW, h: SH, rectRadius: 0.38, fill: { color: COL.waScreen }, line: { color: COL.waScreen, width: 0 } });
  s.rrect("base", { x: SX, y: SY, w: SW, h: 0.82, rectRadius: 0.38, fill: { color: COL.waHead }, line: { color: COL.waHead, width: 0 } });
  s.rect("base", { x: SX, y: SY + 0.45, w: SW, h: 0.37, fill: { color: COL.waHead }, line: { color: COL.waHead, width: 0 } });
  s.rrect("base", { x: SX + SW / 2 - 0.45, y: SY + 0.08, w: 0.9, h: 0.13, rectRadius: 0.065, fill: { color: "000000" }, line: { color: "000000", width: 0 } });
  s.img("base", { data: I.logo, x: SX + 0.2, y: SY + 0.3, w: 0.42, h: 0.42 });
  s.text("base", "CartCloser AI", { x: SX + 0.75, y: SY + 0.28, w: 2.4, h: 0.26, fontSize: 12.5, bold: true, color: COL.white });
  s.text("base", "Store assistant · online", { x: SX + 0.75, y: SY + 0.52, w: 2.4, h: 0.22, fontSize: 9.5, color: COL.green });

  const L = SX + 0.16, R = SX + SW - 0.16;
  const bubble = (g, side, y, w, h, text, extra) => {
    const x = side === "in" ? L : R - w;
    s.rrect(g, { x, y, w, h, rectRadius: 0.12, fill: { color: side === "in" ? COL.waIn : COL.waOut }, line: { color: side === "in" ? COL.waIn : COL.waOut, width: 0 } });
    s.text(g, text, { x: x + 0.14, y: y + 0.08, w: w - 0.28, h: (extra ? h - 0.6 : h) - 0.16, fontSize: 11.5, color: "E9EDEF", valign: extra ? "top" : "middle" });
  };
  s.rrect("chip", { x: SX + SW / 2 - 1.2, y: SY + 0.98, w: 2.4, h: 0.28, rectRadius: 0.14, fill: { color: "182229" }, line: { color: "182229", width: 0 } });
  s.text("chip", "Opted in  ·  Reply STOP to opt out", { x: SX + SW / 2 - 1.2, y: SY + 0.98, w: 2.4, h: 0.28, fontSize: 9, color: "8696A0", align: "center", valign: "middle" });
  bubble("bot1", "in", 1.9, 2.75, 0.62, "Your linen kurta is still in your cart. Any questions?");
  bubble("user1", "out", 2.62, 2.45, 0.62, "Will this arrive in Karachi by Friday?");
  // typing indicator (sits under bot2; bot2 covers it in the final state)
  s.rrect("typing", { x: L, y: 3.34, w: 0.78, h: 0.4, rectRadius: 0.12, fill: { color: COL.waIn }, line: { color: COL.waIn, width: 0 } });
  [0, 1, 2].forEach((k) => s.oval("typing", { x: L + 0.17 + k * 0.17, y: 3.49, w: 0.1, h: 0.1, fill: { color: "8696A0" }, line: { color: "8696A0", width: 0 } }));
  bubble("bot2", "in", 3.34, 2.75, 0.62, "Let me check the store's delivery estimate for your area.");
  bubble("user2", "out", 4.06, 2.5, 0.44, "Can I pay cash on delivery?");
  bubble("bot3", "in", 4.6, 2.85, 1.2, "If available for this item, yes. Here's your checkout link.", true);
  s.rrect("bot3", { x: L + 0.14, y: 5.2, w: 2.57, h: 0.46, rectRadius: 0.1, fill: { color: "111B21" }, line: { color: "2A3942", width: 1 } });
  s.img("bot3", { data: I.linkGreen, x: L + 0.27, y: 5.32, w: 0.22, h: 0.22 });
  s.text("bot3", "Complete checkout", { x: L + 0.6, y: 5.2, w: 2.0, h: 0.46, fontSize: 11.5, bold: true, color: COL.green, valign: "middle" });

  s.rrect("confirm", { x: L, y: 5.98, w: R - L, h: 0.5, rectRadius: 0.25, fill: { color: COL.green }, line: { color: COL.green, width: 0 } });
  s.img("confirm", { data: I.checkInk, x: L + 0.17, y: 6.09, w: 0.28, h: 0.28 });
  s.text("confirm", "Order placed  ·  COD confirmed", { x: L + 0.55, y: 5.98, w: R - L - 0.6, h: 0.5, fontSize: 11.5, bold: true, color: COL.ink, valign: "middle" });

  s.text("base", "ILLUSTRATIVE DEMO  ·  CONCEPT", { x: PX, y: PY + PH + 0.1, w: PW, h: 0.25, fontSize: 10, bold: true, color: COL.dim, align: "center", charSpacing: 2 });
}

function slide3(s, I, pres) {
  s.background = { color: COL.ink };
  s.img("base", { data: I.glow3, x: 0, y: 0, w: 13.333, h: 7.5, altText: "Ambient glow" });
  s.text("base", "WHY WE BUILT IT", { x: 0.8, y: 0.45, w: 4, h: 0.3, fontSize: 13, bold: true, color: COL.cyan, charSpacing: 3 });
  s.text("base", "The sale shouldn't end at a question", { x: 0.8, y: 0.8, w: 11.8, h: 0.85, fontSize: 44, bold: true, color: COL.white });

  s.text("leftLabel", "AT CHECKOUT TODAY", { x: 0.8, y: 1.9, w: 3.8, h: 0.3, fontSize: 12, bold: true, color: COL.coral, charSpacing: 2 });
  s.text("rightLabel", "WITH CARTCLOSER AI", { x: 8.4, y: 1.9, w: 4.2, h: 0.3, fontSize: 12, bold: true, color: COL.green, charSpacing: 2 });

  const ys = [2.35, 3.2, 4.05], h = 0.72;
  const qs = [["q1", "Will it fit?", I.rulerCoral], ["q2", "When will it arrive?", I.truckCoral], ["q3", "Is COD available?", I.cashCoral]];
  qs.forEach(([g, t, ic], i) => {
    s.rrect(g, { x: 0.8, y: ys[i], w: 3.75, h, rectRadius: 0.4, fill: { color: COL.coral, transparency: 88 }, line: { color: COL.coral, transparency: 45, width: 1.25 } });
    s.img(g, { data: ic, x: 1.08, y: ys[i] + 0.18, w: 0.36, h: 0.36 });
    s.text(g, t, { x: 1.65, y: ys[i], w: 2.85, h, fontSize: 21, bold: true, color: COL.white, valign: "middle" });
  });

  s.img("linesL", { data: I.linesL, x: 4.55, y: 2.57, w: 1.5, h: 2.0 });
  s.img("linesR", { data: I.linesR, x: 7.3, y: 2.57, w: 1.1, h: 2.0 });
  // hub
  s.oval("hub", { x: 5.93, y: 2.81, w: 1.5, h: 1.5, fill: { color: COL.cyan, transparency: 86 }, line: { color: COL.cyan, transparency: 100 } });
  s.oval("hub", { x: 6.05, y: 2.93, w: 1.26, h: 1.26, fill: { color: COL.navy }, line: { color: COL.cyan, width: 2 } });
  s.img("hub", { data: I.logo, x: 6.34, y: 3.22, w: 0.68, h: 0.68 });
  s.text("hub", "AI assistant", { x: 5.68, y: 4.4, w: 2.0, h: 0.3, fontSize: 13, bold: true, color: COL.cyan, align: "center" });

  const as = [["a1", "Store's own size guide"], ["a2", "Store's delivery estimate"], ["a3", "Store's COD options"]];
  as.forEach(([g, t], i) => {
    s.rrect(g, { x: 8.4, y: ys[i], w: 4.2, h, rectRadius: 0.4, fill: { color: COL.green, transparency: 88 }, line: { color: COL.green, transparency: 45, width: 1.25 } });
    s.oval(g, { x: 8.62, y: ys[i] + 0.15, w: 0.42, h: 0.42, fill: { color: COL.green }, line: { color: COL.green, width: 0 } });
    s.img(g, { data: I.checkInk, x: 8.71, y: ys[i] + 0.24, w: 0.24, h: 0.24 });
    s.text(g, t, { x: 9.22, y: ys[i], w: 3.3, h, fontSize: 17, bold: true, color: COL.white, valign: "middle" });
  });

  s.text("statement", [{ text: "We help merchants recover opportunities from shoppers ", options: { color: COL.white } }, { text: "they've already attracted.", options: { color: COL.cyan } }], { x: 0.8, y: 4.98, w: 11.8, h: 1.05, fontSize: 26, bold: true, valign: "top" });
  const vs = [["v1", "Less checkout friction", I.zap], ["v2", "Designed for local buying habits", I.pin], ["v3", "Potentially fewer failed deliveries", I.package]];
  const ws = [3.0, 4.1, 4.3];
  let vx = 0.8;
  vs.forEach(([g, t, ic], i) => {
    const x = vx, w = ws[i];
    vx += w + 0.2;
    s.rrect(g, { x, y: 6.3, w, h: 0.62, rectRadius: 0.31, ...glass(92) });
    s.img(g, { data: ic, x: x + 0.22, y: 6.46, w: 0.3, h: 0.3 });
    s.text(g, t, { x: x + 0.62, y: 6.3, w: w - 0.7, h: 0.62, fontSize: 15, color: COL.white, valign: "middle" });
  });
}

const BUILDERS = { 1: slide1, 2: slide2, 3: slide3 };

// ---------------------------------------------------------------- OOXML timing
function timingXml(slideNo, ids) {
  let id = 2;
  const nid = () => ++id;
  const tgt = (spid) => `<p:tgtEl><p:spTgt spid="${spid}"/></p:tgtEl>`;
  const setVis = (spid, val, delay = 0) => `<p:set><p:cBhvr><p:cTn id="${nid()}" dur="1" fill="hold"><p:stCondLst><p:cond delay="${delay}"/></p:stCondLst></p:cTn>${tgt(spid)}<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val="${val}"/></p:to></p:set>`;
  const animProp = (spid, attr, from, to, dur) => `<p:anim calcmode="lin" valueType="num"><p:cBhvr additive="base"><p:cTn id="${nid()}" dur="${dur}" fill="hold"/>${tgt(spid)}<p:attrNameLst><p:attrName>${attr}</p:attrName></p:attrNameLst></p:cBhvr><p:tavLst><p:tav tm="0"><p:val><p:strVal val="${from}"/></p:val></p:tav><p:tav tm="100000"><p:val><p:strVal val="${to}"/></p:val></p:tav></p:tavLst></p:anim>`;
  const fade = (spid, dur, dir = "in", filter = "fade") => `<p:animEffect transition="${dir}" filter="${filter}"><p:cBhvr><p:cTn id="${nid()}" dur="${dur}"/>${tgt(spid)}</p:cBhvr></p:animEffect>`;

  const effect = (fx, spid, dur) => {
    switch (fx) {
      case "fade": return { p: [10, "entr", 0], body: setVis(spid, "visible") + fade(spid, dur) };
      case "up": return { p: [42, "entr", 0], body: setVis(spid, "visible") + fade(spid, dur) + animProp(spid, "ppt_x", "#ppt_x", "#ppt_x", dur) + animProp(spid, "ppt_y", "#ppt_y+.04", "#ppt_y", dur) };
      case "zoom": return { p: [53, "entr", 16], body: setVis(spid, "visible") + animProp(spid, "ppt_w", "#ppt_w*0.6", "#ppt_w", dur) + animProp(spid, "ppt_h", "#ppt_h*0.6", "#ppt_h", dur) + fade(spid, dur) };
      case "wipeR": return { p: [22, "entr", 8], body: setVis(spid, "visible") + fade(spid, dur, "in", "wipe(right)") };
      case "wipeD": return { p: [22, "entr", 1], body: setVis(spid, "visible") + fade(spid, dur, "in", "wipe(down)") };
      case "exit": return { p: [10, "exit", 0], body: fade(spid, dur, "out") + setVis(spid, "hidden", dur - 1) };
      case "pulse": return { p: [6, "emph", 0], body: `<p:animScale><p:cBhvr><p:cTn id="${nid()}" dur="${dur}" autoRev="1" fill="hold"/>${tgt(spid)}</p:cBhvr><p:by x="108000" y="108000"/></p:animScale>` };
    }
    throw new Error("fx " + fx);
  };

  const clicks = ANIM[slideNo].map((c) => {
    const outerId = nid(), innerId = nid();
    let first = true;
    const effs = [];
    for (const st of c.steps) {
      const spids = ids[st.g];
      if (!spids || !spids.length) throw new Error(`slide ${slideNo}: no shapes for group ${st.g}`);
      for (const spid of spids) {
        const nodeType = first ? (c.trigger === "auto" ? "afterEffect" : "clickEffect") : "withEffect";
        first = false;
        const effId = nid();
        const e = effect(st.fx, spid, st.dur);
        effs.push(`<p:par><p:cTn id="${effId}" presetID="${e.p[0]}" presetClass="${e.p[1]}" presetSubtype="${e.p[2]}" fill="hold" nodeType="${nodeType}"><p:stCondLst><p:cond delay="${st.at}"/></p:stCondLst><p:childTnLst>${e.body}</p:childTnLst></p:cTn></p:par>`);
      }
    }
    const start = c.trigger === "auto" ? `<p:cond delay="indefinite"/><p:cond evt="onBegin" delay="0"><p:tn val="2"/></p:cond>` : `<p:cond delay="indefinite"/>`;
    return `<p:par><p:cTn id="${outerId}" fill="hold"><p:stCondLst>${start}</p:stCondLst><p:childTnLst><p:par><p:cTn id="${innerId}" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>${effs.join("")}</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>`;
  });

  return `<p:transition spd="med"><p:fade/></p:transition><p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>${clicks.join("")}</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst><p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>`;
}

async function injectAnimations(file) {
  const zip = await JSZip.loadAsync(fs.readFileSync(file));
  const report = [];
  for (const n of [1, 2, 3]) {
    const p = `ppt/slides/slide${n}.xml`;
    let xml = await zip.file(p).async("string");
    const ids = {};
    for (const m of xml.matchAll(/<p:cNvPr id="(\d+)" name="([^"#]+)#\d+"/g)) (ids[m[2]] ||= []).push(m[1]);
    const t = timingXml(n, ids);
    if (!xml.includes("</p:clrMapOvr>")) throw new Error("no clrMapOvr in " + p);
    xml = xml.replace("</p:clrMapOvr>", "</p:clrMapOvr>" + t);
    zip.file(p, xml);
    const effects = (t.match(/presetClass=/g) || []).length;
    report.push({ slide: n, clicks: ANIM[n].length, effects, groups: Object.keys(ids).length });
  }
  fs.writeFileSync(file, await zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" }));
  return report;
}

// ---------------------------------------------------------------- stages (for preview video)
// returns list of {slide, visible:Set, hold(ms), fade(ms)} snapshots
function stageList() {
  const out = [];
  for (const n of [1, 2, 3]) {
    const vis = new Set();
    // initial (before any animation)
    out.push({ slide: n, visible: new Set(vis), hold: n === 1 ? 300 : 1200, fade: 600, label: `s${n}-start` });
    ANIM[n].forEach((c, ci) => {
      const steps = [...c.steps].sort((a, b) => a.at - b.at);
      steps.forEach((st, si) => {
        if (st.fx === "pulse") return;
        if (st.fx === "exit") vis.delete(st.g); else vis.add(st.g);
        const next = steps.slice(si + 1).find((x) => x.fx !== "pulse");
        const hold = next ? Math.max(150, next.at - st.at - st.dur) : 1800;
        out.push({ slide: n, visible: new Set(vis), hold, fade: st.dur, label: `s${n}-c${ci}-${st.g}-${st.fx}` });
      });
    });
    out[out.length - 1].hold = 2500;
  }
  return out;
}

async function main() {
  const [mode, outFile] = process.argv.slice(2);
  const I = await loadAssets();
  const pres = new pptxgen();
  pres.layout = "LAYOUT_WIDE";
  pres.title = "CartCloser AI — IGNITE XIII Pitch";
  pres.author = "CartCloser AI team";
  pres.subject = "Investor pitch, 3 slides";
  pres.theme = { headFontFace: FONT, bodyFontFace: FONT };

  if (mode === "final") {
    for (const n of [1, 2, 3]) {
      const slide = pres.addSlide();
      BUILDERS[n](api(slide, makeCtx(null), pres), I, pres);
      slide.addNotes(NOTES[n]);
    }
    await pres.writeFile({ fileName: outFile });
    const rep = await injectAnimations(outFile);
    fs.writeFileSync(outFile + ".anim.json", JSON.stringify(rep, null, 2));
    console.log("written", outFile, JSON.stringify(rep));
  } else {
    const stages = stageList();
    for (const st of stages) {
      const slide = pres.addSlide();
      BUILDERS[st.slide](api(slide, makeCtx(st.visible), pres), I, pres);
    }
    await pres.writeFile({ fileName: outFile });
    fs.writeFileSync(outFile + ".stages.json", JSON.stringify(stages.map(({ slide, hold, fade, label }) => ({ slide, hold, fade, label })), null, 2));
    console.log("stages", stages.length);
  }
}
main().catch((e) => { console.error(e); process.exit(1); });
