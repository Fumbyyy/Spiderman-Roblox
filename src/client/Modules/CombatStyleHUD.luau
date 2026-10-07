--!strict
--[[
	CombatStyleHUD.luau
	Phase 4.3 & 5: High-energy Arcade Style Meter & Combo Multiplier HUD.
	- Displays bouncy combo counts, rank progression (D -> C -> B -> A -> S -> SPIDER-TIER)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local CombatStyleHUD = {
	currentCombo = 0,
	lastHitTime = 0,
	isActive = false,
	currentRankIndex = 1,
}

local isUIVisible = not (CombatConfig.CinematicMode == true)

-- GUI Elements
local screenGui: ScreenGui? = nil
local mainContainer: Frame? = nil
local comboLabel: TextLabel? = nil
local hitsSubLabel: TextLabel? = nil
local rankBadge: Frame? = nil
local rankLetter: TextLabel? = nil
local rankTitle: TextLabel? = nil
local decayBarFill: Frame? = nil
local decayBarBackground: Frame? = nil
local activeSlideTween: Tween? = nil
local abilityTrayFrame: Frame? = nil
local abilityTrayTween: Tween? = nil

-- 🎨 Build GUI Elements Programmatically
local function createHUD()
	if PlayerGui:FindFirstChild("CombatStyleHUD") then
		PlayerGui:FindFirstChild("CombatStyleHUD"):Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatStyleHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Enabled = isUIVisible

	-- Style Container (Right-Center Screen Anchor with safe edge margin)
	local container = Instance.new("Frame")
	container.Name = "StyleContainer"
	container.AnchorPoint = Vector2.new(1, 0.5)
	container.Position = UDim2.new(1, -36, 0.44, 0)
	container.Size = UDim2.new(0, 230, 0, 110)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = gui

	-- Rank Badge Container
	local badge = Instance.new("Frame")
	badge.Name = "RankBadge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 0, 0.42, 0)
	badge.Size = UDim2.new(0, 64, 0, 64)
	badge.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	badge.BackgroundTransparency = 0.25
	badge.BorderSizePixel = 0
	badge.Parent = container

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 14)
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Name = "BadgeStroke"
	badgeStroke.Thickness = 2.5
	badgeStroke.Color = Color3.fromRGB(190, 195, 205)
	badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeStroke.Parent = badge

	-- Rank Letter Text (e.g. "S", "SS", "A")
	local rLetter = Instance.new("TextLabel")
	rLetter.Name = "RankLetter"
	rLetter.Size = UDim2.new(1, 0, 1, 0)
	rLetter.BackgroundTransparency = 1
	rLetter.Font = Enum.Font.GothamBlack
	rLetter.Text = "D"
	rLetter.TextColor3 = Color3.fromRGB(255, 255, 255)
	rLetter.TextScaled = true
	rLetter.Parent = badge

	local rLetterStroke = Instance.new("UIStroke")
	rLetterStroke.Thickness = 2
	rLetterStroke.Color = Color3.fromRGB(0, 0, 0)
	rLetterStroke.Parent = rLetter

	-- Rank Title (e.g. "SPECTACULAR")
	local rTitle = Instance.new("TextLabel")
	rTitle.Name = "RankTitle"
	rTitle.Position = UDim2.new(0, 74, 0, 10)
	rTitle.Size = UDim2.new(0, 150, 0, 20)
	rTitle.BackgroundTransparency = 1
	rTitle.Font = Enum.Font.GothamBold
	rTitle.Text = "DECENT"
	rTitle.TextColor3 = Color3.fromRGB(190, 195, 205)
	rTitle.TextSize = 14
	rTitle.TextXAlignment = Enum.TextXAlignment.Left
	rTitle.Parent = container

	-- Combo Number Text (e.g. "24x")
	local cLabel = Instance.new("TextLabel")
	cLabel.Name = "ComboLabel"
	cLabel.Position = UDim2.new(0, 74, 0, 26)
	cLabel.Size = UDim2.new(0, 85, 0, 42)
	cLabel.BackgroundTransparency = 1
	cLabel.Font = Enum.Font.GothamBlack
	cLabel.Text = "1x"
	cLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	cLabel.TextSize = 38
	cLabel.TextXAlignment = Enum.TextXAlignment.Left
	cLabel.Parent = container

	local cLabelStroke = Instance.new("UIStroke")
	cLabelStroke.Thickness = 2.5
	cLabelStroke.Color = Color3.fromRGB(15, 18, 25)
	cLabelStroke.Parent = cLabel

	-- "COMBO" Sub-label
	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "HitsSubLabel"
	subLabel.Position = UDim2.new(0, 160, 0, 36)
	subLabel.Size = UDim2.new(0, 65, 0, 24)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamBold
	subLabel.Text = "HITS"
	subLabel.TextColor3 = Color3.fromRGB(190, 210, 235)
	subLabel.TextSize = 14
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Parent = container

	-- Combo Decay Bar Background
	local decayBg = Instance.new("Frame")
	decayBg.Name = "DecayBarBackground"
	decayBg.Position = UDim2.new(0, 74, 0, 72)
	decayBg.Size = UDim2.new(0, 146, 0, 6)
	decayBg.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
	decayBg.BackgroundTransparency = 0.3
	decayBg.BorderSizePixel = 0
	decayBg.Parent = container

	local decayBgCorner = Instance.new("UICorner")
	decayBgCorner.CornerRadius = UDim.new(0, 3)
	decayBgCorner.Parent = decayBg

	-- Combo Decay Bar Fill
	local decayFill = Instance.new("Frame")
	decayFill.Name = "DecayBarFill"
	decayFill.Size = UDim2.new(1, 0, 1, 0)
	decayFill.BackgroundColor3 = Color3.fromRGB(85, 235, 255)
	decayFill.BorderSizePixel = 0
	decayFill.Parent = decayBg

	local decayFillCorner = Instance.new("UICorner")
	decayFillCorner.CornerRadius = UDim.new(0, 3)
	decayFillCorner.Parent = decayFill

	-- 2. ⚡ Sleek Ability Cooldown Hotbar (Bottom-Right Minimal Anchor)
	local abilityTray = Instance.new("Frame")
	abilityTray.Name = "AbilityTray"
	abilityTray.AnchorPoint = Vector2.new(1, 1)
	abilityTray.Position = UDim2.new(0.98, 0, 1.15, 0)
	abilityTray.Size = UDim2.new(0, 290, 0, 26)
	abilityTray.BackgroundTransparency = 1
	abilityTray.Visible = false
	abilityTray.Parent = gui

	local trayLayout = Instance.new("UIListLayout")
	trayLayout.FillDirection = Enum.FillDirection.Horizontal
	trayLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	trayLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	trayLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trayLayout.Padding = UDim.new(0, 6)
	trayLayout.Parent = abilityTray

	-- 🕸️ [E] Web-Pellet / Impact Blast Pill
	local pelletPill = Instance.new("Frame")
	pelletPill.Name = "PelletPill"
	pelletPill.LayoutOrder = 1
	pelletPill.Size = UDim2.new(0, 86, 0, 24)
	pelletPill.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	pelletPill.BackgroundTransparency = 0.35
	pelletPill.BorderSizePixel = 0
	pelletPill.Parent = abilityTray

	local pelletCorner = Instance.new("UICorner")
	pelletCorner.CornerRadius = UDim.new(0, 6)
	pelletCorner.Parent = pelletPill

	local pelletStroke = Instance.new("UIStroke")
	pelletStroke.Name = "PelletStroke"
	pelletStroke.Thickness = 1.0
	pelletStroke.Color = Color3.fromRGB(195, 215, 245)
	pelletStroke.Transparency = 0.35
	pelletStroke.Parent = pelletPill

	local pelletCooldownOverlay = Instance.new("Frame")
	pelletCooldownOverlay.Name = "CooldownOverlay"
	pelletCooldownOverlay.Size = UDim2.new(0, 0, 1, 0)
	pelletCooldownOverlay.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
	pelletCooldownOverlay.BackgroundTransparency = 0.6
	pelletCooldownOverlay.BorderSizePixel = 0
	pelletCooldownOverlay.Parent = pelletPill

	local pelletOverlayCorner = Instance.new("UICorner")
	pelletOverlayCorner.CornerRadius = UDim.new(0, 6)
	pelletOverlayCorner.Parent = pelletCooldownOverlay

	local pelletLabel = Instance.new("TextLabel")
	pelletLabel.Name = "PelletLabel"
	pelletLabel.Size = UDim2.new(1, 0, 1, 0)
	pelletLabel.BackgroundTransparency = 1
	pelletLabel.Font = Enum.Font.GothamBold
	pelletLabel.Text = "[E] 🕸️ PELLET"
	pelletLabel.TextColor3 = Color3.fromRGB(220, 235, 255)
	pelletLabel.TextSize = 10
	pelletLabel.ZIndex = 2
	pelletLabel.Parent = pelletPill

	-- ⚡ [R] Web-Strike Zip-Kick Pill
	local strikePill = Instance.new("Frame")
	strikePill.Name = "StrikePill"
	strikePill.LayoutOrder = 2
	strikePill.Size = UDim2.new(0, 92, 0, 24)
	strikePill.BackgroundColor3 = Color3.fromRGB(18, 16, 26)
	strikePill.BackgroundTransparency = 0.35
	strikePill.BorderSizePixel = 0
	strikePill.Parent = abilityTray

	local strikeCorner = Instance.new("UICorner")
	strikeCorner.CornerRadius = UDim.new(0, 6)
	strikeCorner.Parent = strikePill

	local strikeStroke = Instance.new("UIStroke")
	strikeStroke.Name = "StrikeStroke"
	strikeStroke.Thickness = 1.0
	strikeStroke.Color = Color3.fromRGB(240, 180, 60)
	strikeStroke.Transparency = 0.35
	strikeStroke.Parent = strikePill

	local strikeCooldownOverlay = Instance.new("Frame")
	strikeCooldownOverlay.Name = "CooldownOverlay"
	strikeCooldownOverlay.Size = UDim2.new(0, 0, 1, 0)
	strikeCooldownOverlay.BackgroundColor3 = Color3.fromRGB(45, 35, 20)
	strikeCooldownOverlay.BackgroundTransparency = 0.6
	strikeCooldownOverlay.BorderSizePixel = 0
	strikeCooldownOverlay.Parent = strikePill

	local strikeOverlayCorner = Instance.new("UICorner")
	strikeOverlayCorner.CornerRadius = UDim.new(0, 6)
	strikeOverlayCorner.Parent = strikeCooldownOverlay

	local strikeLabel = Instance.new("TextLabel")
	strikeLabel.Name = "StrikeLabel"
	strikeLabel.Size = UDim2.new(1, 0, 1, 0)
	strikeLabel.BackgroundTransparency = 1
	strikeLabel.Font = Enum.Font.GothamBold
	strikeLabel.Text = "[R] ⚡ ZIP-KICK"
	strikeLabel.TextColor3 = Color3.fromRGB(255, 210, 85)
	strikeLabel.TextSize = 10
	strikeLabel.ZIndex = 2
	strikeLabel.Parent = strikePill

	-- 🌪️ [T] Web Cyclone Button Pill
	local cyclonePill = Instance.new("Frame")
	cyclonePill.Name = "CyclonePill"
	cyclonePill.LayoutOrder = 3
	cyclonePill.Size = UDim2.new(0, 96, 0, 24)
	cyclonePill.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	cyclonePill.BackgroundTransparency = 0.35
	cyclonePill.BorderSizePixel = 0
	cyclonePill.Parent = abilityTray

	local cycloneCorner = Instance.new("UICorner")
	cycloneCorner.CornerRadius = UDim.new(0, 6)
	cycloneCorner.Parent = cyclonePill

	local cycloneStroke = Instance.new("UIStroke")
	cycloneStroke.Name = "CycloneStroke"
	cycloneStroke.Thickness = 1.0
	cycloneStroke.Color = Color3.fromRGB(75, 215, 255)
	cycloneStroke.Transparency = 0.35
	cycloneStroke.Parent = cyclonePill

	local cycloneCooldownOverlay = Instance.new("Frame")
	cycloneCooldownOverlay.Name = "CooldownOverlay"
	cycloneCooldownOverlay.Size = UDim2.new(0, 0, 1, 0)
	cycloneCooldownOverlay.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	cycloneCooldownOverlay.BackgroundTransparency = 0.6
	cycloneCooldownOverlay.BorderSizePixel = 0
	cycloneCooldownOverlay.Parent = cyclonePill

	local cycloneOverlayCorner = Instance.new("UICorner")
	cycloneOverlayCorner.CornerRadius = UDim.new(0, 6)
	cycloneOverlayCorner.Parent = cycloneCooldownOverlay

	local cycloneLabel = Instance.new("TextLabel")
	cycloneLabel.Name = "CycloneLabel"
	cycloneLabel.Size = UDim2.new(1, 0, 1, 0)
	cycloneLabel.BackgroundTransparency = 1
	cycloneLabel.Font = Enum.Font.GothamBold
	cycloneLabel.Text = "[T] 🌪️ CYCLONE"
	cycloneLabel.TextColor3 = Color3.fromRGB(95, 230, 255)
	cycloneLabel.TextSize = 10
	cycloneLabel.ZIndex = 2
	cycloneLabel.Parent = cyclonePill



	gui.Parent = PlayerGui

	screenGui = gui
	mainContainer = container
	comboLabel = cLabel
	hitsSubLabel = subLabel
	rankBadge = badge
	rankLetter = rLetter
	rankTitle = rTitle
	decayBarFill = decayFill
	decayBarBackground = decayBg
	abilityTrayFrame = abilityTray
end

-- 🏆 Get Style Rank based on Hit Count
local function getRankInfo(hitCount: number)
	local ranks = CombatConfig.StyleMeter and CombatConfig.StyleMeter.Ranks or {
		{ MinHits = 1,  Name = "DECENT",      Rank = "D",  Color = Color3.fromRGB(190, 195, 205) },
		{ MinHits = 5,  Name = "COOL",        Rank = "C",  Color = Color3.fromRGB(75, 225, 120) },
		{ MinHits = 10, Name = "BRUTAL",      Rank = "B",  Color = Color3.fromRGB(60, 175, 255) },
		{ MinHits = 16, Name = "AMAZING",     Rank = "A",  Color = Color3.fromRGB(200, 85, 255) },
		{ MinHits = 24, Name = "SPECTACULAR", Rank = "S",  Color = Color3.fromRGB(255, 205, 45) },
		{ MinHits = 32, Name = "SPIDER-TIER!",Rank = "SS", Color = Color3.fromRGB(255, 55, 75) },
	}

	local currentRank = ranks[1]
	local rankIdx = 1
	for idx, r in ranks do
		if hitCount >= r.MinHits then
			currentRank = r
			rankIdx = idx
		end
	end
	return currentRank, rankIdx
end

-- 💥 Bouncy Hit Punch-In Animation
local function playHitBounce(isNewRank: boolean)
	if not comboLabel or not rankBadge or not rankLetter then return end

	-- Number Spring Scale
	comboLabel.TextSize = 48
	local numTween = TweenService:Create(comboLabel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 38,
	})
	numTween:Play()

	-- Rank Badge Pop if upgraded
	if isNewRank then
		rankBadge.Size = UDim2.new(0, 78, 0, 78)
		local badgeTween = TweenService:Create(rankBadge, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 64, 0, 64),
		})
		badgeTween:Play()
	end
