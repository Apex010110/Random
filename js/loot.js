class LootDrop {
    constructor(x, y, weaponId) {
        this.x = x; this.y = y;
        this.weaponId = weaponId;
        this.cfg = CONFIG.WEAPONS[weaponId];
        this.radius = 14;
        this.pulse = Math.random() * Math.PI * 2;
        this.dead = false;
        this.floatY = 0;
    }

    update() {
        this.pulse += 0.055;
        this.floatY = Math.sin(this.pulse) * 3;
    }

    draw(ctx, cam) {
        const vw = ctx.canvas.width, vh = ctx.canvas.height;
        const sx = this.x - cam.x + vw/2;
        const sy = this.y - cam.y + vh/2 + this.floatY;
        if (sx < -40 || sx > vw+40 || sy < -40 || sy > vh+40) return;

        const col = this.cfg.rarityColor;
        const r = 16;

        // Glow ring
        ctx.shadowBlur = 22;
        ctx.shadowColor = col;

        // Background box
        ctx.fillStyle = 'rgba(10,10,20,0.82)';
        ctx.strokeStyle = col;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.roundRect(sx - r, sy - r, r*2, r*2, 5);
        ctx.fill();
        ctx.stroke();
        ctx.shadowBlur = 0;

        // Weapon icon text
        ctx.fillStyle = col;
        ctx.font = `bold 9px 'Segoe UI', Arial`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(this.cfg.name.toUpperCase(), sx, sy);
    }
}

class Chest {
    constructor(x, y) {
        this.x = x; this.y = y;
        this.radius = 16;
        this.open = false;
        this.dead = false;
        this.pulse = Math.random() * Math.PI * 2;
        this.floatY = 0;
        this.sparkles = [];
    }

    update() {
        this.pulse += 0.04;
        this.floatY = Math.sin(this.pulse) * 2.5;
        // Randomly spawn sparkles
        if (Math.random() < 0.15) {
            this.sparkles.push({
                x: this.x + (Math.random() - 0.5) * 28,
                y: this.y + (Math.random() - 0.5) * 20,
                vy: -0.8 - Math.random() * 1.2,
                life: 1, alpha: 1
            });
        }
        this.sparkles = this.sparkles.filter(s => {
            s.y += s.vy;
            s.life -= 0.03;
            s.alpha = s.life;
            return s.life > 0;
        });
    }

    tryOpen(px, py) {
        if (this.open || this.dead) return null;
        if (dist2(px, py, this.x, this.y) < (this.radius + 44)**2) {
            this.open = true;
            this.dead = true;
            const wId = CONFIG.LOOT.DROP_WEAPONS[Math.floor(Math.random() * CONFIG.LOOT.DROP_WEAPONS.length)];
            return new LootDrop(this.x, this.y, wId);
        }
        return null;
    }

    draw(ctx, cam) {
        if (this.dead) return;
        const vw = ctx.canvas.width, vh = ctx.canvas.height;
        const sx = this.x - cam.x + vw/2;
        const sy = this.y - cam.y + vh/2 + this.floatY;
        if (sx < -40 || sx > vw+40 || sy < -40 || sy > vh+40) return;

        // Sparkles
        for (const s of this.sparkles) {
            const spx = s.x - cam.x + vw/2;
            const spy = s.y - cam.y + vh/2;
            ctx.globalAlpha = s.alpha * 0.8;
            ctx.fillStyle = '#ffd700';
            ctx.shadowBlur = 8;
            ctx.shadowColor = '#ffd700';
            ctx.beginPath();
            ctx.arc(spx, spy, 2, 0, Math.PI*2);
            ctx.fill();
        }
        ctx.globalAlpha = 1;
        ctx.shadowBlur = 0;

        // Glow aura
        ctx.shadowBlur = 18 + Math.sin(this.pulse) * 6;
        ctx.shadowColor = '#ffd700';

        // Chest body
        ctx.fillStyle = '#7b5120';
        ctx.beginPath();
        ctx.roundRect(sx - 16, sy - 11, 32, 22, 3);
        ctx.fill();

        // Lid
        ctx.fillStyle = '#9b6830';
        ctx.beginPath();
        ctx.roundRect(sx - 16, sy - 11, 32, 12, 3);
        ctx.fill();

        // Gold trim
        ctx.strokeStyle = '#ffd700';
        ctx.lineWidth = 2;
        ctx.strokeRect(sx - 16, sy - 11, 32, 22);
        ctx.strokeRect(sx - 16, sy - 11, 32, 12);

        // Lock
        ctx.fillStyle = '#ffd700';
        ctx.beginPath();
        ctx.arc(sx, sy + 3, 4.5, 0, Math.PI*2);
        ctx.fill();

        ctx.shadowBlur = 0;

        // Label above
        ctx.fillStyle = '#ffd700';
        ctx.font = 'bold 10px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText('CHEST', sx, sy - 22 + this.floatY);
    }
}

