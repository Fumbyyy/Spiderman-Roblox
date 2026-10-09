--!strict
--[[
	PoliceRadioHUD.luau
	Master Client Controller for In-Suit Smartphone / Police Radio HUD & Holographic Waypoints.
	Delegates to modular subsystems:
	- RadioUIBuilder: Glassmorphic ScreenGui, CommCard, WaypointMarker, and VictoryBanner
	- WorldBeacon: 3D holographic sky pillar and ground scanner ring
	- WaypointTracker: Mathematical 3D-to-screen projection, elevation tracking, edge clamping
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local PoliceRadio = script.Parent:WaitForChild("PoliceRadio")
local WorldBeacon = require(PoliceRadio:WaitForChild("WorldBeacon"))
local RadioUIBuilder = require(PoliceRadio:WaitForChild("RadioUIBuilder"))
local WaypointTracker = require(PoliceRadio:WaitForChild("WaypointTracker"))

local isUIVisible = not (CombatConfig.CinematicMode == true)
local LocalPlayer = Players.LocalPlayer

export type CrimeData = {
	Id: string?,
	Title: string?,
	PoliceCode: string?,
	DispatchMessage: string?,
	Icon: string?,
	Epicenter: Vector3?,
	ThemeColor: Color3?,
	Timeout: number?,
	RewardXP: number?,
	RewardCash: number?,
	ParticipantCount: number?,
	Reason: string?,
}

local PoliceRadioHUD = {
	activeCrimeData = nil :: CrimeData?,
	isRadioSpeaking = false,
	isCrimeActive = false,
	isRadioMuted = false,
	isVisorOpen = false,
}

local uiRefs: RadioUIBuilder.RadioUIReferences? = nil
local isVictoryBannerShowing = false
local lastLevelUpTime = 0
local activeTypewriterToken = 0

local function playDispatchSound(_soundType: "RadioSquelch" | "Victory" | "Siren")
	-- Zero SFX Policy: Completely silent visual-only dispatch
	return
end

local function runTypewriterDialogue(fullText: string, durationSeconds: number)
	activeTypewriterToken += 1
	local currentToken = activeTypewriterToken
	PoliceRadioHUD.isRadioSpeaking = true

	if uiRefs and uiRefs.IntelDialogueLabel then
		uiRefs.IntelDialogueLabel.Text = fullText
		uiRefs.IntelDialogueLabel.MaxVisibleGraphemes = 0
	end

	local glyphCount = utf8.len(fullText) or string.len(fullText)
	if glyphCount == 0 then
		PoliceRadioHUD.isRadioSpeaking = false
		return
	end

	local stepDelay = math.clamp(durationSeconds / glyphCount, 0.015, 0.065)

	task.spawn(function()
		for i = 1, glyphCount do
			if currentToken ~= activeTypewriterToken then break end
			if uiRefs and uiRefs.IntelDialogueLabel then
				uiRefs.IntelDialogueLabel.MaxVisibleGraphemes = i
			end
			task.wait(stepDelay)
		end

		if currentToken == activeTypewriterToken then
			if uiRefs and uiRefs.IntelDialogueLabel then
				uiRefs.IntelDialogueLabel.MaxVisibleGraphemes = -1
			end
			task.wait(1.5)
			if currentToken == activeTypewriterToken then
				PoliceRadioHUD.isRadioSpeaking = false
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- 🚨 CRIME SPAWNED & RADAR BEACON ACTIVATION
--------------------------------------------------------------------------------

function PoliceRadioHUD.onCrimeSpawned(data: CrimeData)
	PoliceRadioHUD.activeCrimeData = data
	PoliceRadioHUD.isCrimeActive = true

	if not uiRefs then
		PoliceRadioHUD.init()
	end
	if not uiRefs then return end

	local themeColor = data.ThemeColor or Color3.fromRGB(255, 75, 75)
	local pCode = string.upper(data.PoliceCode or "10-31 IN PROGRESS")
	local cTitle = string.upper(data.Title or "ACTIVE CRIME")

	uiRefs.IntelSubheadLabel.Text = string.format("%s %s • %s", data.Icon or "🚨", pCode, cTitle)
	uiRefs.IntelSubheadLabel.TextColor3 = themeColor
	uiRefs.CommCardStroke.Color = themeColor
	uiRefs.WaypointIconLabel.Text = data.Icon or "🚨"
	uiRefs.WaypointTitleLabel.Text = cTitle
	uiRefs.WaypointMarkerStroke.Color = themeColor
	uiRefs.WaypointMarker.Visible = isUIVisible and (not PoliceRadioHUD.isVisorOpen)
	uiRefs.PointerArrow.ImageColor3 = themeColor
	uiRefs.PointerArrow.Visible = isUIVisible and (not PoliceRadioHUD.isVisorOpen)

	if data.Epicenter and isUIVisible then
		WorldBeacon.create(data.Epicenter, themeColor, isUIVisible)
	end

	if isUIVisible and not PoliceRadioHUD.isRadioMuted and not PoliceRadioHUD.isVisorOpen then
		playDispatchSound("RadioSquelch")

		local card = uiRefs.CommCard
		card.Visible = true
		card.Position = UDim2.new(0.5, 0, 0, -120)
		TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, 20),
		}):Play()

		local intelMsg = data.DispatchMessage or "Spider-Man, active incident in progress! Move to intercept immediately."
		task.spawn(function()
			runTypewriterDialogue(intelMsg, 4.5)
		end)

		task.delay(7.5, function()
			if uiRefs and uiRefs.CommCard and PoliceRadioHUD.isCrimeActive then
				TweenService:Create(uiRefs.CommCard, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5, 0, 0, -120),
				}):Play()
			end
		end)
	end
