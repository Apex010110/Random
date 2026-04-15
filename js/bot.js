const BOT_NAMES = [
    'ZeroGhost','NightShadow','IronStorm','BloodRaven','StormPeak',
    'DarkViper','PhantomX','VoidHunter','CrimsonAce','ShadowBane',
    'TitanFall','NovaBurst','ChaosKing','WarPath','DoomEdge',
    'FrostBolt','BlitzKrieg','RuinBlade','SpectreX','GhostFire',
];

const BOT_PALETTE = [
    ['#ff4444','#cc1111'], ['#ff6622','#cc3300'], ['#ff44aa','#cc1177'],
    ['#ff8800','#bb5500'], ['#ee2244','#aa0022'], ['#dd3366','#991144'],
    ['#ff5566','#bb2233'], ['#cc4422','#881100'], ['#ff4466','#bb1144'],
    ['#cc6633','#883311'],
];

class Bot {
    constructor(x, y, id) {
        this.x = x; this.y = y;
        this.id = id;
        this.name = BOT_NAMES[id % BOT_NAMES.length];
        const pal = BOT_PALETTE[id % BOT_PALETTE.length];
        this.color = pal[0]; this.colorDark = pal[1];
        this.radius = CONFIG.BOT.RADIUS;
        this.health = CONFIG.PLAYER.MAX_HEALTH;
        this.shield = Math.random() > 0.5 ? CONFIG.PLAYER.MAX_SHIELD : 0;
        this.angle = Math.random() * Math.PI * 2;
        this.dead = false;
        this.kills = 0;

        // Weapons
        const startW = Math.random() < 0.55 ? 'PISTOL' : 'ASSAULT_RIFLE';
        this.weapons = [new Weapon(startW), null, null];
        this.slot = 0;

        // AI state
        this.state = 'ROAM';
        this.targetX = x; this.targetY = y;
        this.wanderTimer = 0;
        this.strafeDir = 1; this.strafeTimer = 0;
        this.reactionTimer = 0;
        this.lastSeenX = null; this.lastSeenY = null;
        this.chaseTimer = 0;

        // Animation
        this.bobPhase = Math.random() * Math.PI * 2;
        this.moving = false;
        this.damageFlash = 0;
        this.muzzleFlash = 0;
    }

    weapon() { return this.weapons[this.slot] || null; }

    pickupWeapon(wId) {
        const cfg = CONFIG.WEAPONS[wId];
        for (let i = 0; i < 3; i++) {
            if (!this.weapons[i]) {
                this.weapons[i] = new Weapon(wId);
                return true;
            }
        }
        // Replace worst
        let worstI = 0, worstR = 99;
        for (let i = 0; i < 3; i++) {
            if (this.weapons[i] && this.weapons[i].cfg.rarity < worstR) {
                worstR = this.weapons[i].cfg.rarity; worstI = i;
            }
        }
        if (cfg.rarity > worstR) {
            this.weapons[worstI] = new Weapon(wId);
            return true;
        }
        return false;
    }

    takeDamage(amount, now) {
        if (this.dead) return;
        this.damageFlash = 1;
        if (this.shield > 0) {
            const abs = Math.min(this.shield, amount);
            this.shield -= abs; amount -= abs;
        }
        this.health -= amount;
        if (this.health <= 0) { this.health = 0; this.dead = true; }
    }

