--!strict
--[[
	LevelUpCelebration.luau
	Non-Modal Top-Center Screen Fanfare (Genshin Impact AR Rank-Up Style)
	for "Spider-Man: Web of Destiny".

	Hardened & Polished:
	- Dynamic CanvasGroup Banner Height: 96px for Level 2 (with callout pill), 74px for other levels (no empty bottom shelf).
	- High-contrast typography: 11px GothamBold unlock taglines with clean text contrast.
	- Opacity hardening: 0.06 background transparency to block bright in-world 3D waypoints.
	- Bulletproof FOV punch: safe restoration even if interrupted or cancelled.
	- Non-modal: Active = false, Selectable = false across all elements.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local LevelUpCelebration = {}

--------------------------------------------------------------------------------
-- 📊 RANK TITLES & UNLOCK DEFINITIONS
--------------------------------------------------------------------------------

local RANK_TITLES: { [number]: string } = {
	[1] = "Rookie Vigilante",
	[2] = "Neighborhood Defender",
	[3] = "Midtown Guardian",
	[4] = "Urban Avenger",
	[5] = "Protector of Manhattan",
	[6] = "The Spectacular Spider-Man (MAX)",
}

local UNLOCK_TAGLINES: { [number]: string } = {
	[2] = "360° Web Cyclone Blender [T] • Stark Tech Advanced ($800)",
	[3] = "Stealth Big Time Suit ($2,000) • +0.25s Perfect Dodge Window",
	[4] = "Symbiote Alien Suit ($4,500) • +20% Melee Punch & Cleave Damage",
	[5] = "Spider-Armor MK IV ($9,000) • +25 Max Health Shield Plating",
	[6] = "2099 Cyber Suit ($16,000) • +30% Cyclone Radius & Vortex",
}

--------------------------------------------------------------------------------
-- 🛡️ ACTIVE CELEBRATION STATE MANAGEMENT
--------------------------------------------------------------------------------

local activeScreenGui: ScreenGui? = nil
local activeThread: thread? = nil
local isPulsingPill = false

-- FOV Punch Interruption Safety
local activeFovTween: Tween? = nil
local savedOriginalFov: number? = nil

local function cleanupCurrentFanfare()
	isPulsingPill = false

	if activeThread then
		task.cancel(activeThread)
		activeThread = nil
	end

	-- Restore Camera FOV safely if interrupted mid-punch
	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end
	if savedOriginalFov ~= nil then
		local cam = Workspace.CurrentCamera
		if cam then
			cam.FieldOfView = savedOriginalFov :: number
		end
		savedOriginalFov = nil
	end

	if activeScreenGui then
		activeScreenGui:Destroy()
		activeScreenGui = nil
	end
end

--------------------------------------------------------------------------------
-- 🎥 JUICE: CAMERA FOV PUNCH (-6° for 0.12s -> smooth return over 0.30s)
--------------------------------------------------------------------------------

local function triggerFovPunch()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end

	if savedOriginalFov == nil then
		savedOriginalFov = camera.FieldOfView
	end

	local originalFov = savedOriginalFov :: number
	local punchedFOV = math.max(20, originalFov - 6)

	local punchTween = TweenService:Create(
		camera,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = punchedFOV }
	)
	activeFovTween = punchTween
	punchTween:Play()

	task.delay(0.12, function()
		local currentCam = Workspace.CurrentCamera
		if currentCam and savedOriginalFov ~= nil then
			local targetFov = savedOriginalFov :: number
			local recoverTween = TweenService:Create(
				currentCam,
				TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = targetFov }
			)
			activeFovTween = recoverTween
			recoverTween:Play()
			recoverTween.Completed:Connect(function()
				if activeFovTween == recoverTween then
					activeFovTween = nil
					savedOriginalFov = nil
				end
			end)
		end
	end)
end

--------------------------------------------------------------------------------
-- 🌐 JUICE: WORLD-SPACE RADIAL NEON SHOCKWAVE PULSE
--------------------------------------------------------------------------------