end

-- ⏳ Cooldown Tracking State
local pelletCooldownEnd = 0
local pelletCooldownTotal = 0.3

local strikeCooldownEnd = 0
local strikeCooldownTotal = 2.0

local cycloneCooldownEnd = 0
local cycloneCooldownTotal = 15.0

function CombatStyleHUD.setCooldown(skillName: string, duration: number)
	if skillName == "WebCyclone" then
		cycloneCooldownEnd = os.clock() + duration
		cycloneCooldownTotal = duration
	elseif skillName == "WebPellet" or skillName == "ImpactBlast" then
		pelletCooldownEnd = os.clock() + duration
		pelletCooldownTotal = duration
	elseif skillName == "WebStrike" then
		strikeCooldownEnd = os.clock() + duration
		strikeCooldownTotal = duration
	end
end

CombatStyleHUD.isTrayLockedHidden = true

-- 🎮 Dynamic Ability Tray Visibility (Permanently suppressed per user preference)
function CombatStyleHUD.unlockAbilityTray()
	CombatStyleHUD.isTrayLockedHidden = true
end

function CombatStyleHUD.showAbilityTray()
	-- Suppressed: Ability pills [E], [R], [T] removed from screen
	return
end

function CombatStyleHUD.hideAbilityTray(isImmediateLock: boolean?)
	local tray = abilityTrayFrame or (screenGui and screenGui:FindFirstChild("AbilityTray") :: Frame?)
	if tray then
		tray.Visible = false
		tray.Position = UDim2.new(0.98, 0, 1.15, 0)
	end
