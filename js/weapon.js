class Bullet {
    constructor(x, y, angle, cfg, ownerId) {
        this.x = x; this.y = y;
        this.vx = Math.cos(angle) * cfg.bulletSpeed;
        this.vy = Math.sin(angle) * cfg.bulletSpeed;
        this.damage = cfg.damage;
        this.radius = cfg.bulletRadius;
        this.ownerId = ownerId;
        this.maxAge = cfg.bulletLifetime;
        this.age = 0;
        this.dead = false;
        this.color = cfg.color;
        this.trail = [];
    }

    update(world) {
        this.trail.push({ x: this.x, y: this.y });
        if (this.trail.length > 7) this.trail.shift();

        this.x += this.vx;
        this.y += this.vy;
        this.age += 16;

        if (this.age >= this.maxAge || world.bulletHitsWorld(this.x, this.y)) {
            this.dead = true;
        }
    }

    draw(ctx, cam) {
        const vw = ctx.canvas.width, vh = ctx.canvas.height;
        const sx = this.x - cam.x + vw/2;
        const sy = this.y - cam.y + vh/2;
        if (sx < -20 || sx > vw+20 || sy < -20 || sy > vh+20) return;

        // Trail
        for (let i = 0; i < this.trail.length; i++) {
            const tp = this.trail[i];
            const tx = tp.x - cam.x + vw/2;
            const ty = tp.y - cam.y + vh/2;
            const prog = (i + 1) / this.trail.length;
            ctx.globalAlpha = prog * 0.5;
            ctx.fillStyle = this.color;
            ctx.beginPath();
            ctx.arc(tx, ty, this.radius * prog * 0.7, 0, Math.PI*2);
            ctx.fill();
        }
        ctx.globalAlpha = 1;

        // Glow
        ctx.shadowBlur = 16;
        ctx.shadowColor = this.color;
        ctx.fillStyle = '#ffffff';
        ctx.beginPath();
        ctx.arc(sx, sy, this.radius, 0, Math.PI*2);
        ctx.fill();

        // Core color
        ctx.shadowBlur = 0;
        ctx.fillStyle = this.color;
        ctx.beginPath();
        ctx.arc(sx, sy, this.radius * 0.55, 0, Math.PI*2);
        ctx.fill();
    }
}

class Weapon {
    constructor(configId) {
        this.cfg = CONFIG.WEAPONS[configId];
        this.id = configId;
        this.ammo = this.cfg.magSize;
        this.lastFired = -9999;
        this.reloading = false;
        this.reloadStart = 0;
    }

    canFire(now) {
        return !this.reloading && this.ammo > 0 && (now - this.lastFired >= this.cfg.fireRate);
    }

    fire(x, y, angle, ownerId, now) {
        if (!this.canFire(now)) return [];
        this.lastFired = now;
        this.ammo--;

        const bullets = [];
        for (let i = 0; i < this.cfg.pellets; i++) {
            const sp = (Math.random() - 0.5) * this.cfg.spread;
            bullets.push(new Bullet(x, y, angle + sp, this.cfg, ownerId));
        }
        if (this.ammo === 0) this.startReload(now);
        return bullets;
    }

    startReload(now) {
        if (this.reloading || this.ammo >= this.cfg.magSize) return;
        this.reloading = true;
        this.reloadStart = now;
    }

    update(now) {
        if (this.reloading && now - this.reloadStart >= this.cfg.reloadTime) {
            this.reloading = false;
            this.ammo = this.cfg.magSize;
        }
    }

    reloadProgress(now) {
        if (!this.reloading) return 1;
        return clamp((now - this.reloadStart) / this.cfg.reloadTime, 0, 1);
    }
}
