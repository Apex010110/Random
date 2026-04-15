class Player {
    constructor(x, y) {
        this.x = x; this.y = y;
        this.id = 'player';
        this.radius = CONFIG.PLAYER.RADIUS;
        this.health = CONFIG.PLAYER.MAX_HEALTH;
        this.shield = CONFIG.PLAYER.MAX_SHIELD;
        this.angle = 0;
        this.dead = false;
        this.kills = 0;

        this.weapons = [new Weapon('PISTOL'), null, null];
        this.slot = 0;

        this.keys = {};
        this.mouseX = 0; this.mouseY = 0;
        this.shooting = false;
        this.interacting = false;

        this.camX = x; this.camY = y;
        this.bobPhase = 0;
        this.moving = false;

        this.damageFlash = 0;
        this.lastDamageTime = -99999;

        this.muzzleFlash = 0;

        this._setupInput();
    }

    _setupInput() {
        const canvas = document.getElementById('gameCanvas');

        window.addEventListener('keydown', e => {
            this.keys[e.code] = true;
            if (e.code === 'Digit1') this.slot = 0;
            if (e.code === 'Digit2') this.slot = 1;
            if (e.code === 'Digit3') this.slot = 2;
            if (e.code === 'KeyR') { const w = this.weapon(); if (w) w.startReload(performance.now()); }
            if (e.code === 'KeyE') this.interacting = true;
        });
        window.addEventListener('keyup', e => {
            this.keys[e.code] = false;
            if (e.code === 'KeyE') this.interacting = false;
        });

        canvas.addEventListener('mousemove', e => {
            const rect = canvas.getBoundingClientRect();
            this.mouseX = e.clientX - rect.left;
            this.mouseY = e.clientY - rect.top;
        });
        canvas.addEventListener('mousedown', e => { if (e.button === 0) this.shooting = true; });
        canvas.addEventListener('mouseup', e => { if (e.button === 0) this.shooting = false; });
        canvas.addEventListener('contextmenu', e => e.preventDefault());

        canvas.addEventListener('wheel', e => {
            const dir = e.deltaY > 0 ? 1 : -1;
            for (let i = 0; i < 3; i++) {
                this.slot = (this.slot + dir + 3) % 3;
                if (this.weapons[this.slot]) break;
            }
        }, { passive: true });
    }

    weapon() { return this.weapons[this.slot] || null; }

    pickupWeapon(wId) {
        for (let i = 0; i < 3; i++) {
            if (!this.weapons[i]) { this.weapons[i] = new Weapon(wId); return true; }
        }
        this.weapons[this.slot] = new Weapon(wId);
        return true;
    }

    takeDamage(amount, now) {
        if (this.dead) return;
        this.lastDamageTime = now;
        this.damageFlash = 1;
        if (this.shield > 0) {
            const abs = Math.min(this.shield, amount);
            this.shield -= abs; amount -= abs;
        }
        this.health -= amount;
        if (this.health <= 0) { this.health = 0; this.dead = true; }
    }

    update(world, bullets, lootManager, now, dt) {
        if (this.dead) return;

        // Movement
        let dx = 0, dy = 0;
        if (this.keys['KeyW'] || this.keys['ArrowUp'])    dy -= 1;
        if (this.keys['KeyS'] || this.keys['ArrowDown'])  dy += 1;
        if (this.keys['KeyA'] || this.keys['ArrowLeft'])  dx -= 1;
        if (this.keys['KeyD'] || this.keys['ArrowRight']) dx += 1;
        const len = Math.sqrt(dx*dx + dy*dy);
        this.moving = len > 0;
        if (len > 0) { dx /= len; dy /= len; this.bobPhase += 0.22; }

        const nx = this.x + dx * CONFIG.PLAYER.SPEED;
        const ny = this.y + dy * CONFIG.PLAYER.SPEED;
        const res = world.collideCircle(nx, ny, this.radius);
        this.x = res.x; this.y = res.y;

        // Aim
        const cv = document.getElementById('gameCanvas');
        const wmx = this.mouseX + this.camX - cv.width/2;
        const wmy = this.mouseY + this.camY - cv.height/2;
        this.angle = Math.atan2(wmy - this.y, wmx - this.x);

        // Camera smooth follow
        this.camX = lerp(this.camX, this.x, 0.1);
        this.camY = lerp(this.camY, this.y, 0.1);

        // Weapons
        const w = this.weapon();
        if (w) {
            w.update(now);
            if (this.shooting && w.canFire(now)) {
                const b = w.fire(this.x, this.y, this.angle, this.id, now);
                bullets.push(...b);
                this.muzzleFlash = 8;
            }
        }
        if (this.muzzleFlash > 0) this.muzzleFlash--;

        // Interact / loot
        if (this.interacting) lootManager.tryInteract(this);
        lootManager.autoPickup(this);

        // Decay
        this.damageFlash = Math.max(0, this.damageFlash - 0.06);

        // Health regen
        if (now - this.lastDamageTime > CONFIG.PLAYER.HEALTH_REGEN_DELAY && this.health < CONFIG.PLAYER.MAX_HEALTH) {
            this.health = Math.min(CONFIG.PLAYER.MAX_HEALTH, this.health + CONFIG.PLAYER.HEALTH_REGEN_RATE * (dt/1000));
        }
    }

    draw(ctx) {
        const vw = ctx.canvas.width, vh = ctx.canvas.height;
        const sx = vw / 2;
        const sy = vh / 2;
        const bob = this.moving ? Math.sin(this.bobPhase) * 2.5 : 0;

        // Shadow
        ctx.fillStyle = 'rgba(0,0,0,0.4)';
        ctx.beginPath();
        ctx.ellipse(sx + 5, sy + 6 + bob, this.radius * 1.1, this.radius * 0.55, 0, 0, Math.PI*2);
        ctx.fill();

        // Damage flash
        if (this.damageFlash > 0) {
            ctx.shadowBlur = 30 * this.damageFlash;
            ctx.shadowColor = '#ff0000';
        }

        // Body gradient
        const grad = ctx.createRadialGradient(sx - 5, sy - 5 + bob, 2, sx, sy + bob, this.radius);
        grad.addColorStop(0, '#88ccff');
        grad.addColorStop(0.5, '#3a8ee8');
        grad.addColorStop(1, '#1a5fb0');
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(sx, sy + bob, this.radius, 0, Math.PI*2);
        ctx.fill();

        // Shield ring
        if (this.shield > 0) {
            ctx.strokeStyle = `rgba(100,180,255,${0.4 + this.shield/CONFIG.PLAYER.MAX_SHIELD*0.5})`;
            ctx.lineWidth = 2.5;
            ctx.beginPath();
            ctx.arc(sx, sy + bob, this.radius + 4, 0, Math.PI*2);
            ctx.stroke();
        }

        ctx.shadowBlur = 0;

        // Gun barrel
        const gx0 = sx + Math.cos(this.angle) * this.radius;
        const gy0 = sy + bob + Math.sin(this.angle) * this.radius;
        const gx1 = sx + Math.cos(this.angle) * (this.radius + 24);
        const gy1 = sy + bob + Math.sin(this.angle) * (this.radius + 24);

        ctx.strokeStyle = '#888888';
        ctx.lineWidth = 6;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(gx0, gy0);
        ctx.lineTo(gx1, gy1);
        ctx.stroke();

        const w = this.weapon();
        if (w) {
            ctx.strokeStyle = w.cfg.color;
            ctx.lineWidth = 3.5;
            ctx.beginPath();
            ctx.moveTo(gx0, gy0);
            ctx.lineTo(gx1, gy1);
            ctx.stroke();
        }

        // Muzzle flash
        if (this.muzzleFlash > 0) {
            const mf = this.muzzleFlash / 8;
            ctx.shadowBlur = 20 * mf;
            ctx.shadowColor = w ? w.cfg.color : '#ffffff';
            ctx.fillStyle = `rgba(255,255,200,${mf * 0.9})`;
            ctx.beginPath();
            ctx.arc(gx1, gy1, 6 * mf, 0, Math.PI*2);
            ctx.fill();
            ctx.shadowBlur = 0;
        }

        // Name tag
        ctx.fillStyle = '#4a9eff';
        ctx.font = 'bold 11px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText('YOU', sx, sy - this.radius - 12 + bob);
    }
}
