--!strict
--[[
	PoliceRadioHUD.luau
	Phase 5: Client HUD for Police Radio Scanner & 3D Holographic Waypoints.
	
	Features:
	- Atmospheric NYPD Police Scanner Banner with animated audio frequency waves
	- 3D Holographic Waypoint Beacon with distance calculation (meters & studs)
	- Off-screen edge clamping & directional pointer arrow
	- Victory Banner with 0.5s slow-motion freeze and XP/Cash payout display
	- Co-Op scaling alerts & Van Sabotage cues
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrimeConfig = require(Shared:WaitForChild("CrimeConfig"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

local PoliceRadioHUD = {
	activeCrimeData = nil,
	isRadioSpeaking = false,
	isCrimeActive = false,
}

-- GUI References
local screenGui: ScreenGui? = nil
local radioBanner: Frame? = nil
local radioCodeLabel: TextLabel? = nil
local radioSubtitleLabel: TextLabel? = nil
local waveContainer: Frame? = nil
local waveBars: { Frame } = {}

local waypointMarker: Frame? = nil
local waypointIconLabel: TextLabel? = nil
local waypointTitleLabel: TextLabel? = nil
local waypointDistanceLabel: TextLabel? = nil
local waypointArrow: ImageLabel? = nil

local victoryBanner: Frame? = nil
local victoryTitleLabel: TextLabel? = nil
local victoryRewardsLabel: TextLabel? = nil
local victorySubLabel: TextLabel? = nil

-- Holographic Ground Ring
local activeGroundRing: Part? = nil

--------------------------------------------------------------------------------
-- 🎵 AUDIO SYNTHESIS & SFX HELPER
--------------------------------------------------------------------------------

local function playDispatchSound(soundType: "RadioSquelch" | "Victory" | "Siren")
	local soundId = ""
	local volume = 0.8
	local pitch = 1.0

	if soundType == "RadioSquelch" then
		soundId = CrimeConfig.Audio and CrimeConfig.Audio.RadioSquelchId or ""
		pitch = 1.15
	elseif soundType == "Victory" then
		soundId = CrimeConfig.Audio and CrimeConfig.Audio.VictoryFanfareId or ""
		volume = 1.0
	else
		soundId = CrimeConfig.Audio and CrimeConfig.Audio.DispatchSirenId or ""
		pitch = 1.0
	end

	if soundId == "" then return end

	local sound = Instance.new("Sound")
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.SoundId = soundId
	sound.Parent = SoundService
	sound:Play()

	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- 🎨 PROGRAMMATIC UI GENERATION
--------------------------------------------------------------------------------

local function createHUD()
	if PlayerGui:FindFirstChild("PoliceRadioHUD") then
		PlayerGui:FindFirstChild("PoliceRadioHUD"):Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "PoliceRadioHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 15

	-- 📻 1. TOP-CENTER POLICE SCANNER BANNER (Sleek Minimalist HUD)
	local banner = Instance.new("Frame")
	banner.Name = "RadioBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, -0.20, 0) -- Hidden above screen
	banner.Size = UDim2.new(0, 440, 0, 44)
	banner.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
	banner.BackgroundTransparency = 0.30
	banner.BorderSizePixel = 0
	banner.Parent = gui

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 10)
	bannerCorner.Parent = banner

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Thickness = 1.2
	bannerStroke.Color = Color3.fromRGB(255, 65, 65)
	bannerStroke.Transparency = 0.3
	bannerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bannerStroke.Parent = banner

	-- Dispatch Header Code
	local codeLabel = Instance.new("TextLabel")
	codeLabel.Name = "CodeLabel"
	codeLabel.Position = UDim2.new(0, 16, 0, 4)
	codeLabel.Size = UDim2.new(1, -32, 0, 16)
	codeLabel.BackgroundTransparency = 1
	codeLabel.Font = Enum.Font.GothamBold
	codeLabel.Text = "📻 NYPD DISPATCH • 10-31 IN PROGRESS"
	codeLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
	codeLabel.TextSize = 11
	codeLabel.TextXAlignment = Enum.TextXAlignment.Left
	codeLabel.Parent = banner

	-- Dispatch Message Subtitle
	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "SubtitleLabel"
	subtitleLabel.Position = UDim2.new(0, 16, 0, 20)
	subtitleLabel.Size = UDim2.new(1, -32, 0, 18)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.GothamMedium
	subtitleLabel.Text = "Armed robbery at First National Bank. All units respond."
	subtitleLabel.TextColor3 = Color3.fromRGB(210, 225, 245)
	subtitleLabel.TextSize = 11
	subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.Parent = banner

	-- 📍 2. 3D HOLOGRAPHIC WAYPOINT BEACON (Clean Compact Pill)
	local marker = Instance.new("Frame")
	marker.Name = "WaypointMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.new(0.5, 0, 0.5, 0)
	marker.Size = UDim2.new(0, 136, 0, 32)
	marker.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	marker.BackgroundTransparency = 0.35
	marker.BorderSizePixel = 0
	marker.Visible = false
	marker.Parent = gui

	local markerCorner = Instance.new("UICorner")
	markerCorner.CornerRadius = UDim.new(0, 8)
	markerCorner.Parent = marker

	local markerStroke = Instance.new("UIStroke")
	markerStroke.Thickness = 1.2
	markerStroke.Color = Color3.fromRGB(255, 75, 75)
	markerStroke.Transparency = 0.3
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
	titleLabel.Size = UDim2.new(1, -34, 0, 14)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "BANK HEIST"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 10
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = marker

	local distLabel = Instance.new("TextLabel")
	distLabel.Name = "DistanceLabel"
	distLabel.Position = UDim2.new(0, 28, 0, 15)
	distLabel.Size = UDim2.new(1, -34, 0, 13)
	distLabel.BackgroundTransparency = 1
	distLabel.Font = Enum.Font.GothamMedium
	distLabel.Text = "140m"
	distLabel.TextColor3 = Color3.fromRGB(85, 215, 255)
	distLabel.TextSize = 10
	distLabel.TextXAlignment = Enum.TextXAlignment.Left
	distLabel.Parent = marker

	-- Direction Pointer Arrow (For off-screen indicator)
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "DirectionArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.new(0, 16, 0, 16)
	arrow.BackgroundTransparency = 1
	arrow.Image = "rbxassetid://6031094678" -- Standard Roblox UI Arrow
	arrow.ImageColor3 = Color3.fromRGB(255, 75, 75)
	arrow.Visible = false
	arrow.Parent = marker

	-- 🎉 3. VICTORY CELEBRATION BANNER
	local vBanner = Instance.new("Frame")
	vBanner.Name = "VictoryBanner"
	vBanner.AnchorPoint = Vector2.new(0.5, 0.5)
	vBanner.Position = UDim2.new(0.5, 0, -0.3, 0)
	vBanner.Size = UDim2.new(0, 420, 0, 76)
	vBanner.BackgroundColor3 = Color3.fromRGB(12, 20, 16)
	vBanner.BackgroundTransparency = 0.25
	vBanner.BorderSizePixel = 0
	vBanner.Parent = gui

	local vCorner = Instance.new("UICorner")
	vCorner.CornerRadius = UDim.new(0, 12)
	vCorner.Parent = vBanner

	local vStroke = Instance.new("UIStroke")
	vStroke.Thickness = 1.5
	vStroke.Color = Color3.fromRGB(65, 235, 130)
	vStroke.Parent = vBanner

	local vTitle = Instance.new("TextLabel")
	vTitle.Name = "VictoryTitle"
	vTitle.Position = UDim2.new(0, 0, 0, 10)
	vTitle.Size = UDim2.new(1, 0, 0, 26)
	vTitle.BackgroundTransparency = 1
	vTitle.Font = Enum.Font.GothamBlack
	vTitle.Text = "🎉 CRIME STOPPED!"
	vTitle.TextColor3 = Color3.fromRGB(75, 245, 140)
	vTitle.TextSize = 20
	vTitle.Parent = vBanner

	local vRewards = Instance.new("TextLabel")
	vRewards.Name = "VictoryRewards"
	vRewards.Position = UDim2.new(0, 0, 0, 46)
	vRewards.Size = UDim2.new(1, 0, 0, 24)
	vRewards.BackgroundTransparency = 1
	vRewards.Font = Enum.Font.GothamBlack
	vRewards.Text = "+150 XP   |   +$250 HERO CASH"
	vRewards.TextColor3 = Color3.fromRGB(255, 215, 65)
	vRewards.TextSize = 16
	vRewards.Parent = vBanner

	local vSub = Instance.new("TextLabel")
	vSub.Name = "VictorySub"
	vSub.Position = UDim2.new(0, 0, 0, 70)
	vSub.Size = UDim2.new(1, 0, 0, 18)
	vSub.BackgroundTransparency = 1
	vSub.Font = Enum.Font.GothamMedium
	vSub.Text = "Neighborhood is safe once again."
	vSub.TextColor3 = Color3.fromRGB(180, 215, 200)
	vSub.TextSize = 12
	vSub.Parent = vBanner

	gui.Parent = PlayerGui

	screenGui = gui
	radioBanner = banner
	radioCodeLabel = codeLabel
	radioSubtitleLabel = subtitleLabel
	waypointMarker = marker
	waypointIconLabel = iconLabel
	waypointTitleLabel = titleLabel
	waypointDistanceLabel = distLabel
	waypointArrow = arrow
	victoryBanner = vBanner
	victoryTitleLabel = vTitle
	victoryRewardsLabel = vRewards
	victorySubLabel = vSub
end

--------------------------------------------------------------------------------
-- 🌐 HOLOGRAPHIC GROUND RING EFFECT
--------------------------------------------------------------------------------

local function createGroundHologramRing(epicenter: Vector3, themeColor: Color3)
	if activeGroundRing then
		activeGroundRing:Destroy()
		activeGroundRing = nil
	end

	local ring = Instance.new("Part")
	ring.Name = "HoloGroundRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 45, 45)
	ring.CFrame = CFrame.new(epicenter + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = themeColor
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.65
	ring.CanCollide = false
	ring.Anchored = true
	ring.Parent = Workspace

	activeGroundRing = ring

	-- Pulsing effect
	task.spawn(function()
		while ring.Parent do
			local t1 = TweenService:Create(ring, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Transparency = 0.85,
				Size = Vector3.new(0.4, 52, 52),
			})
			t1:Play()
			t1.Completed:Wait()
			if not ring.Parent then break end
			local t2 = TweenService:Create(ring, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Transparency = 0.55,
				Size = Vector3.new(0.4, 42, 42),
			})
			t2:Play()
			t2.Completed:Wait()
		end
	end)
end

--------------------------------------------------------------------------------
-- 📢 EVENT HANDLERS & DISPATCH SEQUENCES
--------------------------------------------------------------------------------

-- 🚨 Display Police Dispatch Broadcast
function PoliceRadioHUD.onCrimeSpawned(data: any)
	PoliceRadioHUD.activeCrimeData = data
	PoliceRadioHUD.isCrimeActive = true
	PoliceRadioHUD.isRadioSpeaking = true

	if not screenGui or not radioBanner then
		createHUD()
	end

	if radioBanner and radioCodeLabel and radioSubtitleLabel and waypointIconLabel and waypointTitleLabel then
		radioCodeLabel.Text = string.format("📻 NYPD DISPATCH [%s]", string.upper(data.PoliceCode or "10-31 IN PROGRESS"))
		radioSubtitleLabel.Text = data.DispatchMessage or "Units respond immediately to active incident..."
		waypointIconLabel.Text = data.Icon or "🚨"
		waypointTitleLabel.Text = string.upper(data.Title or "ACTIVE CRIME")

		local stroke = radioBanner:FindFirstChildOfClass("UIStroke")
		if stroke and data.ThemeColor then
			stroke.Color = data.ThemeColor
		end

		if waypointMarker then
			local wpStroke = waypointMarker:FindFirstChildOfClass("UIStroke")
			if wpStroke and data.ThemeColor then
				wpStroke.Color = data.ThemeColor
			end
			waypointMarker.Visible = true
		end

		-- Play sound
		playDispatchSound("RadioSquelch")

		-- Slide Down Animation
		radioBanner.Position = UDim2.new(0.5, 0, -0.25, 0)
		local slideIn = TweenService:Create(radioBanner, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.04, 0),
		})
		slideIn:Play()

		-- Spawn ground hologram
		if data.Epicenter then
			createGroundHologramRing(data.Epicenter, data.ThemeColor or Color3.fromRGB(255, 60, 60))
		end

		-- Keep banner on screen for 6.5s then slide up
		task.delay(6.5, function()
			PoliceRadioHUD.isRadioSpeaking = false
			if radioBanner then
				local slideOut = TweenService:Create(radioBanner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5, 0, -0.25, 0),
				})
				slideOut:Play()
			end
		end)
	end
