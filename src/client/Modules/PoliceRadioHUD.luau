--!strict
--[[
	PoliceRadioHUD.luau
	Spider-Man: Brand New Day — In-Suit Smartphone / Police Radio HUD & Holographic Waypoints.
	
	Features:
	- 📱 Glassmorphic In-Suit Comm Card (Captain Yuri Dispatch, animated equalizer bars, live call states)
	- ⌨️ Smooth Typewriter Intel Dialogue (12s presentation of authentic police radio chatter)
	- 📍 3D Holographic Waypoints with Elevation Tracking (▲ High-Rise / ▼ Street Level / ◆ Level + 360° off-screen edge clamping)
	- 🎯 Clean Off-Screen Directional Chevron Indicator (Smooth bounds ray-cast, zero text overlap)
	- 🚨 Angular Marvel Comic Victory Celebration Banner & Dynamic Level-Up Offset
	- 🛡️ Strictly Typed (--!strict) & Zero Hardcoded Audio Fallbacks
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrimeConfig = require(Shared:WaitForChild("CrimeConfig"))
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local isUIVisible = not (CombatConfig.CinematicMode == true)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

type CrimeData = {
	Id: string?,
	Title: string?,
	PoliceCode: string?,
	DispatchMessage: string?,
	Icon: string?,
	Epicenter: Vector3?,
	ThemeColor: Color3?,
	Timeout: number?,
	RewardXP: number?,
	RewardCash: number?,
	ParticipantCount: number?,
	Reason: string?,
}

local PoliceRadioHUD = {
	activeCrimeData = nil :: CrimeData?,
	isRadioSpeaking = false,
	isCrimeActive = false,
	isRadioMuted = false,
	isVisorOpen = false,
}

-- GUI Object References
local screenGui: ScreenGui? = nil

-- In-Suit Comm Card
local commCard: Frame? = nil
local commCardStroke: UIStroke? = nil
local callerBadge: TextLabel? = nil
local callerTitleLabel: TextLabel? = nil
local callStatePill: Frame? = nil
local callStatePillStroke: UIStroke? = nil
local callStateDot: Frame? = nil
local callStateLabel: TextLabel? = nil
local intelSubheadLabel: TextLabel? = nil
local intelDialogueLabel: TextLabel? = nil
local waveContainer: Frame? = nil
local waveBars: { Frame } = {}

-- 3D Waypoint Marker
local waypointMarker: Frame? = nil
local waypointMarkerStroke: UIStroke? = nil
local waypointIconLabel: TextLabel? = nil
local waypointTitleLabel: TextLabel? = nil
local waypointDistLabel: TextLabel? = nil
local pointerArrow: ImageLabel? = nil

-- Victory Banner
local victoryBanner: Frame? = nil
local victoryTitleLabel: TextLabel? = nil
local victoryRewardsLabel: TextLabel? = nil
local victorySubLabel: TextLabel? = nil
local isVictoryBannerShowing = false
local lastLevelUpTime = 0
local lastWaypointMode: string? = nil

-- 🌌 3D Holographic World Beacon (Insomniac Manhattan Sky Pillar)
local activeBeaconModel: Model? = nil

local function cleanupWorldBeacon()
	if activeBeaconModel then
		activeBeaconModel:Destroy()
		activeBeaconModel = nil
	end
end

local function createWorldBeacon(epicenter: Vector3, themeColor: Color3)
	cleanupWorldBeacon()
	if not isUIVisible then return end

	local model = Instance.new("Model")
	model.Name = "CrimeHoloBeacon"

	-- 1. Sky Pillar: Glowing neon vertical cylinder rising into the clouds
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(300, 2.6, 2.6) -- Cylinder X is height in Roblox!
	pillar.CFrame = CFrame.new(epicenter + Vector3.new(0, 150, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Color = themeColor
	pillar.Material = Enum.Material.Neon
	pillar.Transparency = 0.55
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanTouch = false
	pillar.CanQuery = false
	pillar.Parent = model

	-- 2. Base Holo Disc / Ground Scanner Ring
	local ring = Instance.new("Part")
	ring.Name = "HoloRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 26, 26)
	ring.CFrame = CFrame.new(epicenter + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = themeColor
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.60
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Parent = model

	-- 3. Core Pulse Light
	local pointLight = Instance.new("PointLight")
	pointLight.Name = "BeaconLight"
	pointLight.Color = themeColor
	pointLight.Brightness = 2.5
	pointLight.Range = 35
	pointLight.Parent = ring

	model.Parent = Workspace
	activeBeaconModel = model
end

--------------------------------------------------------------------------------
-- 🎵 AUDIO SYNTHESIS & SFX HELPER
--------------------------------------------------------------------------------

local function playDispatchSound(_soundType: "RadioSquelch" | "Victory" | "Siren")
	-- Zero SFX Policy: Completely silent visual-only dispatch
	return
end

--------------------------------------------------------------------------------
-- PROGRAMMATIC GLASSMORPHIC UI GENERATION
--------------------------------------------------------------------------------

local function createHUD()
	if PlayerGui:FindFirstChild("PoliceRadioHUD") then
		local existing = PlayerGui:FindFirstChild("PoliceRadioHUD")
		if existing then existing:Destroy() end
	end

	waveBars = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "PoliceRadioHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 15
	gui.IgnoreGuiInset = true
	gui.Enabled = isUIVisible

	----------------------------------------------------------------------------
	-- 📱 1. IN-SUIT GLASSMORPHIC COMM CARD (Dynamic Island Top-Center)
	----------------------------------------------------------------------------
	local card = Instance.new("Frame")
	card.Name = "CommCard"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, -120) -- Hidden above top of screen
	card.Size = UDim2.new(0, 360, 0, 84)
	card.BackgroundColor3 = Color3.fromRGB(11, 15, 24)
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	card.Parent = gui

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Name = "CardStroke"
	cardStroke.Thickness = 1.4
	cardStroke.Color = Color3.fromRGB(65, 195, 255)
	cardStroke.Transparency = 0.25
	cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cardStroke.Parent = card

	-- Subtle Top Gloss Accent
	local topGlow = Instance.new("Frame")
	topGlow.Name = "TopGlow"
	topGlow.Position = UDim2.new(0, 12, 0, 2)
	topGlow.Size = UDim2.new(1, -24, 0, 1)
	topGlow.BackgroundColor3 = Color3.fromRGB(200, 235, 255)
	topGlow.BackgroundTransparency = 0.55
	topGlow.BorderSizePixel = 0
	topGlow.Parent = card

	-- Header Frame
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Position = UDim2.new(0, 12, 0, 6)
	header.Size = UDim2.new(1, -24, 0, 22)
	header.BackgroundTransparency = 1
	header.Parent = card

	-- Caller Avatar Badge
	local badge = Instance.new("TextLabel")
	badge.Name = "CallerBadge"
	badge.Position = UDim2.new(0, 0, 0.5, -10)
	badge.Size = UDim2.new(0, 20, 0, 20)
	badge.BackgroundColor3 = Color3.fromRGB(22, 32, 50)
	badge.BackgroundTransparency = 0.3
	badge.Font = Enum.Font.GothamBlack
	badge.Text = "📞"
	badge.TextSize = 11
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Parent = header

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Thickness = 1
	badgeStroke.Color = Color3.fromRGB(80, 200, 255)
	badgeStroke.Transparency = 0.4
	badgeStroke.Parent = badge

	-- Caller Title Label
	local callerTitle = Instance.new("TextLabel")
	callerTitle.Name = "CallerTitle"
	callerTitle.Position = UDim2.new(0, 26, 0, 0)
	callerTitle.Size = UDim2.new(0, 160, 1, 0)
	callerTitle.BackgroundTransparency = 1
	callerTitle.Font = Enum.Font.GothamBold
	callerTitle.Text = "NYPD DISPATCH | CAPT. YURI"
	callerTitle.TextColor3 = Color3.fromRGB(240, 246, 255)
	callerTitle.TextSize = 9.5
	callerTitle.TextXAlignment = Enum.TextXAlignment.Left
	callerTitle.Parent = header

	-- Live Call State Pill
	local callPill = Instance.new("Frame")
	callPill.Name = "CallStatePill"
	callPill.AnchorPoint = Vector2.new(1, 0.5)
	callPill.Position = UDim2.new(1, 0, 0.5, 0)
	callPill.Size = UDim2.new(0, 64, 0, 18)
	callPill.BackgroundColor3 = Color3.fromRGB(16, 42, 30)
	callPill.BackgroundTransparency = 0.3
	callPill.Parent = header

	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0, 6)
	pillCorner.Parent = callPill

	local pillStroke = Instance.new("UIStroke")
	pillStroke.Thickness = 1
	pillStroke.Color = Color3.fromRGB(60, 220, 130)
	pillStroke.Transparency = 0.45
	pillStroke.Parent = callPill

	local dot = Instance.new("Frame")
	dot.Name = "PulsingDot"
	dot.Position = UDim2.new(0, 6, 0.5, -3)
	dot.Size = UDim2.new(0, 6, 0, 6)
	dot.BackgroundColor3 = Color3.fromRGB(75, 245, 140)
	dot.BorderSizePixel = 0
	dot.Parent = callPill

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local callLabel = Instance.new("TextLabel")
	callLabel.Name = "CallLabel"
	callLabel.Position = UDim2.new(0, 16, 0, 0)
	callLabel.Size = UDim2.new(1, -18, 1, 0)
	callLabel.BackgroundTransparency = 1
	callLabel.Font = Enum.Font.GothamBold
	callLabel.Text = "LIVE RADIO"
	callLabel.TextColor3 = Color3.fromRGB(90, 245, 150)
	callLabel.TextSize = 8
	callLabel.Parent = callPill

	-- Audio Waveform Equalizer Container
	local waves = Instance.new("Frame")
	waves.Name = "EqualizerContainer"
	waves.AnchorPoint = Vector2.new(1, 0.5)
	waves.Position = UDim2.new(1, -70, 0.5, 0)
	waves.Size = UDim2.new(0, 26, 0, 14)
	waves.BackgroundTransparency = 1
	waves.Parent = header
	waveContainer = waves

	local waveLayout = Instance.new("UIListLayout")
	waveLayout.FillDirection = Enum.FillDirection.Horizontal
	waveLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	waveLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	waveLayout.Padding = UDim.new(0, 2)
	waveLayout.Parent = waves

	for _ = 1, 5 do
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 3, 0, 3)
		bar.BackgroundColor3 = Color3.fromRGB(80, 215, 255)
		bar.BorderSizePixel = 0
		bar.Parent = waves
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(1, 0)
		bc.Parent = bar
		table.insert(waveBars, bar)
	end

	-- Subheader (10-Code & Location Tag)
	local subhead = Instance.new("TextLabel")
	subhead.Name = "IntelSubhead"
	subhead.Position = UDim2.new(0, 12, 0, 28)
	subhead.Size = UDim2.new(1, -24, 0, 14)
	subhead.BackgroundTransparency = 1
	subhead.Font = Enum.Font.GothamBlack
	subhead.Text = "🚨 10-70 IN PROGRESS • ROOFTOP ARMS DEAL"
	subhead.TextColor3 = Color3.fromRGB(255, 195, 60)
	subhead.TextSize = 9.5
	subhead.TextXAlignment = Enum.TextXAlignment.Left
	subhead.Parent = card

	-- Body Dialogue (Typewriter Animated Intel)
	local dialogue = Instance.new("TextLabel")
	dialogue.Name = "IntelDialogue"
	dialogue.Position = UDim2.new(0, 12, 0, 44)
	dialogue.Size = UDim2.new(1, -24, 0, 34)
	dialogue.BackgroundTransparency = 1
	dialogue.Font = Enum.Font.GothamMedium
	dialogue.Text = ""
	dialogue.TextColor3 = Color3.fromRGB(220, 235, 250)
	dialogue.TextSize = 10
	dialogue.TextWrapped = true
	dialogue.TextXAlignment = Enum.TextXAlignment.Left
	dialogue.TextYAlignment = Enum.TextYAlignment.Top
	dialogue.Visible = true
	dialogue.Parent = card

	----------------------------------------------------------------------------
	-- 📍 2. 3D HOLOGRAPHIC WAYPOINT BEACON & DISTANCE BADGE
	----------------------------------------------------------------------------
	local marker = Instance.new("Frame")
	marker.Name = "WaypointMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.new(0, 150, 0, 34)
	marker.Position = UDim2.new(0.5, 0, 0.5, 0)
	marker.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
	marker.BackgroundTransparency = 0.18
	marker.BorderSizePixel = 0
	marker.Visible = false
	marker.Parent = gui

	local markerCorner = Instance.new("UICorner")
	markerCorner.CornerRadius = UDim.new(0, 10)
	markerCorner.Parent = marker

	local markerStroke = Instance.new("UIStroke")
	markerStroke.Thickness = 1.2
	markerStroke.Color = Color3.fromRGB(255, 75, 75)
	markerStroke.Transparency = 0.20
	markerStroke.Parent = marker

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "IconLabel"
	iconLabel.Position = UDim2.new(0, 6, 0.5, -9)
	iconLabel.Size = UDim2.new(0, 18, 0, 18)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBlack
	iconLabel.Text = "🚨"
	iconLabel.TextSize = 13
	iconLabel.Parent = marker

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Position = UDim2.new(0, 28, 0, 3)
	titleLabel.Size = UDim2.new(1, -32, 0, 15)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "ROOFTOP ARMS DEAL"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 10
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = marker

	local distLabel = Instance.new("TextLabel")
	distLabel.Name = "DistanceLabel"
	distLabel.Position = UDim2.new(0, 28, 0, 17)
	distLabel.Size = UDim2.new(1, -32, 0, 14)
	distLabel.BackgroundTransparency = 1
	distLabel.Font = Enum.Font.GothamBlack
	distLabel.Text = "▲ 53m (High-Rise)"
	distLabel.TextColor3 = Color3.fromRGB(85, 215, 255)
	distLabel.TextSize = 9.5
	distLabel.TextXAlignment = Enum.TextXAlignment.Left
	distLabel.Parent = marker

	-- Directional Pointer Chevron (Outside the pill)
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "PointerArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.new(0, 18, 0, 18)
	arrow.BackgroundTransparency = 1
	arrow.Image = "rbxassetid://6031094678"
	arrow.ImageColor3 = Color3.fromRGB(255, 75, 75)
	arrow.Visible = false
	arrow.Parent = gui

	----------------------------------------------------------------------------
	-- 🚨 3. VICTORY CELEBRATION BANNER (Stark OS / Marvel Angular Comic Readout)
	----------------------------------------------------------------------------
	local vBanner = Instance.new("Frame")
	vBanner.Name = "VictoryBanner"
	vBanner.AnchorPoint = Vector2.new(0.5, 0)
	vBanner.Position = UDim2.new(0.5, 0, 0, -100)
	vBanner.Size = UDim2.new(0, 420, 0, 78)
	vBanner.BackgroundColor3 = Color3.fromRGB(10, 16, 26)
	vBanner.BackgroundTransparency = 0.12
	vBanner.BorderSizePixel = 0
	vBanner.Parent = gui

	local vCorner = Instance.new("UICorner")
	vCorner.CornerRadius = UDim.new(0, 12)
	vCorner.Parent = vBanner

	local vStroke = Instance.new("UIStroke")
	vStroke.Thickness = 1.5
	vStroke.Color = Color3.fromRGB(80, 240, 255)
	vStroke.Transparency = 0.3
	vStroke.Parent = vBanner

	local vTitle = Instance.new("TextLabel")
	vTitle.Name = "VictoryTitle"
	vTitle.Position = UDim2.new(0, 0, 0, 8)
	vTitle.Size = UDim2.new(1, 0, 0, 24)
	vTitle.BackgroundTransparency = 1
	vTitle.Font = Enum.Font.GothamBlack
	vTitle.Text = "🚨 SECTOR SECURED"
	vTitle.TextColor3 = Color3.fromRGB(80, 240, 255)
	vTitle.TextSize = 19
	vTitle.Parent = vBanner

	local vRewards = Instance.new("TextLabel")
	vRewards.Name = "VictoryRewards"
	vRewards.Position = UDim2.new(0, 0, 0, 32)
	vRewards.Size = UDim2.new(1, 0, 0, 22)
	vRewards.BackgroundTransparency = 1
	vRewards.Font = Enum.Font.GothamBlack
	vRewards.Text = "+$250 HERO CASH   //   +150 XP"
	vRewards.TextColor3 = Color3.fromRGB(255, 215, 65)
	vRewards.TextSize = 15
	vRewards.Parent = vBanner

	local vSub = Instance.new("TextLabel")
	vSub.Name = "VictorySub"
	vSub.Position = UDim2.new(0, 0, 0, 54)
	vSub.Size = UDim2.new(1, 0, 0, 16)
	vSub.BackgroundTransparency = 1
	vSub.Font = Enum.Font.GothamBold
	vSub.Text = "STREET PATROL ACTIVE • MANHATTAN SAFE"
	vSub.TextColor3 = Color3.fromRGB(175, 210, 235)
	vSub.TextSize = 10.5
	vSub.Parent = vBanner

	gui.Parent = PlayerGui

	-- Store refs
	screenGui = gui
	commCard = card
	commCardStroke = cardStroke
	callerBadge = badge
	callerTitleLabel = callerTitle
	callStatePill = callPill
	callStateDot = dot
	callStateLabel = callLabel
	intelSubheadLabel = subhead
	intelDialogueLabel = dialogue
	waypointMarker = marker
	waypointMarkerStroke = markerStroke
	waypointIconLabel = iconLabel
	waypointTitleLabel = titleLabel
	waypointDistLabel = distLabel
	pointerArrow = arrow
	victoryBanner = vBanner
	victoryTitleLabel = vTitle
	victoryRewardsLabel = vRewards
	victorySubLabel = vSub
	lastWaypointMode = nil
end

--------------------------------------------------------------------------------
-- ⌨️ TYPEWRITER INTEL DIALOGUE (Smooth 12s Speech Sync)
--------------------------------------------------------------------------------

local activeTypewriterToken = 0

local function runTypewriterDialogue(fullText: string, durationSeconds: number)
	activeTypewriterToken += 1
	local currentToken = activeTypewriterToken
	PoliceRadioHUD.isRadioSpeaking = true

	if intelDialogueLabel then
		intelDialogueLabel.Text = fullText
		intelDialogueLabel.MaxVisibleGraphemes = 0
	end

	-- utf8-aware length: emoji are multi-byte, so byte-slicing would render broken glyphs
	local glyphCount = utf8.len(fullText) or string.len(fullText)
	if glyphCount == 0 then
		PoliceRadioHUD.isRadioSpeaking = false
		return
	end

	local stepDelay = math.clamp(durationSeconds / glyphCount, 0.015, 0.065)

	task.spawn(function()
		for i = 1, glyphCount do
			if currentToken ~= activeTypewriterToken then break end
			if intelDialogueLabel then
				intelDialogueLabel.MaxVisibleGraphemes = i
			end
			task.wait(stepDelay)
		end

		if currentToken == activeTypewriterToken then
			if intelDialogueLabel then
				intelDialogueLabel.MaxVisibleGraphemes = -1
			end
			task.wait(1.5)
			if currentToken == activeTypewriterToken then
				PoliceRadioHUD.isRadioSpeaking = false
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- 🚨 CRIME SPAWNED & RADAR BEACON ACTIVATION
--------------------------------------------------------------------------------

function PoliceRadioHUD.onCrimeSpawned(data: CrimeData)
	PoliceRadioHUD.activeCrimeData = data
	PoliceRadioHUD.isCrimeActive = true

	if not screenGui or not commCard then
		createHUD()
	end

	local themeColor = data.ThemeColor or Color3.fromRGB(255, 75, 75)

	if commCard and intelSubheadLabel and commCardStroke and waypointIconLabel and waypointTitleLabel then
		local pCode = string.upper(data.PoliceCode or "10-31 IN PROGRESS")
		local cTitle = string.upper(data.Title or "ACTIVE CRIME")
		intelSubheadLabel.Text = string.format("%s %s • %s", data.Icon or "🚨", pCode, cTitle)
		intelSubheadLabel.TextColor3 = themeColor

		commCardStroke.Color = themeColor

		waypointIconLabel.Text = data.Icon or "🚨"
		waypointTitleLabel.Text = cTitle

		if waypointMarker and waypointMarkerStroke then
			waypointMarkerStroke.Color = themeColor
			waypointMarker.Visible = isUIVisible and (not PoliceRadioHUD.isVisorOpen)
		end

		if pointerArrow then
			pointerArrow.ImageColor3 = themeColor
			pointerArrow.Visible = isUIVisible and (not PoliceRadioHUD.isVisorOpen)
		end

		-- 3D Sky Beacon at Epicenter
		if data.Epicenter and isUIVisible then
			createWorldBeacon(data.Epicenter, themeColor)
		end

		if isUIVisible and not PoliceRadioHUD.isRadioMuted and not PoliceRadioHUD.isVisorOpen then
			-- Play radio squelch
			playDispatchSound("RadioSquelch")

			-- Slide In Comm Card from Top Center (Dynamic Island style)
			commCard.Visible = true
			commCard.Position = UDim2.new(0.5, 0, 0, -120)
			local slideIn = TweenService:Create(commCard, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, 0, 0, 20),
			})
			slideIn:Play()

			-- Begin Typewriter Dialogue
			local intelMsg = data.DispatchMessage or "Spider-Man, active incident in progress! Move to intercept immediately."
			task.spawn(function()
				runTypewriterDialogue(intelMsg, 4.5)
			end)

			-- 🕒 Auto-Dismiss after 7.5 seconds (tucks cleanly back into bezel!)
			task.delay(7.5, function()
				if commCard and PoliceRadioHUD.isCrimeActive then
					local slideOut = TweenService:Create(commCard, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						Position = UDim2.new(0.5, 0, 0, -120),
					})
					slideOut:Play()
				end
			end)
		end
	end
