--!strict
--[[
	PlayerHealthHUD.luau
	Top-Right Cinematic Player Health & Nanotech Shield Telemetry HUD.
	Displays:
	- Authoritative Base Health (Emerald Green)
	- Nanotech Armor Shield Bar & Glowing Badge (Electric Cyan: Color3.fromRGB(50, 220, 255))
	- Real-time shield damage absorption telemetry (Shield depletes before green HP)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local LocalPlayer = Players.LocalPlayer

local isUIVisible = not (CombatConfig.CinematicMode == true)

local PlayerHealthHUD = {}

local screenGui: ScreenGui? = nil
local hudContainer: Frame? = nil
local hpBarFill: Frame? = nil
local shieldBarContainer: Frame? = nil
local shieldBarFill: Frame? = nil
local shieldBadge: Frame? = nil
local shieldBadgeText: TextLabel? = nil
local scarletBadge: Frame? = nil
local scarletBadgeText: TextLabel? = nil
local scarletBadgeStroke: UIStroke? = nil
local activeScarletConn: RBXScriptConnection? = nil
local symbioteBadge: Frame? = nil
local cyberBadge: Frame? = nil
local classicBadge: Frame? = nil
local classicBadgeText: TextLabel? = nil
local classicBadgeStroke: UIStroke? = nil
local hudContainerStroke: UIStroke? = nil
local hpBarStroke: UIStroke? = nil
local camoBarTrack: Frame? = nil
local camoBarFill: Frame? = nil
local camoBarFillGrad: UIGradient? = nil
local camoBarText: TextLabel? = nil
local camoTextStroke: UIStroke? = nil
local camoPulseTween: Tween? = nil
local hpTextLabel: TextLabel? = nil
local suitTitleLabel: TextLabel? = nil
local shieldGlowStroke: UIStroke? = nil

local currentShieldBonus: number = 0
local activeHealthConn: RBXScriptConnection? = nil
local activeMaxHealthConn: RBXScriptConnection? = nil
local activeAttrConn: RBXScriptConnection? = nil
local activeCamoEnergyConn: RBXScriptConnection? = nil
local activeCamoStateConn: RBXScriptConnection? = nil
local activePlayerSuitConn: RBXScriptConnection? = nil

-- Disable Roblox default health CoreGui cleanly
task.spawn(function()
	for _ = 1, 10 do
		local success = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if success then break end
		task.wait(0.2)
	end
end)

local function buildGUI(playerGui: PlayerGui)
	if playerGui:FindFirstChild("PlayerHealthHUD") then
		playerGui:FindFirstChild("PlayerHealthHUD"):Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayerHealthHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 15
	gui.Enabled = isUIVisible

	-- Top-Right Container Anchor
	local container = Instance.new("Frame")
	container.Name = "HealthHUDContainer"
	container.AnchorPoint = Vector2.new(1, 0)
	container.Position = UDim2.new(1, -24, 0, 24)
	container.Size = UDim2.new(0, 260, 0, 72)
	container.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
	container.BackgroundTransparency = 0.22
	container.BorderSizePixel = 0
	container.Parent = gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 10)
	containerCorner.Parent = container

	local containerStroke = Instance.new("UIStroke")
	containerStroke.Name = "ContainerStroke"
	containerStroke.Thickness = 1.5
	containerStroke.Color = Color3.fromRGB(45, 55, 75)
	containerStroke.Transparency = 0.35
	containerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	containerStroke.Parent = container
	hudContainerStroke = containerStroke

	-- Top Row: Suit / Hero Label
	local suitLabel = Instance.new("TextLabel")
	suitLabel.Name = "SuitTitleLabel"
	suitLabel.Position = UDim2.new(0, 14, 0, 6)
	suitLabel.Size = UDim2.new(0, 140, 0, 16)
	suitLabel.BackgroundTransparency = 1
	suitLabel.Font = Enum.Font.GothamBold
	suitLabel.Text = "SPIDER-MAN"
	suitLabel.TextColor3 = Color3.fromRGB(220, 230, 245)
	suitLabel.TextSize = 12
	suitLabel.TextXAlignment = Enum.TextXAlignment.Left
	suitLabel.Parent = container
	suitTitleLabel = suitLabel

	-- Top-Right HP Numeric Readout
	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPTextLabel"
	hpLabel.AnchorPoint = Vector2.new(1, 0)
	hpLabel.Position = UDim2.new(1, -14, 0, 6)
	hpLabel.Size = UDim2.new(0, 90, 0, 16)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.Text = "100 / 100"
	hpLabel.TextColor3 = Color3.fromRGB(180, 195, 215)
	hpLabel.TextSize = 12
	hpLabel.TextXAlignment = Enum.TextXAlignment.Right
	hpLabel.Parent = container
	hpTextLabel = hpLabel

	-- 1. Base Health Bar Background (Dark Track)
	local hpTrack = Instance.new("Frame")
	hpTrack.Name = "HPBarTrack"
	hpTrack.Position = UDim2.new(0, 14, 0, 26)
	hpTrack.Size = UDim2.new(1, -28, 0, 12)
	hpTrack.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
	hpTrack.BorderSizePixel = 0
	hpTrack.Parent = container

	local hpTrackCorner = Instance.new("UICorner")
	hpTrackCorner.CornerRadius = UDim.new(0, 4)
	hpTrackCorner.Parent = hpTrack

	local hpTrackStroke = Instance.new("UIStroke")
	hpTrackStroke.Name = "HPTrackStroke"
	hpTrackStroke.Thickness = 1.0
	hpTrackStroke.Color = Color3.fromRGB(45, 55, 75)
	hpTrackStroke.Transparency = 0.5
	hpTrackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hpTrackStroke.Parent = hpTrack
	hpBarStroke = hpTrackStroke

	-- Base Health Bar Fill (Emerald Green)
	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPBarFill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(46, 213, 115)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpTrack
	hpBarFill = hpFill

	local hpFillCorner = Instance.new("UICorner")
	hpFillCorner.CornerRadius = UDim.new(0, 4)
	hpFillCorner.Parent = hpFill

	local hpGrad = Instance.new("UIGradient")
	hpGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 230, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(36, 185, 95)),
	})
	hpGrad.Parent = hpFill

	-- 2. Nanotech Shield Segment Bar (Stacked directly underneath HP bar)
	local shieldTrack = Instance.new("Frame")
	shieldTrack.Name = "ShieldBarTrack"
	shieldTrack.Position = UDim2.new(0, 14, 0, 42)
	shieldTrack.Size = UDim2.new(1, -28, 0, 7)
	shieldTrack.BackgroundColor3 = Color3.fromRGB(15, 30, 45)
	shieldTrack.BorderSizePixel = 0
	shieldTrack.Visible = false
	shieldTrack.Parent = container
	shieldBarContainer = shieldTrack

	local shieldTrackCorner = Instance.new("UICorner")
	shieldTrackCorner.CornerRadius = UDim.new(0, 3)
	shieldTrackCorner.Parent = shieldTrack

	local sFill = Instance.new("Frame")
	sFill.Name = "ShieldBarFill"
	sFill.Size = UDim2.new(1, 0, 1, 0)
	sFill.BackgroundColor3 = Color3.fromRGB(50, 220, 255)
	sFill.BorderSizePixel = 0
	sFill.Parent = shieldTrack
	shieldBarFill = sFill

	local sFillCorner = Instance.new("UICorner")
	sFillCorner.CornerRadius = UDim.new(0, 3)
	sFillCorner.Parent = sFill

	local sGrad = Instance.new("UIGradient")
	sGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 175, 245)),
	})
	sGrad.Parent = sFill

	-- 3. Glowing Nanotech Pill Badge (e.g., "[🛡️ 25 NANOTECH SHIELD]")
	local badge = Instance.new("Frame")
	badge.Name = "NanotechShieldBadge"
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.new(0, 14, 0, 52)
	badge.Size = UDim2.new(1, -28, 0, 16)
	badge.BackgroundColor3 = Color3.fromRGB(10, 35, 55)
	badge.BackgroundTransparency = 0.25
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.Parent = container
	shieldBadge = badge

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 4)
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Name = "ShieldGlowStroke"
	badgeStroke.Thickness = 1.2
	badgeStroke.Color = Color3.fromRGB(50, 220, 255)
	badgeStroke.Transparency = 0.25
	badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeStroke.Parent = badge
	shieldGlowStroke = badgeStroke

	local bText = Instance.new("TextLabel")
	bText.Name = "ShieldText"
	bText.Size = UDim2.new(1, 0, 1, 0)
	bText.BackgroundTransparency = 1
	bText.Font = Enum.Font.GothamBold
	bText.Text = "🛡️ 25 NANOTECH SHIELD"
	bText.TextColor3 = Color3.fromRGB(75, 235, 255)
	bText.TextSize = 10
	bText.TextScaled = false
	bText.Parent = badge
	shieldBadgeText = bText

	-- 3.5 Scarlet Spider Status Badge
	local scBadge = Instance.new("Frame")
	scBadge.Name = "ScarletStatusBadge"
	scBadge.AnchorPoint = Vector2.new(0, 0)
	scBadge.Position = UDim2.new(0, 14, 0, 44)
	scBadge.Size = UDim2.new(1, -28, 0, 18)
	scBadge.BackgroundColor3 = Color3.fromRGB(30, 16, 20)
	scBadge.BackgroundTransparency = 0.15
	scBadge.BorderSizePixel = 0
	scBadge.Visible = false
	scBadge.Parent = container
	scarletBadge = scBadge

	local scCorner = Instance.new("UICorner")
	scCorner.CornerRadius = UDim.new(0, 4)
	scCorner.Parent = scBadge

	local scStroke = Instance.new("UIStroke")
	scStroke.Name = "ScarletStroke"
	scStroke.Thickness = 1.2
	scStroke.Color = Color3.fromRGB(240, 50, 60)
	scStroke.Transparency = 0.25
	scStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	scStroke.Parent = scBadge
	scarletBadgeStroke = scStroke

	local scText = Instance.new("TextLabel")
	scText.Name = "ScarletText"
	scText.Size = UDim2.new(1, 0, 1, 0)
	scText.BackgroundTransparency = 1
	scText.Font = Enum.Font.GothamBold
	scText.Text = "[ 🕸️ IMPACT BLAST READY [E]  |  🚀 225m SLINGSHOT ]"
	scText.TextColor3 = Color3.fromRGB(255, 120, 130)
	scText.TextSize = 9
	scText.TextScaled = false
	scText.Parent = scBadge
	scarletBadgeText = scText

	-- 4. Symbiote Alien Status Badge
	local sBadge = Instance.new("Frame")
	sBadge.Name = "SymbioteStatusBadge"
	sBadge.AnchorPoint = Vector2.new(0, 0)
	sBadge.Position = UDim2.new(0, 14, 0, 44)
	sBadge.Size = UDim2.new(1, -28, 0, 18)
	sBadge.BackgroundColor3 = Color3.fromRGB(25, 20, 32)
	sBadge.BackgroundTransparency = 0.15
	sBadge.BorderSizePixel = 0
	sBadge.Visible = false
	sBadge.Parent = container
	symbioteBadge = sBadge

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 4)
	sCorner.Parent = sBadge

	local sStroke = Instance.new("UIStroke")
	sStroke.Name = "SymbioteStroke"
	sStroke.Thickness = 1.2
	sStroke.Color = Color3.fromRGB(165, 120, 255)
	sStroke.Transparency = 0.25
	sStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sStroke.Parent = sBadge

	local sText = Instance.new("TextLabel")
	sText.Name = "SymbioteText"
	sText.Size = UDim2.new(1, 0, 1, 0)
	sText.BackgroundTransparency = 1
	sText.Font = Enum.Font.GothamBold
	sText.Text = "[ 🌑 SYMBIOTE: +20% BRUTE DAMAGE & PARASITIC SIPHON ]"
	sText.TextColor3 = Color3.fromRGB(210, 190, 255)
	sText.TextSize = 10
	sText.TextScaled = false
	sText.Parent = sBadge

	-- 6. 2099 Cyber Suit Status Badge
	local c2099Badge = Instance.new("Frame")
	c2099Badge.Name = "Cyber2099StatusBadge"
	c2099Badge.AnchorPoint = Vector2.new(0, 0)
	c2099Badge.Position = UDim2.new(0, 14, 0, 44)
	c2099Badge.Size = UDim2.new(1, -28, 0, 18)
	c2099Badge.BackgroundColor3 = Color3.fromRGB(15, 20, 32)
	c2099Badge.BackgroundTransparency = 0.15
	c2099Badge.BorderSizePixel = 0
	c2099Badge.Visible = false
	c2099Badge.Parent = container
	cyberBadge = c2099Badge

	local c2099Corner = Instance.new("UICorner")
	c2099Corner.CornerRadius = UDim.new(0, 4)
	c2099Corner.Parent = c2099Badge

	local c2099Stroke = Instance.new("UIStroke")
	c2099Stroke.Name = "Cyber2099Stroke"
	c2099Stroke.Thickness = 1.2
	c2099Stroke.Color = Color3.fromRGB(255, 45, 75)
	c2099Stroke.Transparency = 0.25
	c2099Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	c2099Stroke.Parent = c2099Badge

	local c2099Text = Instance.new("TextLabel")
	c2099Text.Name = "Cyber2099Text"
	c2099Text.Size = UDim2.new(1, 0, 1, 0)
	c2099Text.BackgroundTransparency = 1
	c2099Text.Font = Enum.Font.GothamBold
	c2099Text.Text = "[ 🤖 2099: TALON SLASHES, LASER WEBS & GRAVITY VORTEX ]"
	c2099Text.TextColor3 = Color3.fromRGB(255, 80, 110)
	c2099Text.TextSize = 8.5
	c2099Text.TextScaled = false
	c2099Text.Parent = c2099Badge

	-- 7. Classic Peter Parker Status Badge
	local clBadge = Instance.new("Frame")
	clBadge.Name = "ClassicStatusBadge"
	clBadge.AnchorPoint = Vector2.new(0, 0)
	clBadge.Position = UDim2.new(0, 14, 0, 44)
	clBadge.Size = UDim2.new(1, -28, 0, 18)
	clBadge.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	clBadge.BackgroundTransparency = 0.15
	clBadge.BorderSizePixel = 0
	clBadge.Visible = false
	clBadge.Parent = container
	classicBadge = clBadge

	local clCorner = Instance.new("UICorner")
	clCorner.CornerRadius = UDim.new(0, 4)
	clCorner.Parent = clBadge

	local clStroke = Instance.new("UIStroke")
	clStroke.Name = "ClassicStroke"
	clStroke.Thickness = 1.2
	clStroke.Color = Color3.fromRGB(225, 45, 55)
	clStroke.Transparency = 0.25
	clStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	clStroke.Parent = clBadge
	classicBadgeStroke = clStroke

	local clText = Instance.new("TextLabel")
	clText.Name = "ClassicText"
	clText.Size = UDim2.new(1, 0, 1, 0)
	clText.BackgroundTransparency = 1
	clText.Font = Enum.Font.GothamBold
	clText.Text = "[ 🕷️ PETER: DOUBLE WEB-SLAM & RAPID SILK (0.16s) ]"
	clText.TextColor3 = Color3.fromRGB(240, 245, 255)
	clText.TextSize = 8.5
	clText.TextScaled = false
	clText.Parent = clBadge
	classicBadgeText = clText

	-- 5. Miles Morales Camouflage Energy Meter
	local cTrack = Instance.new("Frame")
	cTrack.Name = "CamoBarTrack"
	cTrack.AnchorPoint = Vector2.new(0, 0)
	cTrack.Position = UDim2.new(0, 14, 0, 44)
	cTrack.Size = UDim2.new(1, -28, 0, 18)
	cTrack.BackgroundColor3 = Color3.fromRGB(28, 24, 10)
	cTrack.BorderSizePixel = 0
	cTrack.ClipsDescendants = true
	cTrack.Visible = false
	cTrack.Parent = container
	camoBarTrack = cTrack

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 4)
	cCorner.Parent = cTrack

	local cStroke = Instance.new("UIStroke")
	cStroke.Name = "CamoTrackStroke"
	cStroke.Thickness = 1.2
	cStroke.Color = Color3.fromRGB(75, 60, 20)
	cStroke.Transparency = 0.35
	cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cStroke.Parent = cTrack

	local cFill = Instance.new("Frame")
	cFill.Name = "CamoBarFill"
	cFill.Size = UDim2.new(1, 0, 1, 0)
	cFill.BackgroundColor3 = Color3.fromRGB(255, 235, 70)
	cFill.BorderSizePixel = 0
	cFill.Parent = cTrack
	camoBarFill = cFill

	local cFillCorner = Instance.new("UICorner")
	cFillCorner.CornerRadius = UDim.new(0, 4)
	cFillCorner.Parent = cFill

	local cGrad = Instance.new("UIGradient")
	cGrad.Name = "CamoFillGradient"
	cGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 25)),
	})
	cGrad.Parent = cFill
	camoBarFillGrad = cGrad

	local cText = Instance.new("TextLabel")
	cText.Name = "CamoBarText"
	cText.Size = UDim2.new(1, 0, 1, 0)
	cText.Position = UDim2.new(0, 0, 0, 0)
	cText.ZIndex = 3
	cText.BackgroundTransparency = 1
	cText.Font = Enum.Font.GothamBold
	cText.Text = "⚡ CAMOUFLAGE READY [PRESS F]"
	cText.TextColor3 = Color3.fromRGB(255, 235, 70)
	cText.TextSize = 10
	cText.TextScaled = false
	cText.Parent = cTrack
	camoBarText = cText

	local ctStroke = Instance.new("UIStroke")
	ctStroke.Name = "CamoTextStroke"
	ctStroke.Thickness = 1.0
	ctStroke.Color = Color3.fromRGB(255, 215, 50)
	ctStroke.Transparency = 0.2
	ctStroke.Parent = cText
	camoTextStroke = ctStroke

	hudContainer = container
	gui.Parent = playerGui
	screenGui = gui
