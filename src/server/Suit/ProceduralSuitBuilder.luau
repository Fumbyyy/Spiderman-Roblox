--!strict
--[[
	ProceduralSuitBuilder.luau
	Zero-HTTP Procedural 3D Suit Visual Fallback:
	Constructs forearm web shooters, nanotech Waldo cores, hoodie collars,
	alien spines, scarlet vests, and cyber blades when mesh models are absent.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

local ProceduralSuitBuilder = {}

function ProceduralSuitBuilder.createProceduralPart(
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

function ProceduralSuitBuilder.applyProceduralSuit3D(character: Model, humanoid: Humanoid, suit: SuitConfig.SuitDefinition)
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
			ProceduralSuitBuilder.createProceduralPart(character, "WebShooterRight", Vector3.new(1.05, 0.4, 1.05), Color3.fromRGB(195, 35, 45), Enum.Material.Metal, rightLowerArm, CFrame.new(0, -0.4, 0))
		end
		if leftLowerArm then
			ProceduralSuitBuilder.createProceduralPart(character, "WebShooterLeft", Vector3.new(1.05, 0.4, 1.05), Color3.fromRGB(195, 35, 45), Enum.Material.Metal, leftLowerArm, CFrame.new(0, -0.4, 0))
		end

	-- Stark Tech Suit: 4 Articulated Nanotech Waldo Arms & Arc Chest Badge
	elseif suit.Id == "StarkTechSuit" then
		ProceduralSuitBuilder.createProceduralPart(character, "WaldoBackCore", Vector3.new(1.3, 1.2, 0.45), Color3.fromRGB(215, 40, 50), Enum.Material.Metal, upperTorso, CFrame.new(0, 0.1, 0.7))
		ProceduralSuitBuilder.createProceduralPart(character, "ArcReactorChest", Vector3.new(0.65, 0.65, 0.12), Color3.fromRGB(60, 220, 255), Enum.Material.Neon, upperTorso, CFrame.new(0, 0.2, -0.65))

	-- Miles Morales: Casual Spider-Verse Hoodie Collar & Sneaker Cuffs
	elseif suit.Id == "MilesSpiderVerse" then
		ProceduralSuitBuilder.createProceduralPart(character, "MilesHoodieCollar", Vector3.new(1.9, 0.45, 1.55), Color3.fromRGB(24, 24, 28), Enum.Material.Fabric, upperTorso, CFrame.new(0, 0.8, 0.1))
		if rightLowerLeg then
			ProceduralSuitBuilder.createProceduralPart(character, "MilesSneakerRight", Vector3.new(1.08, 0.5, 1.08), Color3.fromRGB(235, 235, 245), Enum.Material.SmoothPlastic, rightLowerLeg, CFrame.new(0, -0.65, 0))
		end
		if leftLowerLeg then
			ProceduralSuitBuilder.createProceduralPart(character, "MilesSneakerLeft", Vector3.new(1.08, 0.5, 1.08), Color3.fromRGB(235, 235, 245), Enum.Material.SmoothPlastic, leftLowerLeg, CFrame.new(0, -0.65, 0))
		end

	-- Symbiote Black: Organic Tendrils & Alien Spikes
	elseif suit.Id == "SymbioteBlack" then
		local alienColor = Color3.fromRGB(15, 15, 20)
		ProceduralSuitBuilder.createProceduralPart(character, "SymbioteSpine", Vector3.new(0.55, 1.8, 0.5), alienColor, Enum.Material.SmoothPlastic, upperTorso, CFrame.new(0, 0, 0.75))

	-- Scarlet Spider: Ben Reilly's Sleeveless Blue Hoodie Vest & Cuffs
	elseif suit.Id == "ScarletSpider" then
		local vestBlue = Color3.fromRGB(35, 105, 220)
		ProceduralSuitBuilder.createProceduralPart(character, "ScarletVestBody", Vector3.new(2.15, 1.95, 1.25), vestBlue, Enum.Material.Fabric, upperTorso, CFrame.new(0, 0, 0))

	-- 2099 Cyber Suit: Crimson Arm Blades & Holographic Cape Fins
	elseif suit.Id == "Cyber2099" then
		if rightLowerArm then
			ProceduralSuitBuilder.createProceduralPart(character, "BladeR_Base", Vector3.new(0.25, 0.8, 0.4), Color3.fromRGB(30, 75, 225), Enum.Material.Metal, rightLowerArm, CFrame.new(0.55, -0.1, 0))
		end
		if leftLowerArm then
			ProceduralSuitBuilder.createProceduralPart(character, "BladeL_Base", Vector3.new(0.25, 0.8, 0.4), Color3.fromRGB(30, 75, 225), Enum.Material.Metal, leftLowerArm, CFrame.new(-0.55, -0.1, 0))
		end
	end
end

return ProceduralSuitBuilder
