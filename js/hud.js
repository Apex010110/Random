class HUD {
    constructor() {
        this.killFeed = [];
        this.dmgNums = [];
    }

    addKill(killer, victim) {
        this.killFeed.unshift({ killer, victim, time: performance.now() });
        if (this.killFeed.length > 6) this.killFeed.pop();
    }

    addDmgNum(x, y, dmg, cam) {
        const vw = window.innerWidth, vh = window.innerHeight;
        this.dmgNums.push({
            sx: x - cam.x + vw/2,
            sy: y - cam.y + vh/2,
            val: dmg,
            life: 1, alpha: 1,
            vy: -1.5
        });
    }

    draw(ctx, player, bots, storm, now) {
        if (player.dead) return;
        const vw = ctx.canvas.width, vh = ctx.canvas.height;
        const alive = bots.filter(b => !b.dead).length + 1;

        // ─── HEALTH + SHIELD ───
        const bx = 22, by = vh - 78, bw = 270, bh1 = 10, bh2 = 16;

        ctx.fillStyle = 'rgba(0,0,0,0.7)';
        ctx.beginPath();
        ctx.roundRect(bx - 12, by - 36, bw + 24, 60, 10);
        ctx.fill();

        // Shield bar
        ctx.fillStyle = '#1a283a';
        ctx.beginPath(); ctx.roundRect(bx, by - 24, bw, bh1, 4); ctx.fill();
        if (player.shield > 0) {
            const shW = bw * (player.shield / CONFIG.PLAYER.MAX_SHIELD);
            const sg = ctx.createLinearGradient(bx, 0, bx + shW, 0);
            sg.addColorStop(0, '#2288ee'); sg.addColorStop(1, '#66aaff');
            ctx.fillStyle = sg;
            ctx.beginPath(); ctx.roundRect(bx, by - 24, shW, bh1, 4); ctx.fill();
        }
        ctx.fillStyle = '#88bbff';
        ctx.font = 'bold 9px Arial'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
        ctx.fillText(`${Math.ceil(player.shield)} SHIELD`, bx + 4, by - 19);

        // HP bar
        ctx.fillStyle = '#1a2b1a';
        ctx.beginPath(); ctx.roundRect(bx, by - 10, bw, bh2, 5); ctx.fill();
        const hpFrac = player.health / CONFIG.PLAYER.MAX_HEALTH;
        const hg = ctx.createLinearGradient(bx, 0, bx + bw, 0);
        hg.addColorStop(0, hpFrac > 0.5 ? '#22cc44' : hpFrac > 0.25 ? '#ee9900' : '#ee2222');
        hg.addColorStop(1, hpFrac > 0.5 ? '#55ff77' : hpFrac > 0.25 ? '#ffcc33' : '#ff5544');
        ctx.fillStyle = hg;
        const hw = bw * hpFrac;
        ctx.beginPath(); ctx.roundRect(bx, by - 10, hw, bh2, 5); ctx.fill();
        ctx.fillStyle = '#fff'; ctx.font = 'bold 11px Arial';
        ctx.fillText(`${Math.ceil(player.health)} HP`, bx + 5, by + bh2/2 - 10);

        // ─── WEAPON SLOTS ───
        const slotW = 64, slotH = 70, gap = 8;
        const totalW = 3 * slotW + 2 * gap;
        const slotX0 = vw/2 - totalW/2;
        const slotY = vh - 82;

        for (let i = 0; i < 3; i++) {
            const w = player.weapons[i];
            const sx = slotX0 + i * (slotW + gap);
            const active = i === player.slot;

            ctx.fillStyle = active ? 'rgba(74,158,255,0.22)' : 'rgba(0,0,0,0.65)';
            ctx.strokeStyle = active ? '#4a9eff' : 'rgba(255,255,255,0.22)';
            ctx.lineWidth = active ? 2.5 : 1;
            ctx.shadowBlur = active ? 12 : 0;
            ctx.shadowColor = '#4a9eff';
            ctx.beginPath(); ctx.roundRect(sx, slotY, slotW, slotH, 7); ctx.fill(); ctx.stroke();
            ctx.shadowBlur = 0;

            if (w) {
                // Rarity strip at top
                ctx.fillStyle = w.cfg.rarityColor;
                ctx.beginPath(); ctx.roundRect(sx, slotY, slotW, 4, [7,7,0,0]); ctx.fill();

                ctx.fillStyle = w.cfg.color;
                ctx.font = `bold ${w.cfg.name.length > 5 ? 9 : 11}px Arial`;
                ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
                ctx.fillText(w.cfg.name, sx + slotW/2, slotY + 24);

                ctx.fillStyle = '#ffffff';
                ctx.font = 'bold 14px Arial';
                ctx.fillText(`${w.ammo}/${w.cfg.magSize}`, sx + slotW/2, slotY + 43);

                if (w.reloading) {
                    const prog = w.reloadProgress(now);
                    ctx.fillStyle = `rgba(255,200,0,0.25)`;
                    ctx.beginPath(); ctx.roundRect(sx, slotY, slotW * prog, slotH, 7); ctx.fill();
                    ctx.fillStyle = '#ffd700'; ctx.font = 'bold 9px Arial';
                    ctx.fillText('RELOAD', sx + slotW/2, slotY + 59);
                } else {
                    ctx.fillStyle = '#666'; ctx.font = '9px Arial';
                    ctx.fillText(`[${i+1}]`, sx + slotW/2, slotY + 60);
                }
            } else {
                ctx.fillStyle = '#444'; ctx.font = '10px Arial';
                ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
                ctx.fillText(`[${i+1}] Empty`, sx + slotW/2, slotY + slotH/2);
            }
        }

        // ─── PLAYERS ALIVE (top right) ───
        ctx.fillStyle = 'rgba(0,0,0,0.7)';
        ctx.beginPath(); ctx.roundRect(vw - 168, 8, 158, 58, 10); ctx.fill();

        ctx.fillStyle = '#ffffff'; ctx.font = 'bold 36px Arial';
        ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
        ctx.fillText(alive, vw - 16, 32);
        ctx.fillStyle = '#888'; ctx.font = '10px Arial';
        ctx.fillText('ALIVE', vw - 16, 52);
        ctx.fillStyle = '#ffd700'; ctx.font = 'bold 13px Arial';
        ctx.fillText(`${player.kills}💀`, vw - 86, 37);

        // ─── STORM INFO (top center) ───
        const stormText = storm.getPhaseText();
        const stW = ctx.measureText(stormText).width;
        ctx.fillStyle = 'rgba(0,0,0,0.7)';
        ctx.beginPath(); ctx.roundRect(vw/2 - stW/2 - 16, 10, stW + 32, 34, 8); ctx.fill();
        ctx.fillStyle = storm.shrinking ? '#ee66ff' : '#cc44ff';
        ctx.font = 'bold 13px Arial'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(stormText, vw/2, 27);

        // Storm warning overlay
        if (storm.isOutside(player.x, player.y)) {
            ctx.fillStyle = 'rgba(120,0,200,0.1)';
            ctx.fillRect(0, 0, vw, vh);
            ctx.fillStyle = '#ee44ff';
            ctx.font = 'bold 16px Arial';
            ctx.textAlign = 'center';
            ctx.fillText('⚡ GET INSIDE THE ZONE! ⚡', vw/2, 58);
        }

        // ─── KILL FEED (top-right below alive) ───
        const kfX = vw - 268;
        let kfY = 76;
        this.killFeed = this.killFeed.filter(k => now - k.time < 6000);
        for (const k of this.killFeed) {
            const age = now - k.time;
            const alpha = clamp((6000 - age) / 1200, 0, 1);
            ctx.globalAlpha = alpha;
            ctx.fillStyle = 'rgba(0,0,0,0.65)';
            ctx.beginPath(); ctx.roundRect(kfX, kfY, 250, 22, 4); ctx.fill();

            ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
            ctx.font = 'bold 11px Arial';
            ctx.fillStyle = k.killer === 'YOU' ? '#4a9eff' : '#ff5555';
            ctx.fillText(k.killer, kfX + 7, kfY + 11);
            const kw = ctx.measureText(k.killer).width;
            ctx.fillStyle = '#ccc';
            ctx.fillText(' ✖ ', kfX + 7 + kw, kfY + 11);
            const mw = ctx.measureText(' ✖ ').width;
            ctx.fillStyle = '#ffaaaa';
            ctx.fillText(k.victim, kfX + 7 + kw + mw, kfY + 11);
            kfY += 26;
        }
        ctx.globalAlpha = 1;

        // ─── MINIMAP ───
        const mapSz = 160;
        const mapX = vw - mapSz - 8;
        const mapY = vh - mapSz - 96;
        const s = mapSz / CONFIG.WORLD_SIZE;

        ctx.save();
        ctx.beginPath(); ctx.roundRect(mapX, mapY, mapSz, mapSz, 6); ctx.clip();

        ctx.fillStyle = '#162b16';
        ctx.fillRect(mapX, mapY, mapSz, mapSz);

        ctx.save(); ctx.translate(mapX, mapY);

        // Storm
        storm.drawMinimap(ctx, s);

        // Bots
        ctx.fillStyle = '#ff4444';
        for (const b of bots) {
            if (b.dead) continue;
            ctx.beginPath();
            ctx.arc(b.x * s, b.y * s, 2.5, 0, Math.PI*2);
            ctx.fill();
        }

        // Player dot
        ctx.fillStyle = '#4a9eff';
        ctx.shadowBlur = 6; ctx.shadowColor = '#4a9eff';
        ctx.beginPath();
        ctx.arc(player.x * s, player.y * s, 4.5, 0, Math.PI*2);
        ctx.fill();

        // Player direction
        ctx.strokeStyle = '#88ccff'; ctx.lineWidth = 1.5; ctx.shadowBlur = 0;
        ctx.beginPath();
        ctx.moveTo(player.x * s, player.y * s);
        ctx.lineTo(player.x * s + Math.cos(player.angle) * 10, player.y * s + Math.sin(player.angle) * 10);
        ctx.stroke();

        ctx.restore();
        ctx.restore();

        // Minimap border
        ctx.strokeStyle = 'rgba(255,255,255,0.3)';
        ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.roundRect(mapX, mapY, mapSz, mapSz, 6); ctx.stroke();
        ctx.fillStyle = 'rgba(255,255,255,0.5)'; ctx.font = '9px Arial';
        ctx.textAlign = 'center';
        ctx.fillText('MAP', mapX + mapSz/2, mapY - 6);

        // ─── DAMAGE NUMBERS ───
        this.dmgNums = this.dmgNums.filter(d => d.life > 0);
        for (const d of this.dmgNums) {
            d.sy += d.vy;
            d.life -= 0.025;
            d.alpha = d.life;
            ctx.globalAlpha = d.alpha;
            ctx.fillStyle = '#ff4444';
            ctx.shadowBlur = 8; ctx.shadowColor = '#ff0000';
            ctx.font = `bold ${12 + Math.floor((1-d.life)*4)}px Arial`;
            ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
            ctx.fillText(`-${d.val}`, d.sx, d.sy);
        }
        ctx.globalAlpha = 1;
        ctx.shadowBlur = 0;

        // ─── INTERACT HINT ───
        const nearChest = window._game && window._game.loot
            ? window._game.loot.chests.some(c => !c.dead && dist2(player.x, player.y, c.x, c.y) < 60*60)
            : false;
        if (nearChest) {
            ctx.fillStyle = 'rgba(0,0,0,0.7)';
            ctx.beginPath(); ctx.roundRect(vw/2 - 80, vh/2 + 30, 160, 28, 6); ctx.fill();
            ctx.fillStyle = '#ffd700'; ctx.font = 'bold 12px Arial';
            ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
            ctx.fillText('[E] Open Chest', vw/2, vh/2 + 44);
        }
    }
}
