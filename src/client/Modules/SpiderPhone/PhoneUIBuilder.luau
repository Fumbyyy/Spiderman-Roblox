--!strict
--[[
	PhoneUIBuilder.luau
	Constructs the fullscreen Stark AR Visor HUD, Spider-Phone Datapad chassis,
	navigation tabs, and mobile floating open button.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local SuitShowcaseView = require(script.Parent.SuitShowcaseView)

export type UIReferences = {
	ScreenGui: ScreenGui,
	VisorContainer: Frame,
	PhoneFrame: Frame,
	ContentArea: Frame,
	CashDisplayLabel: TextLabel,
	StatusClockLabel: TextLabel,
	FloatingOpenButton: TextButton,
	SuitShowcase: SuitShowcaseView.ShowcaseElements,
	NavButtons: { [string]: TextButton },
}

local PhoneUIBuilder = {}

function PhoneUIBuilder.build(callbacks: {
	onToggle: (state: boolean?) -> (),
	onTabSelected: (tabId: "FNSM" | "Moves" | "Suits" | "Profile") -> (),
	activeTab: string,
}): UIReferences
	if PlayerGui:FindFirstChild("SpiderPhoneGui") then
		local existing = PlayerGui:FindFirstChild("SpiderPhoneGui")
		if existing then existing:Destroy() end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpiderPhoneGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 15
	gui.Parent = PlayerGui

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
		callbacks.onToggle(false)
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

	local navButtons: { [string]: TextButton } = {}

	for _, tabData in tabs do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. tabData.Id
		tabBtn.Size = UDim2.new(0.24, -2, 0, 28)
		tabBtn.BackgroundColor3 = Color3.fromRGB(20, 26, 40)
		tabBtn.BackgroundTransparency = (tabData.Id == callbacks.activeTab) and 0.1 or 0.8
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.Text = tabData.Name
		tabBtn.TextColor3 = (tabData.Id == callbacks.activeTab) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 170, 195)
		tabBtn.TextSize = 10
		tabBtn.Parent = navBar

		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = UDim.new(0, 6)
		tCorner.Parent = tabBtn

		tabBtn.MouseButton1Click:Connect(function()
			callbacks.onTabSelected(tabData.Id :: any)
		end)

		navButtons[tabData.Id] = tabBtn
	end

	-- Dynamic Content Area (App Views inside Phone)
	local content = Instance.new("Frame")
	content.Name = "ContentArea"
	content.Position = UDim2.new(0, 12, 0, 78)
	content.Size = UDim2.new(1, -24, 1, -86)
	content.BackgroundTransparency = 1
	content.Parent = phone

	-- 🧬 PANEL 2 (RIGHT): 3D Hero Showcase Column
	local suitShowcase = SuitShowcaseView.create(mainBody)

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

	local fCorner = Instance.new("UICorner")
	fCorner.CornerRadius = UDim.new(0, 10)
	fCorner.Parent = floatBtn

	local fStroke = Instance.new("UIStroke")
	fStroke.Thickness = 1.4
	fStroke.Color = Color3.fromRGB(45, 115, 255)
	fStroke.Transparency = 0.4
	fStroke.Parent = floatBtn

	floatBtn.MouseButton1Click:Connect(function()
		callbacks.onToggle()
	end)

	return {
		ScreenGui = gui,
		VisorContainer = visor,
		PhoneFrame = phone,
		ContentArea = content,
		CashDisplayLabel = cashLabel,
		StatusClockLabel = clockLabel,
		FloatingOpenButton = floatBtn,
		SuitShowcase = suitShowcase,
		NavButtons = navButtons,
	}
end

return PhoneUIBuilder
