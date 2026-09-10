--!strict
--[[
	SuitConfig.luau
	Configuration for Spider-Man Suit Wardrobe & Hero Cash Economy:
	- 6 Iconic Canonical Spider-Suits with unlock tiers and perk bonuses
	- Zero-trust economy validation (Level requirements & Hero Cash costs)
	- Aesthetic themes, accent colors, and procedural visual styling
]]

export type SuitDefinition = {
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
			PerkDescription = "Balanced hero mobility with standard kinetic output.",
			PerkType = "Special",
			PerkValue = 1.0,
			ThemeColor = Color3.fromRGB(225, 45, 55),
			AccentColor = Color3.fromRGB(35, 95, 215),
			Icon = "🕷️",
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
			PerkDescription = "+15% Swing Velocity & Apex Boost Acceleration.",
			PerkType = "Velocity",
			PerkValue = 1.15,
			ThemeColor = Color3.fromRGB(255, 55, 65),
			AccentColor = Color3.fromRGB(255, 215, 65),
			Icon = "⚡",
			ProceduralColors = {
				Head = Color3.fromRGB(215, 40, 50),
				Torso = Color3.fromRGB(225, 185, 40),
				Arms = Color3.fromRGB(215, 40, 50),
				Legs = Color3.fromRGB(45, 50, 65),
			},
		},
		{
			Id = "StealthBigTime",
			Name = "Stealth Big Time",
			Tagline = "Light-warping neon matrix designed at Horizon Labs.",
			UnlockLevel = 3,
			HeroCashCost = 2000,
			PerkDescription = "+0.25s Spider-Sense Perfect Dodge Reaction Window.",
			PerkType = "Dodge",
			PerkValue = 0.25,
			ThemeColor = Color3.fromRGB(35, 245, 125),
			AccentColor = Color3.fromRGB(15, 25, 20),
			Icon = "🟢",
			ProceduralColors = {
				Head = Color3.fromRGB(20, 25, 25),
				Torso = Color3.fromRGB(35, 235, 120),
				Arms = Color3.fromRGB(20, 25, 25),
				Legs = Color3.fromRGB(20, 25, 25),
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
			ThemeColor = Color3.fromRGB(25, 25, 35),
			AccentColor = Color3.fromRGB(255, 255, 255),
			Icon = "🌑",
			ProceduralColors = {
				Head = Color3.fromRGB(15, 15, 20),
				Torso = Color3.fromRGB(15, 15, 20),
				Arms = Color3.fromRGB(15, 15, 20),
				Legs = Color3.fromRGB(15, 15, 20),
			},
		},
		{
			Id = "SpiderArmorMK4",
			Name = "Spider-Armor MK IV",
			Tagline = "Liquid metallic weave developed by Parker Industries.",
			UnlockLevel = 5,
			HeroCashCost = 9000,
			PerkDescription = "+25 Max Health Shield & Defensive Plating.",
			PerkType = "Defense",
			PerkValue = 25,
			ThemeColor = Color3.fromRGB(195, 35, 55),
			AccentColor = Color3.fromRGB(60, 220, 255),
			Icon = "🛡️",
			ProceduralColors = {
				Head = Color3.fromRGB(180, 30, 45),
				Torso = Color3.fromRGB(45, 180, 225),
				Arms = Color3.fromRGB(180, 30, 45),
				Legs = Color3.fromRGB(45, 180, 225),
			},
		},
		{
			Id = "Cyber2099",
			Name = "2099 Cyber Suit",
			Tagline = "Futuristic unstable molecule fabric from Nueva York.",
			UnlockLevel = 6,
			HeroCashCost = 16000,
			PerkDescription = "+30% Web Cyclone AOE Blender Radius.",
			PerkType = "Acrobatic",
			PerkValue = 1.30,
			ThemeColor = Color3.fromRGB(30, 75, 225),
			AccentColor = Color3.fromRGB(255, 45, 75),
			Icon = "🤖",
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
	["StealthBigTimeSuit"] = "StealthBigTime",
	["SymbioteSuit"] = "SymbioteBlack",
	["SpiderArmorMK4Suit"] = "SpiderArmorMK4",
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
