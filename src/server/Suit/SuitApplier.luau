--!strict
--[[
	SuitApplier.luau
	Authoritative Suit Dressing Orchestrator:
	Applies custom avatar restoration, 3D rig dressing, procedural fallbacks,
	stat scaling, and gameplay perk replication.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

local AvatarFitter = require(script.Parent.AvatarFitter)
local ProceduralSuitBuilder = require(script.Parent.ProceduralSuitBuilder)

local SuitApplier = {}

function SuitApplier.applySuitToCharacter(
	player: Player,
	character: Model,
	suitId: string,
	playerAvatarBackups: { [Player]: Folder }
)
	local suit = SuitConfig.getSuitById(suitId)
	if not suit then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Mark character to avoid auto-discovery loops
	character:SetAttribute("IsPlayerCharacter", true)

	-- 🌟 Custom Avatar Option: Restore player's authentic Roblox avatar appearance!
	if suit.Id == "CustomAvatar" then
		AvatarFitter.stripCharacterAvatar(character)

		local restored = false
		local backupFolder = playerAvatarBackups[player]
		if not backupFolder or #backupFolder:GetChildren() == 0 then
			backupFolder = AvatarFitter.saveAvatarBackup(player, character, playerAvatarBackups)
		end

		if backupFolder and #backupFolder:GetChildren() > 0 then
			for _, item in backupFolder:GetChildren() do
				if item:IsA("Accessory") then
					humanoid:AddAccessory(item:Clone())
					restored = true
				elseif item:IsA("Shirt") or item:IsA("Pants") or item:IsA("ShirtGraphic") or item:IsA("BodyColors") then
					local existing = character:FindFirstChildOfClass(item.ClassName)
					if existing then existing:Destroy() end
					item:Clone().Parent = character
					restored = true
				end
			end

			local scaleFolder = backupFolder:FindFirstChild("Scales")
			if scaleFolder then
				for _, sc in scaleFolder:GetChildren() do
					if sc:IsA("NumberValue") then
						local humVal = humanoid:FindFirstChild(sc.Name) :: NumberValue?
						if humVal then
							humVal.Value = sc.Value
						end
					end
				end
			end
		end

		-- Fallback 1: Native LoadCharacterAppearance
		if not restored then
			pcall(function()
				player:LoadCharacterAppearance(character)
			end)
			task.wait(0.1)
			for _, child in character:GetChildren() do
				if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") then
					restored = true
					break
				end
			end
		end

		-- Fallback 2: HumanoidDescription from UserId
		if not restored then
			local targetUserId = player.UserId
			if targetUserId <= 0 then
				pcall(function()
					targetUserId = Players:GetUserIdFromNameAsync(player.Name)
				end)
			end
			if targetUserId > 0 then
				local sDesc, desc = pcall(function()
					return Players:GetHumanoidDescriptionFromUserId(targetUserId)
				end)
				if sDesc and desc then
					pcall(function()
						humanoid:ApplyDescription(desc)
					end)
					restored = true
				end
			end
		end

		-- Fallback 3: Clean street clothes so player is NEVER a naked dummy
		if not character:FindFirstChildOfClass("Shirt") then
			local shirt = Instance.new("Shirt")
			shirt.Name = "CasualShirt"
			shirt.ShirtTemplate = "rbxassetid://382537826"
			shirt.Parent = character
		end
		if not character:FindFirstChildOfClass("Pants") then
			local pants = Instance.new("Pants")
			pants.Name = "CasualPants"
			pants.PantsTemplate = "rbxassetid://382538059"
			pants.Parent = character
		end

		-- Ensure Head face decal is visible and unhidden
		local head = character:FindFirstChild("Head") :: BasePart?
		if head then
			local face = head:FindFirstChildOfClass("Decal")
			if face then
				face.Transparency = 0
				local savedFace = (backupFolder and backupFolder:GetAttribute("FaceTexture")) or character:GetAttribute("OriginalFaceTexture")
				if savedFace and typeof(savedFace) == "string" and savedFace ~= "" then
					face.Texture = savedFace
				end
			end
		end

		-- Authoritative Health & Level Scaling
		local leaderstats = player:FindFirstChild("leaderstats")
		local levelVal = leaderstats and leaderstats:FindFirstChild("Level") :: IntValue?
		local baseMaxHp = 100 + (levelVal and (levelVal.Value - 1) * 10 or 0)
		humanoid.MaxHealth = baseMaxHp
		humanoid.Health = math.clamp(humanoid.Health, 0, humanoid.MaxHealth)

		AvatarFitter.purgeRogueLimbWelds(character)

		player:SetAttribute("EquippedSuit", "CustomAvatar")
		player:SetAttribute("SuitPerkType", "Special")
		player:SetAttribute("SuitPerkValue", 1.0)
		player:SetAttribute("StarkShieldBonus", 0)
		character:SetAttribute("EquippedSuit", "CustomAvatar")
		character:SetAttribute("StarkShieldBonus", 0)
		return
	end

	-- 1. Apply dynamic R15 body proportions FIRST so rig dimensions are authoritative before attaching
	AvatarFitter.applySuitProportions(humanoid, suit)

	-- 2. Thoroughly strip personal avatar assets (Hair, Hats, Clothes, Face Decal)
	AvatarFitter.stripCharacterAvatar(character)

	-- 3. Try applying pre-authored rig template from ReplicatedStorage.Suits
	local templateApplied = AvatarFitter.applySuitTemplate(character, humanoid, suit)

	-- 4. If no pre-authored model exists, run procedural 3D visual customization
	if not templateApplied then
		ProceduralSuitBuilder.applyProceduralSuit3D(character, humanoid, suit)
	end

	-- 5. Apply Authoritative Gameplay Perks & Level Scaling
	local leaderstats = player:FindFirstChild("leaderstats")
	local levelVal = leaderstats and leaderstats:FindFirstChild("Level") :: IntValue?
	local baseMaxHp = 100 + (levelVal and (levelVal.Value - 1) * 10 or 0)

	local bonusHp = 0
	if suit.Id == "StarkTechSuit" then
		bonusHp = 25 -- Nanotech Armor Shield (+25 Max Health)
	elseif suit.PerkType == "Defense" then
		bonusHp = suit.PerkValue
	end

	humanoid.MaxHealth = baseMaxHp + bonusHp
	humanoid.Health = math.clamp(humanoid.Health + bonusHp, 0, humanoid.MaxHealth)

	-- 6. Purge any rogue welds and guarantee 100% movement freedom
	AvatarFitter.purgeRogueLimbWelds(character)

	-- Expose Authoritative Attributes
	player:SetAttribute("EquippedSuit", suit.Id)
	player:SetAttribute("SuitPerkType", suit.PerkType)
	player:SetAttribute("SuitPerkValue", suit.PerkValue)
	player:SetAttribute("StarkShieldBonus", if suit.Id == "StarkTechSuit" then 25 else 0)
	character:SetAttribute("EquippedSuit", suit.Id)
	character:SetAttribute("StarkShieldBonus", if suit.Id == "StarkTechSuit" then 25 else 0)
end

return SuitApplier