end

-- 🚨 Display Victory Banner & Rewards Payout (Task 4)
function PoliceRadioHUD.onCrimeCleared(data: CrimeData)
	local CombatStyleHUD = require(script.Parent:WaitForChild("CombatStyleHUD"))
	CombatStyleHUD.hideAbilityTray(true)
	CombatStyleHUD.resetCombo()

	PoliceRadioHUD.isCrimeActive = false
	PoliceRadioHUD.activeCrimeData = nil
	PoliceRadioHUD.isRadioSpeaking = false
	activeTypewriterToken += 1

	cleanupWorldBeacon()

	if waypointMarker then
		waypointMarker.Visible = false
	end
	if pointerArrow then
		pointerArrow.Visible = false
	end

	-- Dismiss comm card immediately if open
	if commCard then
		TweenService:Create(commCard, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -120),
		}):Play()
	end

	if not isUIVisible then
		return
	end

	if not screenGui or not victoryBanner then
		createHUD()
	end

	if victoryBanner and victoryTitleLabel and victoryRewardsLabel and victorySubLabel then
		local xp = data.RewardXP or 150
		local cash = data.RewardCash or 250
		local pCount = data.ParticipantCount or 1

		victoryTitleLabel.Text = "🚨 SECTOR SECURED"
		victoryRewardsLabel.Text = string.format("+$%d HERO CASH   //   +%d XP", cash, xp)

		if pCount > 1 then
			victorySubLabel.Text = string.format("CO-OP SQUAD VICTORY • %d HEROES (+%d%% TEAM BONUS)", pCount, (pCount - 1) * 25)
		else
			victorySubLabel.Text = "STREET PATROL ACTIVE • MANHATTAN SAFE"
		end

		playDispatchSound("Victory")

		-- Tactile Slow-Motion Impact
		task.spawn(function()
			local char = LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				local origSpeed = hum.WalkSpeed
				hum.WalkSpeed = origSpeed * 0.4
				task.wait(0.45)
				if hum and hum.Parent then
					hum.WalkSpeed = origSpeed
				end
			end
		end)

		-- Detect active Level-Up fanfare to stack cleanly without overlap
		local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local isLevelUpActive = (playerGui and playerGui:FindFirstChild("LevelUpFanfareGui") ~= nil) or ((os.clock() - lastLevelUpTime) < 3.5)

		local targetY = if isLevelUpActive then 140 else 38
		local targetPos = UDim2.new(0.5, 0, 0, targetY)

		isVictoryBannerShowing = true
		victoryBanner.AnchorPoint = Vector2.new(0.5, 0)
		victoryBanner.Position = UDim2.new(0.5, 0, 0, -100)
		victoryBanner.Size = UDim2.new(0, 420, 0, 78)

		local popIn = TweenService:Create(victoryBanner, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = targetPos,
		})
		popIn:Play()

		-- Dismiss after 4.5s
		task.delay(4.5, function()
			if victoryBanner then
				isVictoryBannerShowing = false
				local popOut = TweenService:Create(victoryBanner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5, 0, 0, -100),
				})
				popOut:Play()
			end
		end)
	end