end

-- 🎉 Display Victory Banner & Rewards Payout
function PoliceRadioHUD.onCrimeCleared(data: any)
	PoliceRadioHUD.isCrimeActive = false
	PoliceRadioHUD.activeCrimeData = nil

	if activeGroundRing then
		activeGroundRing:Destroy()
		activeGroundRing = nil
	end

	if waypointMarker then
		waypointMarker.Visible = false
	end

	if not screenGui or not victoryBanner then
		createHUD()
	end

	if victoryBanner and victoryTitleLabel and victoryRewardsLabel and victorySubLabel then
		local xp = data.RewardXP or 150
		local cash = data.RewardCash or 250
		local pCount = data.ParticipantCount or 1

		victoryTitleLabel.Text = "🎉 CRIME STOPPED!"
		victoryRewardsLabel.Text = string.format("+%d XP   |   +$%d HERO CASH", xp, cash)

		if pCount > 1 then
			victorySubLabel.Text = string.format("🤝 Co-Op Squad Victory! (%d Spider-Heroes +%d%% Team Bonus)", pCount, (pCount - 1) * 25)
		else
			victorySubLabel.Text = "Neighborhood is safe once again."
		end

		playDispatchSound("Victory")

		-- Tactile Slow-Motion Impact
		task.spawn(function()
			-- Micro slow-down effect for punchy reward feeling
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

		-- Victory Banner Pop-In Animation
		victoryBanner.Position = UDim2.new(0.5, 0, -0.3, 0)
		victoryBanner.Size = UDim2.new(0, 420, 0, 76)
		local popIn = TweenService:Create(victoryBanner, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.14, 0),
		})
		popIn:Play()

		-- Dismiss after 4.5s
		task.delay(4.5, function()
			if victoryBanner then
				local popOut = TweenService:Create(victoryBanner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5, 0, -0.3, 0),
				})
				popOut:Play()
			end
		end)
	end