end

local function updateHUDDisplay(humanoid: Humanoid, character: Model)
	if not hudContainer or not hpBarFill or not hpTextLabel then return end

	local shieldBonus = character:GetAttribute("StarkShieldBonus") or 0
	if typeof(shieldBonus) ~= "number" then shieldBonus = 0 end
	currentShieldBonus = shieldBonus

	local totalMax = humanoid.MaxHealth
	local baseMax = math.max(1, totalMax - shieldBonus)
	local curHealth = humanoid.Health

	-- Shield absorption calculation: Shield absorbs damage first from (baseMax + shieldBonus) down to baseMax
	local curShield = 0
	local curBaseHp = curHealth

	if shieldBonus > 0 then
		curShield = math.clamp(curHealth - baseMax, 0, shieldBonus)
		curBaseHp = math.clamp(curHealth, 0, baseMax)
	end

	-- Base HP ratio
	local hpRatio = math.clamp(curBaseHp / baseMax, 0, 1)
	TweenService:Create(hpBarFill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(hpRatio, 0, 1, 0),
	}):Play()

	-- Dynamic Color Shifts for Base HP (Low Health Warning)
	if hpRatio <= 0.25 then
		hpBarFill.BackgroundColor3 = Color3.fromRGB(235, 55, 60)
	elseif hpRatio <= 0.50 then
		hpBarFill.BackgroundColor3 = Color3.fromRGB(255, 175, 45)
	else
		hpBarFill.BackgroundColor3 = Color3.fromRGB(46, 213, 115)
	end

	local suitId = character:GetAttribute("EquippedSuit") or LocalPlayer:GetAttribute("EquippedSuit") or "ClassicSuit"
	local isMiles = (suitId == "MilesSpiderVerse")
	local isSymbiote = (suitId == "SymbioteBlack")
	local isScarlet = (suitId == "ScarletSpider")
	local is2099 = (suitId == "Cyber2099")
	local isClassic = (suitId == "ClassicSuit")

	-- Update Camouflage Meter
	PlayerHealthHUD.updateCamoHUD()

	-- Update Scarlet Spider Meter
	PlayerHealthHUD.updateScarletHUD()

	-- Symbiote Status Badge
	if symbioteBadge then
		symbioteBadge.Visible = isSymbiote
	end

	-- 2099 Cyber Suit Status Badge
	if cyberBadge then
		cyberBadge.Visible = is2099
	end

	-- Classic Peter Parker Status Badge
	if classicBadge then
		classicBadge.Visible = isClassic
	end

	-- Nanotech Shield Telemetry (Hidden if Symbiote, Miles, Scarlet, 2099, or Classic)
	local isShieldActive = (shieldBonus > 0) and not isSymbiote and not isMiles and not isScarlet and not is2099 and not isClassic
	if shieldBarContainer and shieldBarFill and shieldBadge and shieldBadgeText then
		shieldBarContainer.Visible = isShieldActive
		shieldBadge.Visible = isShieldActive

		if isShieldActive then
			hudContainer.Size = UDim2.new(0, 260, 0, 76)
			local shieldRatio = math.clamp(curShield / shieldBonus, 0, 1)

			TweenService:Create(shieldBarFill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(shieldRatio, 0, 1, 0),
			}):Play()

			local roundedShield = math.ceil(curShield)
			shieldBadgeText.Text = string.format("🛡️ %d NANOTECH SHIELD", roundedShield)

			-- If shield is depleted, indicate breached status
			if roundedShield <= 0 then
				shieldBadgeText.Text = "🛡️ SHIELD DEPLETED"
				shieldBadgeText.TextColor3 = Color3.fromRGB(150, 160, 175)
				if shieldGlowStroke then
					shieldGlowStroke.Color = Color3.fromRGB(90, 100, 115)
				end
			else
				shieldBadgeText.TextColor3 = Color3.fromRGB(75, 235, 255)
				if shieldGlowStroke then
					shieldGlowStroke.Color = Color3.fromRGB(50, 220, 255)
				end
			end
		else
			if isMiles or isSymbiote or isScarlet or is2099 or isClassic then
				hudContainer.Size = UDim2.new(0, 260, 0, 72)
			else
				hudContainer.Size = UDim2.new(0, 260, 0, 48)
			end
		end
	end

	-- Numerical readout
	if isShieldActive and curShield > 0 then
		hpTextLabel.Text = string.format("%d (+%d) / %d", math.ceil(curBaseHp), math.ceil(curShield), math.ceil(baseMax))
	else
		hpTextLabel.Text = string.format("%d / %d", math.ceil(curBaseHp), math.ceil(baseMax))
	end