end

-- ❌ Crime Expired / Failed
function PoliceRadioHUD.onCrimeFailed(_data: CrimeData)
	PoliceRadioHUD.isCrimeActive = false
	PoliceRadioHUD.activeCrimeData = nil
	PoliceRadioHUD.isRadioSpeaking = false
	activeTypewriterToken += 1

	cleanupWorldBeacon()

	if waypointMarker then
		waypointMarker.Visible = false
	end
	if pointerArrow then
		pointerArrow.Visible = false
	end

	if commCard then
		TweenService:Create(commCard, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -120),
		}):Play()
	end
end

-- 📱 Interface Isolation: Hide dispatch HUD when Spider-Visor OS is open
function PoliceRadioHUD.setVisorOpen(isOpen: boolean)
	PoliceRadioHUD.isVisorOpen = isOpen
	if commCard then
		commCard.Visible = not isOpen
	end
	if waypointMarker then
		waypointMarker.Visible = not isOpen and PoliceRadioHUD.isCrimeActive and isUIVisible
	end
	if pointerArrow then
		pointerArrow.Visible = not isOpen and PoliceRadioHUD.isCrimeActive and isUIVisible
	end
end

-- 🎬 Cinematic / Recording UI Master Switch
function PoliceRadioHUD.setUIVisible(visible: boolean)
	isUIVisible = visible
	if screenGui then
		screenGui.Enabled = visible
	end
	if not visible then
		cleanupWorldBeacon()
		if commCard then commCard.Visible = false end
		if waypointMarker then waypointMarker.Visible = false end
		if pointerArrow then pointerArrow.Visible = false end
		if victoryBanner then victoryBanner.Visible = false end
	else
		if PoliceRadioHUD.isCrimeActive and PoliceRadioHUD.activeCrimeData and PoliceRadioHUD.activeCrimeData.Epicenter then
			createWorldBeacon(PoliceRadioHUD.activeCrimeData.Epicenter, PoliceRadioHUD.activeCrimeData.ThemeColor or Color3.fromRGB(255, 75, 75))
		end
	end
