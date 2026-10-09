--!strict
--[[
	RadioUIBuilder.luau
	Programmatic UI construction for Police Radio HUD:
	In-suit comm card, animated equalizer wavebars, 3D waypoint marker, and victory banner.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

export type RadioUIReferences = {
	ScreenGui: ScreenGui,
	CommCard: Frame,
	CommCardStroke: UIStroke,
	CallerBadge: TextLabel,
	CallerTitleLabel: TextLabel,
	CallStatePill: Frame,
	CallStateDot: Frame,
	CallStateLabel: TextLabel,
	IntelSubheadLabel: TextLabel,
	IntelDialogueLabel: TextLabel,
	WaveContainer: Frame,
	WaveBars: { Frame },
	WaypointMarker: Frame,
	WaypointMarkerStroke: UIStroke,
	WaypointIconLabel: TextLabel,
	WaypointTitleLabel: TextLabel,
	WaypointDistLabel: TextLabel,
	PointerArrow: ImageLabel,
	VictoryBanner: Frame,
	VictoryTitleLabel: TextLabel,
	VictoryRewardsLabel: TextLabel,
	VictorySubLabel: TextLabel,
}

local RadioUIBuilder = {}

function RadioUIBuilder.build(isUIVisible: boolean): RadioUIReferences
	if PlayerGui:FindFirstChild("PoliceRadioHUD") then
		local existing = PlayerGui:FindFirstChild("PoliceRadioHUD")
		if existing then existing:Destroy() end
	end

	local waveBars: { Frame } = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "PoliceRadioHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 15
	gui.IgnoreGuiInset = true
	gui.Enabled = isUIVisible

	-- 📱 1. IN-SUIT GLASSMORPHIC COMM CARD (Dynamic Island Top-Center)
	local card = Instance.new("Frame")
	card.Name = "CommCard"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, -120)
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

	local topGlow = Instance.new("Frame")
	topGlow.Name = "TopGlow"
	topGlow.Position = UDim2.new(0, 12, 0, 2)
	topGlow.Size = UDim2.new(1, -24, 0, 1)
	topGlow.BackgroundColor3 = Color3.fromRGB(200, 235, 255)
	topGlow.BackgroundTransparency = 0.55
	topGlow.BorderSizePixel = 0
	topGlow.Parent = card

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Position = UDim2.new(0, 12, 0, 6)
	header.Size = UDim2.new(1, -24, 0, 22)
	header.BackgroundTransparency = 1
	header.Parent = card

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

	local waves = Instance.new("Frame")
	waves.Name = "EqualizerContainer"
	waves.AnchorPoint = Vector2.new(1, 0.5)
	waves.Position = UDim2.new(1, -70, 0.5, 0)
	waves.Size = UDim2.new(0, 26, 0, 14)
	waves.BackgroundTransparency = 1
	waves.Parent = header

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

	-- 📍 2. 3D HOLOGRAPHIC WAYPOINT BEACON & DISTANCE BADGE
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

	local arrow = Instance.new("ImageLabel")
	arrow.Name = "PointerArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.new(0, 18, 0, 18)
	arrow.BackgroundTransparency = 1
	arrow.Image = "rbxassetid://6031094678"
	arrow.ImageColor3 = Color3.fromRGB(255, 75, 75)
	arrow.Visible = false
	arrow.Parent = gui

	-- 🚨 3. VICTORY CELEBRATION BANNER
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

	return {
		ScreenGui = gui,
		CommCard = card,
		CommCardStroke = cardStroke,
		CallerBadge = badge,
		CallerTitleLabel = callerTitle,
		CallStatePill = callPill,
		CallStateDot = dot,
		CallStateLabel = callLabel,
		IntelSubheadLabel = subhead,
		IntelDialogueLabel = dialogue,
		WaveContainer = waves,
		WaveBars = waveBars,
		WaypointMarker = marker,
		WaypointMarkerStroke = markerStroke,
		WaypointIconLabel = iconLabel,
		WaypointTitleLabel = titleLabel,
		WaypointDistLabel = distLabel,
		PointerArrow = arrow,
		VictoryBanner = vBanner,
		VictoryTitleLabel = vTitle,
		VictoryRewardsLabel = vRewards,
		VictorySubLabel = vSub,
	}
end

return RadioUIBuilder