end

-- Trigger a momentary electric cyan pulse on the shield when hit
function PlayerHealthHUD.updateCamoHUD()
	if not hudContainer or not camoBarTrack or not camoBarFill or not camoBarText or not camoBarFillGrad or not camoTextStroke then return end

	local suitId = LocalPlayer:GetAttribute("EquippedSuit")
	if not suitId and LocalPlayer.Character then
		suitId = LocalPlayer.Character:GetAttribute("EquippedSuit")
	end
	local isMiles = (suitId == "MilesSpiderVerse")

	camoBarTrack.Visible = isMiles
	if not isMiles then
		if camoPulseTween then
			camoPulseTween:Cancel()
			camoPulseTween = nil
		end
		return
	end

	hudContainer.Size = UDim2.new(0, 260, 0, 72)

	local camoState = LocalPlayer:GetAttribute("MilesCamoState") or "Ready"
	local camoEnergy = LocalPlayer:GetAttribute("MilesCamoEnergy")
	if typeof(camoEnergy) ~= "number" then
		camoEnergy = (if camoState == "Ready" then 1.0 else 0.0)
	end
	camoEnergy = math.clamp(camoEnergy, 0, 1)

	if camoState == "Ready" then
		-- State: Ready (100%)
		camoBarFill.Size = UDim2.new(1, 0, 1, 0)
		camoBarFillGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 70)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 25)),
		})
		camoBarText.Text = "⚡ CAMOUFLAGE READY [PRESS F]"
		camoBarText.TextColor3 = Color3.fromRGB(255, 235, 70)
		camoTextStroke.Color = Color3.fromRGB(255, 215, 50)

		-- Pulsing yellow outline
		if not camoPulseTween then
			camoTextStroke.Transparency = 0.1
			camoTextStroke.Thickness = 1.0
			camoPulseTween = TweenService:Create(camoTextStroke, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				Transparency = 0.75,
				Thickness = 1.8,
			})
			camoPulseTween:Play()
		end

	elseif camoState == "Active" then
		-- State: Active (Draining over 5.0s)
		if camoPulseTween then
			camoPulseTween:Cancel()
			camoPulseTween = nil
		end
		camoTextStroke.Transparency = 0.3
		camoTextStroke.Thickness = 1.0
		camoTextStroke.Color = Color3.fromRGB(15, 30, 45)

		camoBarFill.Size = UDim2.new(camoEnergy, 0, 1, 0)
		camoBarFillGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 240, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 180, 245)),
		})
		camoBarText.Text = "👤 INVISIBLE: ATTACK TO DETONATE VENOM NOVA!"
		camoBarText.TextColor3 = Color3.fromRGB(100, 245, 255)

	elseif camoState == "Recharging" then
		-- State: Recharging (Refilling over 8.0s)
		if camoPulseTween then
			camoPulseTween:Cancel()
			camoPulseTween = nil
		end
		camoTextStroke.Transparency = 0.4
		camoTextStroke.Thickness = 1.0
		camoTextStroke.Color = Color3.fromRGB(20, 18, 10)

		camoBarFill.Size = UDim2.new(camoEnergy, 0, 1, 0)
		camoBarFillGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 185, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 135, 30)),
		})
		camoBarText.Text = "⚡ RECHARGING..."
		camoBarText.TextColor3 = Color3.fromRGB(215, 195, 110)
	end