end

--------------------------------------------------------------------------------
-- 🧭 MATHEMATICAL 3D TO SCREEN CLAMPING WITH SMOOTH BOUNDS INTERSECTION (Task 3)
--------------------------------------------------------------------------------

local function calculateScreenPoint(targetWorldPos: Vector3, margin: number, topMargin: number?): (Vector2, boolean, number, Vector2)
	local curCam = Workspace.CurrentCamera or Camera
	local screenPos, onScreen = curCam:WorldToViewportPoint(targetWorldPos)
	local viewportSize = curCam.ViewportSize
	local center = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
	local actualTopMargin = topMargin or margin

	if onScreen and screenPos.Z > 0 then
		local clampedY = math.clamp(screenPos.Y, actualTopMargin, math.max(actualTopMargin + 20, viewportSize.Y - margin))
		return Vector2.new(screenPos.X, clampedY), true, 0, Vector2.zero
	end

	-- Behind camera or outside viewport bounds
	local toTarget = targetWorldPos - curCam.CFrame.Position
	local forward = curCam.CFrame.LookVector
	local isBehind = forward:Dot(toTarget) < 0 or screenPos.Z < 0

	local rawDir = Vector2.new(screenPos.X - center.X, screenPos.Y - center.Y)
	if isBehind then
		rawDir = -rawDir
	end

	local dir = rawDir.Magnitude > 0.001 and rawDir.Unit or Vector2.new(0, -1)

	local safeHalfW = math.max(20, (viewportSize.X / 2) - margin)
	local safeHalfH = math.max(20, (viewportSize.Y / 2) - actualTopMargin)

	local scaleX = math.abs(dir.X) > 0.0001 and (safeHalfW / math.abs(dir.X)) or 1e6
	local scaleY = math.abs(dir.Y) > 0.0001 and (safeHalfH / math.abs(dir.Y)) or 1e6
	local scale = math.min(scaleX, scaleY)

	local clampedPos = center + (dir * scale)
	local finalY = math.clamp(clampedPos.Y, actualTopMargin, math.max(actualTopMargin + 20, viewportSize.Y - margin))
	local angleDeg = math.deg(math.atan2(dir.Y, dir.X)) + 90

	return Vector2.new(clampedPos.X, finalY), false, angleDeg, dir
