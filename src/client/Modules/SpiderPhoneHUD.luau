--!strict
--[[
	SpiderPhoneHUD.luau
	Left-Docked Spider-Phone & Stark Tech AR Visor Datapad:
	- Inspired by Miles Morales & Iron Man Stark OS v4.2
	- Left-docked smartphone datapad (340x620) with smooth slide-in/out animation
	- 4 Complete Functional Apps:
		1. 🚨 FNSM Crime Scanner (Live crime status, distance, on-demand dispatch button)
		2. 🛍️ Suit Wardrobe (6 canonical suits, Hero Cash purchasing, server-validated equip)
		3. ⭐ Hero Profile (Avatar thumbnail, Level rank, live XP bar, crimes stopped)
		4. ⚙️ Comms & Settings (Radio audio mute, keybind quick reference)
	- Accessible via M key, Tab key, or floating bottom-left [📱 FNSM] button
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))
local CrimeConfig = require(Shared:WaitForChild("CrimeConfig"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))

-- Remotes
local SuitRemotes = ReplicatedStorage:WaitForChild("SuitRemotes")
local SuitPurchaseRF = SuitRemotes:WaitForChild("SuitPurchase") :: RemoteFunction
local SuitEquipRF = SuitRemotes:WaitForChild("SuitEquip") :: RemoteFunction
local GetSuitDataRF = SuitRemotes:WaitForChild("GetSuitData") :: RemoteFunction

local CrimeRemotes = ReplicatedStorage:WaitForChild("CrimeRemotes")
local GetActiveCrimesRF = CrimeRemotes:WaitForChild("GetActiveCrimes") :: RemoteFunction
local CrimeInteractRemote = CrimeRemotes:WaitForChild("CrimeInteract") :: RemoteEvent
local CrimeNotificationRemote = CrimeRemotes:WaitForChild("CrimeNotification") :: RemoteEvent

local SpiderPhoneHUD = {
	isOpen = false,
	activeTab = "FNSM" :: "FNSM" | "Moves" | "Suits" | "Profile",
	isRadioMuted = false,
}

-- GUI References
local screenGui: ScreenGui? = nil
local visorContainer: Frame? = nil
local phoneFrame: Frame? = nil
local rightSuitFrame: Frame? = nil
local contentArea: Frame? = nil
local floatingOpenButton: TextButton? = nil
local tabUnderline: Frame? = nil
local cashDisplayLabel: TextLabel? = nil
local statusClockLabel: TextLabel? = nil

-- 3D Suit Viewport References
local suitViewport: ViewportFrame? = nil
local suitWorldModel: WorldModel? = nil
local suitHoloModel: Model? = nil
local suitRotationAngle = 0
local isDraggingSuit = false
local lastMouseX = 0
local suitNameLabel: TextLabel? = nil
local suitTierLabel: TextLabel? = nil
local suitQuoteLabel: TextLabel? = nil
local suitPerkLabel: TextLabel? = nil
local suitDefenseLabel: TextLabel? = nil
local suitStatusBadge: TextLabel? = nil

-- Movement Lock State
local savedWalkSpeed: number? = nil
local savedJumpHeight: number? = nil
local savedJumpPower: number? = nil

-- Cache for Suit Data
local cachedUnlockedSuits: { [string]: boolean } = { ["ClassicSuit"] = true }
local cachedEquippedSuit: string = "ClassicSuit"

--------------------------------------------------------------------------------
-- 🔊 AUDIO FEEDBACK (Zero Hardcoded IDs)
--------------------------------------------------------------------------------

local function playPhoneSound(_soundName: string)
	-- Zero SFX Policy: Silent visual-only UI interaction
	return
end

--------------------------------------------------------------------------------
-- 🌫️ STARK VISOR BLUR & MOVEMENT LOCKING
--------------------------------------------------------------------------------

local function getOrCreateBlur(): BlurEffect
	local existing = Lighting:FindFirstChild("StarkVisorBlur") :: BlurEffect?
	if existing then return existing end
	local blur = Instance.new("BlurEffect")
	blur.Name = "StarkVisorBlur"
	blur.Size = 0
	blur.Enabled = true
	blur.Parent = Lighting
	return blur
end

local function lockMovement(locked: boolean)
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		if locked then
			if hum.WalkSpeed > 0 then
				savedWalkSpeed = hum.WalkSpeed
			end
			if hum.UseJumpPower then
				if hum.JumpPower > 0 then savedJumpPower = hum.JumpPower end
				hum.JumpPower = 0
			else
				if hum.JumpHeight > 0 then savedJumpHeight = hum.JumpHeight end
				hum.JumpHeight = 0
			end
			hum.WalkSpeed = 0
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		else
			hum.WalkSpeed = savedWalkSpeed or 16
			if hum.UseJumpPower then
				hum.JumpPower = savedJumpPower or 50
			else
				hum.JumpHeight = savedJumpHeight or 7.2
			end
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end
end

--------------------------------------------------------------------------------
-- 🧬 3D HOLOGRAPHIC SUIT SHOWCASE
--------------------------------------------------------------------------------

local function updateSuitHologram()
	if not suitViewport then return end
	if suitHoloModel then
		suitHoloModel:Destroy()
		suitHoloModel = nil
	end

	local char = LocalPlayer.Character
	if not char then return end

	local wasArchivable = char.Archivable
	char.Archivable = true
	local clone = char:Clone()
	char.Archivable = wasArchivable

	if not clone then return end

	for _, item in clone:GetDescendants() do
		if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("Sound") or item:IsA("Highlight") or item:IsA("ForceField") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
		end
	end

	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	clone:PivotTo(CFrame.new(0, 0.2, 0) * CFrame.Angles(0, suitRotationAngle, 0))

	clone.Parent = suitWorldModel or suitViewport
	suitHoloModel = clone
end

local function updateSuitShowcase()
	updateSuitHologram()
	local suitDef = SuitConfig.getSuitById(cachedEquippedSuit)
	if suitDef then
		if suitNameLabel then
			suitNameLabel.Text = string.upper(suitDef.Name)
			suitNameLabel.TextColor3 = suitDef.ThemeColor or Color3.fromRGB(85, 185, 255)
		end
		if suitTierLabel then
			suitTierLabel.Text = string.format("TIER %d // CANONICAL", suitDef.UnlockLevel)
		end
		if suitQuoteLabel then
			suitQuoteLabel.Text = string.format("“%s”", suitDef.Tagline)
		end
		if suitPerkLabel then
			suitPerkLabel.Text = string.format("⚡ PERK: %s", suitDef.PerkDescription)
		end
		if suitDefenseLabel then
			local bonusShieldText = if suitDef.PerkType == "Defense" then string.format("+%d HP Nanotech Shielding", suitDef.PerkValue) else "Standard Nanoweave"
			suitDefenseLabel.Text = string.format("🛡️ DEFENSE: %s", bonusShieldText)
		end
		if suitStatusBadge then
			local isEquipped = (cachedEquippedSuit == suitDef.Id)
			suitStatusBadge.Text = if isEquipped then "● ACTIVE RIG" else "○ SPEC ARCHIVE"
			suitStatusBadge.TextColor3 = if isEquipped then Color3.fromRGB(80, 245, 140) else Color3.fromRGB(150, 175, 205)
			suitStatusBadge.BackgroundColor3 = if isEquipped then Color3.fromRGB(18, 42, 30) else Color3.fromRGB(20, 26, 38)
		end
	end
end

--------------------------------------------------------------------------------
-- 🎨 BUILD FULLSCREEN STARK AR VISOR & 3-COLUMN DATAPAD
--------------------------------------------------------------------------------