end

function PlayerHealthHUD.updateScarletHUD()
	if not scarletBadge or not scarletBadgeText or not scarletBadgeStroke then return end
	local suitId = LocalPlayer:GetAttribute("EquippedSuit")
	if not suitId and LocalPlayer.Character then
		suitId = LocalPlayer.Character:GetAttribute("EquippedSuit")
	end
	local isScarlet = (suitId == "ScarletSpider")

	scarletBadge.Visible = isScarlet
	if not isScarlet then return end

	local isReady = LocalPlayer:GetAttribute("ScarletImpactReady") ~= false
	if isReady then
		scarletBadgeText.Text = "[ 🕸️ IMPACT BLAST READY [E]  |  🚀 225m SLINGSHOT ]"
		scarletBadgeText.TextColor3 = Color3.fromRGB(255, 120, 130)
		scarletBadgeStroke.Color = Color3.fromRGB(240, 50, 60)
		scarletBadgeStroke.Transparency = 0.2
	else
		scarletBadgeText.Text = "[ 🕸️ IMPACT BLAST RECHARGING... ]"
		scarletBadgeText.TextColor3 = Color3.fromRGB(160, 165, 175)
		scarletBadgeStroke.Color = Color3.fromRGB(75, 45, 55)
		scarletBadgeStroke.Transparency = 0.5
	end