end

--------------------------------------------------------------------------------
-- 🧭 WAYPOINT LAYOUT MODES (applied only on change, never per-frame)
--------------------------------------------------------------------------------

local function applyWaypointLayout(mode: string)
	if not waypointMarker then return end
	local isFull = mode == "Full"
	local isMini = mode == "Mini"

	if waypointTitleLabel then
		waypointTitleLabel.Visible = isFull
	end
	waypointMarker.Size = if isFull then UDim2.fromOffset(150, 34) elseif isMini then UDim2.fromOffset(72, 24) else UDim2.fromOffset(124, 26)
	waypointMarker.BackgroundTransparency = if isFull then 0.18 elseif isMini then 0.35 else 0.22
	if waypointMarkerStroke then
		waypointMarkerStroke.Transparency = if isFull then 0.2 elseif isMini then 0.45 else 0.25
	end
	if waypointIconLabel then
		waypointIconLabel.Position = if isFull then UDim2.new(0, 6, 0.5, -9) else UDim2.new(0, if isMini then 4 else 6, 0.5, -8)
		waypointIconLabel.Size = if isFull then UDim2.fromOffset(18, 18) else UDim2.fromOffset(16, 16)
		waypointIconLabel.TextSize = if isFull then 13 elseif isMini then 11 else 12
	end
	if waypointDistLabel then
		if isFull then
			waypointDistLabel.Position = UDim2.fromOffset(28, 17)
			waypointDistLabel.Size = UDim2.new(1, -32, 0, 14)
			waypointDistLabel.TextSize = 9.5
		else
			local left = if isMini then 22 else 24
			waypointDistLabel.Position = UDim2.fromOffset(left, 0)
			waypointDistLabel.Size = UDim2.new(1, -(left + 4), 1, 0)
			waypointDistLabel.TextSize = 10
		end
	end