local function createPhoneHUD()
	if PlayerGui:FindFirstChild("SpiderPhoneGui") then
		PlayerGui:FindFirstChild("SpiderPhoneGui"):Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpiderPhoneGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 15
	gui.Parent = PlayerGui
	screenGui = gui

	-- 🕶️ 1. Fullscreen Stark AR Visor Container
	local visor = Instance.new("Frame")
	visor.Name = "StarkVisorContainer"
	visor.Size = UDim2.new(1, 0, 1, 0)
	visor.Position = UDim2.new(0, 0, 0, 0)
	visor.BackgroundColor3 = Color3.fromRGB(6, 10, 18)
	visor.BackgroundTransparency = 0.2
	visor.BorderSizePixel = 0
	visor.Visible = false
	visor.Parent = gui
	visorContainer = visor

	-- 🛰️ Top Telemetry Header Bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopTelemetryBar"
	topBar.Size = UDim2.new(1, 0, 0, 42)
	topBar.BackgroundColor3 = Color3.fromRGB(10, 16, 28)
	topBar.BackgroundTransparency = 0.4
	topBar.BorderSizePixel = 0
	topBar.Parent = visor

	local topStroke = Instance.new("UIStroke")
	topStroke.Color = Color3.fromRGB(45, 95, 225)
	topStroke.Thickness = 1
	topStroke.Transparency = 0.5
	topStroke.Parent = topBar

	local titleBrand = Instance.new("TextLabel")
	titleBrand.Name = "TitleBrand"
	titleBrand.Size = UDim2.new(0, 260, 1, 0)
	titleBrand.Position = UDim2.new(0, 16, 0, 0)
	titleBrand.BackgroundTransparency = 1
	titleBrand.Font = Enum.Font.GothamBlack
	titleBrand.Text = "STARK OS v4.2 // SPIDER-VISOR HUD"
	titleBrand.TextColor3 = Color3.fromRGB(85, 185, 255)
	titleBrand.TextSize = 12
	titleBrand.TextXAlignment = Enum.TextXAlignment.Left
	titleBrand.Parent = topBar

	local satLink = Instance.new("TextLabel")
	satLink.Name = "SatLinkLabel"
	satLink.AnchorPoint = Vector2.new(0.5, 0.5)
	satLink.Position = UDim2.new(0.5, 0, 0.5, 0)
	satLink.Size = UDim2.new(0, 360, 1, 0)
	satLink.BackgroundTransparency = 1
	satLink.Font = Enum.Font.GothamBold
	satLink.Text = "📡 [SAT-LINK ACTIVE // NYPD FREQ: 460.125 MHz]"
	satLink.TextColor3 = Color3.fromRGB(160, 195, 235)
	satLink.TextSize = 11
	satLink.Parent = topBar

	local exitBtn = Instance.new("TextButton")
	exitBtn.Name = "ExitVisorButton"
	exitBtn.AnchorPoint = Vector2.new(1, 0.5)
	exitBtn.Position = UDim2.new(1, -14, 0.5, 0)
	exitBtn.Size = UDim2.new(0, 130, 0, 28)
	exitBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 50)
	exitBtn.BackgroundTransparency = 0.2
	exitBtn.Font = Enum.Font.GothamBold
	exitBtn.Text = "✕ EXIT VISOR [M]"
	exitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	exitBtn.TextSize = 11
	exitBtn.Parent = topBar
	local exitCorn = Instance.new("UICorner")
	exitCorn.CornerRadius = UDim.new(0, 7)
	exitCorn.Parent = exitBtn

	exitBtn.MouseButton1Click:Connect(function()
		SpiderPhoneHUD.toggle(false)
	end)

	-- 📊 Bottom Telemetry Footer Bar
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomTelemetryBar"
	bottomBar.AnchorPoint = Vector2.new(0, 1)
	bottomBar.Position = UDim2.new(0, 0, 1, 0)
	bottomBar.Size = UDim2.new(1, 0, 0, 32)
	bottomBar.BackgroundColor3 = Color3.fromRGB(8, 12, 22)
	bottomBar.BackgroundTransparency = 0.4
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = visor

	local bottomStroke = Instance.new("UIStroke")
	bottomStroke.Color = Color3.fromRGB(45, 95, 225)
	bottomStroke.Thickness = 1
	bottomStroke.Transparency = 0.6
	bottomStroke.Parent = bottomBar

	local diagLabel = Instance.new("TextLabel")
	diagLabel.Size = UDim2.new(0, 320, 1, 0)
	diagLabel.Position = UDim2.new(0, 16, 0, 0)
	diagLabel.BackgroundTransparency = 1
	diagLabel.Font = Enum.Font.GothamBold
	diagLabel.Text = "SYSTEM DIAGNOSTIC: 100% OPTIMAL // SUIT: SECURE"
	diagLabel.TextColor3 = Color3.fromRGB(80, 245, 140)
	diagLabel.TextSize = 10
	diagLabel.TextXAlignment = Enum.TextXAlignment.Left
	diagLabel.Parent = bottomBar

	local escTipLabel = Instance.new("TextLabel")
	escTipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	escTipLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	escTipLabel.Size = UDim2.new(0, 280, 1, 0)
	escTipLabel.BackgroundTransparency = 1
	escTipLabel.Font = Enum.Font.Gotham
	escTipLabel.Text = "PRESS [M] OR [ESC] TO RETURN TO GAMEPLAY"
	escTipLabel.TextColor3 = Color3.fromRGB(160, 175, 205)
	escTipLabel.TextSize = 10
	escTipLabel.Parent = bottomBar

	local cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "CashLabel"
	cashLabel.AnchorPoint = Vector2.new(1, 0.5)
	cashLabel.Position = UDim2.new(1, -16, 0.5, 0)
	cashLabel.Size = UDim2.new(0, 200, 1, 0)
	cashLabel.BackgroundTransparency = 1
	cashLabel.Font = Enum.Font.GothamBold
	cashLabel.Text = "💰 $0 HERO CASH"
	cashLabel.TextColor3 = Color3.fromRGB(255, 210, 60)
	cashLabel.TextSize = 11.5
	cashLabel.TextXAlignment = Enum.TextXAlignment.Right
	cashLabel.Parent = bottomBar
	cashDisplayLabel = cashLabel

	-- 🖥️ 2. Main 3-Column Body Frame
	local mainBody = Instance.new("Frame")
	mainBody.Name = "MainBody"
	mainBody.Position = UDim2.new(0, 16, 0, 48)
	mainBody.Size = UDim2.new(1, -32, 1, -86)
	mainBody.BackgroundTransparency = 1
	mainBody.Parent = visor

	-- 📱 PANEL 1 (LEFT): Spider-Phone Datapad Chassis (390px width)
	local phone = Instance.new("Frame")
	phone.Name = "PhoneChassis"
	phone.Position = UDim2.new(0, 0, 0, 0)
	phone.Size = UDim2.new(0, 390, 1, 0)
	phone.BackgroundColor3 = Color3.fromRGB(11, 15, 24)
	phone.BackgroundTransparency = 0.08
	phone.BorderSizePixel = 0
	phone.Parent = mainBody
	phoneFrame = phone

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = phone

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.0
	stroke.Color = Color3.fromRGB(45, 95, 225)
	stroke.Transparency = 0.35
	stroke.Parent = phone

	-- Phone Bezel Notch
	local notch = Instance.new("Frame")
	notch.Name = "Notch"
	notch.AnchorPoint = Vector2.new(0.5, 0)
	notch.Position = UDim2.new(0.5, 0, 0, 6)
	notch.Size = UDim2.new(0, 80, 0, 5)
	notch.BackgroundColor3 = Color3.fromRGB(25, 32, 48)
	notch.BorderSizePixel = 0
	notch.Parent = phone
	local notchCorner = Instance.new("UICorner")
	notchCorner.CornerRadius = UDim.new(0, 3)
	notchCorner.Parent = notch

	-- Status Bar (Clock & Signal)
	local statusBar = Instance.new("Frame")
	statusBar.Name = "StatusBar"
	statusBar.Position = UDim2.new(0, 14, 0, 14)
	statusBar.Size = UDim2.new(1, -28, 0, 18)
	statusBar.BackgroundTransparency = 1
	statusBar.Parent = phone

	local clockLabel = Instance.new("TextLabel")
	clockLabel.Name = "ClockLabel"
	clockLabel.Size = UDim2.new(0, 80, 1, 0)
	clockLabel.BackgroundTransparency = 1
	clockLabel.Font = Enum.Font.GothamBold
	clockLabel.Text = "12:44 PM"
	clockLabel.TextColor3 = Color3.fromRGB(215, 225, 240)
	clockLabel.TextSize = 11
	clockLabel.TextXAlignment = Enum.TextXAlignment.Left
	clockLabel.Parent = statusBar
	statusClockLabel = clockLabel

	local brandLabel = Instance.new("TextLabel")
	brandLabel.Name = "BrandLabel"
	brandLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	brandLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	brandLabel.Size = UDim2.new(0, 120, 1, 0)
	brandLabel.BackgroundTransparency = 1
	brandLabel.Font = Enum.Font.GothamBlack
	brandLabel.Text = "SPIDER-PHONE"
	brandLabel.TextColor3 = Color3.fromRGB(65, 145, 255)
	brandLabel.TextSize = 10
	brandLabel.Parent = statusBar

	local signalLabel = Instance.new("TextLabel")
	signalLabel.Name = "SignalLabel"
	signalLabel.AnchorPoint = Vector2.new(1, 0)
	signalLabel.Position = UDim2.new(1, 0, 0, 0)
	signalLabel.Size = UDim2.new(0, 80, 1, 0)
	signalLabel.BackgroundTransparency = 1
	signalLabel.Font = Enum.Font.GothamBold
	signalLabel.Text = "5G 📶 100%"
	signalLabel.TextColor3 = Color3.fromRGB(200, 215, 235)
	signalLabel.TextSize = 10
	signalLabel.TextXAlignment = Enum.TextXAlignment.Right
	signalLabel.Parent = statusBar

	-- Navigation Bar (4 App Tabs)
	local navBar = Instance.new("Frame")
	navBar.Name = "NavBar"
	navBar.Position = UDim2.new(0, 12, 0, 38)
	navBar.Size = UDim2.new(1, -24, 0, 34)
	navBar.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
	navBar.BackgroundTransparency = 0.3
	navBar.Parent = phone
	local navCorner = Instance.new("UICorner")
	navCorner.CornerRadius = UDim.new(0, 9)
	navCorner.Parent = navBar

	local navLayout = Instance.new("UIListLayout")
	navLayout.FillDirection = Enum.FillDirection.Horizontal
	navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	navLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	navLayout.Padding = UDim.new(0, 4)
	navLayout.Parent = navBar

	local tabs = {
		{ Id = "FNSM", Name = "🚨 FNSM" },
		{ Id = "Moves", Name = "🥋 MOVES" },
		{ Id = "Suits", Name = "🛍️ SUITS" },
		{ Id = "Profile", Name = "⭐ HERO" },
	}

	for _, tabData in tabs do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. tabData.Id
		tabBtn.Size = UDim2.new(0.24, -2, 0, 28)
		tabBtn.BackgroundColor3 = Color3.fromRGB(20, 26, 40)
		tabBtn.BackgroundTransparency = (tabData.Id == SpiderPhoneHUD.activeTab) and 0.1 or 0.8
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.Text = tabData.Name
		tabBtn.TextColor3 = (tabData.Id == SpiderPhoneHUD.activeTab) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 170, 195)
		tabBtn.TextSize = 10
		tabBtn.Parent = navBar

		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = UDim.new(0, 6)
		tCorner.Parent = tabBtn

		tabBtn.MouseButton1Click:Connect(function()
			SpiderPhoneHUD.switchTab(tabData.Id :: any)
		end)
	end

	-- Dynamic Content Area (App Views inside Phone)
	local content = Instance.new("Frame")
	content.Name = "ContentArea"
	content.Position = UDim2.new(0, 12, 0, 78)
	content.Size = UDim2.new(1, -24, 1, -86)
	content.BackgroundTransparency = 1
	content.Parent = phone
	contentArea = content

	-- 🧬 PANEL 2 (RIGHT): Grand 3D Hero Showcase & Lore Dossier
	local suitCol = Instance.new("Frame")
	suitCol.Name = "RightSuitFrame"
	suitCol.Position = UDim2.new(0, 406, 0, 0)
	suitCol.Size = UDim2.new(1, -406, 1, 0)
	suitCol.BackgroundColor3 = Color3.fromRGB(12, 17, 28)
	suitCol.BackgroundTransparency = 0.15
	suitCol.BorderSizePixel = 0
	suitCol.Parent = mainBody
	rightSuitFrame = suitCol

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

	-- Balanced 3-Point Studio Lighting
	vp.Ambient = Color3.fromRGB(150, 175, 215)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.85, -1.3, -1.0).Unit

	-- Optical Head-to-Toe Camera Framing
	local holoCam = Instance.new("Camera")
	holoCam.FieldOfView = 34
	holoCam.CFrame = CFrame.lookAt(Vector3.new(0, 0.95, 10.2), Vector3.new(0, 0.45, 0))
	holoCam.Parent = vp
	vp.CurrentCamera = holoCam

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "SuitWorldModel"
	worldModel.Parent = vp
	suitWorldModel = worldModel

	-- Multi-Layered Sci-Fi Pedestal Platform
	local pedestalModel = Instance.new("Model")
	pedestalModel.Name = "PedestalPlatform"
	pedestalModel.Parent = worldModel

	-- 1. Dark Metallic Structural Deck
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

	-- 2. Outer Perimeter Neon Rim
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

	-- 3. Concentric Projection Ring
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

	-- 4. Center Holo Core Emitter
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

	-- Holographic Telemetry HUD Elements
	local tagLeft = Instance.new("TextLabel")
	tagLeft.Size = UDim2.new(0, 220, 0, 16)
	tagLeft.Position = UDim2.new(0, 14, 0, 10)
	tagLeft.BackgroundTransparency = 1
	tagLeft.Font = Enum.Font.GothamBold
	tagLeft.Text = "SUIT LOCKER // PROTOCOL"
	tagLeft.TextColor3 = Color3.fromRGB(85, 195, 255)
	tagLeft.TextSize = 10
	tagLeft.TextXAlignment = Enum.TextXAlignment.Left
	tagLeft.Parent = vp

	local tagRight = Instance.new("TextLabel")
	tagRight.AnchorPoint = Vector2.new(1, 0)
	tagRight.Position = UDim2.new(1, -14, 0, 10)
	tagRight.Size = UDim2.new(0, 200, 0, 16)
	tagRight.BackgroundTransparency = 1
	tagRight.Font = Enum.Font.GothamBold
	tagRight.Text = "NEW YORK • TAC-NET"
	tagRight.TextColor3 = Color3.fromRGB(140, 185, 235)
	tagRight.TextSize = 10
	tagRight.TextXAlignment = Enum.TextXAlignment.Right
	tagRight.Parent = vp

	-- Subtle Blueprint Guidelines
	local guide1 = Instance.new("Frame")
	guide1.Position = UDim2.new(0, 12, 0.33, 0)
	guide1.Size = UDim2.new(1, -24, 0, 1)
	guide1.BackgroundColor3 = Color3.fromRGB(45, 115, 255)
	guide1.BackgroundTransparency = 0.88
	guide1.BorderSizePixel = 0
	guide1.Parent = vp

	local guide2 = Instance.new("Frame")
	guide2.Position = UDim2.new(0, 12, 0.66, 0)
	guide2.Size = UDim2.new(1, -24, 0, 1)
	guide2.BackgroundColor3 = Color3.fromRGB(45, 115, 255)
	guide2.BackgroundTransparency = 0.88
	guide2.BorderSizePixel = 0
	guide2.Parent = vp

	-- Sci-Fi Corner Brackets
	local cornerData = {
		{ Pos = UDim2.new(0, 6, 0, 6), Anchor = Vector2.new(0, 0) },
		{ Pos = UDim2.new(1, -6, 0, 6), Anchor = Vector2.new(1, 0) },
		{ Pos = UDim2.new(0, 6, 1, -6), Anchor = Vector2.new(0, 1) },
		{ Pos = UDim2.new(1, -6, 1, -6), Anchor = Vector2.new(1, 1) },
	}
	for _, c in cornerData do
		local b = Instance.new("Frame")
		b.Position = c.Pos
		b.AnchorPoint = c.Anchor
		b.Size = UDim2.new(0, 12, 0, 12)
		b.BackgroundTransparency = 1
		b.Parent = vp
		local bs = Instance.new("UIStroke")
		bs.Thickness = 1.2
		bs.Color = Color3.fromRGB(65, 155, 255)
		bs.Transparency = 0.4
		bs.Parent = b
	end

	-- Sleek Glassmorphic Drag Capsule
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

	suitViewport = vp

	-- 360 Drag Interaction
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

	-- Stark OS Spec Sheet Dossier Card (Below Viewport)
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

	-- Header Row: Name, Tier, and Status Pill
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
	suitNameLabel = sName

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
	suitStatusBadge = sStatus

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
	suitTierLabel = sTier

	-- Lore Tagline Row
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
	suitQuoteLabel = sQuote

	-- Pill Badges Row (Perk & Defense Shielding)
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
	suitPerkLabel = sPerks

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
	suitDefenseLabel = sDef

	-- 📱 Floating Bottom-Left Button for Mobile / Mouse Access
	local floatBtn = Instance.new("TextButton")
	floatBtn.Name = "SpiderPhoneFloatingButton"
	floatBtn.AnchorPoint = Vector2.new(0, 1)
	floatBtn.Position = UDim2.new(0, 24, 1, -48)
	floatBtn.Size = UDim2.new(0, 108, 0, 34)
	floatBtn.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
	floatBtn.BackgroundTransparency = 0.15
	floatBtn.Font = Enum.Font.GothamBold
	floatBtn.Text = "📱 [M] FNSM"
	floatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	floatBtn.TextSize = 12
	floatBtn.Visible = false
	floatBtn.Parent = gui
	floatingOpenButton = floatBtn

	local fCorner = Instance.new("UICorner")
	fCorner.CornerRadius = UDim.new(0, 10)
	fCorner.Parent = floatBtn

	local fStroke = Instance.new("UIStroke")
	fStroke.Thickness = 1.4
	fStroke.Color = Color3.fromRGB(45, 115, 255)
	fStroke.Transparency = 0.4
	fStroke.Parent = floatBtn

	floatBtn.MouseButton1Click:Connect(function()
		SpiderPhoneHUD.toggle()
	end)

	-- Initial View Render
	SpiderPhoneHUD.renderActiveApp()