end

function PlayerHealthHUD.pulseSymbioteHeal()
	if hpBarStroke then
		hpBarStroke.Color = Color3.fromRGB(165, 120, 255)
		hpBarStroke.Thickness = 2.2
		hpBarStroke.Transparency = 0.05
		TweenService:Create(hpBarStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Color = Color3.fromRGB(45, 55, 75),
			Thickness = 1.0,
			Transparency = 0.5,
		}):Play()
	end
	if hudContainerStroke then
		hudContainerStroke.Color = Color3.fromRGB(165, 120, 255)
		hudContainerStroke.Thickness = 2.2
		hudContainerStroke.Transparency = 0.1
		TweenService:Create(hudContainerStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Color = Color3.fromRGB(45, 55, 75),
			Thickness = 1.5,
			Transparency = 0.35,
		}):Play()
	end
end

function PlayerHealthHUD.pulseShieldDamage()
	if not shieldGlowStroke or not shieldBarFill or currentShieldBonus <= 0 then return end

	local pulseTween = TweenService:Create(shieldGlowStroke, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Thickness = 2.8,
		Transparency = 0,
	})
	pulseTween:Play()
	pulseTween.Completed:Connect(function()
		TweenService:Create(shieldGlowStroke, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Thickness = 1.2,
			Transparency = 0.25,
		}):Play()
	end)
