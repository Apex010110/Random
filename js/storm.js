class Storm {
    constructor() {
        const S = CONFIG.WORLD_SIZE;
        this.cx = S / 2;
        this.cy = S / 2;
        this.currentRadius = S * 0.72;
        this.startRadius = this.currentRadius;

        this.phases = CONFIG.STORM.PHASES;
        this.phaseIdx = 0;
        this.timer = 0;
        this.shrinking = false;

        this.lastDamageTick = 0;
        this.electricOffset = 0;
    }

    update(dt, now) {
        this.timer += dt;
        this.electricOffset += dt * 0.003;

        const phase = this.phases[Math.min(this.phaseIdx, this.phases.length - 1)];

        if (!this.shrinking) {
            if (this.timer >= phase.waitTime) {
                this.shrinking = true;
                this.startRadius = this.currentRadius;
                this.timer = 0;
            }
        } else {
            const t = clamp(this.timer / phase.shrinkTime, 0, 1);
            this.currentRadius = lerp(this.startRadius, phase.targetRadius, t);
            if (t >= 1) {
                this.currentRadius = phase.targetRadius;
                this.shrinking = false;
                this.timer = 0;
                if (this.phaseIdx < this.phases.length - 1) this.phaseIdx++;
            }
        }
    }

    isOutside(x, y) {
        return dist2(x, y, this.cx, this.cy) > this.currentRadius * this.currentRadius;
    }

    shouldDamage(now) {
        if (now - this.lastDamageTick >= CONFIG.STORM.TICK_INTERVAL) {
            this.lastDamageTick = now;
            return true;
        }
        return false;
    }

    getPhaseText() {
        const phase = this.phases[Math.min(this.phaseIdx, this.phases.length - 1)];
        if (!this.shrinking) {
            const rem = Math.max(0, phase.waitTime - this.timer);
            return `Storm closes in ${Math.ceil(rem / 1000)}s`;
        } else {
            const rem = Math.max(0, phase.shrinkTime - this.timer);
            return `⚡ Storm moving! ${Math.ceil(rem / 1000)}s`;
        }
    }

    draw(ctx, cam) {
        const vw = ctx.canvas.width, vh = ctx.canvas.height;
        const scx = this.cx - cam.x + vw/2;
        const scy = this.cy - cam.y + vh/2;

        // Outside fill – dark purple fog
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, 0, vw, vh);
        ctx.arc(scx, scy, this.currentRadius, 0, Math.PI*2, true);
        ctx.fillStyle = 'rgba(80, 20, 160, 0.38)';
        ctx.fill();
        ctx.restore();

        // Electric border
        ctx.save();
        const segments = 120;
        const amp = 4;
        for (let i = 0; i < 2; i++) {
            ctx.beginPath();
            for (let j = 0; j <= segments; j++) {
                const angle = (j / segments) * Math.PI * 2;
                const noise = Math.sin(angle * 7 + this.electricOffset + i * 2.4) * amp
                            + Math.sin(angle * 13 - this.electricOffset * 1.7 + i) * amp * 0.5;
                const r = this.currentRadius + noise;
                const px = scx + Math.cos(angle) * r;
                const py = scy + Math.sin(angle) * r;
                j === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
            }
            ctx.closePath();
            ctx.strokeStyle = i === 0 ? '#dd44ff' : '#ff88ff';
            ctx.lineWidth = i === 0 ? 3 : 1.5;
            ctx.shadowBlur = 25;
            ctx.shadowColor = '#cc00ff';
            ctx.stroke();
        }
        ctx.restore();
        ctx.shadowBlur = 0;
    }

    drawMinimap(ctx, s) {
        ctx.beginPath();
        ctx.arc(this.cx * s, this.cy * s, this.currentRadius * s, 0, Math.PI*2);
        ctx.strokeStyle = '#cc44ff';
        ctx.lineWidth = 1.5;
        ctx.stroke();

        // Storm fill on minimap
        ctx.save();
        ctx.beginPath();
        ctx.rect(-5, -5, 200, 200);
        ctx.arc(this.cx * s, this.cy * s, this.currentRadius * s, 0, Math.PI*2, true);
        ctx.fillStyle = 'rgba(100, 20, 180, 0.35)';
        ctx.fill();
        ctx.restore();
    }
}
