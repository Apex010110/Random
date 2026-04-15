const CONFIG = {
    WORLD_SIZE: 3200,
    BOT_COUNT: 19,

    PLAYER: {
        SPEED: 5,
        RADIUS: 15,
        MAX_HEALTH: 100,
        MAX_SHIELD: 50,
        HEALTH_REGEN_DELAY: 8000,
        HEALTH_REGEN_RATE: 3,
    },

    BOT: {
        SPEED: 3.2,
        WANDER_SPEED: 1.8,
        RADIUS: 15,
        SIGHT_RANGE: 440,
        SHOOT_RANGE: 380,
    },

    STORM: {
        PHASES: [
            { targetRadius: 1100, waitTime: 30000, shrinkTime: 35000 },
            { targetRadius: 650,  waitTime: 22000, shrinkTime: 28000 },
            { targetRadius: 340,  waitTime: 18000, shrinkTime: 22000 },
            { targetRadius: 160,  waitTime: 13000, shrinkTime: 16000 },
            { targetRadius: 60,   waitTime: 9000,  shrinkTime: 12000 },
        ],
        DAMAGE_PER_TICK: 5,
        TICK_INTERVAL: 1000,
    },

    WEAPONS: {
        PISTOL: {
            id: 'PISTOL', name: 'Pistol',
            damage: 30, fireRate: 380, bulletSpeed: 14, spread: 0.04,
            pellets: 1, magSize: 12, reloadTime: 1300,
            color: '#ffd700', rarityColor: '#aaaaaa', rarity: 0,
            autoFire: false, bulletRadius: 4, bulletLifetime: 900,
        },
        SHOTGUN: {
            id: 'SHOTGUN', name: 'Shotgun',
            damage: 20, fireRate: 750, bulletSpeed: 10, spread: 0.22,
            pellets: 8, magSize: 6, reloadTime: 2000,
            color: '#ff6347', rarityColor: '#22cc55', rarity: 1,
            autoFire: false, bulletRadius: 4, bulletLifetime: 240,
        },
        ASSAULT_RIFLE: {
            id: 'ASSAULT_RIFLE', name: 'AR',
            damage: 22, fireRate: 95, bulletSpeed: 16, spread: 0.07,
            pellets: 1, magSize: 30, reloadTime: 2200,
            color: '#00ced1', rarityColor: '#4488ff', rarity: 2,
            autoFire: true, bulletRadius: 3, bulletLifetime: 700,
        },
        SNIPER: {
            id: 'SNIPER', name: 'Sniper',
            damage: 105, fireRate: 1600, bulletSpeed: 24, spread: 0.005,
            pellets: 1, magSize: 5, reloadTime: 2600,
            color: '#a855f7', rarityColor: '#aa44ff', rarity: 3,
            autoFire: false, bulletRadius: 5, bulletLifetime: 1400,
        },
    },

    LOOT: {
        CHEST_COUNT: 90,
        FLOOR_COUNT: 60,
        DROP_WEAPONS: ['SHOTGUN', 'ASSAULT_RIFLE', 'SNIPER', 'PISTOL'],
    },
};