end

-- ❌ Crime Expired/Failed
function PoliceRadioHUD.onCrimeFailed(data: any)
	PoliceRadioHUD.isCrimeActive = false
	PoliceRadioHUD.activeCrimeData = nil

	if activeGroundRing then
		activeGroundRing:Destroy()
		activeGroundRing = nil
	end

	if waypointMarker then
		waypointMarker.Visible = false
	end
end

--------------------------------------------------------------------------------
-- 🔄 RENDERSTEPPED LOOP (3D Waypoint Tracking, Distance & Waveform Animation)
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	local now = os.clock()

	-- 1. Animated Radio Waveform Bars
	if PoliceRadioHUD.isRadioSpeaking and #waveBars > 0 then
		for idx, bar in waveBars do
			local height = 4 + (math.abs(math.sin(now * 14 + (idx * 0.8))) * 18)
			bar.Size = UDim2.new(0, 3, 0, height)
		end
	end

	-- 2. 3D Holographic Waypoint Projection & Screen Clamping
	if PoliceRadioHUD.isCrimeActive and PoliceRadioHUD.activeCrimeData and waypointMarker then
		local epicenter: Vector3 = PoliceRadioHUD.activeCrimeData.Epicenter
		if not epicenter then return end

		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local distStuds = root and (root.Position - epicenter).Magnitude or 100
		local distMeters = math.floor(distStuds / 3)

		if waypointDistanceLabel then
			waypointDistanceLabel.Text = string.format("%dm (%d studs)", distMeters, math.floor(distStuds))
		end

		-- Project world point to 2D screen coordinate
		local targetWorldPos = epicenter + Vector3.new(0, 10, 0)
		local screenPos, onScreen = Camera:WorldToViewportPoint(targetWorldPos)

		local viewportSize = Camera.ViewportSize
		local margin = 70

		if onScreen and screenPos.Z > 0 then
			-- On-screen: Position smoothly above the crime scene
			waypointMarker.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
			if waypointArrow then waypointArrow.Visible = false end
		else
			-- Off-screen: Clamp to edge of screen with pointing arrow
			local center = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
			local dir = (Vector2.new(screenPos.X, screenPos.Y) - center)
			if screenPos.Z < 0 then
				dir = -dir -- Flip when behind camera
			end

			local marginX = math.min(margin, viewportSize.X * 0.4)
			local marginY = math.min(margin, viewportSize.Y * 0.4)
			local minX = marginX
			local maxX = math.max(viewportSize.X - marginX, minX + 1)
			local minY = marginY
			local maxY = math.max(viewportSize.Y - marginY, minY + 1)

			local targetX = (viewportSize.X / 2) + (dir.X * math.max(viewportSize.X / 2 - marginX, 1))
			local targetY = (viewportSize.Y / 2) + (dir.Y * math.max(viewportSize.Y / 2 - marginY, 1))

			local clampedX = math.clamp(targetX, minX, maxX)
			local clampedY = math.clamp(targetY, minY, maxY)

			waypointMarker.Position = UDim2.new(0, clampedX, 0, clampedY)

			if waypointArrow then
				waypointArrow.Visible = true
				local angleRad = math.atan2(dir.Y, dir.X)
				waypointArrow.Rotation = math.deg(angleRad) + 90
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
		if eventType == "CrimeSpawned" then
			PoliceRadioHUD.onCrimeSpawned(data)
		elseif eventType == "CrimeCleared" then
			PoliceRadioHUD.onCrimeCleared(data)
		elseif eventType == "CrimeFailed" then
			PoliceRadioHUD.onCrimeFailed(data)
		elseif eventType == "CoOpScaleActive" then
			if radioBanner and radioCodeLabel and radioSubtitleLabel then
				radioCodeLabel.Text = "🤝 MULTI-HERO CO-OP ACTIVE!"
				radioCodeLabel.TextColor3 = Color3.fromRGB(85, 235, 255)
				radioSubtitleLabel.Text = string.format("%d Spider-Heroes in combat! Enemies reinforced +25%% Team Rewards!", data or 2)
				radioBanner.Position = UDim2.new(0.5, 0, -0.25, 0)
				local slide = TweenService:Create(radioBanner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0.04, 0),
				})
				slide:Play()
				task.delay(4.0, function()
					if radioBanner then
						TweenService:Create(radioBanner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							Position = UDim2.new(0.5, 0, -0.25, 0),
						}):Play()
					end
				end)
			end
		elseif eventType == "VanDisabled" then
			if radioBanner and radioCodeLabel and radioSubtitleLabel then
				radioCodeLabel.Text = "⚡ GETAWAY VAN DISABLED!"
				radioCodeLabel.TextColor3 = Color3.fromRGB(255, 205, 50)
				radioSubtitleLabel.Text = "Suspects bailing out to fight! Neutralize all hostiles!"
				radioBanner.Position = UDim2.new(0.5, 0, -0.25, 0)
				TweenService:Create(radioBanner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0.04, 0),
				}):Play()
				task.delay(3.5, function()
					if radioBanner then
						TweenService:Create(radioBanner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							Position = UDim2.new(0.5, 0, -0.25, 0),
						}):Play()
					end
				end)
			end
		end
	end)
end

PoliceRadioHUD.init()

return PoliceRadioHUD