end

--------------------------------------------------------------------------------
-- 🔄 RENDERSTEPPED LOOP (3D Waypoint Tracking, Elevation & Equalizer Waveform)
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if not isUIVisible then
		if waypointMarker and waypointMarker.Visible then
			waypointMarker.Visible = false
		end
		if pointerArrow and pointerArrow.Visible then
			pointerArrow.Visible = false
		end
		if activeBeaconModel then
			cleanupWorldBeacon()
		end
		return
	end

	local now = os.clock()

	-- 1. Animated Radio Waveform Bars (Dynamic Equalizer)
	if #waveBars > 0 then
		if PoliceRadioHUD.isRadioSpeaking then
			for idx, bar in waveBars do
				local freq = math.abs(math.sin((now * 16) + (idx * 0.9))) * 11 + 3
				bar.Size = UDim2.new(0, 3, 0, freq)
			end
		else
			for _, bar in waveBars do
				bar.Size = UDim2.new(0, 3, 0, 3)
			end
		end
	end

	-- 2. 3D Holographic Waypoint Projection with Elevation Tracking & Smooth Edge Clamping (Task 3)
	if PoliceRadioHUD.isCrimeActive and PoliceRadioHUD.activeCrimeData and waypointMarker then
		local epicenter = PoliceRadioHUD.activeCrimeData.Epicenter
		if not epicenter then return end

		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local playerPos = root and root.Position or Vector3.zero

		local distStuds = (playerPos - epicenter).Magnitude

		-- Waypoint Proximity Combat Fade: When within 35 studs of the crime epicenter, hide 2D waypoint to avoid cluttering melee combat
		if distStuds <= 35 or PoliceRadioHUD.isVisorOpen then
			waypointMarker.Visible = false
			lastWaypointMode = nil
			if pointerArrow then
				pointerArrow.Visible = false
			end
		else
			local distMeters = math.floor(distStuds / 3)

			-- Elevation Tracking
			local deltaY = epicenter.Y - playerPos.Y
			local elevationSymbol = "◆"
			local elevationDesc = "Level"

			if deltaY > 18 then
				elevationSymbol = "▲"
				elevationDesc = "High-Rise"
			elseif deltaY < -18 then
				elevationSymbol = "▼"
				elevationDesc = "Street"
			end

			-- Detect if commCard is displayed (Task 3)
			local isCommCardVisible = (commCard ~= nil and commCard.Position.Y.Offset > 0)
			local mode = if isCommCardVisible then "Compact" elseif distMeters > 90 then "Mini" else "Full"
			if mode ~= lastWaypointMode then
				lastWaypointMode = mode
				applyWaypointLayout(mode)
			end

			if waypointDistLabel then
				local distText = if mode == "Mini"
					then string.format("%s %dm", elevationSymbol, distMeters)
					else string.format("%s %dm  ·  %s", elevationSymbol, distMeters, elevationDesc)
				if waypointDistLabel.Text ~= distText then
					waypointDistLabel.Text = distText
				end
				waypointDistLabel.TextColor3 = if deltaY > 18 then Color3.fromRGB(255, 195, 60)
					elseif deltaY < -18 then Color3.fromRGB(255, 95, 95)
					else Color3.fromRGB(85, 220, 255)
			end

			-- Target World Anchor (Head height over crime scene)
			local targetWorldPos = epicenter + Vector3.new(0, 6.5, 0)
			-- Top Margin Clamp: 135 when Yuri card is active, 90 otherwise (Task 3)
			local topMargin = if isCommCardVisible then 135 else 90
			local screenPos2D, onScreen, angleDeg, dirVector = calculateScreenPoint(targetWorldPos, 90, topMargin)

			-- Keep the pill clear of the top-right Health HUD and fully inside the viewport
			local viewport = (Workspace.CurrentCamera or Camera).ViewportSize
			local healthHudBottom = GuiService:GetGuiInset().Y + 112
			local pillX, pillY = screenPos2D.X, screenPos2D.Y
			if pillX > viewport.X - 330 and pillY < healthHudBottom then
				pillY = healthHudBottom
			end
			local halfW = waypointMarker.AbsoluteSize.X / 2 + 8
			pillX = math.clamp(pillX, halfW, math.max(halfW, viewport.X - halfW))
			screenPos2D = Vector2.new(pillX, pillY)

			-- Position the main pill
			waypointMarker.Position = UDim2.fromOffset(screenPos2D.X, screenPos2D.Y)
			waypointMarker.Visible = true

			if pointerArrow then
				if onScreen then
					-- When looking straight at the objective, hide the directional arrow
					pointerArrow.Visible = false
				else
					-- When off-screen, show the arrow floating cleanly outside the pill pointing to the target!
					pointerArrow.Visible = true
					pointerArrow.Position = UDim2.new(0, screenPos2D.X + (dirVector.X * 32), 0, screenPos2D.Y + (dirVector.Y * 24))
					pointerArrow.Rotation = angleDeg
				end
			end
		end
	end

	-- 3. World Beacon Distance Proximity Fade (Smoothly dissolves when arriving at crime fight)
	if activeBeaconModel and PoliceRadioHUD.activeCrimeData and PoliceRadioHUD.activeCrimeData.Epicenter then
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dist = (root.Position - PoliceRadioHUD.activeCrimeData.Epicenter).Magnitude
			local pillar = activeBeaconModel:FindFirstChild("Pillar") :: BasePart?
			local ring = activeBeaconModel:FindFirstChild("HoloRing") :: BasePart?
			if dist < 45 then
				if pillar and pillar.Transparency < 0.98 then
					pillar.Transparency = math.clamp(pillar.Transparency + 0.08, 0, 1)
				end
				if ring and ring.Transparency < 0.98 then
					ring.Transparency = math.clamp(ring.Transparency + 0.08, 0, 1)
				end
			else
				if pillar and pillar.Transparency > 0.55 then
					pillar.Transparency = math.clamp(pillar.Transparency - 0.08, 0.55, 1)
				end
				if ring and ring.Transparency > 0.60 then
					ring.Transparency = math.clamp(ring.Transparency - 0.08, 0.60, 1)
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- 🌐 INITIALIZE CRIME REMOTES LISTENER
--------------------------------------------------------------------------------