end

-- 🚨 Display Victory Banner & Rewards Payout
function PoliceRadioHUD.onCrimeCleared(data: CrimeData)
	local CombatStyleHUD = require(script.Parent:WaitForChild("CombatStyleHUD"))
	CombatStyleHUD.hideAbilityTray(true)
	CombatStyleHUD.resetCombo()

	PoliceRadioHUD.isCrimeActive = false
	PoliceRadioHUD.activeCrimeData = nil
	PoliceRadioHUD.isRadioSpeaking = false
	activeTypewriterToken += 1

	WorldBeacon.cleanup()
	WaypointTracker.resetMode()

	if uiRefs then
		uiRefs.WaypointMarker.Visible = false
		uiRefs.PointerArrow.Visible = false
		TweenService:Create(uiRefs.CommCard, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -120),
		}):Play()
	end

	if not isUIVisible or not uiRefs then return end

	local xp = data.RewardXP or 150
	local cash = data.RewardCash or 250
	local pCount = data.ParticipantCount or 1

	uiRefs.VictoryTitleLabel.Text = "🚨 SECTOR SECURED"
	uiRefs.VictoryRewardsLabel.Text = string.format("+$%d HERO CASH   //   +%d XP", cash, xp)

	if pCount > 1 then
		uiRefs.VictorySubLabel.Text = string.format("CO-OP SQUAD VICTORY • %d HEROES (+%d%% TEAM BONUS)", pCount, (pCount - 1) * 25)
	else
		uiRefs.VictorySubLabel.Text = "STREET PATROL ACTIVE • MANHATTAN SAFE"
	end

	playDispatchSound("Victory")

	task.spawn(function()
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

	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local isLevelUpActive = (playerGui and playerGui:FindFirstChild("LevelUpFanfareGui") ~= nil) or ((os.clock() - lastLevelUpTime) < 3.5)
	local targetY = if isLevelUpActive then 140 else 38
	local targetPos = UDim2.new(0.5, 0, 0, targetY)

	isVictoryBannerShowing = true
	local banner = uiRefs.VictoryBanner
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -100)
	banner.Size = UDim2.new(0, 420, 0, 78)

	TweenService:Create(banner, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = targetPos,
	}):Play()

	task.delay(4.5, function()
		if uiRefs and uiRefs.VictoryBanner then
			isVictoryBannerShowing = false
			TweenService:Create(uiRefs.VictoryBanner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, 0, 0, -100),
			}):Play()
		end
	end)
end

function PoliceRadioHUD.onCrimeFailed(_data: CrimeData)
	PoliceRadioHUD.isCrimeActive = false
	PoliceRadioHUD.activeCrimeData = nil
	PoliceRadioHUD.isRadioSpeaking = false
	activeTypewriterToken += 1

	WorldBeacon.cleanup()
	WaypointTracker.resetMode()

	if uiRefs then
		uiRefs.WaypointMarker.Visible = false
		uiRefs.PointerArrow.Visible = false
		TweenService:Create(uiRefs.CommCard, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -120),
		}):Play()
	end
end

function PoliceRadioHUD.setVisorOpen(isOpen: boolean)
	PoliceRadioHUD.isVisorOpen = isOpen
	if uiRefs then
		uiRefs.CommCard.Visible = not isOpen
		uiRefs.WaypointMarker.Visible = not isOpen and PoliceRadioHUD.isCrimeActive and isUIVisible
		uiRefs.PointerArrow.Visible = not isOpen and PoliceRadioHUD.isCrimeActive and isUIVisible
	end
end

function PoliceRadioHUD.setUIVisible(visible: boolean)
	isUIVisible = visible
	if uiRefs and uiRefs.ScreenGui then
		uiRefs.ScreenGui.Enabled = visible
	end
	if not visible then
		WorldBeacon.cleanup()
		if uiRefs then
			uiRefs.CommCard.Visible = false
			uiRefs.WaypointMarker.Visible = false
			uiRefs.PointerArrow.Visible = false
			uiRefs.VictoryBanner.Visible = false
		end
	else
		if PoliceRadioHUD.isCrimeActive and PoliceRadioHUD.activeCrimeData and PoliceRadioHUD.activeCrimeData.Epicenter then
			WorldBeacon.create(PoliceRadioHUD.activeCrimeData.Epicenter, PoliceRadioHUD.activeCrimeData.ThemeColor or Color3.fromRGB(255, 75, 75), true)
		end
	end
end

