--!strict
--[[
	SuitService.server.luau
	Server Authority for Spider-Man Suit Wardrobe & Hero Cash Economy:
	- Zero-trust cash deduction and level requirement enforcement
	- Procedural suit coloring & clothing mesh replication
	- Active suit perk buffs (Defense HP shield, Velocity boost, etc.)
	- Persistent suit re-equipping upon character respawn
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

-- 📦 Create Suit Remotes Folder in ReplicatedStorage
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

-- 🎨 Apply Visual Appearance & Suit Perks to Character Model
local function applySuitToCharacter(player: Player, character: Model, suitId: string)
	local suit = SuitConfig.getSuitById(suitId)
	if not suit then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- 1. Apply Procedural Body Colors
	if suit.ProceduralColors then
		local bodyColors = character:FindFirstChildOfClass("BodyColors")
		if not bodyColors then
			bodyColors = Instance.new("BodyColors")
			bodyColors.Parent = character
		end

		bodyColors.HeadColor3 = suit.ProceduralColors.Head
		bodyColors.TorsoColor3 = suit.ProceduralColors.Torso
		bodyColors.LeftArmColor3 = suit.ProceduralColors.Arms
		bodyColors.RightArmColor3 = suit.ProceduralColors.Arms
		bodyColors.LeftLegColor3 = suit.ProceduralColors.Legs
		bodyColors.RightLegColor3 = suit.ProceduralColors.Legs
	end

	-- 2. Apply Custom Clothing if defined
	if suit.Clothing then
		if suit.Clothing.ShirtId then
			local shirt = character:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
			shirt.ShirtTemplate = suit.Clothing.ShirtId
			shirt.Parent = character
		end
		if suit.Clothing.PantsId then
			local pants = character:FindFirstChildOfClass("Pants") or Instance.new("Pants")
			pants.PantsTemplate = suit.Clothing.PantsId
			pants.Parent = character
		end
	end

	-- 3. Apply Gameplay Perks (Additive with Level-Scaled Base Health)
	local leaderstats = player:FindFirstChild("leaderstats")
	local levelVal = leaderstats and leaderstats:FindFirstChild("Level") :: IntValue?
	local baseMaxHp = 100 + (levelVal and (levelVal.Value - 1) * 10 or 0)

	if suit.PerkType == "Defense" then
		local bonusHp = suit.PerkValue
		humanoid.MaxHealth = baseMaxHp + bonusHp
		humanoid.Health = math.clamp(humanoid.Health + bonusHp, 0, humanoid.MaxHealth)
	else
		humanoid.MaxHealth = baseMaxHp
	end

	-- Expose Perk Attributes to Player
	player:SetAttribute("EquippedSuit", suit.Id)
	player:SetAttribute("SuitPerkType", suit.PerkType)
	player:SetAttribute("SuitPerkValue", suit.PerkValue)
end

-- 🌟 Create High-Tech Holographic Nanotech Equip VFX
local function triggerEquipVFX(character: Model, themeColor: Color3)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = themeColor
	ring.Transparency = 0.2
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Anchored = true
	ring.Parent = Workspace.Terrain

	local TweenService = game:GetService("TweenService")
	local tw = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 16, 16),
		Transparency = 1,
	})
	tw:Play()
	Debris:AddItem(ring, 0.5)
end

--------------------------------------------------------------------------------
-- 🌐 REMOTE FUNCTION HANDLERS
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

	if unlocked[suitId] == true then
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
	unlocked[suitId] = true

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
	suitId = suit.Id -- Canonicalize suit ID

	local unlocked = playerUnlockedSuits[player]
	if RunService:IsStudio() then
		if not unlocked then
			unlocked = {}
			playerUnlockedSuits[player] = unlocked
		end
		unlocked[suitId] = true
	end

	if not unlocked or unlocked[suitId] ~= true then
		return false, "You do not own this suit yet."
	end

	playerEquippedSuit[player] = suitId
	player:SetAttribute("EquippedSuit", suitId)

	local char = player.Character
	if char then
		applySuitToCharacter(player, char, suitId)
		triggerEquipVFX(char, suit.ThemeColor)
		SuitEquippedVFXRemote:FireAllClients(player, suitId, suit.ThemeColor)
	end

	print(string.format("🕷️ [SuitService] %s equipped '%s'", player.Name, suit.Name))
	return true, "Suit equipped!"
end

--------------------------------------------------------------------------------
-- 🔄 PLAYER LIFECYCLE MANAGEMENT
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local unlocked = { [SuitConfig.DefaultSuitId] = true }
	if RunService:IsStudio() then
		for _, s in SuitConfig.Suits do
			unlocked[s.Id] = true
		end
	end
	playerUnlockedSuits[player] = unlocked
	playerEquippedSuit[player] = SuitConfig.DefaultSuitId
	player:SetAttribute("EquippedSuit", SuitConfig.DefaultSuitId)

	player.CharacterAdded:Connect(function(char)
		task.wait(0.2)
		local currentSuit = playerEquippedSuit[player] or SuitConfig.DefaultSuitId
		applySuitToCharacter(player, char, currentSuit)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end

Players.PlayerRemoving:Connect(function(player)
	playerUnlockedSuits[player] = nil
	playerEquippedSuit[player] = nil
end)

print("🛍️ [SuitService] Spider-Man Wardrobe Authority & Hero Cash Economy Online!")
