--!strict
--[[
	AvatarFitter.luau
	Handles avatar stripping, R15 limb resolution, accessory socketing,
	dynamic proportions, template cloning, and rogue limb weld purging.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

local SuitTemplateScanner = require(script.Parent.SuitTemplateScanner)

local AvatarFitter = {}

function AvatarFitter.isCharacterLimb(name: string): boolean
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

function AvatarFitter.resolveCharacterLimb(character: Model, limbName: string): BasePart?
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

function AvatarFitter.resolveR15AttachmentName(accessory: Accessory, handle: BasePart): (string, string)
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

function AvatarFitter.saveAvatarBackup(player: Player, character: Model, playerAvatarBackups: { [Player]: Folder }): Folder?
	local existing = playerAvatarBackups[player]
	if existing and #existing:GetChildren() > 0 then
		return existing
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	-- Check if character currently has authentic personal items
	local count = 0
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("BodyColors") then
			count += 1
		end
	end

	-- If character was already stripped (e.g. from a prior suit), attempt to load authentic appearance from Roblox
	if count <= 1 then
		pcall(function()
			player:LoadCharacterAppearance(character)
		end)
		task.wait(0.2)
	end

	local backupFolder = Instance.new("Folder")
	backupFolder.Name = "AvatarBackup_" .. tostring(player.UserId)

	for _, child in character:GetChildren() do
		if (child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("BodyColors"))
			and not child:GetAttribute("IsSuitAsset")
			and not CollectionService:HasTag(child, "SuitAsset")
		then
			child:Clone().Parent = backupFolder
		end
	end

	local scaleFolder = Instance.new("Folder")
	scaleFolder.Name = "Scales"
	scaleFolder.Parent = backupFolder
	for _, sc in humanoid:GetChildren() do
		if sc:IsA("NumberValue") then
			sc:Clone().Parent = scaleFolder
		end
	end

	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		local face = head:FindFirstChildOfClass("Decal")
		if face and face.Texture ~= "" then
			backupFolder:SetAttribute("FaceTexture", face.Texture)
		end
	end

	playerAvatarBackups[player] = backupFolder
	return backupFolder
end

function AvatarFitter.stripCharacterAvatar(character: Model)
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

function AvatarFitter.applyAccessorySafely(humanoid: Humanoid, character: Model, accessoryTemplate: Accessory)
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

	local targetAttName, targetLimbName = AvatarFitter.resolveR15AttachmentName(acc, handle)
	local targetLimb = AvatarFitter.resolveCharacterLimb(character, targetLimbName)

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

function AvatarFitter.applySuitProportions(humanoid: Humanoid, suit: SuitConfig.SuitDefinition)
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

function AvatarFitter.applySuitTemplate(character: Model, humanoid: Humanoid, suit: SuitConfig.SuitDefinition): boolean
	local template = SuitTemplateScanner.getSuitTemplate(suit.Id)

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
			AvatarFitter.applyAccessorySafely(humanoid, character, child)
		elseif child:IsA("Model") and upperTorso then
			-- Verify model is not actually an R6 limb container
			if not AvatarFitter.isCharacterLimb(child.Name) then
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
		elseif child:IsA("BasePart") and not AvatarFitter.isCharacterLimb(child.Name) and upperTorso then
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
					if p0 == child and p1 and AvatarFitter.isCharacterLimb(p1.Name) then
						targetLimbName = p1.Name
						break
					elseif p1 == child and p0 and AvatarFitter.isCharacterLimb(p0.Name) then
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
						if limb:IsA("BasePart") and AvatarFitter.isCharacterLimb(limb.Name) then
							local dist = (limb.Position - child.Position).Magnitude
							if dist < closestDist then
								closestDist = dist
								targetLimbName = limb.Name
							end
						end
					end
				end
			end

			local targetLimb = AvatarFitter.resolveCharacterLimb(character, targetLimbName or "UpperTorso")
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

function AvatarFitter.purgeRogueLimbWelds(character: Model)
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

return AvatarFitter
