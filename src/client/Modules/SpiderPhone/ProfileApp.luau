--!strict
--[[
	ProfileApp.luau
	Hero Profile & Level Progression view for SpiderPhoneHUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrimeConfig = require(Shared:WaitForChild("CrimeConfig"))
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

local ProfileApp = {}

export type ProfileContext = {
	cachedEquippedSuit: string,
	isRadioMuted: boolean,
	onRadioMuteToggled: (boolean) -> (),
}

function ProfileApp.render(parent: Frame, ctx: ProfileContext)
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

	local equippedSuitDef = SuitConfig.getSuitById(ctx.cachedEquippedSuit)
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
	muteBtn.BackgroundColor3 = ctx.isRadioMuted and Color3.fromRGB(185, 45, 55) or Color3.fromRGB(35, 145, 65)
	muteBtn.Font = Enum.Font.GothamBold
	muteBtn.Text = ctx.isRadioMuted and "MUTED" or "ACTIVE"
	muteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	muteBtn.TextSize = 10
	muteBtn.Parent = muteCard
	local btnCorn = Instance.new("UICorner")
	btnCorn.CornerRadius = UDim.new(0, 8)
	btnCorn.Parent = muteBtn

	muteBtn.MouseButton1Click:Connect(function()
		local newState = not ctx.isRadioMuted
		ctx.onRadioMuteToggled(newState)
		muteBtn.BackgroundColor3 = newState and Color3.fromRGB(185, 45, 55) or Color3.fromRGB(35, 145, 65)
		muteBtn.Text = newState and "MUTED" or "ACTIVE"
	end)
end

return ProfileApp
