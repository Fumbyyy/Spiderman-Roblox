--!strict
--[[
	FNSMApp.luau
	Friendly Neighborhood Spider-Man (FNSM) Crime Scanner App view for SpiderPhoneHUD.
]]

local FNSMApp = {}

export type FNSMContext = {
	GetActiveCrimesRF: RemoteFunction,
	CrimeInteractRemote: RemoteEvent,
	playPhoneSound: (string) -> (),
	togglePhone: (boolean?) -> (),
	renderActiveApp: () -> (),
}

function FNSMApp.render(parent: Frame, ctx: FNSMContext)
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
		return ctx.GetActiveCrimesRF:InvokeServer()
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
			ctx.togglePhone(false)
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
			ctx.playPhoneSound("RadioChirp")
			reCallBtn.Text = "📞 CALLING..."
			ctx.CrimeInteractRemote:FireServer("RequestDispatch")
			task.delay(1.2, function()
				reCallBtn.Text = "🚨 CALL YURI"
				ctx.renderActiveApp()
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
			ctx.playPhoneSound("RadioChirp")
			reqBtn.Text = "📡 CONTACTING CAPTAIN WATANABE..."
			reqBtn.BackgroundColor3 = Color3.fromRGB(120, 130, 145)
			ctx.CrimeInteractRemote:FireServer("RequestDispatch")
			task.delay(1.2, function()
				ctx.renderActiveApp()
			end)
		end)
	end
end

return FNSMApp
