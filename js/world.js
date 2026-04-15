class World {
    constructor() {
        this.size = CONFIG.WORLD_SIZE;
        this.buildings = [];
        this.trees = [];
        this.rocks = [];
        this.roads = [];
        this._buildingCache = null;
        this._treeCache = null;
        this.generate();
    }

    generate() {
        const rng = seededRandom(42);
        const S = this.size;
        const margin = 200;

        // Road grid (for visual)
        for (let gx = 1; gx < 4; gx++) {
            this.roads.push({ x: 0, y: S * gx / 4 - 20, w: S, h: 40, dir: 'h' });
            this.roads.push({ x: S * gx / 4 - 20, y: 0, w: 40, h: S, dir: 'v' });
        }

        // Buildings – clustered near roads
        const buildingAttempts = 160;
        for (let i = 0; i < buildingAttempts && this.buildings.length < 85; i++) {
            const w = 70 + Math.floor(rng() * 130);
            const h = 70 + Math.floor(rng() * 130);
            const x = margin + rng() * (S - w - margin * 2);
            const y = margin + rng() * (S - h - margin * 2);

            let overlaps = false;
            for (const b of this.buildings) {
                if (x < b.x + b.w + 50 && x + w + 50 > b.x &&
                    y < b.y + b.h + 50 && y + h + 50 > b.y) {
                    overlaps = true; break;
                }
            }
            // Keep off roads
            for (const r of this.roads) {
                if (!overlaps && circleRectOverlap(x + w/2, y + h/2, Math.max(w,h)/2 + 30, r.x, r.y, r.w, r.h)) {
                    overlaps = true; break;
                }
            }

            if (!overlaps) {
                const hue = Math.floor(200 + rng() * 60);
                const sat = 10 + rng() * 15;
                const lgt = 18 + rng() * 14;
                this.buildings.push({
                    x, y, w, h,
                    wallColor: `hsl(${hue},${sat}%,${lgt}%)`,
                    roofColor: `hsl(${hue},${sat+5}%,${lgt+10}%)`,
                    accentColor: `hsl(${hue+20},40%,${lgt+20}%)`,
                    windowColor: `rgba(${120 + rng()*80}, ${180 + rng()*60}, ${220 + rng()*35}, 0.7)`,
                });
            }
        }

        // Trees
        for (let i = 0; i < 400 && this.trees.length < 280; i++) {
            const r = 12 + rng() * 18;
            const x = margin + rng() * (S - margin * 2);
            const y = margin + rng() * (S - margin * 2);

            let ok = true;
            for (const b of this.buildings) {
                if (circleRectOverlap(x, y, r + 25, b.x, b.y, b.w, b.h)) { ok = false; break; }
            }
            for (const rd of this.roads) {
                if (ok && circleRectOverlap(x, y, r + 10, rd.x, rd.y, rd.w, rd.h)) { ok = false; break; }
            }
            if (ok) {
                const hue = 90 + rng() * 50;
                this.trees.push({
                    x, y, r,
                    canopyColor: `hsl(${hue},${45+rng()*25}%,${20+rng()*15}%)`,
                    canopyColor2: `hsl(${hue+10},${40+rng()*20}%,${28+rng()*12}%)`,
                    trunkColor: `hsl(30,${30+rng()*20}%,${20+rng()*10}%)`,
                });
            }
        }

        // Rocks
        for (let i = 0; i < 120 && this.rocks.length < 80; i++) {
            const r = 10 + rng() * 20;
            const x = margin + rng() * (S - margin * 2);
            const y = margin + rng() * (S - margin * 2);
            let ok = true;
            for (const b of this.buildings) {
                if (circleRectOverlap(x, y, r + 20, b.x, b.y, b.w, b.h)) { ok = false; break; }
            }
            if (ok) {
                this.rocks.push({ x, y, r, color: `hsl(220,${10+rng()*10}%,${28+rng()*15}%)` });
            }
        }
    }

    collideCircle(x, y, r) {
        let px = clamp(x, r, this.size - r);
        let py = clamp(y, r, this.size - r);

        for (const b of this.buildings) {
            if (circleRectOverlap(px, py, r, b.x, b.y, b.w, b.h)) {
                const res = pushOutOfRect(px, py, r, b.x, b.y, b.w, b.h);
                if (res) { px = res.x; py = res.y; }
            }
        }
        for (const t of this.trees) {
            const dx = px - t.x, dy = py - t.y;
            const d = Math.sqrt(dx*dx + dy*dy);
            const mn = r + t.r;
            if (d < mn && d > 0) { px += (dx/d)*(mn-d); py += (dy/d)*(mn-d); }
        }
        for (const t of this.rocks) {
            const dx = px - t.x, dy = py - t.y;
            const d = Math.sqrt(dx*dx + dy*dy);
            const mn = r + t.r;
            if (d < mn && d > 0) { px += (dx/d)*(mn-d); py += (dy/d)*(mn-d); }
        }
        return { x: px, y: py };
    }

    isBlocked(x, y, r) {
        for (const b of this.buildings) {
            if (circleRectOverlap(x, y, r, b.x, b.y, b.w, b.h)) return true;
        }
        for (const t of this.trees) {
            if (dist2(x,y,t.x,t.y) < (r+t.r)**2) return true;
        }
        for (const t of this.rocks) {
            if (dist2(x,y,t.x,t.y) < (r+t.r)**2) return true;
        }
        return false;
    }

    bulletHitsWorld(bx, by) {
        if (bx < 0 || bx > this.size || by < 0 || by > this.size) return true;
        for (const b of this.buildings) {
            if (bx >= b.x && bx <= b.x + b.w && by >= b.y && by <= b.y + b.h) return true;
        }
        for (const t of this.trees) {
            if (dist2(bx,by,t.x,t.y) < t.r*t.r) return true;
        }
        for (const t of this.rocks) {
            if (dist2(bx,by,t.x,t.y) < t.r*t.r) return true;
        }
        return false;
    }

    // LoS check (quick step trace)
    hasLoS(ax, ay, bx, by) {
        const dx = bx - ax, dy = by - ay;
        const steps = Math.ceil(Math.sqrt(dx*dx+dy*dy) / 18);
        for (let i = 1; i < steps; i++) {
            const t = i / steps;
            const cx = ax + dx * t, cy = ay + dy * t;
            for (const b of this.buildings) {
                if (cx >= b.x && cx <= b.x+b.w && cy >= b.y && cy <= b.y+b.h) return false;
            }
        }
        return true;
    }

    draw(ctx, cam) {
        const vw = ctx.canvas.width, vh = ctx.canvas.height;

        // === Ground ===
        // Grass gradient
        const gGrad = ctx.createRadialGradient(vw/2, vh/2, 0, vw/2, vh/2, Math.max(vw,vh)*0.7);
        gGrad.addColorStop(0, '#1e3a1e');
        gGrad.addColorStop(1, '#162b16');
        ctx.fillStyle = gGrad;
        ctx.fillRect(0, 0, vw, vh);

        // Subtle grass texture lines
        ctx.strokeStyle = 'rgba(255,255,255,0.018)';
        ctx.lineWidth = 1;
        const gs = 80;
        const ox = Math.floor((cam.x - vw/2) / gs) * gs;
        const oy = Math.floor((cam.y - vh/2) / gs) * gs;
        for (let wx = ox; wx < cam.x + vw/2 + gs; wx += gs) {
            for (let wy = oy; wy < cam.y + vh/2 + gs; wy += gs) {
                ctx.strokeRect(wx - cam.x + vw/2, wy - cam.y + vh/2, gs, gs);
            }
        }

        // === Roads ===
        for (const r of this.roads) {
            const sx = r.x - cam.x + vw/2;
            const sy = r.y - cam.y + vh/2;
            if (sx + r.w < -10 || sx > vw + 10 || sy + r.h < -10 || sy > vh + 10) continue;

            ctx.fillStyle = '#1a1a22';
            ctx.fillRect(sx, sy, r.w, r.h);

            // Road markings
            ctx.strokeStyle = 'rgba(255,255,200,0.15)';
            ctx.lineWidth = 2;
            ctx.setLineDash([30, 30]);
            ctx.beginPath();
            if (r.dir === 'h') {
                ctx.moveTo(sx, sy + r.h/2); ctx.lineTo(sx + r.w, sy + r.h/2);
            } else {
                ctx.moveTo(sx + r.w/2, sy); ctx.lineTo(sx + r.w/2, sy + r.h);
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        // === World border ===
        const bx = -cam.x + vw/2, by = -cam.y + vh/2;
        ctx.strokeStyle = '#ff3333';
        ctx.lineWidth = 5;
        ctx.shadowBlur = 12;
        ctx.shadowColor = '#ff0000';
        ctx.strokeRect(bx, by, this.size, this.size);
        ctx.shadowBlur = 0;

        // === Buildings ===
        for (const b of this.buildings) {
            const sx = b.x - cam.x + vw/2;
            const sy = b.y - cam.y + vh/2;
            if (sx + b.w < -20 || sx > vw + 20 || sy + b.h < -20 || sy > vh + 20) continue;

            // Drop shadow
            ctx.fillStyle = 'rgba(0,0,0,0.45)';
            ctx.fillRect(sx + 8, sy + 8, b.w, b.h);

            // Walls
            ctx.fillStyle = b.wallColor;
            ctx.fillRect(sx, sy, b.w, b.h);

            // Roof
            ctx.fillStyle = b.roofColor;
            ctx.fillRect(sx + 6, sy + 6, b.w - 12, b.h - 12);

            // Roof center detail
            ctx.fillStyle = b.accentColor;
            const pad = Math.min(b.w, b.h) * 0.15;
            ctx.fillRect(sx + pad, sy + pad, b.w - pad*2, b.h - pad*2);

            // Windows
            const winCols = Math.max(1, Math.floor(b.w / 35));
            const winRows = Math.max(1, Math.floor(b.h / 35));
            ctx.fillStyle = b.windowColor;
            ctx.shadowBlur = 6;
            ctx.shadowColor = b.windowColor;
            for (let wi = 0; wi < winCols; wi++) {
                for (let wj = 0; wj < winRows; wj++) {
                    const wx = sx + 14 + wi * (b.w - 28) / Math.max(1, winCols - 0.5);
                    const wy = sy + 14 + wj * (b.h - 28) / Math.max(1, winRows - 0.5);
                    ctx.fillRect(wx - 6, wy - 5, 12, 10);
                }
            }
            ctx.shadowBlur = 0;

            // Border
            ctx.strokeStyle = 'rgba(255,255,255,0.12)';
            ctx.lineWidth = 1.5;
            ctx.strokeRect(sx, sy, b.w, b.h);
        }

        // === Rocks ===
        for (const t of this.rocks) {
            const sx = t.x - cam.x + vw/2;
            const sy = t.y - cam.y + vh/2;
            if (sx < -t.r-5 || sx > vw+t.r+5 || sy < -t.r-5 || sy > vh+t.r+5) continue;

            ctx.fillStyle = 'rgba(0,0,0,0.3)';
            ctx.beginPath();
            ctx.ellipse(sx+3, sy+4, t.r, t.r*0.7, 0, 0, Math.PI*2);
            ctx.fill();

            ctx.fillStyle = t.color;
            ctx.beginPath();
            ctx.arc(sx, sy, t.r, 0, Math.PI*2);
            ctx.fill();

            ctx.fillStyle = 'rgba(255,255,255,0.12)';
            ctx.beginPath();
            ctx.arc(sx - t.r*0.25, sy - t.r*0.25, t.r*0.5, 0, Math.PI*2);
            ctx.fill();
        }

        // === Trees ===
        for (const t of this.trees) {
            const sx = t.x - cam.x + vw/2;
            const sy = t.y - cam.y + vh/2;
            if (sx < -t.r-10 || sx > vw+t.r+10 || sy < -t.r-10 || sy > vh+t.r+10) continue;

            // Shadow
            ctx.fillStyle = 'rgba(0,0,0,0.35)';
            ctx.beginPath();
            ctx.ellipse(sx+5, sy+5, t.r, t.r*0.65, 0, 0, Math.PI*2);
            ctx.fill();

            // Trunk
            ctx.fillStyle = t.trunkColor;
            ctx.beginPath();
            ctx.ellipse(sx, sy + t.r*0.35, t.r*0.28, t.r*0.45, 0, 0, Math.PI*2);
            ctx.fill();

            // Outer canopy
            ctx.fillStyle = t.canopyColor;
            ctx.beginPath();
            ctx.arc(sx, sy, t.r, 0, Math.PI*2);
            ctx.fill();

            // Inner canopy
            const cg = ctx.createRadialGradient(sx-t.r*0.2, sy-t.r*0.2, 0, sx, sy, t.r);
            cg.addColorStop(0, t.canopyColor2);
            cg.addColorStop(1, 'transparent');
            ctx.fillStyle = cg;
            ctx.beginPath();
            ctx.arc(sx, sy, t.r, 0, Math.PI*2);
            ctx.fill();

            // Highlight
            ctx.fillStyle = 'rgba(255,255,255,0.07)';
            ctx.beginPath();
            ctx.arc(sx - t.r*0.3, sy - t.r*0.3, t.r*0.55, 0, Math.PI*2);
            ctx.fill();
        }
    }
}