end

-- 🥊 Register a successful attack hit on enemy
function CombatStyleHUD.registerHit(damage: number?)
	if not screenGui or not mainContainer then
		createHUD()
	end
	-- Respects isTrayLockedHidden: only local offensive input (CombatController) re-arms the tray
	CombatStyleHUD.showAbilityTray()

	local now = os.clock()
	local wasInactive = not CombatStyleHUD.isActive
	CombatStyleHUD.currentCombo += 1
	CombatStyleHUD.lastHitTime = now
	CombatStyleHUD.isActive = true

	local rankInfo, rankIdx = getRankInfo(CombatStyleHUD.currentCombo)
	local isNewRank = rankIdx > CombatStyleHUD.currentRankIndex
	CombatStyleHUD.currentRankIndex = rankIdx

	if mainContainer and comboLabel and rankLetter and rankTitle and rankBadge and decayBarFill then
		if wasInactive then
			if activeSlideTween then activeSlideTween:Cancel() end
			mainContainer.Position = UDim2.new(1, 80, 0.44, 0)
			mainContainer.Visible = true
			activeSlideTween = TweenService:Create(mainContainer, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.new(1, -36, 0.44, 0),
			})
			activeSlideTween:Play()
		else
			mainContainer.Visible = true
			mainContainer.Position = UDim2.new(1, -36, 0.44, 0)
		end

		-- Update text
		comboLabel.Text = tostring(CombatStyleHUD.currentCombo) .. "x"
		rankLetter.Text = rankInfo.Rank
		rankTitle.Text = rankInfo.Name

		-- Update colors
		rankLetter.TextColor3 = rankInfo.Color
		rankTitle.TextColor3 = rankInfo.Color
		decayBarFill.BackgroundColor3 = rankInfo.Color

		local stroke = rankBadge:FindFirstChild("BadgeStroke") :: UIStroke?
		if stroke then
			stroke.Color = rankInfo.Color
		end

		playHitBounce(isNewRank)
	end
