--!strict
--[[
	SpiderPhoneHUD.luau
	Master Client Controller for Spider-Man's Stark AR Visor & Spider-Phone Datapad.
	Delegates UI construction and sub-apps to:
	- PhoneUIBuilder: ScreenGui, 3-column datapad chassis, telemetry headers/footers
	- SuitShowcaseView: 3D interactive suit viewport, pedestal, 360° drag rotation
	- FNSMApp: Live city crimes dispatch feed and GPS tracking
	- SuitsApp: Suit wardrobe closet, perk preview, purchase & equip flows
	- MovesApp: Combat moves codex and keybind display
	- ProfileApp: Career stats, rank, and police radio controls
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))

local CameraController = require(script.Parent:WaitForChild("CameraController"))

local SpiderPhone = script.Parent:WaitForChild("SpiderPhone")
local PhoneUIBuilder = require(SpiderPhone:WaitForChild("PhoneUIBuilder"))
local FNSMApp = require(SpiderPhone:WaitForChild("FNSMApp"))
local SuitsApp = require(SpiderPhone:WaitForChild("SuitsApp"))
local MovesApp = require(SpiderPhone:WaitForChild("MovesApp"))
local ProfileApp = require(SpiderPhone:WaitForChild("ProfileApp"))

local SpiderPhoneHUD = {}
SpiderPhoneHUD.isOpen = false
SpiderPhoneHUD.activeTab = "FNSM" :: "FNSM" | "Moves" | "Suits" | "Profile"
SpiderPhoneHUD.isRadioMuted = false

-- 📦 Networking Remotes
local CrimeRemotes = ReplicatedStorage:WaitForChild("CrimeRemotes")
local CrimeNotificationRemote = CrimeRemotes:WaitForChild("CrimeNotification") :: RemoteEvent
local CrimeInteractRemote = CrimeRemotes:WaitForChild("CrimeInteract") :: RemoteEvent
local GetActiveCrimesRF = CrimeRemotes:WaitForChild("GetActiveCrimes") :: RemoteFunction

local SuitRemotes = ReplicatedStorage:WaitForChild("SuitRemotes")
local GetSuitDataRF = SuitRemotes:WaitForChild("GetSuitData") :: RemoteFunction
local SuitPurchaseRF = SuitRemotes:WaitForChild("SuitPurchase") :: RemoteFunction
local SuitEquipRF = SuitRemotes:WaitForChild("SuitEquip") :: RemoteFunction

-- Client Cache
local cachedUnlockedSuits: { [string]: boolean } = { [SuitConfig.DefaultSuitId] = true }
local cachedEquippedSuit: string = SuitConfig.DefaultSuitId

-- UI State References
local uiRefs: PhoneUIBuilder.UIReferences? = nil
local savedWalkSpeed: number? = nil
local savedJumpHeight: number? = nil
local savedJumpPower: number? = nil

-- 🔊 SFX Player
local function playPhoneSound(soundType: "PhoneSlideIn" | "PhoneSlideOut" | "TabClick" | "ButtonClick" | "SuitPurchased" | "SuitEquipped" | "ErrorSound")
	local soundMap = {
		PhoneSlideIn = "rbxassetid://9114223170",
		PhoneSlideOut = "rbxassetid://9114223362",
		TabClick = "rbxassetid://6895079853",
		ButtonClick = "rbxassetid://6895079853",
		SuitPurchased = "rbxassetid://9069609268",
		SuitEquipped = "rbxassetid://9069609438",
		ErrorSound = "rbxassetid://9069609085",
	}

	local soundId = soundMap[soundType]
	if not soundId or soundId == "" then return end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.45
	sound.PlayOnRemove = true
	sound.Parent = Lighting
	sound:Destroy()
end

-- 🛑 Lock / Unlock Character Movement
local function lockMovement(lock: boolean)
	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if lock then
		if savedWalkSpeed == nil then
			savedWalkSpeed = humanoid.WalkSpeed
			savedJumpHeight = humanoid.JumpHeight
			savedJumpPower = humanoid.JumpPower
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	else
		humanoid.WalkSpeed = savedWalkSpeed or 28
		if savedJumpHeight and savedJumpHeight > 0 then
			humanoid.JumpHeight = savedJumpHeight
		end
		if savedJumpPower and savedJumpPower > 0 then
			humanoid.JumpPower = savedJumpPower
		end
		savedWalkSpeed = nil
		savedJumpHeight = nil
		savedJumpPower = nil
	end
end

-- 🌫️ Cinematic Stark Tech Depth Blur
local function getOrCreateBlur(): DepthOfFieldEffect
	local blur = Lighting:FindFirstChild("StarkVisorBlur") :: DepthOfFieldEffect?
	if not blur then
		blur = Instance.new("DepthOfFieldEffect")
		blur.Name = "StarkVisorBlur"
		blur.FarIntensity = 0
		blur.FocusDistance = 0
		blur.InFocusRadius = 0
		blur.NearIntensity = 0
		blur.Parent = Lighting
	end
	return blur
end

local function updateSuitShowcase(specificSuitDef: SuitConfig.SuitDefinition?)
	if not uiRefs then return end
	local targetSuit = specificSuitDef or SuitConfig.getSuitById(cachedEquippedSuit) or SuitConfig.Suits[1]
	uiRefs.SuitShowcase.Update(targetSuit, cachedUnlockedSuits, cachedEquippedSuit)
end

--------------------------------------------------------------------------------
-- 🔄 APP ROUTER & VIEW SWITCHER
--------------------------------------------------------------------------------

