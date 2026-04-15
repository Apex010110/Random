function rand(min, max) { return min + Math.random() * (max - min); }
function randInt(min, max) { return Math.floor(rand(min, max + 1)); }
function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }
function lerp(a, b, t) { return a + (b - a) * t; }
function angleLerp(a, b, t) {
    let d = b - a;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    return a + d * t;
}
function dist2(ax, ay, bx, by) { return (ax-bx)**2 + (ay-by)**2; }
function dist(ax, ay, bx, by) { return Math.sqrt(dist2(ax,ay,bx,by)); }

function seededRandom(seed) {
    let s = seed;
    return function() {
        s = (s * 1664525 + 1013904223) & 0xffffffff;
        return (s >>> 0) / 0xffffffff;
    };
}

function circleRectOverlap(cx, cy, cr, rx, ry, rw, rh) {
    const nearX = clamp(cx, rx, rx + rw);
    const nearY = clamp(cy, ry, ry + rh);
    const dx = cx - nearX, dy = cy - nearY;
    return dx * dx + dy * dy < cr * cr;
}

function pushOutOfRect(cx, cy, cr, rx, ry, rw, rh) {
    const nearX = clamp(cx, rx, rx + rw);
    const nearY = clamp(cy, ry, ry + rh);
    const dx = cx - nearX, dy = cy - nearY;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d === 0) {
        const toLeft   = cx - rx;
        const toRight  = rx + rw - cx;
        const toTop    = cy - ry;
        const toBot    = ry + rh - cy;
        const mn = Math.min(toLeft, toRight, toTop, toBot);
        if (mn === toLeft)  return { x: rx - cr,      y: cy };
        if (mn === toRight) return { x: rx + rw + cr, y: cy };
        if (mn === toTop)   return { x: cx, y: ry - cr };
                            return { x: cx, y: ry + rh + cr };
    }
    if (d < cr) {
        const ov = cr - d;
        return { x: cx + (dx / d) * ov, y: cy + (dy / d) * ov };
    }
    return null;
}
