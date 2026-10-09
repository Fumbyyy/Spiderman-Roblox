--!strict
--[[
	SuitService.server.luau
	Master Server Authority for Spider-Man Suit Wardrobe & Hero Cash Economy.
	Delegates avatar fitting, rig scanning, and procedural dressing to:
	- SuitTemplateScanner: Auto-discovery and caching of 3D models in Workspace/ReplicatedStorage.Suits
	- AvatarFitter: Personal asset stripping, limb resolution, accessory socketing, and joint weld hygiene
	- ProceduralSuitBuilder: Zero-HTTP procedural 3D fallbacks (bracers, blades, waldos, vests)
	- SuitApplier: Cohesive character dressing, custom avatar restoration, and perk scaling
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

local Suit = script.Parent:WaitForChild("Suit")
local AvatarFitter = require(Suit:WaitForChild("AvatarFitter"))
local SuitApplier = require(Suit:WaitForChild("SuitApplier"))

-- 📡 Suit Remotes Folder in ReplicatedStorage
local SuitRemotes = ReplicatedStorage:FindFirstChild("SuitRemotes")
if not SuitRemotes then
	local folder = Instance.new("Folder")
	folder.Name = "SuitRemotes"
	folder.Parent = ReplicatedStorage
	SuitRemotes = folder
end

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local rf = SuitRemotes:FindFirstChild(name)
	if not rf or not rf:IsA("RemoteFunction") then
		local newRf = Instance.new("RemoteFunction")
		newRf.Name = name
		newRf.Parent = SuitRemotes
		return newRf
	end
	return rf
end

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local re = SuitRemotes:FindFirstChild(name)
	if not re or not re:IsA("RemoteEvent") then
		local newRe = Instance.new("RemoteEvent")
		newRe.Name = name
		newRe.Parent = SuitRemotes
		return newRe
	end
	return re
end

local SuitPurchaseRF = getOrCreateRemoteFunction("SuitPurchase")
local SuitEquipRF = getOrCreateRemoteFunction("SuitEquip")
local GetSuitDataRF = getOrCreateRemoteFunction("GetSuitData")
local SuitEquippedVFXRemote = getOrCreateRemoteEvent("SuitEquippedVFX")

-- Player Ownership Tracking: player -> { [suitId]: true }
local playerUnlockedSuits: { [Player]: { [string]: boolean } } = {}
local playerEquippedSuit: { [Player]: string } = {}
local playerAvatarBackups: { [Player]: Folder } = {}

-- 🔇 ZERO SFX POLICY: Neutralize any legacy Sound instances lingering in SoundService or Workspace
for _, sound in SoundService:GetDescendants() do
	if sound:IsA("Sound") then
		sound:Stop()
		sound.SoundId = ""
		sound:Destroy()
	end
end
for _, sound in Workspace:GetDescendants() do
	if sound:IsA("Sound") then
		sound:Stop()
		sound.SoundId = ""
		sound:Destroy()
	end
end

--------------------------------------------------------------------------------
-- 📡 REMOTE FUNCTION HANDLERS
--------------------------------------------------------------------------------

-- 1. Fetch Player's Unlocked Suits & Current Equipped Suit
GetSuitDataRF.OnServerInvoke = function(player: Player): ({ [string]: boolean }, string)
	local unlocked = playerUnlockedSuits[player]
	if not unlocked then
		unlocked = { [SuitConfig.DefaultSuitId] = true }
		playerUnlockedSuits[player] = unlocked
	end
	if RunService:IsStudio() then
		for _, s in SuitConfig.Suits do
			unlocked[s.Id] = true
		end
	end
	local equipped = playerEquippedSuit[player] or SuitConfig.DefaultSuitId
	return unlocked, equipped
end

-- 2. Purchase a New Suit (Server Authority Cash & Level Check)
SuitPurchaseRF.OnServerInvoke = function(player: Player, suitId: string): (boolean, string)
	if typeof(suitId) ~= "string" then
		return false, "Invalid suit ID."
	end

	local suit = SuitConfig.getSuitById(suitId)
	if not suit then
		return false, "Suit does not exist."
	end

	local unlocked = playerUnlockedSuits[player]
	if not unlocked then
		unlocked = { [SuitConfig.DefaultSuitId] = true }
		playerUnlockedSuits[player] = unlocked
	end

	if unlocked[suit.Id] == true then
		return false, "You already own this suit."
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return false, "PlayerData not loaded."
	end

	local levelVal = leaderstats:FindFirstChild("Level") :: IntValue?
	local cashVal = leaderstats:FindFirstChild("Hero Cash") :: IntValue?
	if not levelVal or not cashVal then
		return false, "Hero stats missing."
	end

	-- Level Requirement Check
	if levelVal.Value < suit.UnlockLevel then
		return false, string.format("Requires Level %d Hero Rank.", suit.UnlockLevel)
	end

	-- Hero Cash Economy Check
	if cashVal.Value < suit.HeroCashCost then
		return false, string.format("Insufficient Hero Cash (Needs $%d).", suit.HeroCashCost)
	end

	-- Deduct Cash & Grant Suit
	cashVal.Value -= suit.HeroCashCost
	unlocked[suit.Id] = true

	print(string.format("🛍️ [SuitService] %s purchased '%s' for $%d Hero Cash!", player.Name, suit.Name, suit.HeroCashCost))
	return true, "Suit unlocked!"
end

-- 3. Equip an Owned Suit
SuitEquipRF.OnServerInvoke = function(player: Player, suitId: string): (boolean, string)
	if typeof(suitId) ~= "string" then
		return false, "Invalid suit ID."
	end

	local suit = SuitConfig.getSuitById(suitId)
	if not suit then
		return false, "Suit does not exist."
	end
	local canonicalId = suit.Id

	local unlocked = playerUnlockedSuits[player]
	if RunService:IsStudio() then
		if not unlocked then
			unlocked = {}
			playerUnlockedSuits[player] = unlocked
		end
		unlocked[canonicalId] = true
	end

	if not unlocked or unlocked[canonicalId] ~= true then
		return false, "You do not own this suit yet."
	end

	playerEquippedSuit[player] = canonicalId
	player:SetAttribute("EquippedSuit", canonicalId)

	local char = player.Character
	if char then
		SuitApplier.applySuitToCharacter(player, char, canonicalId, playerAvatarBackups)
		SuitEquippedVFXRemote:FireAllClients(player, canonicalId, suit.ThemeColor)
	end

	print(string.format("🧬 [SuitService] %s equipped '%s'", player.Name, suit.Name))
	return true, "Suit equipped!"
end

--------------------------------------------------------------------------------
-- 👤 PLAYER LIFECYCLE MANAGEMENT
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local unlocked = { [SuitConfig.DefaultSuitId] = true, ["CustomAvatar"] = true }
	if RunService:IsStudio() then
		for _, s in SuitConfig.Suits do
			unlocked[s.Id] = true
		end
	end
	playerUnlockedSuits[player] = unlocked
	playerEquippedSuit[player] = SuitConfig.DefaultSuitId
	player:SetAttribute("EquippedSuit", SuitConfig.DefaultSuitId)

	local function handleCharacter(char: Model)
		-- Wait for Roblox to finish loading player's personal avatar appearance so we can cleanly capture/replace it
		if not player:HasAppearanceLoaded() then
			local appearanceLoaded = false
			local conn
			conn = player.CharacterAppearanceLoaded:Connect(function(c)
				if c == char then
					appearanceLoaded = true
					if conn then conn:Disconnect() end
				end
			end)
			local elapsed = 0
			while not appearanceLoaded and elapsed < 3.0 do
				task.wait(0.1)
				elapsed += 0.1
			end
			if conn then conn:Disconnect() end
		end

		task.wait(0.1)

		-- Capture authentic player appearance into permanent backup before any suit touches the rig!
		AvatarFitter.saveAvatarBackup(player, char, playerAvatarBackups)

		local currentSuit = playerEquippedSuit[player] or SuitConfig.DefaultSuitId
		SuitApplier.applySuitToCharacter(player, char, currentSuit, playerAvatarBackups)
	end

	player.CharacterAdded:Connect(handleCharacter)
	if player.Character then
		task.spawn(handleCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end

Players.PlayerRemoving:Connect(function(player)
	playerUnlockedSuits[player] = nil
	playerEquippedSuit[player] = nil
	if playerAvatarBackups[player] then
		playerAvatarBackups[player]:Destroy()
		playerAvatarBackups[player] = nil
	end
end)

print("🕷️ [SuitService] Spider-Man Wardrobe Authority (Modularized: TemplateScanner, AvatarFitter, ProceduralBuilder, SuitApplier) Online!")