end

--------------------------------------------------------------------------------
-- 🚨 APP 1: FNSM CRIME SCANNER
--------------------------------------------------------------------------------

local function renderFNSMApp(parent: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "FNSMScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(55, 120, 235)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = parent

	local sPad = Instance.new("UIPadding")
	sPad.PaddingRight = UDim.new(0, 8)
	sPad.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = scroll

	-- Fetch live crime from server
	local activeCrime: any = nil
	local success, result = pcall(function()
		return GetActiveCrimesRF:InvokeServer()
	end)
	if success then
		activeCrime = result
	end

	-- Header Banner
	local banner = Instance.new("Frame")
	banner.Name = "AppBanner"
	banner.LayoutOrder = 1
	banner.Size = UDim2.new(1, 0, 0, 50)
	banner.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
	banner.BackgroundTransparency = 0.2
	banner.Parent = scroll
	local bCorn = Instance.new("UICorner")
	bCorn.CornerRadius = UDim.new(0, 10)
	bCorn.Parent = banner

	local bTitle = Instance.new("TextLabel")
	bTitle.Size = UDim2.new(1, -16, 0, 24)
	bTitle.Position = UDim2.new(0, 10, 0, 4)
	bTitle.BackgroundTransparency = 1
	bTitle.Font = Enum.Font.GothamBlack
	bTitle.Text = "🚨 FRIENDLY NEIGHBORHOOD APP"
	bTitle.TextColor3 = Color3.fromRGB(85, 185, 255)
	bTitle.TextSize = 11.5
	bTitle.TextXAlignment = Enum.TextXAlignment.Left
	bTitle.Parent = banner

	local bSub = Instance.new("TextLabel")
	bSub.Size = UDim2.new(1, -16, 0, 18)
	bSub.Position = UDim2.new(0, 10, 0, 26)
	bSub.BackgroundTransparency = 1
	bSub.Font = Enum.Font.Gotham
	bSub.Text = "Live Manhattan Police Scanner & Incident Feed"
	bSub.TextColor3 = Color3.fromRGB(160, 175, 195)
	bSub.TextSize = 9.5
	bSub.TextXAlignment = Enum.TextXAlignment.Left
	bSub.Parent = banner

	-- 1. Active Incident Card
	if activeCrime ~= nil then
		local card = Instance.new("Frame")
		card.Name = "ActiveCrimeCard"
		card.LayoutOrder = 2
		card.Size = UDim2.new(1, 0, 0, 156)
		card.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
		card.BackgroundTransparency = 0.15
		card.Parent = scroll
		local cCorn = Instance.new("UICorner")
		cCorn.CornerRadius = UDim.new(0, 12)
		cCorn.Parent = card

		local themeColor = activeCrime.ThemeColor or Color3.fromRGB(255, 75, 75)
		local cStroke = Instance.new("UIStroke")
		cStroke.Thickness = 1.4
		cStroke.Color = themeColor
		cStroke.Parent = card

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Size = UDim2.new(0, 36, 0, 36)
		iconLabel.Position = UDim2.new(0, 10, 0, 10)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.GothamBlack
		iconLabel.Text = activeCrime.Icon or "🚨"
		iconLabel.TextSize = 22
		iconLabel.Parent = card

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Size = UDim2.new(1, -60, 0, 20)
		titleLabel.Position = UDim2.new(0, 50, 0, 10)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBlack
		titleLabel.Text = string.upper(activeCrime.Title or "ACTIVE INCIDENT")
		titleLabel.TextColor3 = themeColor
		titleLabel.TextSize = 12
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.Parent = card

		local codeLabel = Instance.new("TextLabel")
		codeLabel.Size = UDim2.new(1, -60, 0, 16)
		codeLabel.Position = UDim2.new(0, 50, 0, 30)
		codeLabel.BackgroundTransparency = 1
		codeLabel.Font = Enum.Font.GothamBold
		codeLabel.Text = string.format("CODE: %s • %s", activeCrime.PoliceCode or "10-31", activeCrime.District or "Midtown")
		codeLabel.TextColor3 = Color3.fromRGB(180, 195, 215)
		codeLabel.TextSize = 9.5
		codeLabel.TextXAlignment = Enum.TextXAlignment.Left
		codeLabel.Parent = card

		-- Rewards tag
		local rewLabel = Instance.new("TextLabel")
		rewLabel.Size = UDim2.new(1, -20, 0, 24)
		rewLabel.Position = UDim2.new(0, 12, 0, 56)
		rewLabel.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
		rewLabel.BackgroundTransparency = 0.5
		rewLabel.Font = Enum.Font.GothamBold
		rewLabel.Text = string.format("🏆 REWARDS: +%d XP  |  +$%d HERO CASH", activeCrime.RewardXP or 150, activeCrime.RewardCash or 250)
		rewLabel.TextColor3 = Color3.fromRGB(255, 210, 65)
		rewLabel.TextSize = 10
		rewLabel.Parent = card
		local rewCorn = Instance.new("UICorner")
		rewCorn.CornerRadius = UDim.new(0, 6)
		rewCorn.Parent = rewLabel

		-- Track Waypoint Action & On-Demand Dispatch Hotline
		local trackBtn = Instance.new("TextButton")
		trackBtn.Size = UDim2.new(0.56, -12, 0, 34)
		trackBtn.Position = UDim2.new(0, 10, 0, 88)
		trackBtn.BackgroundColor3 = Color3.fromRGB(35, 105, 235)
		trackBtn.Font = Enum.Font.GothamBold
		trackBtn.Text = "🧭 TRACK GPS"
		trackBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		trackBtn.TextSize = 10.5
		trackBtn.Parent = card
		local trkCorn = Instance.new("UICorner")
		trkCorn.CornerRadius = UDim.new(0, 8)
		trkCorn.Parent = trackBtn

		trackBtn.MouseButton1Click:Connect(function()
			SpiderPhoneHUD.toggle(false)
		end)

		local reCallBtn = Instance.new("TextButton")
		reCallBtn.Size = UDim2.new(0.44, -12, 0, 34)
		reCallBtn.Position = UDim2.new(0.56, 2, 0, 88)
		reCallBtn.BackgroundColor3 = Color3.fromRGB(205, 45, 60)
		reCallBtn.Font = Enum.Font.GothamBold
		reCallBtn.Text = "🚨 CALL YURI"
		reCallBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		reCallBtn.TextSize = 10
		reCallBtn.Parent = card
		local rcCorn = Instance.new("UICorner")
		rcCorn.CornerRadius = UDim.new(0, 8)
		rcCorn.Parent = reCallBtn

		reCallBtn.MouseButton1Click:Connect(function()
			playPhoneSound("RadioChirp")
			reCallBtn.Text = "📞 CALLING..."
			CrimeInteractRemote:FireServer("RequestDispatch")
			task.delay(1.2, function()
				reCallBtn.Text = "🚨 CALL YURI"
				SpiderPhoneHUD.renderActiveApp()
			end)
		end)

		local statusPill = Instance.new("TextLabel")
		statusPill.Size = UDim2.new(1, -20, 0, 22)
		statusPill.Position = UDim2.new(0, 10, 0, 126)
		statusPill.BackgroundTransparency = 1
		statusPill.Font = Enum.Font.Gotham
		statusPill.Text = "● Move to location and neutralize all hostiles"
		statusPill.TextColor3 = Color3.fromRGB(80, 245, 135)
		statusPill.TextSize = 9.5
		statusPill.Parent = card
	else
		-- No Crime Active Card
		local emptyCard = Instance.new("Frame")
		emptyCard.Name = "EmptyCard"
		emptyCard.LayoutOrder = 2
		emptyCard.Size = UDim2.new(1, 0, 0, 130)
		emptyCard.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
		emptyCard.BackgroundTransparency = 0.2
		emptyCard.Parent = scroll
		local eCorn = Instance.new("UICorner")
		eCorn.CornerRadius = UDim.new(0, 12)
		eCorn.Parent = emptyCard

		local eMsg = Instance.new("TextLabel")
		eMsg.Size = UDim2.new(1, -20, 0, 42)
		eMsg.Position = UDim2.new(0, 10, 0, 16)
		eMsg.BackgroundTransparency = 1
		eMsg.Font = Enum.Font.Gotham
		eMsg.Text = "🏙️ All Manhattan districts are currently quiet.\nNo 10-Codes reported."
		eMsg.TextColor3 = Color3.fromRGB(170, 185, 205)
		eMsg.TextSize = 11
		eMsg.Parent = emptyCard

		-- On-Demand Request Dispatch Button
		local reqBtn = Instance.new("TextButton")
		reqBtn.Size = UDim2.new(1, -20, 0, 40)
		reqBtn.Position = UDim2.new(0, 10, 0, 72)
		reqBtn.BackgroundColor3 = Color3.fromRGB(225, 45, 60)
		reqBtn.Font = Enum.Font.GothamBold
		reqBtn.Text = "🚨 CALL DISPATCH (YURI WATANABE)"
		reqBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		reqBtn.TextSize = 11
		reqBtn.Parent = emptyCard
		local rCorn = Instance.new("UICorner")
		rCorn.CornerRadius = UDim.new(0, 8)
		rCorn.Parent = reqBtn

		reqBtn.MouseButton1Click:Connect(function()
			playPhoneSound("RadioChirp")
			reqBtn.Text = "📡 CONTACTING CAPTAIN WATANABE..."
			reqBtn.BackgroundColor3 = Color3.fromRGB(120, 130, 145)
			CrimeInteractRemote:FireServer("RequestDispatch")
			task.delay(1.2, function()
				SpiderPhoneHUD.renderActiveApp()
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- 🛍️ APP 2: SUIT WARDROBE & HERO CASH ECONOMY
--------------------------------------------------------------------------------

local function renderSuitsApp(parent: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "SuitsScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 75, 95)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = parent

	local sPad = Instance.new("UIPadding")
	sPad.PaddingRight = UDim.new(0, 8)
	sPad.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = scroll

	-- Fetch Player Data
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	local playerLevel = leaderstats and leaderstats:FindFirstChild("Level") and (leaderstats.Level :: IntValue).Value or 1
	local playerCash = leaderstats and leaderstats:FindFirstChild("Hero Cash") and (leaderstats["Hero Cash"] :: IntValue).Value or 0

	-- Refresh Server Data
	pcall(function()
		local unlocked, equipped = GetSuitDataRF:InvokeServer()
		if unlocked then cachedUnlockedSuits = unlocked end
		if equipped then cachedEquippedSuit = equipped end
	end)

	for suitIndex, suit in SuitConfig.Suits do
		local isUnlocked = cachedUnlockedSuits[suit.Id] == true
		local isEquipped = cachedEquippedSuit == suit.Id
		local meetsLevel = playerLevel >= suit.UnlockLevel

		local card = Instance.new("Frame")
		card.Name = "SuitCard_" .. suit.Id
		card.LayoutOrder = suitIndex
		card.Size = UDim2.new(1, 0, 0, 96)
		card.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
		card.BackgroundTransparency = 0.15
		card.Parent = scroll
		local cCorn = Instance.new("UICorner")
		cCorn.CornerRadius = UDim.new(0, 10)
		cCorn.Parent = card

		local cStroke = Instance.new("UIStroke")
		cStroke.Thickness = isEquipped and 2.0 or 1.0
		cStroke.Color = isEquipped and Color3.fromRGB(80, 245, 140) or suit.ThemeColor
		cStroke.Transparency = isEquipped and 0.1 or 0.4
		cStroke.Parent = card

		-- Suit Icon
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0, 32, 0, 32)
		icon.Position = UDim2.new(0, 8, 0, 8)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.GothamBlack
		icon.Text = suit.Icon
		icon.TextSize = 20
		icon.Parent = card

		-- Suit Title & Tagline
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -120, 0, 18)
		nameLabel.Position = UDim2.new(0, 44, 0, 8)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.Text = suit.Name
		nameLabel.TextColor3 = isEquipped and Color3.fromRGB(80, 245, 140) or Color3.fromRGB(240, 245, 255)
		nameLabel.TextSize = 11.5
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		-- Perk Description
		local perkLabel = Instance.new("TextLabel")
		perkLabel.Size = UDim2.new(1, -120, 0, 32)
		perkLabel.Position = UDim2.new(0, 44, 0, 26)
		perkLabel.BackgroundTransparency = 1
		perkLabel.Font = Enum.Font.Gotham
		perkLabel.Text = suit.PerkDescription
		perkLabel.TextColor3 = Color3.fromRGB(205, 220, 240)
		perkLabel.TextSize = 9.5
		perkLabel.TextWrapped = true
		perkLabel.TextXAlignment = Enum.TextXAlignment.Left
		perkLabel.Parent = card

		-- Price / Level Tag
		local reqLabel = Instance.new("TextLabel")
		reqLabel.Size = UDim2.new(1, -120, 0, 16)
		reqLabel.Position = UDim2.new(0, 44, 0, 68)
		reqLabel.BackgroundTransparency = 1
		reqLabel.Font = Enum.Font.GothamBold
		if isUnlocked then
			reqLabel.Text = "✅ UNLOCKED IN CLOSET"
			reqLabel.TextColor3 = Color3.fromRGB(80, 245, 140)
		else
			reqLabel.Text = string.format("🔒 LVL %d  •  💰 $%d CASH", suit.UnlockLevel, suit.HeroCashCost)
			reqLabel.TextColor3 = Color3.fromRGB(205, 220, 240)
		end
		reqLabel.TextSize = 9.5
		reqLabel.TextXAlignment = Enum.TextXAlignment.Left
		reqLabel.Parent = card

		-- Action Button (EQUIP / EQUIPPED / BUY)
		local actionBtn = Instance.new("TextButton")
		actionBtn.AnchorPoint = Vector2.new(1, 0.5)
		actionBtn.Position = UDim2.new(1, -8, 0.5, 0)
		actionBtn.Size = UDim2.new(0, 68, 0, 32)
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.TextSize = 10
		actionBtn.Parent = card
		local aCorn = Instance.new("UICorner")
		aCorn.CornerRadius = UDim.new(0, 8)
		aCorn.Parent = actionBtn

		if isEquipped then
			actionBtn.BackgroundColor3 = Color3.fromRGB(24, 45, 34)
			actionBtn.Text = "EQUIPPED"
			actionBtn.TextColor3 = Color3.fromRGB(80, 245, 140)
			actionBtn.AutoButtonColor = false
		elseif isUnlocked then
			actionBtn.BackgroundColor3 = Color3.fromRGB(35, 95, 225)
			actionBtn.Text = "EQUIP"
			actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

			actionBtn.MouseButton1Click:Connect(function()
				local ok, msg = SuitEquipRF:InvokeServer(suit.Id)
				if ok then
					cachedEquippedSuit = suit.Id
					SpiderPhoneHUD.renderActiveApp()
					updateSuitShowcase()
				end
			end)
		else
			if not meetsLevel then
				actionBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 60)
				actionBtn.Text = "LVL " .. suit.UnlockLevel
				actionBtn.TextColor3 = Color3.fromRGB(150, 160, 175)
				actionBtn.AutoButtonColor = false
			elseif playerCash < suit.HeroCashCost then
				actionBtn.BackgroundColor3 = Color3.fromRGB(55, 35, 40)
				actionBtn.Text = "BUY"
				actionBtn.TextColor3 = Color3.fromRGB(220, 110, 110)
				actionBtn.AutoButtonColor = false
			else
				actionBtn.BackgroundColor3 = Color3.fromRGB(225, 175, 45)
				actionBtn.Text = "BUY"
				actionBtn.TextColor3 = Color3.fromRGB(15, 20, 25)

				actionBtn.MouseButton1Click:Connect(function()
					local ok, msg = SuitPurchaseRF:InvokeServer(suit.Id)
					if ok then
						cachedUnlockedSuits[suit.Id] = true
						cachedEquippedSuit = suit.Id
						SuitEquipRF:InvokeServer(suit.Id)
						SpiderPhoneHUD.renderActiveApp()
						updateSuitShowcase()
					end
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 🥋 APP 2: HERO MOVES & COMBAT ARSENAL
--------------------------------------------------------------------------------

local function renderMovesApp(parent: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "MovesScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(65, 155, 255)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = parent

	local sPad = Instance.new("UIPadding")
	sPad.PaddingRight = UDim.new(0, 8)
	sPad.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = scroll

	-- Header Banner
	local banner = Instance.new("Frame")
	banner.Name = "MovesBanner"
	banner.LayoutOrder = 1
	banner.Size = UDim2.new(1, 0, 0, 50)
	banner.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
	banner.BackgroundTransparency = 0.2
	banner.Parent = scroll
	local bCorn = Instance.new("UICorner")
	bCorn.CornerRadius = UDim.new(0, 10)
	bCorn.Parent = banner

	local bTitle = Instance.new("TextLabel")
	bTitle.Size = UDim2.new(1, -16, 0, 22)
	bTitle.Position = UDim2.new(0, 10, 0, 4)
	bTitle.BackgroundTransparency = 1
	bTitle.Font = Enum.Font.GothamBlack
	bTitle.Text = "🥋 HERO MOVES & COMBAT ARSENAL"
	bTitle.TextColor3 = Color3.fromRGB(85, 185, 255)
	bTitle.TextSize = 12
	bTitle.TextXAlignment = Enum.TextXAlignment.Left
	bTitle.Parent = banner

	local bSub = Instance.new("TextLabel")
	bSub.Size = UDim2.new(1, -16, 0, 18)
	bSub.Position = UDim2.new(0, 10, 0, 26)
	bSub.BackgroundTransparency = 1
	bSub.Font = Enum.Font.Gotham
	bSub.Text = "Master Spider-Man's kinetic combat, web gadgets, and signature ultimate!"
	bSub.TextColor3 = Color3.fromRGB(160, 175, 195)
	bSub.TextSize = 9.5
	bSub.TextXAlignment = Enum.TextXAlignment.Left
	bSub.Parent = banner

	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	local playerLevel = leaderstats and leaderstats:FindFirstChild("Level") and (leaderstats.Level :: IntValue).Value or 1
	local isCycloneUnlocked = playerLevel >= 2 or RunService:IsStudio()

	-- 🌪️ TOP SPOTLIGHT CARD: Level 2 Ultimate (360° Web Cyclone Blender)
	local spotCard = Instance.new("Frame")
	spotCard.Name = "SpotlightCard_Cyclone"
	spotCard.LayoutOrder = 2
	spotCard.Size = UDim2.new(1, 0, 0, 84)
	spotCard.BackgroundColor3 = isCycloneUnlocked and Color3.fromRGB(24, 30, 46) or Color3.fromRGB(15, 18, 28)
	spotCard.BackgroundTransparency = 0.15
	spotCard.Parent = scroll
	local spCorn = Instance.new("UICorner")
	spCorn.CornerRadius = UDim.new(0, 12)
	spCorn.Parent = spotCard

	local spStroke = Instance.new("UIStroke")
	spStroke.Thickness = isCycloneUnlocked and 1.8 or 1.0
	spStroke.Color = isCycloneUnlocked and Color3.fromRGB(255, 170, 45) or Color3.fromRGB(70, 60, 50)
	spStroke.Transparency = isCycloneUnlocked and 0.2 or 0.6
	spStroke.Parent = spotCard

	local spIcon = Instance.new("TextLabel")
	spIcon.Size = UDim2.new(0, 36, 0, 36)
	spIcon.Position = UDim2.new(0, 10, 0, 10)
	spIcon.BackgroundTransparency = 1
	spIcon.Font = Enum.Font.GothamBlack
	spIcon.Text = "🌪️"
	spIcon.TextSize = 24
	spIcon.Parent = spotCard

	local spTitle = Instance.new("TextLabel")
	spTitle.Size = UDim2.new(1, -165, 0, 20)
	spTitle.Position = UDim2.new(0, 50, 0, 8)
	spTitle.BackgroundTransparency = 1
	spTitle.Font = Enum.Font.GothamBlack
	spTitle.Text = "360° WEB CYCLONE BLENDER"
	spTitle.TextColor3 = isCycloneUnlocked and Color3.fromRGB(255, 200, 75) or Color3.fromRGB(170, 160, 150)
	spTitle.TextSize = 12
	spTitle.TextXAlignment = Enum.TextXAlignment.Left
	spTitle.Parent = spotCard

	local spKeyPill = Instance.new("TextLabel")
	spKeyPill.AnchorPoint = Vector2.new(1, 0)
	spKeyPill.Position = UDim2.new(1, -10, 0, 8)
	spKeyPill.Size = UDim2.new(0, 120, 0, 20)
	spKeyPill.BackgroundColor3 = isCycloneUnlocked and Color3.fromRGB(48, 36, 20) or Color3.fromRGB(25, 25, 32)
	spKeyPill.Font = Enum.Font.GothamBold
	spKeyPill.Text = "T KEY // ULTIMATE"
	spKeyPill.TextColor3 = isCycloneUnlocked and Color3.fromRGB(255, 195, 65) or Color3.fromRGB(130, 130, 140)
	spKeyPill.TextSize = 9
	spKeyPill.Parent = spotCard
	local spKeyCorn = Instance.new("UICorner")
	spKeyCorn.CornerRadius = UDim.new(0, 5)
	spKeyCorn.Parent = spKeyPill

	local spStatus = Instance.new("TextLabel")
	spStatus.Size = UDim2.new(1, -60, 0, 16)
	spStatus.Position = UDim2.new(0, 50, 0, 28)
	spStatus.BackgroundTransparency = 1
	spStatus.Font = Enum.Font.GothamBold
	if isCycloneUnlocked then
		spStatus.Text = "✅ UNLOCKED // READY"
		spStatus.TextColor3 = Color3.fromRGB(80, 245, 140)
	else
		spStatus.Text = "🔒 UNLOCKS AT LEVEL 2 (3–4 Crimes)"
		spStatus.TextColor3 = Color3.fromRGB(245, 110, 110)
	end
	spStatus.TextSize = 9.5
	spStatus.TextXAlignment = Enum.TextXAlignment.Left
	spStatus.Parent = spotCard

	local spSum = Instance.new("TextLabel")
	spSum.Size = UDim2.new(1, -20, 0, 24)
	spSum.Position = UDim2.new(0, 10, 0, 50)
	spSum.BackgroundTransparency = 1
	spSum.Font = Enum.Font.GothamMedium
	spSum.Text = "360° Dual-Web Cyclone • 60 AoE DPS • Wall-Pin Slam Finisher"
	spSum.TextColor3 = isCycloneUnlocked and Color3.fromRGB(205, 215, 235) or Color3.fromRGB(135, 145, 160)
	spSum.TextSize = 9.5
	spSum.TextWrapped = true
	spSum.TextXAlignment = Enum.TextXAlignment.Left
	spSum.Parent = spotCard

	-- ⚡ CODEX DIVIDER
	local codexDivider = Instance.new("Frame")
	codexDivider.Name = "CodexDivider"
	codexDivider.LayoutOrder = 3
	codexDivider.Size = UDim2.new(1, 0, 0, 28)
	codexDivider.BackgroundColor3 = Color3.fromRGB(15, 20, 32)
	codexDivider.BackgroundTransparency = 0.3
	codexDivider.Parent = scroll
	local cdCorn = Instance.new("UICorner")
	cdCorn.CornerRadius = UDim.new(0, 6)
	cdCorn.Parent = codexDivider

	local cdLabel = Instance.new("TextLabel")
	cdLabel.Size = UDim2.new(1, -16, 1, 0)
	cdLabel.Position = UDim2.new(0, 8, 0, 0)
	cdLabel.BackgroundTransparency = 1
	cdLabel.Font = Enum.Font.GothamBlack
	cdLabel.Text = "⚡ DAY-1 ACTIVE COMBAT CODEX (ALL CORE MOVES UNLOCKED)"
	cdLabel.TextColor3 = Color3.fromRGB(85, 185, 255)
	cdLabel.TextSize = 10
	cdLabel.TextXAlignment = Enum.TextXAlignment.Left
	cdLabel.Parent = codexDivider

	-- 🥋 6 DAY-1 ACTIVE COMBAT ABILITIES + SIGNATURE TRAVERSAL
	local codexMoves = {
		{
			Icon = "🥊",
			Name = "Kinetic Strike Combo",
			Keybind = "L-CLICK TAP (1-2-3)",
			Summary = "3-Hit Combo • Forward Lunge • Multi-Target Cleave",
			ThemeColor = Color3.fromRGB(85, 185, 255),
			Category = "CORE COMBAT",
		},
		{
			Icon = "🚀",
			Name = "Uppercut Launcher",
			Keybind = "HOLD L-CLICK (0.22s)",
			Summary = "Vertical Launch • 14-Stud Air Juggle Setup",
			ThemeColor = Color3.fromRGB(65, 195, 255),
			Category = "CORE COMBAT",
		},
		{
			Icon = "💥",
			Name = "Web-Line Ground Slam",
			Keybind = "IN-AIR L-CLICK",
			Summary = "Air Dive-Slam • 24-Stud Crater Shockwave",
			ThemeColor = Color3.fromRGB(255, 85, 95),
			Category = "CORE COMBAT",
		},
		{
			Icon = "🕸️",
			Name = "Rapid Web-Pellets & Wall-Pin",
			Keybind = "E KEY (TAP / HOLD)",
			Summary = "Rapid Bursts • 3-Stack Web Cocoon • Wall Pin",
			ThemeColor = Color3.fromRGB(80, 245, 140),
			Category = "CORE COMBAT",
		},
		{
			Icon = "📦",
			Name = "Web-Yank & Prop Throw",
			Keybind = "Q KEY",
			Summary = "Disarm Armed Guns • Snatch & Hurl Props",
			ThemeColor = Color3.fromRGB(255, 175, 45),
			Category = "CORE COMBAT",
		},
		{
			Icon = "⚡",
			Name = "Spider-Sense Perfect Dodge",
			Keybind = "F KEY",
			Summary = "0.45s Invulnerability • Point-Blank Web Counter",
			ThemeColor = Color3.fromRGB(180, 85, 255),
			Category = "CORE COMBAT",
		},
		{
			Icon = "🎯",
			Name = "Web-Strike Zip Dropkick",
			Keybind = "R KEY",
			Summary = "65-Stud Zip-Kick • Guard Break • Splash Impact",
			ThemeColor = Color3.fromRGB(65, 145, 255),
			Category = "SIGNATURE MOVE",
		},
		{
			Icon = "💨",
			Name = "Slingshot Super Launch",
			Keybind = "DOUBLE SPACE",
			Summary = "Dual-Web Catapult • Supersonic Launch",
			ThemeColor = Color3.fromRGB(145, 95, 255),
			Category = "TRAVERSAL",
		},
	}

	for i, move in codexMoves do
		local card = Instance.new("Frame")
		card.Name = "CodexCard_" .. i
		card.LayoutOrder = 10 + i
		card.Size = UDim2.new(1, 0, 0, 78)
		card.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
		card.BackgroundTransparency = 0.15
		card.Parent = scroll
		local cCorn = Instance.new("UICorner")
		cCorn.CornerRadius = UDim.new(0, 10)
		cCorn.Parent = card

		local cStroke = Instance.new("UIStroke")
		cStroke.Thickness = 1.0
		cStroke.Color = move.ThemeColor
		cStroke.Transparency = 0.45
		cStroke.Parent = card

		-- Move Icon
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0, 34, 0, 34)
		icon.Position = UDim2.new(0, 10, 0, 10)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.GothamBlack
		icon.Text = move.Icon
		icon.TextSize = 22
		icon.Parent = card

		-- Move Title
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -150, 0, 20)
		title.Position = UDim2.new(0, 48, 0, 8)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.Text = move.Name
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextSize = 12
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = card

		-- Keybind Pill
		local keyPill = Instance.new("TextLabel")
		keyPill.AnchorPoint = Vector2.new(1, 0)
		keyPill.Position = UDim2.new(1, -10, 0, 8)
		keyPill.Size = UDim2.new(0, 120, 0, 20)
		keyPill.BackgroundColor3 = Color3.fromRGB(28, 42, 68)
		keyPill.Font = Enum.Font.GothamBold
		keyPill.Text = move.Keybind
		keyPill.TextColor3 = move.ThemeColor
		keyPill.TextSize = 8.5
		keyPill.Parent = card
		local kpCorn = Instance.new("UICorner")
		kpCorn.CornerRadius = UDim.new(0, 5)
		kpCorn.Parent = keyPill

		-- Status Tag
		local status = Instance.new("TextLabel")
		status.Size = UDim2.new(1, -58, 0, 16)
		status.Position = UDim2.new(0, 48, 0, 28)
		status.BackgroundTransparency = 1
		status.Font = Enum.Font.GothamBold
		status.Text = string.format("✅ UNLOCKED // %s", move.Category)
		status.TextColor3 = Color3.fromRGB(80, 245, 140)
		status.TextSize = 9.5
		status.TextXAlignment = Enum.TextXAlignment.Left
		status.Parent = card

		-- Summary text
		local sum = Instance.new("TextLabel")
		sum.Size = UDim2.new(1, -20, 0, 24)
		sum.Position = UDim2.new(0, 10, 0, 48)
		sum.BackgroundTransparency = 1
		sum.Font = Enum.Font.GothamMedium
		sum.Text = move.Summary
		sum.TextColor3 = Color3.fromRGB(180, 195, 215)
		sum.TextSize = 9.5
		sum.TextWrapped = true
		sum.TextXAlignment = Enum.TextXAlignment.Left
		sum.Parent = card
	end
end

--------------------------------------------------------------------------------
-- ⭐ APP 4: HERO PROFILE & LEVEL PROGRESSION
--------------------------------------------------------------------------------

local function renderProfileApp(parent: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ProfileScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(65, 175, 255)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = parent

	local sPad = Instance.new("UIPadding")
	sPad.PaddingRight = UDim.new(0, 8)
	sPad.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = scroll

	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	local levelVal = leaderstats and leaderstats:FindFirstChild("Level") and (leaderstats.Level :: IntValue).Value or 1
	local xpVal = leaderstats and leaderstats:FindFirstChild("XP") and (leaderstats.XP :: IntValue).Value or 0
	local cashVal = leaderstats and leaderstats:FindFirstChild("Hero Cash") and (leaderstats["Hero Cash"] :: IntValue).Value or 0
	local crimesVal = leaderstats and leaderstats:FindFirstChild("Crimes Stopped") and (leaderstats["Crimes Stopped"] :: IntValue).Value or 0

	local baseXP = CrimeConfig.Economy.BaseXPForLevel or 350
	local scale = CrimeConfig.Economy.LevelScaleFactor or 1.18
	local nextLevelXP = math.floor(baseXP * (levelVal ^ scale))
	local xpRatio = math.clamp(xpVal / math.max(1, nextLevelXP), 0, 1)

	-- Hero Avatar Card
	local avatarCard = Instance.new("Frame")
	avatarCard.LayoutOrder = 1
	avatarCard.Size = UDim2.new(1, 0, 0, 100)
	avatarCard.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
	avatarCard.BackgroundTransparency = 0.2
	avatarCard.Parent = scroll
	local aCorn = Instance.new("UICorner")
	aCorn.CornerRadius = UDim.new(0, 12)
	aCorn.Parent = avatarCard

	local avatarImg = Instance.new("ImageLabel")
	avatarImg.Size = UDim2.new(0, 68, 0, 68)
	avatarImg.Position = UDim2.new(0, 14, 0, 16)
	avatarImg.BackgroundColor3 = Color3.fromRGB(24, 32, 50)
	avatarImg.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", LocalPlayer.UserId)
	avatarImg.Parent = avatarCard
	local imgCorn = Instance.new("UICorner")
	imgCorn.CornerRadius = UDim.new(0, 34)
	imgCorn.Parent = avatarImg

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -100, 0, 22)
	nameLabel.Position = UDim2.new(0, 94, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.Text = LocalPlayer.DisplayName
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = avatarCard

	local rankTitle = "Spider-Recruit"
	if levelVal >= 6 then
		rankTitle = "Legendary Spider-Protector"
	elseif levelVal >= 4 then
		rankTitle = "Senior Web-Warrior"
	elseif levelVal >= 2 then
		rankTitle = "City Vigilante"
	end

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Size = UDim2.new(1, -100, 0, 18)
	rankLabel.Position = UDim2.new(0, 94, 0, 44)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.Text = string.format("LEVEL %d • %s", levelVal, rankTitle)
	rankLabel.TextColor3 = Color3.fromRGB(65, 175, 255)
	rankLabel.TextSize = 11
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.Parent = avatarCard

	-- Level XP Progress Bar Card
	local xpCard = Instance.new("Frame")
	xpCard.LayoutOrder = 2
	xpCard.Size = UDim2.new(1, 0, 0, 60)
	xpCard.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
	xpCard.BackgroundTransparency = 0.2
	xpCard.Parent = scroll
	local xCorn = Instance.new("UICorner")
	xCorn.CornerRadius = UDim.new(0, 10)
	xCorn.Parent = xpCard

	local xpText = Instance.new("TextLabel")
	xpText.Size = UDim2.new(1, -20, 0, 18)
	xpText.Position = UDim2.new(0, 10, 0, 8)
	xpText.BackgroundTransparency = 1
	xpText.Font = Enum.Font.GothamBold
	xpText.Text = string.format("EXPERIENCE PROGRESS: %d / %d XP (%.0f%%)", xpVal, nextLevelXP, xpRatio * 100)
	xpText.TextColor3 = Color3.fromRGB(200, 215, 235)
	xpText.TextSize = 10
	xpText.TextXAlignment = Enum.TextXAlignment.Left
	xpText.Parent = xpCard

	local xpBg = Instance.new("Frame")
	xpBg.Position = UDim2.new(0, 10, 0, 32)
	xpBg.Size = UDim2.new(1, -20, 0, 10)
	xpBg.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
	xpBg.Parent = xpCard
	local xpBgCorn = Instance.new("UICorner")
	xpBgCorn.CornerRadius = UDim.new(0, 5)
	xpBgCorn.Parent = xpBg

	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(xpRatio, 0, 1, 0)
	xpFill.BackgroundColor3 = Color3.fromRGB(65, 175, 255)
	xpFill.Parent = xpBg
	local xpFillCorn = Instance.new("UICorner")
	xpFillCorn.CornerRadius = UDim.new(0, 5)
	xpFillCorn.Parent = xpFill

	-- Career Stats Matrix
	local statsCard = Instance.new("Frame")
	statsCard.LayoutOrder = 3
	statsCard.Size = UDim2.new(1, 0, 0, 172)
	statsCard.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
	statsCard.BackgroundTransparency = 0.2
	statsCard.Parent = scroll
	local sCorn = Instance.new("UICorner")
	sCorn.CornerRadius = UDim.new(0, 10)
	sCorn.Parent = statsCard

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.Padding = UDim.new(0, 6)
	statsLayout.Parent = statsCard

	local statsPadding = Instance.new("UIPadding")
	statsPadding.PaddingTop = UDim.new(0, 8)
	statsPadding.PaddingBottom = UDim.new(0, 8)
	statsPadding.PaddingLeft = UDim.new(0, 12)
	statsPadding.PaddingRight = UDim.new(0, 12)
	statsPadding.Parent = statsCard

	local equippedSuitDef = SuitConfig.getSuitById(cachedEquippedSuit)
	local activeSuitName = if equippedSuitDef then equippedSuitDef.Name else "Classic Red & Blue"
	local activeSuitPerk = if equippedSuitDef then equippedSuitDef.PerkDescription else "Standard hero mobility"

	local statLines = {
		{ Icon = "🚨", Title = "Crimes Stopped", Val = tostring(crimesVal) },
		{ Icon = "💰", Title = "Hero Cash Bank", Val = "$" .. tostring(cashVal) },
		{ Icon = "🕷️", Title = "Active Suit", Val = activeSuitName },
		{ Icon = "⚡", Title = "Current Perk", Val = activeSuitPerk },
	}

	for _, s in statLines do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, 0, 0, 32)
		line.BackgroundTransparency = 1
		line.Parent = statsCard

		local lText = Instance.new("TextLabel")
		lText.Size = UDim2.new(0.55, 0, 1, 0)
		lText.BackgroundTransparency = 1
		lText.Font = Enum.Font.GothamBold
		lText.Text = string.format("%s %s:", s.Icon, s.Title)
		lText.TextColor3 = Color3.fromRGB(175, 190, 210)
		lText.TextSize = 10.5
		lText.TextXAlignment = Enum.TextXAlignment.Left
		lText.Parent = line

		local rText = Instance.new("TextLabel")
		rText.Size = UDim2.new(0.45, 0, 1, 0)
		rText.Position = UDim2.new(0.55, 0, 0, 0)
		rText.BackgroundTransparency = 1
		rText.Font = Enum.Font.GothamBlack
		rText.Text = s.Val
		rText.TextColor3 = Color3.fromRGB(240, 245, 255)
		rText.TextSize = 10
		rText.TextXAlignment = Enum.TextXAlignment.Right
		rText.Parent = line
	end

	-- Radio Mute Toggle Card
	local muteCard = Instance.new("Frame")
	muteCard.LayoutOrder = 4
	muteCard.Size = UDim2.new(1, 0, 0, 68)
	muteCard.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
	muteCard.BackgroundTransparency = 0.2
	muteCard.Parent = scroll
	local mCorn = Instance.new("UICorner")
	mCorn.CornerRadius = UDim.new(0, 10)
	mCorn.Parent = muteCard

	local mTitle = Instance.new("TextLabel")
	mTitle.Size = UDim2.new(0.65, 0, 0, 24)
	mTitle.Position = UDim2.new(0, 12, 0, 12)
	mTitle.BackgroundTransparency = 1
	mTitle.Font = Enum.Font.GothamBold
	mTitle.Text = "📻 Police Dispatch Radio"
	mTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
	mTitle.TextSize = 11.5
	mTitle.TextXAlignment = Enum.TextXAlignment.Left
	mTitle.Parent = muteCard

	local mSub = Instance.new("TextLabel")
	mSub.Size = UDim2.new(0.65, 0, 0, 18)
	mSub.Position = UDim2.new(0, 12, 0, 36)
	mSub.BackgroundTransparency = 1
	mSub.Font = Enum.Font.Gotham
	mSub.Text = "Yuri dispatch audio & squelch"
	mSub.TextColor3 = Color3.fromRGB(160, 175, 195)
	mSub.TextSize = 9.5
	mSub.TextXAlignment = Enum.TextXAlignment.Left
	mSub.Parent = muteCard

	local muteBtn = Instance.new("TextButton")
	muteBtn.AnchorPoint = Vector2.new(1, 0.5)
	muteBtn.Position = UDim2.new(1, -12, 0.5, 0)
	muteBtn.Size = UDim2.new(0, 72, 0, 32)
	muteBtn.BackgroundColor3 = SpiderPhoneHUD.isRadioMuted and Color3.fromRGB(185, 45, 55) or Color3.fromRGB(35, 145, 65)
	muteBtn.Font = Enum.Font.GothamBold
	muteBtn.Text = SpiderPhoneHUD.isRadioMuted and "MUTED" or "ACTIVE"
	muteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	muteBtn.TextSize = 10
	muteBtn.Parent = muteCard
	local btnCorn = Instance.new("UICorner")
	btnCorn.CornerRadius = UDim.new(0, 8)
	btnCorn.Parent = muteBtn

	muteBtn.MouseButton1Click:Connect(function()
		SpiderPhoneHUD.isRadioMuted = not SpiderPhoneHUD.isRadioMuted
		muteBtn.BackgroundColor3 = SpiderPhoneHUD.isRadioMuted and Color3.fromRGB(185, 45, 55) or Color3.fromRGB(35, 145, 65)
		muteBtn.Text = SpiderPhoneHUD.isRadioMuted and "MUTED" or "ACTIVE"

		pcall(function()
			local PoliceRadio = require(script.Parent:WaitForChild("PoliceRadioHUD"))
			if PoliceRadio then
				PoliceRadio.isRadioMuted = SpiderPhoneHUD.isRadioMuted
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- 🔄 APP ROUTER & VIEW SWITCHER
--------------------------------------------------------------------------------

function SpiderPhoneHUD.renderActiveApp()
	if not contentArea then return end
	contentArea:ClearAllChildren()

	-- Update Cash balance header
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	local cashVal = leaderstats and leaderstats:FindFirstChild("Hero Cash") and (leaderstats["Hero Cash"] :: IntValue).Value or 0
	if cashDisplayLabel then
		cashDisplayLabel.Text = string.format("💰 $%d HERO CASH", cashVal)
	end

	if SpiderPhoneHUD.activeTab == "FNSM" then
		renderFNSMApp(contentArea)
	elseif SpiderPhoneHUD.activeTab == "Moves" then
		renderMovesApp(contentArea)
	elseif SpiderPhoneHUD.activeTab == "Suits" then
		renderSuitsApp(contentArea)
	elseif SpiderPhoneHUD.activeTab == "Profile" then
		renderProfileApp(contentArea)
	end
end

function SpiderPhoneHUD.switchTab(tabId: "FNSM" | "Moves" | "Suits" | "Profile")
	SpiderPhoneHUD.activeTab = tabId
	playPhoneSound("TabClick")

	if phoneFrame then
		local navBar = phoneFrame:FindFirstChild("NavBar")
		if navBar then
			for _, child in navBar:GetChildren() do
				if child:IsA("TextButton") then
					local isActive = (child.Name == "Tab_" .. tabId)
					child.BackgroundTransparency = isActive and 0.1 or 0.8
					child.TextColor3 = isActive and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 170, 195)
				end
			end
		end
	end

	SpiderPhoneHUD.renderActiveApp()
end

--------------------------------------------------------------------------------
-- 📱 PHONE OPEN / CLOSE TOGGLE
--------------------------------------------------------------------------------

function SpiderPhoneHUD.toggle(forcedState: boolean?)
	local newState = if forcedState ~= nil then forcedState else not SpiderPhoneHUD.isOpen
	if SpiderPhoneHUD.isOpen == newState then return end
	SpiderPhoneHUD.isOpen = newState

	-- 🔓 Unlock/Lock mouse and shift-lock for UI interaction
	CameraController.setUIMode(newState)

	-- 🛑 Lock character movement (WalkSpeed = 0, Jump = 0)
	lockMovement(newState)

	-- 🌫️ Cinematic Stark Tech Depth Blur
	local blur = getOrCreateBlur()
	TweenService:Create(blur, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = newState and 16 or 0,
	}):Play()

	if not screenGui or not visorContainer then
		createPhoneHUD()
	end

	if visorContainer then
		visorContainer.Visible = newState
	end

	if floatingOpenButton then
		floatingOpenButton.Visible = false
	end

	if newState then
		playPhoneSound("PhoneSlideIn")
		SpiderPhoneHUD.renderActiveApp()
		updateSuitShowcase()
	else
		playPhoneSound("PhoneSlideOut")
	end

	-- 🛡️ Isolate Police Radio HUD so it doesn't overlap the visor header
	pcall(function()
		local PoliceRadio = require(script.Parent:WaitForChild("PoliceRadioHUD"))
		if PoliceRadio and PoliceRadio.setVisorOpen then
			PoliceRadio.setVisorOpen(newState)
		end
	end)
end

--------------------------------------------------------------------------------
-- 🌐 INITIALIZATION & EVENT LISTENERS
--------------------------------------------------------------------------------

function SpiderPhoneHUD.init()
	createPhoneHUD()

	-- Auto-refresh active crime data on spawn/clear
	CrimeNotificationRemote.OnClientEvent:Connect(function()
		if SpiderPhoneHUD.isOpen then
			if SpiderPhoneHUD.activeTab == "FNSM" then
				SpiderPhoneHUD.renderActiveApp()
			end
		end
	end)

	-- Keybind Toggles (M Key and Esc Key)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.M then
			SpiderPhoneHUD.toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and SpiderPhoneHUD.isOpen then
			SpiderPhoneHUD.toggle(false)
		end
	end)

	-- Character Respawn Handling (Reset walkspeed locks & reload 3D hologram)
	LocalPlayer.CharacterAdded:Connect(function()
		savedWalkSpeed = nil
		savedJumpHeight = nil
		savedJumpPower = nil
		if SpiderPhoneHUD.isOpen then
			task.defer(function()
				lockMovement(true)
				updateSuitShowcase()
			end)
		end
	end)

	-- 3D Suit Hologram Idle Slow Rotation
	RunService.RenderStepped:Connect(function(dt)
		if SpiderPhoneHUD.isOpen and suitHoloModel and not isDraggingSuit then
			suitRotationAngle = (suitRotationAngle + (dt * 0.45)) % (math.pi * 2)
			suitHoloModel:PivotTo(CFrame.new(0, 0.2, 0) * CFrame.Angles(0, suitRotationAngle, 0))
		end
	end)
end

SpiderPhoneHUD.init()

return SpiderPhoneHUD
