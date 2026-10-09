--!strict
--[[
	SuitsApp.luau
	Suit Wardrobe & Hero Cash Economy view for SpiderPhoneHUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

local SuitsApp = {}

export type SuitsContext = {
	GetSuitDataRF: RemoteFunction,
	SuitPurchaseRF: RemoteFunction,
	SuitEquipRF: RemoteFunction,
	cachedUnlockedSuits: { [string]: boolean },
	cachedEquippedSuit: string,
	updateSuitShowcase: () -> (),
	renderActiveApp: () -> (),
}

function SuitsApp.render(parent: Frame, ctx: SuitsContext)
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
		local unlocked, equipped = ctx.GetSuitDataRF:InvokeServer()
		if unlocked then ctx.cachedUnlockedSuits = unlocked end
		if equipped then ctx.cachedEquippedSuit = equipped end
	end)

	for suitIndex, suit in SuitConfig.Suits do
		local isUnlocked = ctx.cachedUnlockedSuits[suit.Id] == true
		local isEquipped = ctx.cachedEquippedSuit == suit.Id
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
				local ok, _msg = ctx.SuitEquipRF:InvokeServer(suit.Id)
				if ok then
					ctx.cachedEquippedSuit = suit.Id
					ctx.renderActiveApp()
					ctx.updateSuitShowcase()
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
					local ok, _msg = ctx.SuitPurchaseRF:InvokeServer(suit.Id)
					if ok then
						ctx.cachedUnlockedSuits[suit.Id] = true
						ctx.cachedEquippedSuit = suit.Id
						ctx.SuitEquipRF:InvokeServer(suit.Id)
						ctx.renderActiveApp()
						ctx.updateSuitShowcase()
					end
				end)
			end
		end
	end
end

return SuitsApp
