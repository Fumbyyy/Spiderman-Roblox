--!strict
--[[
	CrimeConfig.luau
	Configuration for Spider-Man Phase 5: Dynamic City Crimes & Police Scanner.
	Defines 4 procedural crime archetypes, police radio dispatch chatter,
	co-op wave scaling, reward economics, and interactive world props.
]]

export type EnemyWaveEntry = {
	Archetype: "Gunner" | "Brute" | "Brawler",
	Count: number,
	Sniper: boolean?,
}

export type CrimeArchetypeConfig = {
	Id: string,
	Title: string,
	PoliceCode: string,
	DispatchMessage: string,
	Icon: string,
	ThemeColor: Color3,
	Enemies: { EnemyWaveEntry },
	RewardXP: number,
	RewardCash: number,
	InteractiveCrates: number?,
	HasCivilian: boolean?,
	IsVehicleChase: boolean?,
	VanSpeed: number?,
	EnemiesOnDisable: { EnemyWaveEntry }?,
}

local CrimeConfig = {
	-- ⏱️ Crime Spawner Lifecycle Settings
	Scheduler = {
		AutoStart = true,
		SpawnIntervalMin = 25,          -- Seconds between crime dispatches
		SpawnIntervalMax = 45,
		PostClearCooldown = 8,          -- Brief breather after clearing a crime
		CrimeTimeout = 240,             -- Max duration before crime expires (seconds)
		ActivationRadius = 110,         -- Distance (studs) to trigger "InProgress" state
		DespawnCleanupDelay = 5.0,      -- Seconds before cleaning up finished crime arena
	},

	-- 🤝 Co-Op Multiplayer Wave Scaling Engine
	CoOp = {
		ProximityRadius = 120,          -- Detection radius around crime center for active heroes
		MinPlayersForScale = 2,         -- Multi-hero threshold
		HealthScalePerPlayer = 0.20,    -- +20% HP to Brutes & Gunners per additional hero
		BonusRewardPerPlayer = 0.25,    -- +25% bonus XP & Hero Cash for cooperative teamwork!
		ExtraBrawlersPerPlayer = 1,     -- Extra reinforcement mobs per additional hero
	},

	-- 🌟 Progression & Economy Defaults (Hourglass Pacing: Fast early hook, rewarding endgame mountain)
	Economy = {
		BaseXPForLevel = 500,        -- Level 1 -> 2 requires 500 XP (earn your First Ultimate!)
		LevelScaleFactor = 1.25,
		DefaultCash = 100,
		DefaultLevel = 1,
	},

	-- 🚨 4 Procedural Crime Archetypes
	Archetypes = {
		-- 🏦 1. Bank Heist in Progress (Downtown Ground)
		BankHeist = {
			Id = "BankHeist",
			Title = "Bank Heist in Progress",
			PoliceCode = "10-31 IN PROGRESS",
			DispatchMessage = "Spider-Man, 10-31 in progress downtown! Armed syndicate thugs breached the First National vault. They're heavily armored—intercept before they breach the perimeter!",
			Icon = "🚨",
			ThemeColor = Color3.fromRGB(255, 60, 60),
			Enemies = {
				{ Archetype = "Gunner", Count = 2 },
				{ Archetype = "Brute", Count = 1 },
				{ Archetype = "Brawler", Count = 2 },
			},
			RewardXP = 150,
			RewardCash = 250,
		} :: CrimeArchetypeConfig,

		-- 🎯 2. Rooftop Arms Deal (High-Rise Skyscrapers)
		RooftopDeal = {
			Id = "RooftopDeal",
			Title = "Rooftop Arms Deal",
			PoliceCode = "10-70 IN PROGRESS",
			DispatchMessage = "Spider-Man! 10-70 in progress on the high-rise rooftop—heavy weapon arms deal! They have snipers on water towers. Can you intercept before SWAT gets pinned down?",
			Icon = "📦",
			ThemeColor = Color3.fromRGB(255, 170, 45),
			Enemies = {
				{ Archetype = "Gunner", Count = 2, Sniper = true },
				{ Archetype = "Brute", Count = 1 },
			},
			InteractiveCrates = 3,
			RewardXP = 150,
			RewardCash = 250,
		} :: CrimeArchetypeConfig,

		-- 🆘 3. Alleyway Mugging (Street Level Assault)
		AlleywayMugging = {
			Id = "AlleywayMugging",
			Title = "Alleyway Mugging",
			PoliceCode = "10-10 IN PROGRESS",
			DispatchMessage = "Spider-Man, 10-10 in progress in the alleyway! Innocent civilian cornered by aggressive street thugs. We need you on scene before anyone gets hurt!",
			Icon = "🆘",
			ThemeColor = Color3.fromRGB(255, 90, 160),
			Enemies = {
				{ Archetype = "Brawler", Count = 3 },
			},
			HasCivilian = true,
			RewardXP = 120,
			RewardCash = 200,
		} :: CrimeArchetypeConfig,

		-- 🚐 4. High-Speed Getaway Van (Street Chase)
		GetawayChase = {
			Id = "GetawayChase",
			Title = "High-Speed Getaway Van",
			PoliceCode = "10-04 ALL UNITS",
			DispatchMessage = "Spider-Man, 10-04 all units! Armed syndicate thugs loading stolen military tech into an armored getaway van! Web up the engine and neutralize all hostiles!",
			Icon = "🚐",
			ThemeColor = Color3.fromRGB(75, 215, 255),
			IsVehicleChase = true,
			VanSpeed = 0,
			Enemies = {
				{ Archetype = "Gunner", Count = 1 },
				{ Archetype = "Brawler", Count = 2 },
			},
			RewardXP = 200,
			RewardCash = 350,
		} :: CrimeArchetypeConfig,
	},

	-- 🎵 Audio Asset IDs (with fallback support)
	Audio = {
		RadioSquelchId = "",
		DispatchSirenId = "",
		VictoryFanfareId = "",
		EngineSabotageId = "",
	},
}

return CrimeConfig