end

-- ⏳ Reset Combo (Decay Timeout or Taking Damage)
function CombatStyleHUD.resetCombo()
	CombatStyleHUD.hideAbilityTray()
	if not CombatStyleHUD.isActive then return end
	CombatStyleHUD.isActive = false
	CombatStyleHUD.currentCombo = 0
	CombatStyleHUD.currentRankIndex = 1

	if mainContainer then
		if activeSlideTween then activeSlideTween:Cancel() end
		activeSlideTween = TweenService:Create(mainContainer, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(1, 80, 0.44, 0),
		})
		activeSlideTween:Play()
		activeSlideTween.Completed:Connect(function()
			if not CombatStyleHUD.isActive and mainContainer then
				mainContainer.Visible = false
				mainContainer.Position = UDim2.new(1, 80, 0.44, 0)
			end
		end)
	end
end

-- 💥 Taking damage drops combo
function CombatStyleHUD.onTakeDamage()
	if CombatStyleHUD.currentCombo > 0 then
		CombatStyleHUD.resetCombo()
	end
end

-- 🔄 RenderStepped Loop (Decay Bar + Ability Cooldown Hotbar Animation)
RunService.RenderStepped:Connect(function()
	local now = os.clock()

	-- Combo Decay Bar
	if CombatStyleHUD.isActive and decayBarFill then
		local decayDuration = CombatConfig.StyleMeter and CombatConfig.StyleMeter.DecayTime or 3.6
		local elapsed = now - CombatStyleHUD.lastHitTime
		local remainingRatio = math.clamp(1 - (elapsed / decayDuration), 0, 1)

		decayBarFill.Size = UDim2.new(remainingRatio, 0, 1, 0)

		if remainingRatio <= 0 then
			CombatStyleHUD.resetCombo()
		end
	end

	-- Cooldown Hotbar Updates (Optimized: only executes when AbilityTray is visible)
	local abilityTray = abilityTrayFrame
	if abilityTray and abilityTray.Visible then
		-- [E] Web-Pellet / Impact Blast Pill
		local pelletPill = abilityTray:FindFirstChild("PelletPill") :: Frame?
		if pelletPill then
			local pelletLabel = pelletPill:FindFirstChild("PelletLabel") :: TextLabel?
			local pelletOverlay = pelletPill:FindFirstChild("CooldownOverlay") :: Frame?
			local pelletStroke = pelletPill:FindFirstChild("PelletStroke") :: UIStroke?
			local isScarlet = LocalPlayer:GetAttribute("EquippedSuit") == "ScarletSpider"

			if now < pelletCooldownEnd then
				local rem = pelletCooldownEnd - now
				local ratio = math.clamp(rem / math.max(0.1, pelletCooldownTotal), 0, 1)
				if pelletLabel then
					pelletLabel.Text = if rem >= 1.0 then string.format("[E] ⏳ %ds", math.ceil(rem)) else string.format("[E] ⏳ %.1fs", rem)
					pelletLabel.TextColor3 = Color3.fromRGB(160, 175, 190)
				end
				if pelletOverlay then pelletOverlay.Size = UDim2.new(ratio, 0, 1, 0) end
				if pelletStroke then pelletStroke.Color = Color3.fromRGB(60, 70, 80) end
			else
				if pelletLabel then
					if isScarlet then
						pelletLabel.Text = "[E] 💥 BLAST"
						pelletLabel.TextColor3 = Color3.fromRGB(255, 120, 130)
					else
						pelletLabel.Text = "[E] 🕸️ PELLET"
						pelletLabel.TextColor3 = Color3.fromRGB(220, 235, 255)
					end
				end
				if pelletOverlay then pelletOverlay.Size = UDim2.new(0, 0, 1, 0) end
				if pelletStroke then pelletStroke.Color = if isScarlet then Color3.fromRGB(240, 50, 60) else Color3.fromRGB(195, 215, 245) end
			end
		end

		-- [R] Web-Strike Zip-Kick Pill
		local strikePill = abilityTray:FindFirstChild("StrikePill") :: Frame?
		if strikePill then
			local strikeLabel = strikePill:FindFirstChild("StrikeLabel") :: TextLabel?
			local strikeOverlay = strikePill:FindFirstChild("CooldownOverlay") :: Frame?
			local strikeStroke = strikePill:FindFirstChild("StrikeStroke") :: UIStroke?

			if now < strikeCooldownEnd then
				local rem = strikeCooldownEnd - now
				local ratio = math.clamp(rem / math.max(0.1, strikeCooldownTotal), 0, 1)
				if strikeLabel then
					strikeLabel.Text = string.format("[R] ⏳ %.1fs", rem)
					strikeLabel.TextColor3 = Color3.fromRGB(160, 175, 190)
				end
				if strikeOverlay then strikeOverlay.Size = UDim2.new(ratio, 0, 1, 0) end
				if strikeStroke then strikeStroke.Color = Color3.fromRGB(60, 70, 80) end
			else
				if strikeLabel then
					strikeLabel.Text = "[R] ⚡ ZIP-KICK"
					strikeLabel.TextColor3 = Color3.fromRGB(255, 210, 85)
				end
				if strikeOverlay then strikeOverlay.Size = UDim2.new(0, 0, 1, 0) end
				if strikeStroke then strikeStroke.Color = Color3.fromRGB(240, 180, 60) end
			end
		end

		-- [T] Web Cyclone Cooldown Update
		local cyclonePill = abilityTray:FindFirstChild("CyclonePill") :: Frame?
		if cyclonePill then
			local cycloneLabel = cyclonePill:FindFirstChild("CycloneLabel") :: TextLabel?
			local cycloneOverlay = cyclonePill:FindFirstChild("CooldownOverlay") :: Frame?
			local cycloneStroke = cyclonePill:FindFirstChild("CycloneStroke") :: UIStroke?

			if now < cycloneCooldownEnd then
				local rem = math.ceil(cycloneCooldownEnd - now)
				local ratio = math.clamp((cycloneCooldownEnd - now) / math.max(0.1, cycloneCooldownTotal), 0, 1)
				if cycloneLabel then
					cycloneLabel.Text = string.format("[T] ⏳ %ds", rem)
					cycloneLabel.TextColor3 = Color3.fromRGB(160, 175, 190)
				end
				if cycloneOverlay then cycloneOverlay.Size = UDim2.new(ratio, 0, 1, 0) end
				if cycloneStroke then cycloneStroke.Color = Color3.fromRGB(60, 70, 80) end
			else
				if cycloneLabel then
					cycloneLabel.Text = "[T] 🌪️ CYCLONE"
					cycloneLabel.TextColor3 = Color3.fromRGB(95, 230, 255)
				end
				if cycloneOverlay then cycloneOverlay.Size = UDim2.new(0, 0, 1, 0) end
				if cycloneStroke then cycloneStroke.Color = Color3.fromRGB(75, 215, 255) end
			end
		end


	end
end)

-- Initialize on load
createHUD()

-- 🎬 Cinematic / Recording UI Master Switch
function CombatStyleHUD.setUIVisible(visible: boolean)
	isUIVisible = visible
	if screenGui then
		screenGui.Enabled = visible
	end
end

return CombatStyleHUD
