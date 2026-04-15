class Game {
    constructor() {
        this.canvas = document.getElementById('gameCanvas');
        this.ctx = this.canvas.getContext('2d');
        this.ctx.imageSmoothingEnabled = true;
        this.ctx.imageSmoothingQuality = 'high';

        this.resize();
        window.addEventListener('resize', () => this.resize());

        this.state = 'MENU';
        this.world = null;
        this.player = null;
        this.bots = [];
        this.bullets = [];
        this.loot = null;
        this.storm = null;
        this.hud = null;
        this.particles = [];

        this.lastTime = 0;
        this._setupMenus();

        window._game = this;
        requestAnimationFrame(t => this.loop(t));
    }

    resize() {
        this.canvas.width = window.innerWidth;
        this.canvas.height = window.innerHeight;
    }

    _setupMenus() {
        document.getElementById('playBtn').addEventListener('click', () => this.startGame());
        document.getElementById('respawnBtn').addEventListener('click', () => this.startGame());
        document.getElementById('winPlayBtn').addEventListener('click', () => this.startGame());
    }

    startGame() {
        ['menu','deathScreen','winScreen'].forEach(id => {
            document.getElementById(id).classList.add('hidden');
        });

        this.world = new World();
        this.storm = new Storm();
        this.hud = new HUD();
        this.bullets = [];
        this.particles = [];

        const sp = this._safeSpawn();
        this.player = new Player(sp.x, sp.y);
        this.player.camX = sp.x; this.player.camY = sp.y;

        this.bots = [];
        for (let i = 0; i < CONFIG.BOT_COUNT; i++) {
            const bp = this._safeSpawn();
            this.bots.push(new Bot(bp.x, bp.y, i));
        }

        this.loot = new LootManager(this.world);
        this.state = 'PLAYING';
    }

    _safeSpawn() {
        const S = CONFIG.WORLD_SIZE;
        for (let i = 0; i < 300; i++) {
            const x = 200 + Math.random() * (S - 400);
            const y = 200 + Math.random() * (S - 400);
            if (!this.world.isBlocked(x, y, 22)) return { x, y };
        }
        return { x: S/2, y: S/2 };
    }

    loop(now) {
        // Target 120 FPS – cap dt so physics stays stable if tab backgrounded
        const dt = Math.min(32, now - this.lastTime);
        this.lastTime = now;

        if (this.state === 'PLAYING') this.update(dt, now);
        this.draw(now);

        requestAnimationFrame(t => this.loop(t));
    }

    update(dt, now) {
        // Storm
        this.storm.update(dt, now);

        // Storm damage tick
        if (this.storm.shouldDamage(now)) {
            if (this.storm.isOutside(this.player.x, this.player.y)) {
                this.player.takeDamage(CONFIG.STORM.DAMAGE_PER_TICK, now);
            }
            for (const b of this.bots) {
                if (!b.dead && this.storm.isOutside(b.x, b.y)) {
                    b.takeDamage(CONFIG.STORM.DAMAGE_PER_TICK, now);
                }
            }
        }

        // Player
        this.player.update(this.world, this.bullets, this.loot, now, dt);

        // Bots
        for (const bot of this.bots) {
            bot.update(this.world, this.player, this.bullets, this.loot, this.storm, now, dt);
        }

        // Bullets
        for (const b of this.bullets) {
            b.update(this.world);
            if (b.dead) continue;

            // vs Player
            if (b.ownerId !== 'player' && !this.player.dead) {
                if (dist2(b.x, b.y, this.player.x, this.player.y) < (b.radius + this.player.radius)**2) {
                    this.player.takeDamage(b.damage, now);
                    this._spawnHit(b.x, b.y, b.color);
                    this.hud.addDmgNum(b.x, b.y, Math.round(b.damage), { x: this.player.camX, y: this.player.camY });
                    b.dead = true;
                    continue;
                }
            }

            // vs Bots (player bullets)
            if (b.ownerId === 'player') {
                let hit = false;
                for (const bot of this.bots) {
                    if (bot.dead) continue;
                    if (dist2(b.x, b.y, bot.x, bot.y) < (b.radius + bot.radius)**2) {
                        bot.takeDamage(b.damage, now);
                        this._spawnHit(b.x, b.y, '#ff4444');
                        this.hud.addDmgNum(b.x, b.y, Math.round(b.damage), { x: this.player.camX, y: this.player.camY });
                        if (bot.dead) {
                            this.player.kills++;
                            this.hud.addKill('YOU', bot.name);
                            this._spawnDeathEffect(bot.x, bot.y, bot.color);
                        }
                        b.dead = true; hit = true; break;
                    }
                }
                if (hit) continue;
            }

            // Bot vs Bot (friendly fire, reduced)
            if (b.ownerId !== 'player') {
                for (const bot of this.bots) {
                    if (bot.dead || bot.id === b.ownerId) continue;
                    if (dist2(b.x, b.y, bot.x, bot.y) < (b.radius + bot.radius)**2) {
                        bot.takeDamage(b.damage * 0.5, now);
                        this._spawnHit(b.x, b.y, '#ff8844');
                        if (bot.dead) {
                            const shooter = this.bots.find(x => x.id === b.ownerId);
                            this.hud.addKill(shooter ? shooter.name : 'Bot', bot.name);
                            this._spawnDeathEffect(bot.x, bot.y, bot.color);
                        }
                        b.dead = true; break;
                    }
                }
            }
        }

        this.bullets = this.bullets.filter(b => !b.dead);

        // Particles
        this.particles = this.particles.filter(p => p.life > 0);
        for (const p of this.particles) {
            p.x += p.vx; p.y += p.vy;
            p.vx *= 0.94; p.vy *= 0.94;
            p.life -= p.decay;
            p.alpha = p.life;
        }

        // Loot
        this.loot.update();

        // Win/loss check
        const aliveBots = this.bots.filter(b => !b.dead).length;
        if (this.player.dead) {
            this.state = 'DEAD';
            setTimeout(() => {
                document.getElementById('deathScreen').classList.remove('hidden');
                document.getElementById('deathStats').textContent =
                    `Kills: ${this.player.kills}  |  Players remaining: ${aliveBots + 1}`;
            }, 600);
        } else if (aliveBots === 0) {
            this.state = 'WIN';
            setTimeout(() => {
                document.getElementById('winScreen').classList.remove('hidden');
                document.getElementById('winStats').textContent =
                    `Victory with ${this.player.kills} elimination${this.player.kills !== 1 ? 's' : ''}!`;
            }, 400);
        }
    }

    _spawnHit(x, y, color) {
        for (let i = 0; i < 8; i++) {
            const a = Math.random() * Math.PI * 2;
            const spd = 1.5 + Math.random() * 2.5;
            this.particles.push({
                x, y, color,
                vx: Math.cos(a) * spd, vy: Math.sin(a) * spd,
                r: 2 + Math.random() * 3,
                life: 1, alpha: 1, decay: 0.045 + Math.random() * 0.03,
            });
        }
    }

    _spawnDeathEffect(x, y, color) {
        for (let i = 0; i < 22; i++) {
            const a = Math.random() * Math.PI * 2;
            const spd = 2 + Math.random() * 5;
            this.particles.push({
                x, y, color,
                vx: Math.cos(a) * spd, vy: Math.sin(a) * spd,
                r: 3 + Math.random() * 5,
                life: 1, alpha: 1, decay: 0.02 + Math.random() * 0.02,
            });
        }
    }

    draw(now) {
        const ctx = this.ctx;
        const vw = this.canvas.width, vh = this.canvas.height;

        ctx.clearRect(0, 0, vw, vh);

        if (this.state === 'MENU') {
            ctx.fillStyle = '#0a140a';
            ctx.fillRect(0, 0, vw, vh);
            return;
        }

        const cam = { x: this.player.camX, y: this.player.camY };

        // World (ground + buildings + trees)
        this.world.draw(ctx, cam);

        // Storm
        this.storm.draw(ctx, cam);

        // Loot
        this.loot.draw(ctx, cam);

        // Particles
        for (const p of this.particles) {
            const sx = p.x - cam.x + vw/2;
            const sy = p.y - cam.y + vh/2;
            ctx.globalAlpha = p.alpha;
            ctx.fillStyle = p.color;
            ctx.shadowBlur = 8;
            ctx.shadowColor = p.color;
            ctx.beginPath();
            ctx.arc(sx, sy, p.r, 0, Math.PI*2);
            ctx.fill();
        }
        ctx.globalAlpha = 1;
        ctx.shadowBlur = 0;

        // Bullets
        for (const b of this.bullets) b.draw(ctx, cam);

        // Bots (behind player)
        for (const b of this.bots) { if (!b.dead) b.draw(ctx, cam); }

        // Player
        if (!this.player.dead) this.player.draw(ctx);

        // HUD
        this.hud.draw(ctx, this.player, this.bots, this.storm, now);

        // Crosshair
        if (!this.player.dead) this._drawCrosshair(ctx, this.player.mouseX, this.player.mouseY);
    }

    _drawCrosshair(ctx, x, y) {
        const sz = 13, gap = 5;
        ctx.strokeStyle = 'rgba(255,255,255,0.92)';
        ctx.lineWidth = 1.5;
        ctx.shadowBlur = 6;
        ctx.shadowColor = 'rgba(0,0,0,0.8)';
        ctx.lineCap = 'round';

        ctx.beginPath();
        ctx.moveTo(x - sz, y); ctx.lineTo(x - gap, y);
        ctx.moveTo(x + gap, y); ctx.lineTo(x + sz, y);
        ctx.moveTo(x, y - sz); ctx.lineTo(x, y - gap);
        ctx.moveTo(x, y + gap); ctx.lineTo(x, y + sz);
        ctx.stroke();

        ctx.fillStyle = 'rgba(255,255,255,0.9)';
        ctx.shadowBlur = 4;
        ctx.beginPath();
        ctx.arc(x, y, 1.5, 0, Math.PI*2);
        ctx.fill();
        ctx.shadowBlur = 0;
    }
}

window.addEventListener('load', () => { window._game = new Game(); });
