--!strict
--[[
	SuitService.server.luau
	Server Authority for Spider-Man Suit Wardrobe & Hero Cash Economy:
	- Seamless avatar dressing & rig transformation across 6 canonical Spider-Man suits
	- Intelligent Auto-Discovery: Automatically detects imported avatar models in Workspace or ReplicatedStorage.Suits
	- Clean Avatar Stripping: Purges personal hair, hats, clothing & face decals so Spider-Man avatars fit flawlessly
	- Safe avatar cloning from ReplicatedStorage.Suits (Accessories, Models/Waldos, Clothing, BodyColors, SurfaceAppearances)
	- Zero-HTTP procedural 3D fallback (Waldos, Arm Blades, Hoodies, Tendrils, Web Bracers)
	- Dynamic R15 proportions via HumanoidDescription (pcall safe with NumberValue fallback)
	- Zero-trust cash deduction, level requirement enforcement, and persistent respawn dressing
	- Explicit lifecycle cleanup to prevent memory leaks and accessory stacking
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

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

-- 🔇 ZERO SFX POLICY: Neutralize any legacy Sound instances lingering in SoundService or Workspace
local SoundService = game:GetService("SoundService")
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
-- 🔍 INTELLIGENT SUIT TEMPLATE AUTO-DISCOVERY & CACHING
--------------------------------------------------------------------------------

local suitsFolder: Folder = (ReplicatedStorage:FindFirstChild("Suits") :: Folder?) or (function()
	local f = Instance.new("Folder")
	f.Name = "Suits"
	f.Parent = ReplicatedStorage
	return f
end)()

-- Identifies which canonical Spider-Man suit a model represents based on names, accessories, and parts
local function identifySuitIdForModel(model: Model): string?
	local mName = string.lower(model.Name)

	-- Direct name matching
	if string.find(mName, "symbiote") or string.find(mName, "venom") then return "SymbioteBlack" end
	if string.find(mName, "2099") or string.find(mName, "miguel") then return "Cyber2099" end
	if string.find(mName, "scarlet") then return "ScarletSpider" end
	if string.find(mName, "stark") or string.find(mName, "iron") then return "StarkTechSuit" end
	if string.find(mName, "miles") or string.find(mName, "spiderverse") or string.find(mName, "yugoxsf") then return "MilesSpiderVerse" end
	if string.find(mName, "classic") or string.find(mName, "wistumy") or string.find(mName, "peter") then return "ClassicSuit" end

	-- Deep inspection of accessories, parts, and clothing
	for _, child in model:GetDescendants() do
		local cName = string.lower(child.Name)
		if string.find(cName, "symbiote") then
			return "SymbioteBlack"
		elseif string.find(cName, "2099") or string.find(cName, "blade") then
			return "Cyber2099"
		elseif string.find(cName, "scarlet") or string.find(cName, "blue hoodie") then
			return "ScarletSpider"
		elseif string.find(cName, "extraredhead") or string.find(cName, "waldo") or string.find(cName, "iron") then
			return "StarkTechSuit"
		elseif string.find(cName, "darkhood") or string.find(cName, "sneaker") or string.find(cName, "comic eyes") then
			return "MilesSpiderVerse"
		elseif string.find(cName, "tight red web") or string.find(cName, "wistumy") then
			return "ClassicSuit"
		end
	end

	return nil
end

-- Scans Workspace showroom lineup and automatically registers templates into ReplicatedStorage.Suits
local function scanAndCacheTemplates()
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child.Name ~= "Terrain" and not child:GetAttribute("IsPlayerCharacter") then
			local matchedSuitId = identifySuitIdForModel(child)
			if matchedSuitId and not suitsFolder:FindFirstChild(matchedSuitId) then
				local clone = child:Clone()
				clone.Name = matchedSuitId

				-- Clean up scripts and humanoids inside the template so it acts as a clean static wardrobe asset
				for _, desc in clone:GetDescendants() do
					if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("Sound") then
						desc:Destroy()
					elseif desc:IsA("Humanoid") then
						desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					end
				end

				clone.Parent = suitsFolder
				print(string.format("🎯 [SuitService] Automatically linked '%s' as template for suit '%s'!", child.Name, matchedSuitId))
			end
		end
	end
end

-- Run initial template discovery
scanAndCacheTemplates()

-- Resolves the template model for a given suit ID
local function getSuitTemplate(suitId: string): Model?
	local template = suitsFolder:FindFirstChild(suitId) :: Model?
	if template then return template end

	-- Check if any model inside suitsFolder matches this suit ID via name/appearance
	for _, child in suitsFolder:GetChildren() do
		if child:IsA("Model") and identifySuitIdForModel(child) == suitId then
			return child
		end
	end

	-- Re-scan Workspace if not cached yet
	scanAndCacheTemplates()
	template = suitsFolder:FindFirstChild(suitId) :: Model?
	if template then return template end

	for _, child in suitsFolder:GetChildren() do
		if child:IsA("Model") and identifySuitIdForModel(child) == suitId then
			return child
		end
	end

	-- Check direct Workspace children as fallback
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child.Name ~= "Terrain" then
			if identifySuitIdForModel(child) == suitId then
				return child
			end
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- 🧼 AVATAR CLEANUP & LIFECYCLE MANAGEMENT
--------------------------------------------------------------------------------

-- Thoroughly strips player's personal avatar assets (Hair, Hats, Glasses, Layered Clothing, Civilian Shirts/Pants & Face Decals)
-- Ensures the Spider-Man suit avatar fits flawlessly without personal items poking through.
local function isCharacterLimb(name: string): boolean
	local lower = string.lower(name)
	local clean = string.gsub(lower, "[%s_]", "")
	if clean == "head"
		or clean == "torso"
		or clean == "uppertorso"
		or clean == "lowertorso"
		or clean == "humanoidrootpart"
		or clean == "rootpart"
		or string.find(clean, "arm") ~= nil
		or string.find(clean, "leg") ~= nil
		or string.find(clean, "hand") ~= nil
		or string.find(clean, "foot") ~= nil
	then
		return true
	end
	return false
end

local function resolveCharacterLimb(character: Model, limbName: string): BasePart?
	local direct = character:FindFirstChild(limbName) :: BasePart?
	if direct then return direct end

	local lower = string.lower(limbName)
	local clean = string.gsub(lower, "[%s_]", "")

	if clean == "head" then
		return character:FindFirstChild("Head") :: BasePart?
	elseif clean == "torso" or clean == "uppertorso" then
		return (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	elseif clean == "lowertorso" then
		return (character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?
	elseif string.find(clean, "left") and (string.find(clean, "wrist") or string.find(clean, "hand")) then
		return (character:FindFirstChild("LeftHand") or character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("Left Arm")) :: BasePart?
	elseif string.find(clean, "right") and (string.find(clean, "wrist") or string.find(clean, "hand")) then
		return (character:FindFirstChild("RightHand") or character:FindFirstChild("RightLowerArm") or character:FindFirstChild("Right Arm")) :: BasePart?
	elseif string.find(clean, "left") and string.find(clean, "arm") then
		return (character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")) :: BasePart?
	elseif string.find(clean, "right") and string.find(clean, "arm") then
		return (character:FindFirstChild("RightLowerArm") or character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")) :: BasePart?
	elseif string.find(clean, "left") and (string.find(clean, "leg") or string.find(clean, "foot")) then
		return (character:FindFirstChild("LeftLowerLeg") or character:FindFirstChild("LeftUpperLeg") or character:FindFirstChild("Left Leg")) :: BasePart?
	elseif string.find(clean, "right") and (string.find(clean, "leg") or string.find(clean, "foot")) then
		return (character:FindFirstChild("RightLowerLeg") or character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("Right Leg")) :: BasePart?
	end

	return (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
end

local function resolveR15AttachmentName(accessory: Accessory, handle: BasePart): (string, string)
	local accName = string.lower(accessory.Name)
	local handleName = string.lower(handle.Name)
	local att = handle:FindFirstChildOfClass("Attachment")
	local rawAttName = if att then string.lower(att.Name) else ""
	local combined = accName .. " " .. handleName .. " " .. rawAttName

	-- 1. Web Shooters & Wrist / Forearm accessories
	local hasShooter = string.find(combined, "shooter")
		or string.find(combined, "wrist")
		or string.find(combined, "bracer")
		or string.find(combined, "gauntlet")
		or string.find(combined, "blade")
		or string.find(combined, "cuff")
	if hasShooter then
		local isLeft = string.find(combined, "left")
			or string.find(combined, "%s+l%s*")
			or string.find(combined, "[%._-]l")
			or string.sub(accName, -2) == " l"
			or string.sub(accName, -1) == "l"
		local isRight = string.find(combined, "right")
			or string.find(combined, "%s+r%s*")
			or string.find(combined, "[%._-]r")
			or string.sub(accName, -2) == " r"
			or string.sub(accName, -1) == "r"

		if isLeft and not isRight then
			return "LeftWristAttachment", "LeftHand"
		else
			return "RightWristAttachment", "RightHand"
		end
	end

	-- 2. Belt / Waist / Hip accessories
	if string.find(combined, "belt") or string.find(combined, "waist") or string.find(combined, "hip") or string.find(combined, "pelvis") then
		return "WaistCenterAttachment", "LowerTorso"
	end

	-- 3. Torso / Vest / Hoodie / Jacket / Cape / Waldo / Back / Web Wings
	if string.find(combined, "hoodie") or string.find(combined, "vest") or string.find(combined, "jacket") or string.find(combined, "shirt") or string.find(combined, "torso") then
		if string.find(combined, "front") then
			return "BodyFrontAttachment", "UpperTorso"
		else
			return "BodyBackAttachment", "UpperTorso"
		end
	end

	if string.find(combined, "back") or string.find(combined, "waldo") or string.find(combined, "pack") or string.find(combined, "wing") or string.find(combined, "cape") or string.find(combined, "tendril") or string.find(combined, "spine") then
		return "BodyBackAttachment", "UpperTorso"
	end

	-- 4. Mask / Face / Eyes / Goggles / Lens
	if string.find(combined, "mask") or string.find(combined, "face") or string.find(combined, "eye") or string.find(combined, "lens") or string.find(combined, "goggle") or string.find(combined, "glasses") or string.find(combined, "hood") then
		return "FaceFrontAttachment", "Head"
	end

	-- 5. Standard Hat / Headwear fallback
	return "HatAttachment", "Head"
end

local function stripCharacterAvatar(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:RemoveAccessories()
	end

	for _, child in character:GetChildren() do
		if child:IsA("Accessory") then
			child:Destroy()
		elseif child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end

	-- Purge all previous suit assets (models, parts, surface appearances, meshes)
	for _, desc in character:GetDescendants() do
		if desc:GetAttribute("IsSuitAsset") == true
			or CollectionService:HasTag(desc, "SuitAsset")
			or string.sub(desc.Name, 1, 5) == "Suit_"
		then
			desc:Destroy()
		end
	end

	-- Make default personal face decal transparent so eyes/smile don't show through the Spider-Man mask
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		local face = head:FindFirstChildOfClass("Decal")
		if face then
			if not character:GetAttribute("OriginalFaceTexture") then
				character:SetAttribute("OriginalFaceTexture", face.Texture)
			end
			face.Transparency = 1
		end
	end
end

-- Safely copy an accessory from a template and socket it to the rig
local function applyAccessorySafely(humanoid: Humanoid, character: Model, accessoryTemplate: Accessory)
	local acc = accessoryTemplate:Clone()
	acc:SetAttribute("IsSuitAsset", true)
	CollectionService:AddTag(acc, "SuitAsset")

	-- 1. Joint & Weld Hygiene: Destroy any stale cloned joints or AccessoryWelds prior to AddAccessory
	for _, desc in acc:GetDescendants() do
		if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
			desc:Destroy()
		end
	end

	-- 2. Physics Safety: Every cloned accessory part must have Anchored = false, CanCollide = false, Massless = true
	for _, desc in acc:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			desc.Massless = true
			desc.CastShadow = false
		end
	end

	local handle = acc:FindFirstChild("Handle") :: BasePart?
	if not handle then
		handle = acc:FindFirstChildWhichIsA("BasePart")
		if handle then
			handle.Name = "Handle"
		end
	end

	if not handle then
		return
	end

	-- 3. R6-to-R15 Attachment Fallback & Socket Redirection
	local existingAtt = handle:FindFirstChildOfClass("Attachment")
	local hasMatchingRigAttachment = false
	if existingAtt then
		local foundAtt = character:FindFirstChild(existingAtt.Name, true)
		if foundAtt and foundAtt:IsA("Attachment") then
			hasMatchingRigAttachment = true
		end
	end

	local targetAttName, targetLimbName = resolveR15AttachmentName(acc, handle)
	local targetLimb = resolveCharacterLimb(character, targetLimbName)

	if not hasMatchingRigAttachment then
		if existingAtt then
			existingAtt.Name = targetAttName
		else
			local newAtt = Instance.new("Attachment")
			newAtt.Name = targetAttName
			newAtt.Parent = handle
		end

		-- Ensure the target host limb on R15 character has this attachment so AddAccessory can socket it
		if targetLimb and not targetLimb:FindFirstChild(targetAttName) then
			local rigAtt = Instance.new("Attachment")
			rigAtt.Name = targetAttName
			rigAtt.Parent = targetLimb
		end
	end

	-- 4. Socket via Humanoid:AddAccessory()
	local ok = pcall(function()
		humanoid:AddAccessory(acc)
	end)

	-- 5. Fallback Weld if AddAccessory failed or failed to parent
	if not ok or not acc:IsDescendantOf(character) then
		acc.Parent = character
		if targetLimb then
			handle.CFrame = targetLimb.CFrame
			local w = Instance.new("WeldConstraint")
			w.Part0 = targetLimb
			w.Part1 = handle
			w.Parent = handle
		end
	end

	-- 6. Guarantee Handle is never anchored
	handle.Anchored = false
end

--------------------------------------------------------------------------------
-- ?? DYNAMIC R15 PROPORTIONS (Humanoid Scale System)
--------------------------------------------------------------------------------

local function applySuitProportions(humanoid: Humanoid, suit: SuitConfig.SuitDefinition)
	local scale = suit.BodyScale

	local h = scale and scale.Height or 1.0
	local w = scale and scale.Width or 1.0
	local d = scale and scale.Depth or 1.0
	local hd = scale and scale.Head or 1.0
	local bt = scale and scale.BodyType or 0.0
	local bp = scale and scale.Proportion or 0.0

	local function setScale(name: string, value: number)
		local val = humanoid:FindFirstChild(name) :: NumberValue?
		if not val then
			val = Instance.new("NumberValue")
			val.Name = name
			val.Parent = humanoid
		end
		val.Value = value
	end

	setScale("BodyHeightScale", h)
	setScale("BodyWidthScale", w)
	setScale("BodyDepthScale", d)
	setScale("HeadScale", hd)
	setScale("BodyTypeScale", bt)
	setScale("BodyProportionScale", bp)
end

--------------------------------------------------------------------------------
-- ?? TEMPLATE CLONING (ReplicatedStorage.Suits)
--------------------------------------------------------------------------------

local function applySuitTemplate(character: Model, humanoid: Humanoid, suit: SuitConfig.SuitDefinition): boolean
	local template = getSuitTemplate(suit.Id)

	if not template or not template:IsA("Model") then
		return false
	end

	-- 1. Apply BodyColors from template
	local templateColors = template:FindFirstChildOfClass("BodyColors")
	if templateColors then
		local charColors = character:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
		charColors.HeadColor3 = templateColors.HeadColor3
		charColors.TorsoColor3 = templateColors.TorsoColor3
		charColors.LeftArmColor3 = templateColors.LeftArmColor3
		charColors.RightArmColor3 = templateColors.RightArmColor3
		charColors.LeftLegColor3 = templateColors.LeftLegColor3
		charColors.RightLegColor3 = templateColors.RightLegColor3
		charColors.Parent = character
	elseif suit.ProceduralColors then
		local charColors = character:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
		charColors.HeadColor3 = suit.ProceduralColors.Head
		charColors.TorsoColor3 = suit.ProceduralColors.Torso
		charColors.LeftArmColor3 = suit.ProceduralColors.Arms
		charColors.RightArmColor3 = suit.ProceduralColors.Arms
		charColors.LeftLegColor3 = suit.ProceduralColors.Legs
		charColors.RightLegColor3 = suit.ProceduralColors.Legs
		charColors.Parent = character
	end

	-- 2. Apply Clothing from template (Shirt & Pants)
	local templateShirt = template:FindFirstChildOfClass("Shirt")
	if templateShirt then
		local charShirt = character:FindFirstChildOfClass("Shirt")
		if charShirt then charShirt:Destroy() end
		local newShirt = templateShirt:Clone()
		newShirt.Parent = character
	end

	local templatePants = template:FindFirstChildOfClass("Pants")
	if templatePants then
		local charPants = character:FindFirstChildOfClass("Pants")
		if charPants then charPants:Destroy() end
		local newPants = templatePants:Clone()
		newPants.Parent = character
	end

	-- 3. Apply Accessories & Welded 3D Equipment (e.g. Waldo Arm Packs, Spikes, Hoodies)
	local upperTorso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?

	for _, child in template:GetChildren() do
		if child:IsA("Accessory") then
			applyAccessorySafely(humanoid, character, child)
		elseif child:IsA("Model") and upperTorso then
			-- Verify model is not actually an R6 limb container
			if not isCharacterLimb(child.Name) then
				local modelClone = child:Clone()
				modelClone:SetAttribute("IsSuitAsset", true)
				CollectionService:AddTag(modelClone, "SuitAsset")

				-- Clean up any cloned welds targeting external instances outside this model
				for _, desc in modelClone:GetDescendants() do
					if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
						local p0 = (desc :: any).Part0
						local p1 = (desc :: any).Part1
						if (p0 and not p0:IsDescendantOf(modelClone)) or (p1 and not p1:IsDescendantOf(modelClone)) then
							desc:Destroy()
						end
					end
				end

				local primary = modelClone.PrimaryPart or modelClone:FindFirstChildWhichIsA("BasePart")
				if primary then
					modelClone.PrimaryPart = primary
					for _, part in modelClone:GetDescendants() do
						if part:IsA("BasePart") then
							part.Anchored = false
							part.CanCollide = false
							part.Massless = true
							part.CastShadow = false
							if part ~= primary then
								local innerWeld = Instance.new("WeldConstraint")
								innerWeld.Part0 = primary
								innerWeld.Part1 = part
								innerWeld.Parent = part
							end
						end
					end

					-- Align to upperTorso, preserving template authored offset if template has a torso
					local templateTorso = (template:FindFirstChild("UpperTorso") or template:FindFirstChild("Torso")) :: BasePart?
					if templateTorso then
						local relPivot = templateTorso.CFrame:ToObjectSpace(child:GetPivot())
						modelClone:PivotTo(upperTorso.CFrame * relPivot)
					else
						modelClone:PivotTo(upperTorso.CFrame)
					end

					local mountWeld = Instance.new("WeldConstraint")
					mountWeld.Part0 = upperTorso
					mountWeld.Part1 = primary
					mountWeld.Parent = primary

					modelClone.Parent = character
				end
			end
		elseif child:IsA("BasePart") and not isCharacterLimb(child.Name) and upperTorso then
			-- Standalone rigid parts (e.g. masks, goggles, chest emblems, web shooters, extra armor)
			local partClone = child:Clone()
			partClone:SetAttribute("IsSuitAsset", true)
			CollectionService:AddTag(partClone, "SuitAsset")
			partClone.Anchored = false
			partClone.CanCollide = false
			partClone.Massless = true
			partClone.CastShadow = false

			-- Clean up internal joints targeting external template instances
			for _, desc in partClone:GetChildren() do
				if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
					desc:Destroy()
				end
			end

			-- Determine which limb this part should attach to
			local targetLimbName: string? = nil

			-- Check if template had a joint linking this part to a limb
			for _, desc in template:GetDescendants() do
				if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
					local p0 = (desc :: any).Part0
					local p1 = (desc :: any).Part1
					if p0 == child and p1 and isCharacterLimb(p1.Name) then
						targetLimbName = p1.Name
						break
					elseif p1 == child and p0 and isCharacterLimb(p0.Name) then
						targetLimbName = p0.Name
						break
					end
				end
			end

			-- Fallback to name heuristic if no joint exists
			if not targetLimbName then
				local lower = string.lower(child.Name)
				if string.find(lower, "head") or string.find(lower, "mask") or string.find(lower, "eye") or string.find(lower, "lens") or string.find(lower, "ear") or string.find(lower, "horn") then
					targetLimbName = "Head"
				elseif string.find(lower, "leftarm") or string.find(lower, "leftwrist") or string.find(lower, "leftforearm") or string.find(lower, "blade_l") or string.find(lower, "bladel") then
					targetLimbName = "LeftLowerArm"
				elseif string.find(lower, "rightarm") or string.find(lower, "rightwrist") or string.find(lower, "rightforearm") or string.find(lower, "blade_r") or string.find(lower, "blader") then
					targetLimbName = "RightLowerArm"
				elseif string.find(lower, "leftleg") or string.find(lower, "leftfoot") or string.find(lower, "leftknee") then
					targetLimbName = "LeftLowerLeg"
				elseif string.find(lower, "rightleg") or string.find(lower, "rightfoot") or string.find(lower, "rightknee") then
					targetLimbName = "RightLowerLeg"
				else
					local closestDist = math.huge
					for _, limb in template:GetChildren() do
						if limb:IsA("BasePart") and isCharacterLimb(limb.Name) then
							local dist = (limb.Position - child.Position).Magnitude
							if dist < closestDist then
								closestDist = dist
								targetLimbName = limb.Name
							end
						end
					end
				end
			end

			local targetLimb = resolveCharacterLimb(character, targetLimbName or "UpperTorso")
			local templateLimb = if targetLimbName then template:FindFirstChild(targetLimbName) :: BasePart? else nil

			if targetLimb then
				if templateLimb then
					local relCFrame = templateLimb.CFrame:ToObjectSpace(child.CFrame)
					partClone.CFrame = targetLimb.CFrame * relCFrame
				else
					partClone.CFrame = targetLimb.CFrame
				end

				partClone.Parent = character

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = targetLimb
				weld.Part1 = partClone
				weld.Parent = partClone
			end
		end
	end

	-- 4. Replicate SurfaceAppearances, SpecialMeshes, and Decals across R15 and R6 limb topologies
	local limbMapping: { [string]: { string } } = {
		["Head"] = { "Head" },
		["UpperTorso"] = { "UpperTorso" },
		["LowerTorso"] = { "LowerTorso" },
		["Torso"] = { "UpperTorso", "LowerTorso" },
		["Left Arm"] = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
		["Right Arm"] = { "RightUpperArm", "RightLowerArm", "RightHand" },
		["Left Leg"] = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
		["Right Leg"] = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
		["LeftUpperArm"] = { "LeftUpperArm" },
		["LeftLowerArm"] = { "LeftLowerArm" },
		["LeftHand"] = { "LeftHand" },
		["RightUpperArm"] = { "RightUpperArm" },
		["RightLowerArm"] = { "RightLowerArm" },
		["RightHand"] = { "RightHand" },
		["LeftUpperLeg"] = { "LeftUpperLeg" },
		["LeftLowerLeg"] = { "LeftLowerLeg" },
		["LeftFoot"] = { "LeftFoot" },
		["RightUpperLeg"] = { "RightUpperLeg" },
		["RightLowerLeg"] = { "RightLowerLeg" },
		["RightFoot"] = { "RightFoot" },
	}

	for tLimbName, targetLimbs in limbMapping do
		local tLimb = template:FindFirstChild(tLimbName) :: BasePart?
		if tLimb then
			local sa = tLimb:FindFirstChildOfClass("SurfaceAppearance")
			local mesh = tLimb:FindFirstChildOfClass("SpecialMesh")

			for _, cLimbName in targetLimbs do
				local cLimb = character:FindFirstChild(cLimbName) :: BasePart?
				if cLimb then
					if sa and not cLimb:FindFirstChildOfClass("SurfaceAppearance") then
						local saClone = sa:Clone()
						saClone:SetAttribute("IsSuitAsset", true)
						CollectionService:AddTag(saClone, "SuitAsset")
						saClone.Parent = cLimb
					end
					if mesh and not cLimb:FindFirstChildOfClass("SpecialMesh") then
						local meshClone = mesh:Clone()
						meshClone:SetAttribute("IsSuitAsset", true)
						CollectionService:AddTag(meshClone, "SuitAsset")
						meshClone.Parent = cLimb
					end
				end
			end
		end
	end

	-- Copy Face Decal (e.g. Spider-Man mask eyes) from template Head to character Head
	local tHead = template:FindFirstChild("Head") :: BasePart?
	local cHead = character:FindFirstChild("Head") :: BasePart?
	if tHead and cHead then
		local tFace = tHead:FindFirstChildOfClass("Decal")
		if tFace then
			local cFace = cHead:FindFirstChildOfClass("Decal")
			if cFace then
				cFace.Texture = tFace.Texture
				cFace.Transparency = tFace.Transparency
			else
				local newFace = tFace:Clone()
				newFace:SetAttribute("IsSuitAsset", true)
				CollectionService:AddTag(newFace, "SuitAsset")
				newFace.Parent = cHead
			end
		end
	end

	return true
end

-- Dedicated physical constraint cleaner: purges any rogue weld that locks legs or arms to torso/root
local function purgeRogueLimbWelds(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local upperTorso = character:FindFirstChild("UpperTorso")
	local lowerTorso = character:FindFirstChild("LowerTorso")

	local torsoAndRoot: { [Instance]: boolean } = {}
	if root then torsoAndRoot[root] = true end
	if upperTorso then torsoAndRoot[upperTorso] = true end
	if lowerTorso then torsoAndRoot[lowerTorso] = true end

	for _, desc in character:GetDescendants() do
		if desc:IsA("WeldConstraint") then
			local p0 = desc.Part0
			local p1 = desc.Part1
			if p0 and p1 then
				local p0IsTorso = torsoAndRoot[p0] == true
				local p1IsTorso = torsoAndRoot[p1] == true

				local p0Name = string.lower(p0.Name)
				local p1Name = string.lower(p1.Name)

				local p0IsLeg = string.find(p0Name, "leg") ~= nil or string.find(p0Name, "foot") ~= nil
				local p1IsLeg = string.find(p1Name, "leg") ~= nil or string.find(p1Name, "foot") ~= nil

				local p0IsArm = string.find(p0Name, "arm") ~= nil or string.find(p0Name, "hand") ~= nil
				local p1IsArm = string.find(p1Name, "arm") ~= nil or string.find(p1Name, "hand") ~= nil

				-- Rogue weld: leg/foot welded to torso or root (destroys leg physics solver)
				if (p0IsTorso and p1IsLeg) or (p1IsTorso and p0IsLeg) then
					desc:Destroy()
				-- Rogue weld: standard character arm welded to torso (bypassing Motor6D shoulder)
				elseif (p0IsTorso and p1IsArm and not desc:GetAttribute("IsSuitAsset")) or (p1IsTorso and p0IsArm and not desc:GetAttribute("IsSuitAsset")) then
					desc:Destroy()
				-- Rogue weld: cross-welding two animated legs together
				elseif p0IsLeg and p1IsLeg and p0 ~= p1 and ((string.find(p0.Name, "Left") and string.find(p1.Name, "Right")) or (string.find(p0.Name, "Right") and string.find(p1.Name, "Left"))) then
					desc:Destroy()
				end
			end
		end

		-- Guarantee all body and suit parts are unanchored (except temporary VFX)
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" and desc.Anchored then
			desc.Anchored = false
		end
	end

	-- Verify humanoid movement freedom
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.Sit = false
		if humanoid.WalkSpeed < 20 then
			humanoid.WalkSpeed = 20
		end
	end
end

--------------------------------------------------------------------------------
-- ?? PROCEDURAL 3D ACCESSORY & RIG CUSTOMIZATION FALLBACK
--------------------------------------------------------------------------------

local function createProceduralPart(
	character: Model,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parentLimb: BasePart,
	offsetCFrame: CFrame
): BasePart
	local part = Instance.new("Part")
	part.Name = "Suit_" .. name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.Massless = true
	part.CastShadow = false
	part:SetAttribute("IsSuitAsset", true)
	CollectionService:AddTag(part, "SuitAsset")
	part.CFrame = parentLimb.CFrame * offsetCFrame
	part.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parentLimb
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function applyProceduralSuit3D(character: Model, humanoid: Humanoid, suit: SuitConfig.SuitDefinition)
	-- 1. Apply Body Colors
	if suit.ProceduralColors then
		local bodyColors = character:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
		bodyColors.HeadColor3 = suit.ProceduralColors.Head
		bodyColors.TorsoColor3 = suit.ProceduralColors.Torso
		bodyColors.LeftArmColor3 = suit.ProceduralColors.Arms
		bodyColors.RightArmColor3 = suit.ProceduralColors.Arms
		bodyColors.LeftLegColor3 = suit.ProceduralColors.Legs
		bodyColors.RightLegColor3 = suit.ProceduralColors.Legs
		bodyColors.Parent = character
	end

	-- 2. Apply Clothing if provided
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

	-- 3. Resolve Target Rig Limbs (Supports R15 and R6)
	local upperTorso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	local rightLowerArm = (character:FindFirstChild("RightLowerArm") or character:FindFirstChild("Right Arm")) :: BasePart?
	local leftLowerArm = (character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("Left Arm")) :: BasePart?
	local rightLowerLeg = (character:FindFirstChild("RightLowerLeg") or character:FindFirstChild("Right Leg")) :: BasePart?
	local leftLowerLeg = (character:FindFirstChild("LeftLowerLeg") or character:FindFirstChild("Left Leg")) :: BasePart?

	if not upperTorso then return end

	-- Classic Red & Blue Suit: Dual Forearm Web Shooter Bracers
	if suit.Id == "ClassicSuit" then
		if rightLowerArm then
			createProceduralPart(character, "WebShooterRight", Vector3.new(1.05, 0.4, 1.05), Color3.fromRGB(195, 35, 45), Enum.Material.Metal, rightLowerArm, CFrame.new(0, -0.4, 0))
		end
		if leftLowerArm then
			createProceduralPart(character, "WebShooterLeft", Vector3.new(1.05, 0.4, 1.05), Color3.fromRGB(195, 35, 45), Enum.Material.Metal, leftLowerArm, CFrame.new(0, -0.4, 0))
		end

	-- Stark Tech Suit: 4 Articulated Nanotech Waldo Arms & Arc Chest Badge
	elseif suit.Id == "StarkTechSuit" then
		createProceduralPart(character, "WaldoBackCore", Vector3.new(1.3, 1.2, 0.45), Color3.fromRGB(215, 40, 50), Enum.Material.Metal, upperTorso, CFrame.new(0, 0.1, 0.7))
		createProceduralPart(character, "ArcReactorChest", Vector3.new(0.65, 0.65, 0.12), Color3.fromRGB(60, 220, 255), Enum.Material.Neon, upperTorso, CFrame.new(0, 0.2, -0.65))

	-- Miles Morales: Casual Spider-Verse Hoodie Collar & Sneaker Cuffs
	elseif suit.Id == "MilesSpiderVerse" then
		createProceduralPart(character, "MilesHoodieCollar", Vector3.new(1.9, 0.45, 1.55), Color3.fromRGB(24, 24, 28), Enum.Material.Fabric, upperTorso, CFrame.new(0, 0.8, 0.1))
		if rightLowerLeg then
			createProceduralPart(character, "MilesSneakerRight", Vector3.new(1.08, 0.5, 1.08), Color3.fromRGB(235, 235, 245), Enum.Material.SmoothPlastic, rightLowerLeg, CFrame.new(0, -0.65, 0))
		end
		if leftLowerLeg then
			createProceduralPart(character, "MilesSneakerLeft", Vector3.new(1.08, 0.5, 1.08), Color3.fromRGB(235, 235, 245), Enum.Material.SmoothPlastic, leftLowerLeg, CFrame.new(0, -0.65, 0))
		end

	-- Symbiote Black: Organic Tendrils & Alien Spikes
	elseif suit.Id == "SymbioteBlack" then
		local alienColor = Color3.fromRGB(15, 15, 20)
		createProceduralPart(character, "SymbioteSpine", Vector3.new(0.55, 1.8, 0.5), alienColor, Enum.Material.SmoothPlastic, upperTorso, CFrame.new(0, 0, 0.75))

	-- Scarlet Spider: Ben Reilly's Sleeveless Blue Hoodie Vest & Cuffs
	elseif suit.Id == "ScarletSpider" then
		local vestBlue = Color3.fromRGB(35, 105, 220)
		createProceduralPart(character, "ScarletVestBody", Vector3.new(2.15, 1.95, 1.25), vestBlue, Enum.Material.Fabric, upperTorso, CFrame.new(0, 0, 0))

	-- 2099 Cyber Suit: Crimson Arm Blades & Holographic Cape Fins
	elseif suit.Id == "Cyber2099" then
		local cyberNeon = Color3.fromRGB(255, 35, 75)
		if rightLowerArm then
			createProceduralPart(character, "BladeR_Base", Vector3.new(0.25, 0.8, 0.4), Color3.fromRGB(30, 75, 225), Enum.Material.Metal, rightLowerArm, CFrame.new(0.55, -0.1, 0))
		end
		if leftLowerArm then
			createProceduralPart(character, "BladeL_Base", Vector3.new(0.25, 0.8, 0.4), Color3.fromRGB(30, 75, 225), Enum.Material.Metal, leftLowerArm, CFrame.new(-0.55, -0.1, 0))
		end
	end
end

--------------------------------------------------------------------------------
-- ⚡ AUTHORITATIVE SUIT APPLICATION
--------------------------------------------------------------------------------

local function applySuitToCharacter(player: Player, character: Model, suitId: string)
	local suit = SuitConfig.getSuitById(suitId)
	if not suit then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Mark character to avoid auto-discovery loops
	character:SetAttribute("IsPlayerCharacter", true)

	-- 1. Apply dynamic R15 body proportions FIRST so rig dimensions are authoritative before attaching
	applySuitProportions(humanoid, suit)

	-- 2. Thoroughly strip personal avatar assets (Hair, Hats, Clothes, Face Decal)
	stripCharacterAvatar(character)

	-- 3. Try applying pre-authored rig template from ReplicatedStorage.Suits
	local templateApplied = applySuitTemplate(character, humanoid, suit)

	-- 4. If no pre-authored model exists, run procedural 3D visual customization
	if not templateApplied then
		applyProceduralSuit3D(character, humanoid, suit)
	end

	-- 5. Apply Authoritative Gameplay Perks & Level Scaling
	local leaderstats = player:FindFirstChild("leaderstats")
	local levelVal = leaderstats and leaderstats:FindFirstChild("Level") :: IntValue?
	local baseMaxHp = 100 + (levelVal and (levelVal.Value - 1) * 10 or 0)

	local bonusHp = 0
	if suit.Id == "StarkTechSuit" then
		bonusHp = 25 -- ??? Nanotech Armor Shield (+25 Max Health)
	elseif suit.PerkType == "Defense" then
		bonusHp = suit.PerkValue
	end

	humanoid.MaxHealth = baseMaxHp + bonusHp
	humanoid.Health = math.clamp(humanoid.Health + bonusHp, 0, humanoid.MaxHealth)

	-- 5. Purge any rogue welds and guarantee 100% movement freedom
	purgeRogueLimbWelds(character)

	-- Expose Authoritative Attributes
	player:SetAttribute("EquippedSuit", suit.Id)
	player:SetAttribute("SuitPerkType", suit.PerkType)
	player:SetAttribute("SuitPerkValue", suit.PerkValue)
	player:SetAttribute("StarkShieldBonus", if suit.Id == "StarkTechSuit" then 25 else 0)
	character:SetAttribute("EquippedSuit", suit.Id)
	character:SetAttribute("StarkShieldBonus", if suit.Id == "StarkTechSuit" then 25 else 0)
end

-- ⚡ High-Tech Holographic Nanotech Equip VFX
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

	local tw = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 16, 16),
		Transparency = 1,
	})
	tw:Play()
	Debris:AddItem(ring, 0.5)
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
		applySuitToCharacter(player, char, canonicalId)
		triggerEquipVFX(char, suit.ThemeColor)
		SuitEquippedVFXRemote:FireAllClients(player, canonicalId, suit.ThemeColor)
	end

	print(string.format("🧬 [SuitService] %s equipped '%s'", player.Name, suit.Name))
	return true, "Suit equipped!"
end

--------------------------------------------------------------------------------
-- 👤 PLAYER LIFECYCLE MANAGEMENT
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
		-- Wait for Roblox to finish loading player's personal avatar appearance so we can cleanly replace it
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
			while not appearanceLoaded and elapsed < 2.5 do
				task.wait(0.1)
				elapsed += 0.1
			end
			if conn then conn:Disconnect() end
		end

		task.wait(0.05)
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

print("🕷️ [SuitService] Spider-Man Wardrobe Authority & Auto-Discovery Rig Engine Online!")