local function triggerShockwavePulse()
	local character = LocalPlayer.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local shockwave = Instance.new("Part")
	shockwave.Name = "LevelUpShockwave"
	shockwave.Shape = Enum.PartType.Cylinder
	shockwave.Material = Enum.Material.Neon
	shockwave.Color = Color3.fromRGB(0, 220, 255)
	shockwave.Transparency = 0.2
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.CastShadow = false
	shockwave.Size = Vector3.new(0.05, 3, 3)

	-- Orient flat on the ground at feet level (2.5 studs below HRP)
	local groundPosition = rootPart.Position - Vector3.new(0, 2.5, 0)
	shockwave.CFrame = CFrame.new(groundPosition) * CFrame.Angles(0, 0, math.rad(90))
	shockwave.Parent = Workspace

	local shockwaveTween = TweenService:Create(
		shockwave,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(0.05, 22, 22),
			Transparency = 1,
		}
	)
	shockwaveTween:Play()
	shockwaveTween.Completed:Connect(function()
		shockwave:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- 🔊 JUICE: AUDIO FANFARE CHIME (T = 0.05s)
--------------------------------------------------------------------------------

local function playFanfareAudio()
	-- Zero SFX Policy: Completely silent visual-only level-up celebration
	return
end

--------------------------------------------------------------------------------
-- 🎬 MAIN CELEBRATION SEQUENCE
--------------------------------------------------------------------------------

function LevelUpCelebration.play(newLevel: number)
	cleanupCurrentFanfare()

	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local rankTitle = RANK_TITLES[newLevel] or string.format("Hero Level %d", newLevel)
	local unlockTagline = UNLOCK_TAGLINES[newLevel] or "🕷️ Core Combat Codex & Traversal Arsenal Ready"
	local isLevelTwo = newLevel == 2
	local isMaxLevel = newLevel >= 6

	-- Dynamic Height: 96px for Level 2 (has callout pill), 74px for all others (cleanly centered, no void)
	local bannerHeight = isLevelTwo and 96 or 74

	-- 1. ScreenGui (Non-Modal, No Focus Grab)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LevelUpFanfareGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 25
	screenGui.IgnoreGuiInset = true
	activeScreenGui = screenGui

	-- 2. CanvasGroup Centered Horizontally
	local banner = Instance.new("CanvasGroup")
	banner.Name = "FanfareBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Size = UDim2.new(0, 480, 0, bannerHeight)
	banner.Position = UDim2.new(0.5, 0, 0, -20)
	banner.GroupTransparency = 1
	banner.BackgroundColor3 = Color3.fromRGB(10, 14, 22)
	banner.BackgroundTransparency = 0.06 -- Higher opacity to prevent 3D waypoint bleedthrough
	banner.Active = false
	banner.Selectable = false
	banner.Parent = screenGui

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 12)
	bannerCorner.Parent = banner

	local strokeColor = (isLevelTwo or isMaxLevel) and Color3.fromRGB(255, 205, 55) or Color3.fromRGB(80, 200, 255)
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Thickness = 1.5
	bannerStroke.Color = strokeColor
	bannerStroke.Parent = banner

	-- 3. Dynamic Internal Content (Balanced vertical alignment)
	local headerColor = (isLevelTwo or isMaxLevel) and Color3.fromRGB(255, 215, 65) or Color3.fromRGB(85, 205, 255)

	local headerLabel = Instance.new("TextLabel")
	headerLabel.Name = "HeaderLabel"
	headerLabel.Size = UDim2.new(1, -24, 0, 18)
	headerLabel.Position = UDim2.new(0, 12, 0, 8)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Font = Enum.Font.GothamBlack
	headerLabel.Text = string.format("LEVEL UP // LEVEL %d REACHED", newLevel)
	headerLabel.TextColor3 = headerColor
	headerLabel.TextSize = isLevelTwo and 12.5 or 13.5
	headerLabel.TextXAlignment = Enum.TextXAlignment.Center
	headerLabel.Active = false
	headerLabel.Selectable = false
	headerLabel.Parent = banner

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, -24, 0, 18)
	titleLabel.Position = UDim2.new(0, 12, 0, isLevelTwo and 27 or 28)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = string.format("[ %s ]", string.upper(rankTitle))
	titleLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
	titleLabel.TextSize = isLevelTwo and 10.5 or 11.5
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.Active = false
	titleLabel.Selectable = false
	titleLabel.Parent = banner

	local unlockLabel = Instance.new("TextLabel")
	unlockLabel.Name = "UnlockLabel"
	unlockLabel.Size = UDim2.new(1, -24, 0, 18)
	unlockLabel.Position = UDim2.new(0, 12, 0, isLevelTwo and 45 or 48)
	unlockLabel.BackgroundTransparency = 1
	unlockLabel.Font = Enum.Font.GothamBold
	unlockLabel.Text = unlockTagline
	unlockLabel.TextColor3 = Color3.fromRGB(205, 220, 240)
	unlockLabel.TextSize = isLevelTwo and 10 or 11
	unlockLabel.TextXAlignment = Enum.TextXAlignment.Center
	unlockLabel.Active = false
	unlockLabel.Selectable = false
	unlockLabel.Parent = banner

	-- Special Level 2 Golden Accent Callout Pill
	if isLevelTwo then
		local calloutPill = Instance.new("Frame")
		calloutPill.Name = "Level2CalloutPill"
		calloutPill.AnchorPoint = Vector2.new(0.5, 0)
		calloutPill.Position = UDim2.new(0.5, 0, 0, 66)
		calloutPill.Size = UDim2.new(0, 370, 0, 20)
		calloutPill.BackgroundColor3 = Color3.fromRGB(48, 36, 16)
		calloutPill.BackgroundTransparency = 0.2
		calloutPill.Active = false
		calloutPill.Selectable = false
		calloutPill.Parent = banner

		local pillCorn = Instance.new("UICorner")
		pillCorn.CornerRadius = UDim.new(0, 6)
		pillCorn.Parent = calloutPill

		local pillStroke = Instance.new("UIStroke")
		pillStroke.Thickness = 1.0
		pillStroke.Color = Color3.fromRGB(255, 195, 55)
		pillStroke.Parent = calloutPill

		local pillText = Instance.new("TextLabel")
		pillText.Size = UDim2.new(1, 0, 1, 0)
		pillText.BackgroundTransparency = 1
		pillText.Font = Enum.Font.GothamBlack
		pillText.Text = "FIRST ULTIMATE UNLOCKED: PRESS [T] IN COMBAT"
		pillText.TextColor3 = Color3.fromRGB(255, 220, 85)
		pillText.TextSize = 9
		pillText.TextXAlignment = Enum.TextXAlignment.Center
		pillText.Active = false
		pillText.Selectable = false
		pillText.Parent = calloutPill

		-- Subtle pulsing loop for the Level 2 pill
		isPulsingPill = true
		task.spawn(function()
			while isPulsingPill and calloutPill and calloutPill.Parent do
				local tUp = TweenService:Create(
					pillStroke,
					TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Transparency = 0.6 }
				)
				tUp:Play()
				task.wait(0.4)
				if not isPulsingPill or not calloutPill.Parent then break end
				local tDown = TweenService:Create(
					pillStroke,
					TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Transparency = 0.0 }
				)
				tDown:Play()
				task.wait(0.4)
			end
		end)
	end

	screenGui.Parent = playerGui

	-- Sequence Thread
	activeThread = task.spawn(function()
		-- T = 0.00s: Slide Down & Fade In
		local slideInTween = TweenService:Create(
			banner,
			TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(0.5, 0, 0, 38),
				GroupTransparency = 0,
			}
		)
		slideInTween:Play()

		-- T = 0.00s: Camera Punch & Ground Shockwave
		triggerFovPunch()
		triggerShockwavePulse()

		-- T = 0.05s: Audio Chime
		task.wait(0.05)
		playFanfareAudio()

		-- Wait until T = 2.80s (2.80 - 0.05 = 2.75s)
		task.wait(2.75)

		-- T = 2.80s: Fade Out & Slide Up
		isPulsingPill = false
		local slideOutTween = TweenService:Create(
			banner,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(0.5, 0, 0, 15),
				GroupTransparency = 1,
			}
		)
		slideOutTween:Play()
		slideOutTween.Completed:Wait()

		-- T = 3.25s: Cleanup
		if activeScreenGui == screenGui then
			activeScreenGui:Destroy()
			activeScreenGui = nil
			activeThread = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- 🛰️ REMOTE EVENT LISTENER INITIALIZATION
--------------------------------------------------------------------------------

local function initRemoteListener()
	task.spawn(function()
		local CrimeRemotes = ReplicatedStorage:WaitForChild("CrimeRemotes", 10)
		if not CrimeRemotes then
			warn("[LevelUpCelebration] CrimeRemotes folder not found in ReplicatedStorage!")
			return
		end

		local CrimeNotificationRemote = CrimeRemotes:WaitForChild("CrimeNotification", 10) :: RemoteEvent?
		if not CrimeNotificationRemote then
			warn("[LevelUpCelebration] CrimeNotification RemoteEvent not found!")
			return
		end

		CrimeNotificationRemote.OnClientEvent:Connect(function(eventType: any, data: any)
			if eventType == "LevelUp" then
				local newLevel = typeof(data) == "number" and data or tonumber(data) or 1
				LevelUpCelebration.play(newLevel)
			end
		end)
	end)
end

initRemoteListener()

return LevelUpCelebration
