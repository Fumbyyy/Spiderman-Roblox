--!strict
--[[
	CombatConfig.luau
	Configuration for Spider-Man Combat System:
	- Move 1: Kinetic Strike Combo (1-2-3), Uppercut Launcher, 4th-Hit Jump Slam
	- Move 2: Rapid Web-Pellets & Wall-Pinning (E Key)
]]

local CombatConfig = {
	-- 🎮 Active 4-Button Controls & Keybinds
	Keybinds = {
		Attack = Enum.UserInputType.MouseButton1, -- L-Click: 1-2-3 Punch Combo (Ground) / Ground Slam (Air)
		WebGadget = Enum.KeyCode.E,               -- E Key: Contextual Smart Web (Disarm Armed Mobs / Shoot Web Pellets)
		Dodge = Enum.KeyCode.F,                   -- F Key: Spider-Sense Perfect Dodge & Face-Web Counter
		WebStrike = Enum.KeyCode.R,               -- R Key: 65-Stud Web-Strike Zip Kick!
	},

	-- 🎯 Freeflow Targeting Settings (Smooth camera, comfortable range)
	Targeting = {
		MaxLockDistance = 65,                     -- Maximum range to soft-target an enemy (studs)
		LockConeAngle = 45,                       -- Cone angle (degrees) around camera crosshair
		ReticleColor = Color3.fromRGB(255, 65, 65),     -- Targeting reticle color (Red)
		LockedColor = Color3.fromRGB(85, 235, 255),     -- Active target color (Cyan/Spider-Blue)
		ArmedColor = Color3.fromRGB(255, 175, 45),      -- Highlight color for armed thugs (Orange/Gold)
		HoldThreshold = 0.22,                     -- Seconds to hold button to trigger Hold moves
	},

	-- 💥 Combat Moves Specifications & Balancing
	Moves = {
		-- 1. 🥊 Kinetic Strike Combo (L-Click Tap 3x on Ground - Multi-Target AoE Cleave)
		KineticCombo = {
			Hit1Damage = 7,                       -- Balanced brawler damage
			Hit2Damage = 10,
			Hit3Damage = 18,                      -- Heavy knockback strike
			MaxMeleeRange = 6.0,                  -- Direct punch reach (studs)
			CleaveRadius = 7.0,                   -- Forward AoE punch cleave reach for hitting clumped enemies
			FinisherCleaveRadius = 8.2,           -- 3rd hit wide roundhouse cleave reach (studs)
			CleaveConeAngle = 70,                 -- Forward cleave arc (degrees)
			LungeForce = 14,                      -- Forward step lunge to close small gaps
			HitCooldown = 0.26,                   -- Snappy, rhythmic punch pacing
			FinisherCooldown = 0.50,              -- Cooldown after 3rd hit
			ComboResetTime = 1.10,                -- Time before combo resets to hit 1
		},

		-- 2. 🚀 Uppercut Launcher (Hold L-Click)
		Uppercut = {
			Cooldown = 2.4,                       -- 2.4s Cooldown (fluid launcher rhythm)
			Damage = 16,
			MaxMeleeRange = 6.0,                  -- Close-range chin launcher range
			LaunchVelocity = 48,                  -- Controlled vertical launch (14 studs height)
			MaxAirJuggleTime = 1.5,
		},

		-- 3. 💥 Web-Line Ground Slam (In-Air Attack / 4th Attack after 1-2-3 Combo)
		AirGroundSlam = {
			Cooldown = 1.4,                       -- 1.4s Cooldown (stops spam while feeling snappy)
			Damage = 24,                          -- Direct impact damage
			SlamSpeed = 85,                       -- Snappy downward whip into pavement
			ShockwaveRadius = 22,                 -- Generous 22-stud AoE shockwave radius!
			ShockwaveDamage = 14,                 -- AoE splash damage to surrounding thugs
		},

		-- 4. 🕸️ Rapid Web-Pellets & Wall Pinning (E Key)
		WebPellet = {
			Cooldown = 0.24,                      -- Fast, crisp web bursts (Thwip-Thwip-Thwip!)
			Damage = 5,                           -- Light projectile damage
			PelletSpeed = 220,                    -- High-velocity web projectile speed (studs/s)
			MaxDistance = 50,                     -- Maximum targeting distance (studs)
			HitsToTrap = 3,                       -- 3 hits = Full Cocoon
			TrapDuration = 5.0,                   -- 5 seconds immobilized in cocoon
			WallPinDistance = 8.0,                -- 8.0 studs proximity to wall for pinning
			Stack1SlowSpeed = 9,                  -- Stack 1 enemy movement speed
			Stack2SlowSpeed = 3,                  -- Stack 2 enemy movement speed (heavy struggle)
		},

		-- 5. 🔫 Web-Yank Disarm & Weapon Throw (Q Key)
		DisarmAndThrow = {
			Cooldown = 2.5,                       -- 2.5s Cooldown (snappy weapon snatches against armed mobs)
			Damage = 26,                          -- Heavy weapon impact damage
			MaxDistance = 45,                     -- Max targeting distance (studs)
			SnatchSpeed = 0.22,                   -- Time to rip weapon towards Spider-Man (s)
			HurlSpeed = 0.20,                     -- Time to throw weapon back into target (s)
			KnockbackForce = 18,                  -- Heavy physical stagger impulse
		},

		-- 6. ⚡ Spider-Sense Flat Step-Back & Face-Web Counter (F Key)
		SpiderSenseDodge = {
			Cooldown = 0.35,                      -- 0.35s Fast Evasion Cadence against aggressive mobs
			InvulnerabilityDuration = 0.55,       -- AoE i-frames during evasion
			ThreatDetectionRadius = 45,           -- Range to detect incoming enemy attack telegraphs
			CounterDamage = 12,                   -- Balanced point-blank web counter damage
		},

		-- 7. 🚀 Web-Strike Zip Kick (R Key - High-Velocity Crowd Buster)
		WebStrike = {
			Cooldown = 1.25,                      -- 1.25s Fast Fluid Cooldown (ideal for Dodge -> Zip Strike combos!)
			ImpactDamage = 22,                    -- Heavy flying dropkick impact on primary target
			SplashDamage = 14,                    -- AoE blast damage on secondary clumped enemies
			SplashRadius = 8.0,                   -- Stud radius for AoE crowd splash on impact
			MaxDistance = 65,                     -- 65 studs crosshair lock-on zip range
			ZipSpeed = 125,                       -- High-velocity zip pull (studs/s)
			KnockbackForce = 26,                  -- Launches thug backwards across street
		},
	},

	-- 🦹 Enemy Settings & Archetype Behaviors
	Enemies = {
		MaxHealth = 90,                           -- Fallback health pool
		RespawnDelay = 6.0,
		AttackCooldown = 3.5,                     -- Default cooldown between attacks
		TelegraphTime = 0.85,
	},

	-- 🎭 Tactical Enemy Archetypes (Phase 4.2)
	Archetypes = {
		-- 🔫 Armed Gunner / Rooftop Sniper (Ranged Threat)
		Gunner = {
			Name = "Armed Gunner",
			MaxHealth = 70,                       -- Lower health pool, high ranged threat
			PreferredMinDistance = 22,            -- Standoff range: backpedals if player closes in
			PreferredMaxDistance = 45,            -- Max combat engagement distance
			TelegraphTime = 0.90,                 -- 0.9s Red Laser telegraph before shot
			Damage = 12,                          -- Sharp gunshot damage
			AttackCooldown = 3.2,                 -- Cadence between sniper shots
			LaserColor = Color3.fromRGB(255, 35, 35),
			WalkSpeed = 13,
		},

		-- 🛡️ Armored Heavy Brute (Defensive / Tank Threat)
		Brute = {
			Name = "Heavy Brute",
			MaxHealth = 160,                      -- Massive health pool
			MeleeRange = 7.0,                     -- Heavy smash reach
			TelegraphTime = 1.10,                 -- Telegraphed wind-up slam
			Damage = 20,                          -- Crushing melee damage
			AttackCooldown = 3.6,
			GuardBreakDuration = 3.5,             -- Seconds guard remains broken after Web-Strike
			BlocksFrontalMelee = true,            -- Parries / deflects frontal punches
			WalkSpeed = 11,                       -- Heavy, deliberate march
		},

		-- 🦹 Street Brawler Mob (Swarm Threat)
		Brawler = {
			Name = "Street Brawler",
			MaxHealth = 80,                       -- Standard brawler health
			MeleeRange = 6.0,                     -- Close range brawl
			TelegraphTime = 0.85,                 -- Fast punch telegraph
			Damage = 8,                           -- Light punch damage
			AttackCooldown = 2.8,
			SurroundRadius = 7.5,                 -- Flanking orbit distance
			WalkSpeed = 15,                       -- Agile jog
		},
	},
}

return CombatConfig