function SpiderPhoneHUD.renderActiveApp()
	if not uiRefs then return end
	local contentArea = uiRefs.ContentArea
	contentArea:ClearAllChildren()

	-- Update Cash balance header
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	local cashVal = leaderstats and leaderstats:FindFirstChild("Hero Cash") and (leaderstats["Hero Cash"] :: IntValue).Value or 0
	if uiRefs.CashDisplayLabel then
		uiRefs.CashDisplayLabel.Text = string.format("💰 $%d HERO CASH", cashVal)
	end

	if SpiderPhoneHUD.activeTab == "FNSM" then
		FNSMApp.render(contentArea, {
			GetActiveCrimesRF = GetActiveCrimesRF,
			CrimeInteractRemote = CrimeInteractRemote,
			playPhoneSound = playPhoneSound,
			togglePhone = SpiderPhoneHUD.toggle,
			renderActiveApp = SpiderPhoneHUD.renderActiveApp,
		})
	elseif SpiderPhoneHUD.activeTab == "Moves" then
		MovesApp.render(contentArea)
	elseif SpiderPhoneHUD.activeTab == "Suits" then
		SuitsApp.render(contentArea, {
			GetSuitDataRF = GetSuitDataRF,
			SuitPurchaseRF = SuitPurchaseRF,
			SuitEquipRF = SuitEquipRF,
			cachedUnlockedSuits = cachedUnlockedSuits,
			cachedEquippedSuit = cachedEquippedSuit,
			updateSuitShowcase = updateSuitShowcase,
			renderActiveApp = SpiderPhoneHUD.renderActiveApp,
		})
	elseif SpiderPhoneHUD.activeTab == "Profile" then
		ProfileApp.render(contentArea, {
			cachedEquippedSuit = cachedEquippedSuit,
			isRadioMuted = SpiderPhoneHUD.isRadioMuted,
			onRadioMuteToggled = function(muted: boolean)
				SpiderPhoneHUD.isRadioMuted = muted
				pcall(function()
					local PoliceRadio = require(script.Parent:WaitForChild("PoliceRadioHUD"))
					if PoliceRadio then
						PoliceRadio.isRadioMuted = muted
					end
				end)
			end,
		})
	end
end

function SpiderPhoneHUD.switchTab(tabId: "FNSM" | "Moves" | "Suits" | "Profile")
	SpiderPhoneHUD.activeTab = tabId
	playPhoneSound("TabClick")

	if uiRefs and uiRefs.NavButtons then
		for id, btn in uiRefs.NavButtons do
			local isActive = (id == tabId)
			btn.BackgroundTransparency = isActive and 0.1 or 0.8
			btn.TextColor3 = isActive and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 170, 195)
		end
	end

	SpiderPhoneHUD.renderActiveApp()
end

--------------------------------------------------------------------------------
-- 📱 PHONE OPEN / CLOSE TOGGLE
--------------------------------------------------------------------------------

function SpiderPhoneHUD.toggle(forcedState: boolean?)
	local newState = if forcedState ~= nil then forcedState else not SpiderPhoneHUD.isOpen
	if SpiderPhoneHUD.isOpen == newState then return end
	SpiderPhoneHUD.isOpen = newState

	-- 🔓 Unlock/Lock mouse and shift-lock for UI interaction
	CameraController.setUIMode(newState)

	-- 🛑 Lock character movement (WalkSpeed = 0, Jump = 0)
	lockMovement(newState)

	-- 🌫️ Cinematic Stark Tech Depth Blur
	local blur = getOrCreateBlur()
	TweenService:Create(blur, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		NearIntensity = newState and 0.85 or 0,
	}):Play()

	if not uiRefs then
		SpiderPhoneHUD.init()
	end

	if uiRefs then
		uiRefs.VisorContainer.Visible = newState
		if uiRefs.FloatingOpenButton then
			uiRefs.FloatingOpenButton.Visible = false
		end
	end

	if newState then
		playPhoneSound("PhoneSlideIn")
		SpiderPhoneHUD.renderActiveApp()
		updateSuitShowcase()
	else
		playPhoneSound("PhoneSlideOut")
	end

	-- 🛡️ Isolate Police Radio HUD so it doesn't overlap the visor header
	pcall(function()
		local PoliceRadio = require(script.Parent:WaitForChild("PoliceRadioHUD"))
		if PoliceRadio and (PoliceRadio :: any).setVisorOpen then
			(PoliceRadio :: any).setVisorOpen(newState)
		end
	end)
end

--------------------------------------------------------------------------------
-- 🌐 INITIALIZATION & EVENT LISTENERS
--------------------------------------------------------------------------------

function SpiderPhoneHUD.init()
	if uiRefs then return end

	uiRefs = PhoneUIBuilder.build({
		onToggle = SpiderPhoneHUD.toggle,
		onTabSelected = SpiderPhoneHUD.switchTab,
		activeTab = SpiderPhoneHUD.activeTab,
	})

	-- Auto-refresh active crime data on spawn/clear
	CrimeNotificationRemote.OnClientEvent:Connect(function()
		if SpiderPhoneHUD.isOpen and SpiderPhoneHUD.activeTab == "FNSM" then
			SpiderPhoneHUD.renderActiveApp()
		end
	end)

	-- Keybind Toggles (M Key and Esc Key)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.M then
			SpiderPhoneHUD.toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and SpiderPhoneHUD.isOpen then
			SpiderPhoneHUD.toggle(false)
		end
	end)

	-- Character Respawn Handling
	LocalPlayer.CharacterAdded:Connect(function()
		savedWalkSpeed = nil
		savedJumpHeight = nil
		savedJumpPower = nil
		if SpiderPhoneHUD.isOpen then
			task.defer(function()
				lockMovement(true)
				updateSuitShowcase()
			end)
		end
	end)

	-- Initial View Render
	SpiderPhoneHUD.renderActiveApp()
end

SpiderPhoneHUD.init()

return SpiderPhoneHUD
