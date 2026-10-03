--!strict
--[[
	SuitConfig.luau
	Configuration for Spider-Man Suit Wardrobe & Hero Cash Economy:
	- 6 Iconic Canonical Spider-Suits with unlock tiers and perk bonuses
	- Zero-trust economy validation (Level requirements & Hero Cash costs)
	- Aesthetic themes, accent colors, and procedural visual styling
]]

export type BodyScaleConfig = {
	Height: number?,
	Width: number?,
	Depth: number?,
	Head: number?,
	BodyType: number?,
	Proportion: number?,
}

export type SuitDefinition = {
	BodyScale: BodyScaleConfig?,
	Id: string,
	Name: string,
	Tagline: string,
	UnlockLevel: number,
	HeroCashCost: number,
	PerkDescription: string,
	PerkType: "Velocity" | "Dodge" | "Damage" | "Defense" | "Acrobatic" | "Special",
	PerkValue: number,
	ThemeColor: Color3,
	AccentColor: Color3,
	Icon: string,
	Clothing: {
		ShirtId: string?,
		PantsId: string?,
	}?,
	ProceduralColors: {
		Head: Color3,
		Torso: Color3,
		Arms: Color3,
		Legs: Color3,
	}?,
}

local SuitConfig = {
	DefaultSuitId = "ClassicSuit",

	Suits = {
		{
			Id = "ClassicSuit",
			Name = "Classic Red & Blue",
			Tagline = "The authentic Peter Parker webbed suit.",
			UnlockLevel = 1,
			HeroCashCost = 0,
			PerkDescription = "Double Web-Slam ([Q]) and Rapid Silk (0.16s).",
			PerkType = "Special",
			PerkValue = 1.0,
			BodyScale = {
				Height = 1.0,
				Width = 1.0,
				Depth = 1.0,
				Head = 1.0,
				BodyType = 0.0,
			},
			ThemeColor = Color3.fromRGB(225, 45, 55),
			AccentColor = Color3.fromRGB(35, 95, 215),
			Icon = "\u{1F577}",
			ProceduralColors = {
				Head = Color3.fromRGB(195, 35, 45),
				Torso = Color3.fromRGB(35, 85, 195),
				Arms = Color3.fromRGB(195, 35, 45),
				Legs = Color3.fromRGB(35, 85, 195),
			},
		},
		{
			Id = "StarkTechSuit",
			Name = "Stark Tech Advanced",
			Tagline = "Reinforced nanotechnology suit engineered by Tony Stark.",
			UnlockLevel = 2,
			HeroCashCost = 800,
			PerkDescription = "Apex Repulsor Thrusters (+15% Velocity), Nanotech Shield (+25 HP) & Waldo Finisher.",
			PerkType = "Velocity",
			PerkValue = 1.15,
			BodyScale = {
				Height = 1.0,
				Width = 1.0,
				Depth = 1.0,
				Head = 1.0,
				BodyType = 0.0,
			},
			ThemeColor = Color3.fromRGB(255, 55, 65),
			AccentColor = Color3.fromRGB(255, 215, 65),
			Icon = "\u{26A1}",
			ProceduralColors = {
				Head = Color3.fromRGB(215, 40, 50),
				Torso = Color3.fromRGB(225, 185, 40),
				Arms = Color3.fromRGB(215, 40, 50),
				Legs = Color3.fromRGB(45, 50, 65),
			},
		},
		{
			Id = "MilesSpiderVerse",
			Name = "Miles Morales (Spider-Verse)",
			Tagline = "Brooklyn's one and only Spider-Man. Camouflage evasion & bio-electricity.",
			UnlockLevel = 2,
			HeroCashCost = 1200,
			PerkDescription = "Bio-Electric Venom Stun (Combo 3), Spider-Verse Camouflage & 1.5x Ambush Strike.",
			PerkType = "Dodge",
			PerkValue = 0.25,
			BodyScale = {
				Height = 0.82,
				Width = 0.65,
				Depth = 0.80,
				Head = 1.0,
				BodyType = 0.55,
			},
			ThemeColor = Color3.fromRGB(225, 35, 45),
			AccentColor = Color3.fromRGB(20, 20, 25),
			Icon = "\u{26A1}",
			ProceduralColors = {
				Head = Color3.fromRGB(18, 18, 22),
				Torso = Color3.fromRGB(18, 18, 22),
				Arms = Color3.fromRGB(18, 18, 22),
				Legs = Color3.fromRGB(18, 18, 22),
			},
		},
		{
			Id = "SymbioteBlack",
			Name = "Symbiote Alien Suit",
			Tagline = "Aggressive alien organism granting raw physical dominance.",
			UnlockLevel = 4,
			HeroCashCost = 4500,
			PerkDescription = "+20% Melee Punch & Cleave Impact Damage.",
			PerkType = "Damage",
			PerkValue = 1.20,
			BodyScale = {
				Height = 1.20,
				Width = 1.10,
				Depth = 1.10,
				Head = 1.0,
				BodyType = 0.90,
			},
			ThemeColor = Color3.fromRGB(25, 25, 35),
			AccentColor = Color3.fromRGB(255, 255, 255),
			Icon = "\u{1F916}",
			ProceduralColors = {
				Head = Color3.fromRGB(15, 15, 20),
				Torso = Color3.fromRGB(15, 15, 20),
				Arms = Color3.fromRGB(15, 15, 20),
				Legs = Color3.fromRGB(15, 15, 20),
			},
		},
		{
			Id = "ScarletSpider",
			Name = "Scarlet Spider (Ben Reilly)",
			Tagline = "Ben Reilly's iconic red suit with sleeveless blue hoodie.",
			UnlockLevel = 5,
			HeroCashCost = 9000,
			PerkDescription = "Slingshot Boost: +25% Slingshot impulse & aerodynamic launch velocity.",
			PerkType = "Velocity",
			PerkValue = 1.25,
			BodyScale = {
				Height = 1.02,
				Width = 1.0,
				Depth = 1.0,
				Head = 1.0,
				BodyType = 0.20,
			},
			ThemeColor = Color3.fromRGB(225, 45, 45),
			AccentColor = Color3.fromRGB(35, 115, 235),
			Icon = "\u{1F577}",
			ProceduralColors = {
				Head = Color3.fromRGB(205, 35, 40),
				Torso = Color3.fromRGB(35, 105, 220),
				Arms = Color3.fromRGB(205, 35, 40),
				Legs = Color3.fromRGB(205, 35, 40),
			},
		},
		{
			Id = "Cyber2099",
			Name = "2099 Cyber Suit",
			Tagline = "Futuristic Miguel O'Hara skull-suit with crimson arm blades.",
			UnlockLevel = 6,
			HeroCashCost = 16000,
			PerkDescription = "Singularity Vortex: +30% Web Cyclone AOE Blender Radius.",
			PerkType = "Acrobatic",
			PerkValue = 1.30,
			BodyScale = {
				Height = 1.12,
				Width = 1.05,
				Depth = 1.05,
				Head = 1.0,
				BodyType = 0.60,
			},
			ThemeColor = Color3.fromRGB(30, 75, 225),
			AccentColor = Color3.fromRGB(255, 45, 75),
			Icon = "\u{1F916}",
			ProceduralColors = {
				Head = Color3.fromRGB(25, 60, 195),
				Torso = Color3.fromRGB(25, 60, 195),
				Arms = Color3.fromRGB(225, 40, 65),
				Legs = Color3.fromRGB(25, 60, 195),
			},
		},
	} :: { SuitDefinition },
}

local SUIT_ALIASES: { [string]: string } = {
	["MilesMoralesSuit"] = "MilesSpiderVerse",
	["MilesSpiderVerse"] = "MilesSpiderVerse",
	["StealthBigTimeSuit"] = "MilesSpiderVerse",
	["SymbioteSuit"] = "SymbioteBlack",
	["ScarletSpiderSuit"] = "ScarletSpider",
	["ScarletSpider"] = "ScarletSpider",
	["SpiderArmorMK4Suit"] = "ScarletSpider",
	["SpiderArmorMK4"] = "ScarletSpider",
	["Cyber2099Suit"] = "Cyber2099",
	["Classic"] = "ClassicSuit",
	["Stark"] = "StarkTechSuit",
}

function SuitConfig.getSuitById(suitId: string): SuitDefinition?
	local resolvedId = SUIT_ALIASES[suitId] or suitId
	for _, suit in SuitConfig.Suits do
		if suit.Id == resolvedId or suit.Id == suitId then
			return suit
		end
	end
	return nil
end

return SuitConfig
