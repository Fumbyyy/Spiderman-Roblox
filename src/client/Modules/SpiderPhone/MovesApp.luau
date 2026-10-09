--!strict
--[[
	MovesApp.luau
	Hero Moves & Combat Arsenal Codex view for SpiderPhoneHUD.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local MovesApp = {}

function MovesApp.render(parent: Frame)
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

return MovesApp
