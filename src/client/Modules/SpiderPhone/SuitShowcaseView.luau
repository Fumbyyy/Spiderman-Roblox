--!strict
--[[
	SuitShowcaseView.luau
	3D ViewportFrame showcase for Spider-Man suits:
	Multi-layered sci-fi pedestal, 360° interactive rotation, and Stark OS dossier card.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

export type ShowcaseElements = {
	Container: Frame,
	Viewport: ViewportFrame,
	WorldModel: WorldModel,
	SuitNameLabel: TextLabel,
	SuitStatusBadge: TextLabel,
	SuitTierLabel: TextLabel,
	SuitQuoteLabel: TextLabel,
	SuitPerkLabel: TextLabel,
	SuitDefenseLabel: TextLabel,
	Update: (suitDef: SuitConfig.SuitDefinition, cachedUnlockedSuits: { [string]: boolean }, cachedEquippedSuit: string) -> (),
}

local SuitShowcaseView = {}

function SuitShowcaseView.create(parent: Frame): ShowcaseElements
	local suitCol = Instance.new("Frame")
	suitCol.Name = "RightSuitFrame"
	suitCol.Position = UDim2.new(0, 406, 0, 0)
	suitCol.Size = UDim2.new(1, -406, 1, 0)
	suitCol.BackgroundColor3 = Color3.fromRGB(12, 17, 28)
	suitCol.BackgroundTransparency = 0.15
	suitCol.BorderSizePixel = 0
	suitCol.Parent = parent

	local sCorn = Instance.new("UICorner")
	sCorn.CornerRadius = UDim.new(0, 18)
	sCorn.Parent = suitCol

	local sStroke = Instance.new("UIStroke")
	sStroke.Thickness = 1.6
	sStroke.Color = Color3.fromRGB(45, 115, 255)
	sStroke.Transparency = 0.4
	sStroke.Parent = suitCol

	local suitHeader = Instance.new("TextLabel")
	suitHeader.Size = UDim2.new(1, -24, 0, 30)
	suitHeader.Position = UDim2.new(0, 14, 0, 10)
	suitHeader.BackgroundTransparency = 1
	suitHeader.Font = Enum.Font.GothamBlack
	suitHeader.Text = "🧬 3D HERO SUIT SHOWCASE & LORE DOSSIER"
	suitHeader.TextColor3 = Color3.fromRGB(85, 185, 255)
	suitHeader.TextSize = 13
	suitHeader.TextXAlignment = Enum.TextXAlignment.Left
	suitHeader.Parent = suitCol

	-- Grand 3D ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "SuitViewport"
	vp.Size = UDim2.new(1, -28, 1, -172)
	vp.Position = UDim2.new(0, 14, 0, 44)
	vp.BackgroundColor3 = Color3.fromRGB(8, 13, 22)
	vp.BackgroundTransparency = 0.4
	vp.BorderSizePixel = 0
	vp.Parent = suitCol

	local vpCorn = Instance.new("UICorner")
	vpCorn.CornerRadius = UDim.new(0, 12)
	vpCorn.Parent = vp

	local vpStrk = Instance.new("UIStroke")
	vpStrk.Thickness = 1.2
	vpStrk.Color = Color3.fromRGB(45, 115, 255)
	vpStrk.Transparency = 0.5
	vpStrk.Parent = vp

	vp.Ambient = Color3.fromRGB(150, 175, 215)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.85, -1.3, -1.0).Unit

	local holoCam = Instance.new("Camera")
	holoCam.FieldOfView = 34
	holoCam.CFrame = CFrame.lookAt(Vector3.new(0, 0.95, 10.2), Vector3.new(0, 0.45, 0))
	holoCam.Parent = vp
	vp.CurrentCamera = holoCam

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "SuitWorldModel"
	worldModel.Parent = vp

	-- Pedestal Platform
	local pedestalModel = Instance.new("Model")
	pedestalModel.Name = "PedestalPlatform"
	pedestalModel.Parent = worldModel

	local deck = Instance.new("Part")
	deck.Name = "BaseDeck"
	deck.Shape = Enum.PartType.Cylinder
	deck.Size = Vector3.new(0.12, 4.5, 4.5)
	deck.CFrame = CFrame.new(0, -2.71, 0) * CFrame.Angles(0, 0, math.rad(90))
	deck.Material = Enum.Material.Metal
	deck.Color = Color3.fromRGB(16, 22, 34)
	deck.Anchored = true
	deck.CanCollide = false
	deck.Parent = pedestalModel

	local rim = Instance.new("Part")
	rim.Name = "PerimeterRim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Size = Vector3.new(0.08, 4.8, 4.8)
	rim.CFrame = CFrame.new(0, -2.73, 0) * CFrame.Angles(0, 0, math.rad(90))
	rim.Material = Enum.Material.Neon
	rim.Color = Color3.fromRGB(0, 215, 255)
	rim.Transparency = 0.25
	rim.Anchored = true
	rim.CanCollide = false
	rim.Parent = pedestalModel

	local projRing = Instance.new("Part")
	projRing.Name = "HoloProjectionRing"
	projRing.Shape = Enum.PartType.Cylinder
	projRing.Size = Vector3.new(0.14, 3.2, 3.2)
	projRing.CFrame = CFrame.new(0, -2.68, 0) * CFrame.Angles(0, 0, math.rad(90))
	projRing.Material = Enum.Material.Neon
	projRing.Color = Color3.fromRGB(30, 85, 175)
	projRing.Transparency = 0.70
	projRing.Anchored = true
	projRing.CanCollide = false
	projRing.Parent = pedestalModel

	local core = Instance.new("Part")
	core.Name = "HoloCoreEmitter"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(0.16, 1.4, 1.4)
	core.CFrame = CFrame.new(0, -2.66, 0) * CFrame.Angles(0, 0, math.rad(90))
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(120, 240, 255)
	core.Transparency = 0.45
	core.Anchored = true
	core.CanCollide = false
	core.Parent = pedestalModel

	-- Drag Capsule
	local dragCapsule = Instance.new("Frame")
	dragCapsule.AnchorPoint = Vector2.new(0.5, 1)
	dragCapsule.Position = UDim2.new(0.5, 0, 1, -10)
	dragCapsule.Size = UDim2.new(0, 220, 0, 24)
	dragCapsule.BackgroundColor3 = Color3.fromRGB(10, 16, 28)
	dragCapsule.BackgroundTransparency = 0.35
	dragCapsule.Parent = vp

	local dcCorn = Instance.new("UICorner")
	dcCorn.CornerRadius = UDim.new(0, 6)
	dcCorn.Parent = dragCapsule

	local dcStroke = Instance.new("UIStroke")
	dcStroke.Thickness = 1.0
	dcStroke.Color = Color3.fromRGB(45, 115, 255)
	dcStroke.Transparency = 0.6
	dcStroke.Parent = dragCapsule

	local dragHint = Instance.new("TextLabel")
	dragHint.Size = UDim2.new(1, 0, 1, 0)
	dragHint.BackgroundTransparency = 1
	dragHint.Font = Enum.Font.GothamBold
	dragHint.Text = "🔄 DRAG TO ROTATE 360°"
	dragHint.TextColor3 = Color3.fromRGB(170, 205, 240)
	dragHint.TextSize = 10
	dragHint.Parent = dragCapsule

	-- 360 Drag Interaction
	local isDraggingSuit = false
	local lastMouseX = 0
	local suitRotationAngle = 0
	local suitHoloModel: Model? = nil

	vp.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDraggingSuit = true
			lastMouseX = input.Position.X
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDraggingSuit = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if isDraggingSuit and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local deltaX = input.Position.X - lastMouseX
			lastMouseX = input.Position.X
			suitRotationAngle = suitRotationAngle - (deltaX * 0.018)
			if suitHoloModel then
				suitHoloModel:PivotTo(CFrame.new(0, 0.2, 0) * CFrame.Angles(0, suitRotationAngle, 0))
			end
		end
	end)

	-- Dossier Card
	local suitInfoCard = Instance.new("Frame")
	suitInfoCard.Name = "SuitInfoCard"
	suitInfoCard.AnchorPoint = Vector2.new(0, 1)
	suitInfoCard.Position = UDim2.new(0, 14, 1, -12)
	suitInfoCard.Size = UDim2.new(1, -28, 0, 112)
	suitInfoCard.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
	suitInfoCard.BackgroundTransparency = 0.2
	suitInfoCard.Parent = suitCol

	local sCardCorn = Instance.new("UICorner")
	sCardCorn.CornerRadius = UDim.new(0, 10)
	sCardCorn.Parent = suitInfoCard

	local sCardStroke = Instance.new("UIStroke")
	sCardStroke.Thickness = 1.0
	sCardStroke.Color = Color3.fromRGB(45, 115, 255)
	sCardStroke.Transparency = 0.5
	sCardStroke.Parent = suitInfoCard

	local sName = Instance.new("TextLabel")
	sName.Size = UDim2.new(1, -260, 0, 22)
	sName.Position = UDim2.new(0, 14, 0, 10)
	sName.BackgroundTransparency = 1
	sName.Font = Enum.Font.GothamBlack
	sName.Text = "CLASSIC SUIT"
	sName.TextColor3 = Color3.fromRGB(255, 75, 95)
	sName.TextSize = 14
	sName.TextXAlignment = Enum.TextXAlignment.Left
	sName.Parent = suitInfoCard

	local sStatus = Instance.new("TextLabel")
	sStatus.AnchorPoint = Vector2.new(1, 0)
	sStatus.Position = UDim2.new(1, -14, 0, 10)
	sStatus.Size = UDim2.new(0, 114, 0, 20)
	sStatus.BackgroundColor3 = Color3.fromRGB(18, 42, 30)
	sStatus.Font = Enum.Font.GothamBold
	sStatus.Text = "● ACTIVE RIG"
	sStatus.TextColor3 = Color3.fromRGB(80, 245, 140)
	sStatus.TextSize = 9.5
	sStatus.Parent = suitInfoCard
	local statCorn = Instance.new("UICorner")
	statCorn.CornerRadius = UDim.new(0, 5)
	statCorn.Parent = sStatus

	local sTier = Instance.new("TextLabel")
	sTier.AnchorPoint = Vector2.new(1, 0)
	sTier.Position = UDim2.new(1, -134, 0, 10)
	sTier.Size = UDim2.new(0, 120, 0, 20)
	sTier.BackgroundTransparency = 1
	sTier.Font = Enum.Font.GothamBold
	sTier.Text = "TIER 1 // CANONICAL"
	sTier.TextColor3 = Color3.fromRGB(160, 185, 215)
	sTier.TextSize = 9.5
	sTier.TextXAlignment = Enum.TextXAlignment.Right
	sTier.Parent = suitInfoCard

	local sQuote = Instance.new("TextLabel")
	sQuote.Size = UDim2.new(1, -28, 0, 18)
	sQuote.Position = UDim2.new(0, 14, 0, 34)
	sQuote.BackgroundTransparency = 1
	sQuote.Font = Enum.Font.GothamMedium
	sQuote.Text = "“The authentic Peter Parker webbed suit.”"
	sQuote.TextColor3 = Color3.fromRGB(180, 200, 225)
	sQuote.TextSize = 10.5
	sQuote.TextXAlignment = Enum.TextXAlignment.Left
	sQuote.Parent = suitInfoCard

	local perkPill = Instance.new("Frame")
	perkPill.Position = UDim2.new(0, 14, 0, 58)
	perkPill.Size = UDim2.new(0.5, -18, 0, 44)
	perkPill.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
	perkPill.BackgroundTransparency = 0.3
	perkPill.Parent = suitInfoCard
	local pCorn = Instance.new("UICorner")
	pCorn.CornerRadius = UDim.new(0, 7)
	pCorn.Parent = perkPill
	local pStroke = Instance.new("UIStroke")
	pStroke.Thickness = 1.0
	pStroke.Color = Color3.fromRGB(255, 185, 45)
	pStroke.Transparency = 0.5
	pStroke.Parent = perkPill

	local sPerks = Instance.new("TextLabel")
	sPerks.Size = UDim2.new(1, -12, 1, -6)
	sPerks.Position = UDim2.new(0, 6, 0, 3)
	sPerks.BackgroundTransparency = 1
	sPerks.Font = Enum.Font.GothamBold
	sPerks.Text = "⚡ PERK: Balanced hero mobility with standard kinetic output."
	sPerks.TextColor3 = Color3.fromRGB(255, 220, 110)
	sPerks.TextSize = 9.5
	sPerks.TextWrapped = true
	sPerks.TextXAlignment = Enum.TextXAlignment.Left
	sPerks.TextYAlignment = Enum.TextYAlignment.Center
	sPerks.Parent = perkPill

	local defPill = Instance.new("Frame")
	defPill.Position = UDim2.new(0.5, 4, 0, 58)
	defPill.Size = UDim2.new(0.5, -18, 0, 44)
	defPill.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
	defPill.BackgroundTransparency = 0.3
	defPill.Parent = suitInfoCard
	local dCorn = Instance.new("UICorner")
	dCorn.CornerRadius = UDim.new(0, 7)
	dCorn.Parent = defPill
	local dStroke = Instance.new("UIStroke")
	dStroke.Thickness = 1.0
	dStroke.Color = Color3.fromRGB(80, 245, 140)
	dStroke.Transparency = 0.5
	dStroke.Parent = defPill

	local sDef = Instance.new("TextLabel")
	sDef.Size = UDim2.new(1, -12, 1, -6)
	sDef.Position = UDim2.new(0, 6, 0, 3)
	sDef.BackgroundTransparency = 1
	sDef.Font = Enum.Font.GothamBold
	sDef.Text = "🛡️ DEFENSE: Standard Nanoweave"
	sDef.TextColor3 = Color3.fromRGB(140, 255, 180)
	sDef.TextSize = 9.5
	sDef.TextWrapped = true
	sDef.TextXAlignment = Enum.TextXAlignment.Left
	sDef.TextYAlignment = Enum.TextYAlignment.Center
	sDef.Parent = defPill

	local function updateShowcase(suitDef: SuitConfig.SuitDefinition, cachedUnlockedSuits: { [string]: boolean }, cachedEquippedSuit: string)
		sName.Text = string.upper(suitDef.Name)
		sName.TextColor3 = suitDef.ThemeColor
		sQuote.Text = string.format("“%s”", suitDef.Description)
		sPerks.Text = string.format("⚡ PERK: %s", suitDef.PerkDescription)
		sTier.Text = string.format("LEVEL %d // TIER %d", suitDef.UnlockLevel, math.clamp(suitDef.UnlockLevel, 1, 5))

		if suitDef.Id == "StarkTechSuit" then
			sDef.Text = "🛡️ DEFENSE: +25 HP Nanotech Shield"
		elseif suitDef.PerkType == "Defense" then
			sDef.Text = string.format("🛡️ DEFENSE: +%d Max Health", suitDef.PerkValue)
		else
			sDef.Text = "🛡️ DEFENSE: Standard Nanoweave"
		end

		local isEquipped = (cachedEquippedSuit == suitDef.Id)
		sStatus.Text = if isEquipped then "● ACTIVE RIG" else "○ SPEC ARCHIVE"
		sStatus.TextColor3 = if isEquipped then Color3.fromRGB(80, 245, 140) else Color3.fromRGB(150, 175, 205)
		sStatus.BackgroundColor3 = if isEquipped then Color3.fromRGB(18, 42, 30) else Color3.fromRGB(20, 26, 38)

		-- Update 3D Holo Model
		if suitHoloModel then
			suitHoloModel:Destroy()
			suitHoloModel = nil
		end

		local suitsFolder = ReplicatedStorage:FindFirstChild("Suits")
		local template = suitsFolder and suitsFolder:FindFirstChild(suitDef.Id) :: Model?
		if template then
			local clone = template:Clone()
			clone.Name = "ShowcaseRig"
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
				end
			end
			clone:PivotTo(CFrame.new(0, 0.2, 0) * CFrame.Angles(0, suitRotationAngle, 0))
			clone.Parent = worldModel
			suitHoloModel = clone
		end
	end

	return {
		Container = suitCol,
		Viewport = vp,
		WorldModel = worldModel,
		SuitNameLabel = sName,
		SuitStatusBadge = sStatus,
		SuitTierLabel = sTier,
		SuitQuoteLabel = sQuote,
		SuitPerkLabel = sPerks,
		SuitDefenseLabel = sDef,
		Update = updateShowcase,
	}
end

return SuitShowcaseView
