--!strict
--[[
	CombatService.server.luau
	Master Server Combat Authority for Spider-Man Combat System.
	Coordinates network remotes, delegating to specialized modules:
	- CombatDamage: Damage calculations, knockback, ragdoll, wall-pinning, and brute shields
	- MeleeCombat: Kinetic combos, uppercut launchers, ground slams, and dodge evasions
	- WebAbilities: Rapid web pellets, cocooning, weapon disarms, web-strikes, and web cyclone
	- ThrowableManager: Environmental props, auto-tagging, and double web-slams
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = script.Parent:WaitForChild("Combat")
local MeleeCombat = require(Combat:WaitForChild("MeleeCombat"))
local WebAbilities = require(Combat:WaitForChild("WebAbilities"))
local ThrowableManager = require(Combat:WaitForChild("ThrowableManager"))

-- 📦 Create Combat Remotes Folder
local CombatRemotesFolder = ReplicatedStorage:FindFirstChild("CombatRemotes")
if not CombatRemotesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "CombatRemotes"
	folder.Parent = ReplicatedStorage
	CombatRemotesFolder = folder
end

local function getOrCreateRemote(name: string): RemoteEvent
	local remote = CombatRemotesFolder:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteEvent") then
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = name
		newRemote.Parent = CombatRemotesFolder
		return newRemote
	end
	return remote
end

local KineticComboRemote = getOrCreateRemote("KineticCombo")
local UppercutRemote = getOrCreateRemote("UppercutLauncher")
local GroundSlamRemote = getOrCreateRemote("AirGroundSlam")
local WebPelletRemote = getOrCreateRemote("WebPellet")
local DisarmThrowRemote = getOrCreateRemote("DisarmAndThrow")
local DodgeRemote = getOrCreateRemote("SpiderSenseDodge")
local WebStrikeRemote = getOrCreateRemote("WebStrike")
local WebCycloneRemote = getOrCreateRemote("WebCycloneRemote")
local PropThrowRemote = getOrCreateRemote("PropThrowRemote")
local CombatVFXRemote = getOrCreateRemote("CombatVFX")

-- 1. 🥊 Kinetic Strike Combo (L-Click Tap)
KineticComboRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, comboIndex: any, isAmbushArg: any)
	MeleeCombat.handleKineticCombo(player, targetModel, comboIndex, isAmbushArg, CombatVFXRemote)
end)

-- 2. 🚀 Uppercut Launcher (Hold L-Click)
UppercutRemote.OnServerEvent:Connect(function(player: Player, targetModel: any)
	MeleeCombat.handleUppercut(player, targetModel, CombatVFXRemote)
end)

-- 3. 💥 Web-Line Ground Slam (In-Air Finisher & AoE Shockwave)
GroundSlamRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, customImpactPos: any)
	MeleeCombat.handleGroundSlam(player, targetModel, customImpactPos, CombatVFXRemote)
end)

-- 4. 🕸️ Rapid Web-Pellets & Progressive Cocooning (E Key)
WebPelletRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, isImpactArg: any)
	WebAbilities.handleWebPellet(player, targetModel, isImpactArg, CombatVFXRemote)
end)

-- 5. 🔫 Web-Yank Disarm & Weapon Throw (Q Key)
DisarmThrowRemote.OnServerEvent:Connect(function(player: Player, targetModel: any)
	WebAbilities.handleDisarmThrow(player, targetModel, CombatVFXRemote)
end)

-- 5b. 📦 Contextual Web-Yank & Prop Throw / Double Web-Slam (Q Key)
PropThrowRemote.OnServerEvent:Connect(function(player: Player, propInstance: any, targetModel: any, secondaryTargetArg: any?)
	ThrowableManager.handlePropThrow(player, propInstance, targetModel, secondaryTargetArg, CombatVFXRemote)
end)

-- 6. ⚡ Spider-Sense Perfect Dodge & Counter (F Key)
DodgeRemote.OnServerEvent:Connect(function(player: Player, arg1: any, arg2: any, arg3: any)
	MeleeCombat.handleDodge(player, arg1, arg2, arg3, CombatVFXRemote, function(p, m)
		WebAbilities.handleWebPelletHit(p, m, false, CombatVFXRemote)
	end)
	MeleeCombat.handleDodgeSecondary(player, arg1, arg2, CombatVFXRemote)
end)

-- 7. ⚡ Web-Strike Remote (60-Stud Zip Dropkick)
WebStrikeRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, isAmbushArg: any)
	WebAbilities.handleWebStrike(player, targetModel, isAmbushArg, CombatVFXRemote)
end)

-- 8. 🌪️ 360° Web Cyclone Finisher (Continuous Multi-Hit AoE DPS)
WebCycloneRemote.OnServerEvent:Connect(function(player: Player, actionType: any, targetModel: any, extraData: any)
	WebAbilities.handleWebCyclone(player, actionType, targetModel, extraData, CombatVFXRemote)
end)

-- 📦 Initialize environmental throwable prop scanner
ThrowableManager.init()

print("⚔️ Spider-Man Combat Service (Modularized: CombatDamage, MeleeCombat, WebAbilities, ThrowableManager) online!")