class LootManager {
    constructor(world) {
        this.drops = [];
        this.chests = [];
        this.spawnAll(world);
    }

    spawnAll(world) {
        const rng = seededRandom(999);
        const S = CONFIG.WORLD_SIZE;

        for (let i = 0; i < CONFIG.LOOT.CHEST_COUNT * 4 && this.chests.length < CONFIG.LOOT.CHEST_COUNT; i++) {
            const x = 100 + rng() * (S - 200);
            const y = 100 + rng() * (S - 200);
            if (!world.isBlocked(x, y, 22)) this.chests.push(new Chest(x, y));
        }

        const wIds = Object.keys(CONFIG.WEAPONS);
        for (let i = 0; i < CONFIG.LOOT.FLOOR_COUNT * 4 && this.drops.length < CONFIG.LOOT.FLOOR_COUNT; i++) {
            const x = 100 + rng() * (S - 200);
            const y = 100 + rng() * (S - 200);
            if (!world.isBlocked(x, y, 18)) {
                this.drops.push(new LootDrop(x, y, wIds[Math.floor(rng() * wIds.length)]));
            }
        }
    }

    update() {
        this.drops = this.drops.filter(d => !d.dead);
        this.chests = this.chests.filter(c => !c.dead);
        this.drops.forEach(d => d.update());
        this.chests.forEach(c => c.update());
    }

    tryInteract(entity) {
        for (const c of this.chests) {
            const drop = c.tryOpen(entity.x, entity.y);
            if (drop) this.drops.push(drop);
        }
        for (const d of this.drops) {
            if (d.dead) continue;
            if (dist2(entity.x, entity.y, d.x, d.y) < (entity.radius + d.radius + 22)**2) {
                if (entity.pickupWeapon && entity.pickupWeapon(d.weaponId)) {
                    d.dead = true;
                }
            }
        }
    }

    // For bots – auto-walk-into pickup
    autoPickup(entity) {
        for (const d of this.drops) {
            if (d.dead) continue;
            if (dist2(entity.x, entity.y, d.x, d.y) < (entity.radius + d.radius + 12)**2) {
                if (entity.pickupWeapon && entity.pickupWeapon(d.weaponId)) {
                    d.dead = true;
                }
            }
        }
    }

    nearestChest(x, y, maxRange) {
        let best = null, bestD = maxRange * maxRange;
        for (const c of this.chests) {
            if (c.dead) continue;
            const d = dist2(x, y, c.x, c.y);
            if (d < bestD) { bestD = d; best = c; }
        }
        return best;
    }

    draw(ctx, cam) {
        this.chests.forEach(c => c.draw(ctx, cam));
        this.drops.forEach(d => d.draw(ctx, cam));
    }

    drawMinimap(ctx, s) {
        ctx.fillStyle = '#ffd700';
        for (const c of this.chests) { ctx.fillRect(c.x*s-1.5, c.y*s-1.5, 3, 3); }
    }
}