    update(world, player, bullets, lootManager, storm, now, dt) {
        if (this.dead) return;

        // Update weapons
        for (const w of this.weapons) { if (w) w.update(now); }

        // Auto loot pickup
        lootManager.autoPickup(this);

        this.damageFlash = Math.max(0, this.damageFlash - 0.055);
        if (this.muzzleFlash > 0) this.muzzleFlash--;

        const outside = storm.isOutside(this.x, this.y);
        const dx = player.x - this.x, dy = player.y - this.y;
        const dToPlayer = Math.sqrt(dx*dx + dy*dy);
        const canSee = !player.dead && dToPlayer < CONFIG.BOT.SIGHT_RANGE && world.hasLoS(this.x, this.y, player.x, player.y);

        if (canSee) { this.lastSeenX = player.x; this.lastSeenY = player.y; this.chaseTimer = 4000; }
        if (this.chaseTimer > 0) this.chaseTimer -= dt;

        // State decision
        if (outside) {
            this.state = 'FLEE_STORM';
        } else if (canSee && dToPlayer < CONFIG.BOT.SHOOT_RANGE) {
            this.state = 'ENGAGE';
        } else if (this.chaseTimer > 0 && this.lastSeenX !== null && !player.dead) {
            this.state = 'CHASE';
        } else {
            this.state = 'ROAM';
        }

        let mx = 0, my = 0;

        if (this.state === 'FLEE_STORM') {
            const sdx = storm.cx - this.x, sdy = storm.cy - this.y;
            const sd = Math.sqrt(sdx*sdx + sdy*sdy);
            if (sd > 0) { mx = sdx/sd; my = sdy/sd; }
            this.reactionTimer = 0;
            this.lastSeenX = null; this.lastSeenY = null;

        } else if (this.state === 'ENGAGE') {
            this.reactionTimer += dt;

            // Strafe
            this.strafeTimer -= dt;
            if (this.strafeTimer <= 0) {
                this.strafeTimer = 600 + Math.random() * 900;
                this.strafeDir *= -1;
            }

            const angle = Math.atan2(dy, dx);
            this.angle = angle;

            // Move to optimal range
            const opt = CONFIG.BOT.SHOOT_RANGE * 0.6;
            if (dToPlayer > opt + 50) { mx = dx/dToPlayer; my = dy/dToPlayer; }
            else if (dToPlayer < opt - 50) { mx = -dx/dToPlayer; my = -dy/dToPlayer; }

            // Strafe perpendicular
            const perpX = -dy/dToPlayer * this.strafeDir;
            const perpY =  dx/dToPlayer * this.strafeDir;
            mx = mx * 0.5 + perpX * 0.8;
            my = my * 0.5 + perpY * 0.8;
            const ml = Math.sqrt(mx*mx+my*my);
            if (ml > 0) { mx /= ml; my /= ml; }

            // Shoot (with reaction delay + aim error)
            if (this.reactionTimer > 650) {
                const w = this.weapon();
                if (w && w.canFire(now)) {
                    const aimErr = (Math.random() - 0.5) * 0.12;
                    const b = w.fire(this.x, this.y, angle + aimErr, this.id, now);
                    bullets.push(...b);
                    this.muzzleFlash = 6;
                }
            }

        } else if (this.state === 'CHASE') {
            const ldx = this.lastSeenX - this.x, ldy = this.lastSeenY - this.y;
            const ld = Math.sqrt(ldx*ldx + ldy*ldy);
            this.angle = Math.atan2(ldy, ldx);
            if (ld > 20) { mx = ldx/ld; my = ldy/ld; }
            else { this.lastSeenX = null; this.chaseTimer = 0; }
            this.reactionTimer = 0;

        } else { // ROAM
            this.reactionTimer = 0;
            this.wanderTimer -= dt;
            if (this.wanderTimer <= 0) {
                const a = Math.random() * Math.PI * 2;
                const d = 120 + Math.random() * 350;
                this.targetX = clamp(this.x + Math.cos(a)*d, 120, CONFIG.WORLD_SIZE - 120);
                this.targetY = clamp(this.y + Math.sin(a)*d, 120, CONFIG.WORLD_SIZE - 120);
                this.wanderTimer = 2500 + Math.random() * 3500;
            }
            const wx = this.targetX - this.x, wy = this.targetY - this.y;
            const wd = Math.sqrt(wx*wx + wy*wy);
            if (wd > 15) {
                mx = wx/wd; my = wy/wd;
                this.angle = Math.atan2(wy, wx);
            }
        }

        const speed = this.state === 'ROAM' ? CONFIG.BOT.WANDER_SPEED : CONFIG.BOT.SPEED;
        this.moving = (mx !== 0 || my !== 0);
        if (this.moving) this.bobPhase += 0.2;

        const res = world.collideCircle(this.x + mx * speed, this.y + my * speed, this.radius);
        this.x = res.x; this.y = res.y;
    }