--------------------------------------------------------------------------------
-- 🔄 RENDERSTEPPED LOOP (3D Waypoint Tracking, Elevation & Equalizer Waveform)
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if not isUIVisible or not uiRefs then
		if uiRefs then
			if uiRefs.WaypointMarker.Visible then uiRefs.WaypointMarker.Visible = false end
			if uiRefs.PointerArrow.Visible then uiRefs.PointerArrow.Visible = false end
		end
		WorldBeacon.cleanup()
		return
	end

	local now = os.clock()

	-- 1. Animated Radio Waveform Bars (Dynamic Equalizer)
	if #uiRefs.WaveBars > 0 then
		if PoliceRadioHUD.isRadioSpeaking then
			for idx, bar in uiRefs.WaveBars do
				local freq = math.abs(math.sin((now * 16) + (idx * 0.9))) * 11 + 3
				bar.Size = UDim2.new(0, 3, 0, freq)
			end
		else
			for _, bar in uiRefs.WaveBars do
				bar.Size = UDim2.new(0, 3, 0, 3)
			end
		end
	end

	-- 2. 3D Holographic Waypoint Projection with Elevation Tracking & Smooth Edge Clamping
	if PoliceRadioHUD.isCrimeActive and PoliceRadioHUD.activeCrimeData and uiRefs.WaypointMarker then
		local epicenter = PoliceRadioHUD.activeCrimeData.Epicenter
		if epicenter then
			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local playerPos = root and root.Position or Vector3.zero
			local isCommCardVisible = (uiRefs.CommCard.Position.Y.Offset > 0)

			WaypointTracker.update(
				uiRefs.WaypointMarker,
				uiRefs.WaypointMarkerStroke,
				uiRefs.WaypointTitleLabel,
				uiRefs.WaypointIconLabel,
				uiRefs.WaypointDistLabel,
				uiRefs.PointerArrow,
				epicenter,
				playerPos,
				isCommCardVisible,
				PoliceRadioHUD.isVisorOpen
			)

			WorldBeacon.updateDistanceFade(playerPos, epicenter)
		end
	end
end)

--------------------------------------------------------------------------------
-- 🌐 INITIALIZATION & EVENT LISTENERS
--------------------------------------------------------------------------------

function PoliceRadioHUD.init()
	if uiRefs then return end
	uiRefs = RadioUIBuilder.build(isUIVisible)

	local remotesFolder = ReplicatedStorage:WaitForChild("CrimeRemotes")
	local notificationRemote = remotesFolder:WaitForChild("CrimeNotification") :: RemoteEvent

	notificationRemote.OnClientEvent:Connect(function(eventType: string, data: any)
		if eventType == "LevelUp" then
			lastLevelUpTime = os.clock()
			if uiRefs and uiRefs.VictoryBanner and isVictoryBannerShowing then
				TweenService:Create(uiRefs.VictoryBanner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0, 140),
				}):Play()
			end
		elseif eventType == "CrimeSpawned" then
			PoliceRadioHUD.onCrimeSpawned(data :: CrimeData)
		elseif eventType == "CrimeCleared" then
			PoliceRadioHUD.onCrimeCleared(data :: CrimeData)
		elseif eventType == "CrimeFailed" then
			PoliceRadioHUD.onCrimeFailed(data :: CrimeData)
		elseif eventType == "CoOpScaleActive" then
			if uiRefs and uiRefs.CommCard and uiRefs.IntelSubheadLabel then
				uiRefs.IntelSubheadLabel.Text = "🤝 CO-OP ACTIVE • +25% BONUS"
				uiRefs.IntelSubheadLabel.TextColor3 = Color3.fromRGB(85, 235, 255)

				uiRefs.CommCard.Position = UDim2.new(0.5, 0, 0, -80)
				TweenService:Create(uiRefs.CommCard, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0, 20),
				}):Play()

				task.delay(4.0, function()
					if uiRefs and uiRefs.CommCard then
						TweenService:Create(uiRefs.CommCard, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							Position = UDim2.new(0.5, 0, 0, -80),
						}):Play()
					end
				end)
			end
		elseif eventType == "VanDisabled" then
			if uiRefs and uiRefs.CommCard and uiRefs.IntelSubheadLabel and uiRefs.IntelDialogueLabel then
				uiRefs.IntelSubheadLabel.Text = "⚡ GETAWAY VAN ENGINE DISABLED!"
				uiRefs.IntelSubheadLabel.TextColor3 = Color3.fromRGB(255, 205, 50)
				uiRefs.IntelDialogueLabel.MaxVisibleGraphemes = -1
				uiRefs.IntelDialogueLabel.Text = "Great work! Suspects are bailing out of the vehicle. Neutralize all remaining hostiles to secure the stolen tech!"

				uiRefs.CommCard.Position = UDim2.new(0.5, 0, 0, -80)
				TweenService:Create(uiRefs.CommCard, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0, 20),
				}):Play()

				task.delay(4.0, function()
					if uiRefs and uiRefs.CommCard then
						TweenService:Create(uiRefs.CommCard, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							Position = UDim2.new(0.5, 0, 0, -80),
						}):Play()
					end
				end)
			end
		end
	end)
end

PoliceRadioHUD.init()

return PoliceRadioHUD