function PoliceRadioHUD.init()
	createHUD()

	local remotesFolder = ReplicatedStorage:WaitForChild("CrimeRemotes")
	local notificationRemote = remotesFolder:WaitForChild("CrimeNotification") :: RemoteEvent

	notificationRemote.OnClientEvent:Connect(function(eventType: string, data: any)
		if eventType == "LevelUp" then
			lastLevelUpTime = os.clock()
			-- If Victory Banner is already active on screen, slide it down smoothly so it doesn't overlap
			if victoryBanner and isVictoryBannerShowing then
				TweenService:Create(victoryBanner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0, 140),
				}):Play()
			end
		elseif eventType == "CrimeSpawned" then
			PoliceRadioHUD.onCrimeSpawned(data :: CrimeData)
		elseif eventType == "CrimeCleared" then
			PoliceRadioHUD.onCrimeCleared(data :: CrimeData)
		elseif eventType == "CrimeFailed" then
			PoliceRadioHUD.onCrimeFailed(data :: CrimeData)
		elseif eventType == "CoOpScaleActive" then
			-- Alert toast
			if commCard and intelSubheadLabel then
				intelSubheadLabel.Text = "🤝 CO-OP ACTIVE • +25% BONUS"
				intelSubheadLabel.TextColor3 = Color3.fromRGB(85, 235, 255)

				commCard.Position = UDim2.new(0.5, 0, 0, -80)
				TweenService:Create(commCard, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0, 20),
				}):Play()

				task.delay(4.0, function()
					if commCard then
						TweenService:Create(commCard, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							Position = UDim2.new(0.5, 0, 0, -80),
						}):Play()
					end
				end)
			end
		elseif eventType == "VanDisabled" then
			if commCard and intelSubheadLabel and intelDialogueLabel then
				intelSubheadLabel.Text = "⚡ GETAWAY VAN ENGINE DISABLED!"
				intelSubheadLabel.TextColor3 = Color3.fromRGB(255, 205, 50)
				intelDialogueLabel.MaxVisibleGraphemes = -1
				intelDialogueLabel.Text = "Great work! Suspects are bailing out of the vehicle. Neutralize all remaining hostiles to secure the stolen tech!"

				commCard.Position = UDim2.new(0.5, 0, 0, -80)
				TweenService:Create(commCard, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0, 20),
				}):Play()

				task.delay(4.0, function()
					if commCard then
						TweenService:Create(commCard, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							Position = UDim2.new(0.5, 0, 0, -80),
						}):Play()
					end
				end)
			end
		end
	end)
end

PoliceRadioHUD.init()

return PoliceRadioHUD