    draw(ctx, cam) {
        const vw = ctx.canvas.width, vh = ctx.canvas.height;
        const sx = this.x - cam.x + vw/2;
        const sy = this.y - cam.y + vh/2;
        if (sx < -40 || sx > vw+40 || sy < -40 || sy > vh+40) return;

        const bob = this.moving ? Math.sin(this.bobPhase) * 2.5 : 0;

        // Shadow
        ctx.fillStyle = 'rgba(0,0,0,0.4)';
        ctx.beginPath();
        ctx.ellipse(sx+5, sy+6+bob, this.radius*1.1, this.radius*0.55, 0, 0, Math.PI*2);
        ctx.fill();

        if (this.damageFlash > 0) {
            ctx.shadowBlur = 28 * this.damageFlash;
            ctx.shadowColor = '#ff2200';
        }

        // Body gradient
        const grad = ctx.createRadialGradient(sx-5, sy-5+bob, 2, sx, sy+bob, this.radius);
        grad.addColorStop(0, this.color);
        grad.addColorStop(1, this.colorDark);
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(sx, sy+bob, this.radius, 0, Math.PI*2);
        ctx.fill();

        if (this.shield > 0) {
            ctx.strokeStyle = `rgba(100,180,255,${0.3 + this.shield/CONFIG.PLAYER.MAX_SHIELD*0.4})`;
            ctx.lineWidth = 2.5;
            ctx.beginPath();
            ctx.arc(sx, sy+bob, this.radius+4, 0, Math.PI*2);
            ctx.stroke();
        }

        ctx.shadowBlur = 0;

        // Gun
        const gx0 = sx + Math.cos(this.angle) * this.radius;
        const gy0 = sy + bob + Math.sin(this.angle) * this.radius;
        const gx1 = sx + Math.cos(this.angle) * (this.radius + 24);
        const gy1 = sy + bob + Math.sin(this.angle) * (this.radius + 24);

        ctx.strokeStyle = '#888';
        ctx.lineWidth = 6;
        ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(gx0, gy0); ctx.lineTo(gx1, gy1); ctx.stroke();

        const w = this.weapon();
        if (w) {
            ctx.strokeStyle = w.cfg.color;
            ctx.lineWidth = 3.5;
            ctx.beginPath(); ctx.moveTo(gx0, gy0); ctx.lineTo(gx1, gy1); ctx.stroke();
        }

        // Muzzle flash
        if (this.muzzleFlash > 0) {
            const mf = this.muzzleFlash / 6;
            ctx.shadowBlur = 16 * mf;
            ctx.shadowColor = w ? w.cfg.color : '#fff';
            ctx.fillStyle = `rgba(255,255,180,${mf*0.85})`;
            ctx.beginPath();
            ctx.arc(gx1, gy1, 5*mf, 0, Math.PI*2);
            ctx.fill();
            ctx.shadowBlur = 0;
        }

        // Health bar
        const bw = 34, bh = 4;
        const bx = sx - bw/2, by = sy - this.radius - 14 + bob;
        ctx.fillStyle = '#222';
        ctx.fillRect(bx, by, bw, bh);
        const hpFrac = this.health / CONFIG.PLAYER.MAX_HEALTH;
        ctx.fillStyle = hpFrac > 0.6 ? '#44ee44' : hpFrac > 0.3 ? '#ffaa00' : '#ff3333';
        ctx.fillRect(bx, by, bw * hpFrac, bh);

        if (this.shield > 0) {
            ctx.fillStyle = '#223344';
            ctx.fillRect(bx, by - 5, bw, 3);
            ctx.fillStyle = '#4499ff';
            ctx.fillRect(bx, by - 5, bw * (this.shield / CONFIG.PLAYER.MAX_SHIELD), 3);
        }

        ctx.fillStyle = '#ffbbbb';
        ctx.font = 'bold 10px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(this.name, sx, by - 8);
    }
}