end

function PlayerHealthHUD.setupCharacter(character: Model)
	if activeHealthConn then activeHealthConn:Disconnect() end
	if activeMaxHealthConn then activeMaxHealthConn:Disconnect() end
	if activeAttrConn then activeAttrConn:Disconnect() end
	if activeCamoEnergyConn then activeCamoEnergyConn:Disconnect() activeCamoEnergyConn = nil end
	if activeCamoStateConn then activeCamoStateConn:Disconnect() activeCamoStateConn = nil end
	if activePlayerSuitConn then activePlayerSuitConn:Disconnect() activePlayerSuitConn = nil end
	if activeScarletConn then activeScarletConn:Disconnect() activeScarletConn = nil end

	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then return end

	local suitId = character:GetAttribute("EquippedSuit") or LocalPlayer:GetAttribute("EquippedSuit") or "ClassicSuit"
	if suitTitleLabel then
		if suitId == "StarkTechSuit" then
			suitTitleLabel.Text = "STARK TECH ADVANCED"
			suitTitleLabel.TextColor3 = Color3.fromRGB(75, 235, 255)
		elseif suitId == "MilesSpiderVerse" then
			suitTitleLabel.Text = "MILES MORALES (SPIDER-VERSE)"
			suitTitleLabel.TextColor3 = Color3.fromRGB(255, 230, 60)
		elseif suitId == "SymbioteBlack" then
			suitTitleLabel.Text = "SYMBIOTE ALIEN SUIT"
			suitTitleLabel.TextColor3 = Color3.fromRGB(180, 150, 255)
		elseif suitId == "ScarletSpider" then
			suitTitleLabel.Text = "SCARLET SPIDER (BEN REILLY)"
			suitTitleLabel.TextColor3 = Color3.fromRGB(240, 50, 60)
		elseif suitId == "Cyber2099" then
			suitTitleLabel.Text = "SPIDER-MAN 2099 (MIGUEL O'HARA)"
			suitTitleLabel.TextColor3 = Color3.fromRGB(255, 50, 85)
		elseif suitId == "ClassicSuit" then
			suitTitleLabel.Text = "CLASSIC PETER PARKER"
			suitTitleLabel.TextColor3 = Color3.fromRGB(225, 45, 55)
		else
			suitTitleLabel.Text = "CLASSIC PETER PARKER"
			suitTitleLabel.TextColor3 = Color3.fromRGB(225, 45, 55)
		end
	end

	updateHUDDisplay(humanoid, character)

	local lastHealth = humanoid.Health
	activeHealthConn = humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < lastHealth and currentShieldBonus > 0 and (lastHealth > (humanoid.MaxHealth - currentShieldBonus)) then
			PlayerHealthHUD.pulseShieldDamage()
		elseif newHealth > lastHealth then
			local currentSuit = character:GetAttribute("EquippedSuit") or LocalPlayer:GetAttribute("EquippedSuit")
			if currentSuit == "SymbioteBlack" then
				PlayerHealthHUD.pulseSymbioteHeal()
			end
		end
		lastHealth = newHealth
		updateHUDDisplay(humanoid, character)
	end)

	activeMaxHealthConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateHUDDisplay(humanoid, character)
	end)

	activeAttrConn = character:GetAttributeChangedSignal("StarkShieldBonus"):Connect(function()
		updateHUDDisplay(humanoid, character)
	end)

	character:GetAttributeChangedSignal("MilesCamouflaged"):Connect(function()
		updateHUDDisplay(humanoid, character)
	end)

	LocalPlayer:GetAttributeChangedSignal("MilesCamouflaged"):Connect(function()
		updateHUDDisplay(humanoid, character)
	end)

	activeCamoEnergyConn = LocalPlayer:GetAttributeChangedSignal("MilesCamoEnergy"):Connect(function()
		PlayerHealthHUD.updateCamoHUD()
	end)

	activeCamoStateConn = LocalPlayer:GetAttributeChangedSignal("MilesCamoState"):Connect(function()
		PlayerHealthHUD.updateCamoHUD()
	end)

	activePlayerSuitConn = LocalPlayer:GetAttributeChangedSignal("EquippedSuit"):Connect(function()
		updateHUDDisplay(humanoid, character)
		PlayerHealthHUD.updateCamoHUD()
		PlayerHealthHUD.updateScarletHUD()
	end)

	activeScarletConn = LocalPlayer:GetAttributeChangedSignal("ScarletImpactReady"):Connect(function()
		PlayerHealthHUD.updateScarletHUD()
	end)

	character:GetAttributeChangedSignal("EquippedSuit"):Connect(function()
		local newSuit = character:GetAttribute("EquippedSuit")
		if suitTitleLabel then
			if newSuit == "StarkTechSuit" then
				suitTitleLabel.Text = "STARK TECH ADVANCED"
				suitTitleLabel.TextColor3 = Color3.fromRGB(75, 235, 255)
			elseif newSuit == "MilesSpiderVerse" then
				suitTitleLabel.Text = "MILES MORALES (SPIDER-VERSE)"
				suitTitleLabel.TextColor3 = Color3.fromRGB(255, 230, 60)
			elseif newSuit == "SymbioteBlack" then
				suitTitleLabel.Text = "SYMBIOTE ALIEN SUIT"
				suitTitleLabel.TextColor3 = Color3.fromRGB(180, 150, 255)
			elseif newSuit == "ScarletSpider" then
				suitTitleLabel.Text = "SCARLET SPIDER (BEN REILLY)"
				suitTitleLabel.TextColor3 = Color3.fromRGB(240, 50, 60)
			elseif newSuit == "Cyber2099" then
				suitTitleLabel.Text = "SPIDER-MAN 2099 (MIGUEL O'HARA)"
				suitTitleLabel.TextColor3 = Color3.fromRGB(255, 50, 85)
			elseif newSuit == "ClassicSuit" then
				suitTitleLabel.Text = "CLASSIC PETER PARKER"
				suitTitleLabel.TextColor3 = Color3.fromRGB(225, 45, 55)
			else
				suitTitleLabel.Text = "CLASSIC PETER PARKER"
				suitTitleLabel.TextColor3 = Color3.fromRGB(225, 45, 55)
			end
		end
		updateHUDDisplay(humanoid, character)
	end)
end

function PlayerHealthHUD.init(playerGui: PlayerGui, player: Player)
	buildGUI(playerGui)

	if player.Character then
		PlayerHealthHUD.setupCharacter(player.Character)
	end

	player.CharacterAdded:Connect(function(newChar)
		task.wait(0.1)
		PlayerHealthHUD.setupCharacter(newChar)
	end)
end

-- 🎬 Cinematic / Recording UI Master Switch
function PlayerHealthHUD.setUIVisible(visible: boolean)
	isUIVisible = visible
	if screenGui then
		screenGui.Enabled = visible
	end
end

return PlayerHealthHUD
