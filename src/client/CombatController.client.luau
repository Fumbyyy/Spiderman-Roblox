--!strict
--[[
	CombatController.client.luau
	Central Client Controller for Spider-Man 6-Move Combat System:
	- 🥊 Move 1: Kinetic Strike Combo (L-Click Tap 1-2-3) [CombatMelee]
	- 🚀 Move 1b: Uppercut Launcher (L-Click Hold) [CombatMelee]
	- 💥 Move 1c: Web Ground Slam (In-Air L-Click) [CombatMelee]
	- 🕸️ Move 2: Rapid Web-Pellets & Wall-Pinning (E Key) [CombatWebs]
	- 🔫 Move 3: Web-Yank Disarm & Spiral Throw (Q Key) [CombatWebs]
	- ⚡ Move 4: Spider-Sense Acrobatic Dodge (F Key) [CombatDodge]
	- 🚀 Move 5: Web-Strike Zip Kick (R Key) [CombatWebs]
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Config & Remotes
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local SuitConfig = require(Shared:WaitForChild("SuitConfig"))
local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local CombatVFXRemote = RemotesFolder:WaitForChild("CombatVFX") :: RemoteEvent

local SuitRemotes = ReplicatedStorage:WaitForChild("SuitRemotes")
local SuitEquipRF = SuitRemotes:WaitForChild("SuitEquip") :: RemoteFunction
local GetSuitDataRF = SuitRemotes:WaitForChild("GetSuitData") :: RemoteFunction

-- Modular Combat Sub-Controllers
local ModulesFolder = script.Parent:WaitForChild("Modules")
local CombatReticle = require(ModulesFolder:WaitForChild("CombatReticle"))
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))
local CombatMelee = require(ModulesFolder:WaitForChild("CombatMelee"))
local CombatWebs = require(ModulesFolder:WaitForChild("CombatWebs"))
local CombatDodge = require(ModulesFolder:WaitForChild("CombatDodge"))
local CombatVFXListener = require(ModulesFolder:WaitForChild("CombatVFXListener"))
local CombatStyleHUD = require(ModulesFolder:WaitForChild("CombatStyleHUD"))
local CombatUltimate = require(ModulesFolder:WaitForChild("CombatUltimate"))
local CameraController = require(ModulesFolder:WaitForChild("CameraController"))
local PoliceRadioHUD = require(ModulesFolder:WaitForChild("PoliceRadioHUD"))
local SpiderPhoneHUD = require(ModulesFolder:WaitForChild("SpiderPhoneHUD"))
local LevelUpCelebration = require(ModulesFolder:WaitForChild("LevelUpCelebration"))
local PlayerHealthHUD = require(ModulesFolder:WaitForChild("PlayerHealthHUD"))
local TargetFinder = require(ModulesFolder:WaitForChild("TargetFinder"))

local lastCombatActionTime = 0
local function registerCombatAction()
	lastCombatActionTime = os.clock()
	CombatStyleHUD.unlockAbilityTray()
end

-- Traversal and Combat Action Lock Guards
local function isTraversing(rootPart: BasePart?): boolean
	if not rootPart then return false end
	return (rootPart:FindFirstChild("WebSwingVelocity") ~= nil)
		or (rootPart:FindFirstChild("SlingshotVelocity") ~= nil)
		or (rootPart:FindFirstChild("WallRunVelocity") ~= nil)
		or (rootPart:FindFirstChild("GlidingVelocity") ~= nil)
		or (rootPart:FindFirstChild("WebGlideVelocity") ~= nil)
end

local function isCombatBusy(): boolean
	local isUlting = (CombatUltimate.isUlting == true) or (CombatUltimate.isExecutingUltimate == true)
	return (CombatWebs.isWebStriking == true)
		or (CombatWebs.isYankingProp == true)
		or (isUlting == true)
		or (CombatDodge.isDodging == true)
end

-- 🦘 Jump & Airborne Tracking (Strictly prevents accidental ground slams when stepping/climbing on mobs)
local lastJumpTime = 0
UserInputService.JumpRequest:Connect(function()
	lastJumpTime = os.clock()
end)

local function isTrulyAirborne(rootPart: BasePart, character: Model, humanoid: Humanoid): boolean
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return false
	end

	local now = os.clock()
	local recentJump = (now - lastJumpTime) < 1.25

	-- Raycast down to find true map geometry beneath Spidey (filtering out character and all enemies)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList: { Instance } = { character }
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if enemiesFolder then
		table.insert(filterList, enemiesFolder)
	end
	for _, enemy in CollectionService:GetTagged("Enemy") do
		table.insert(filterList, enemy)
	end
	rayParams.FilterDescendantsInstances = filterList

	local groundRay = Workspace:Raycast(rootPart.Position, Vector3.new(0, -20, 0), rayParams)
	local distToGround = groundRay and (rootPart.Position.Y - groundRay.Position.Y) or 999

	-- Standing height is ~3.0 studs. If stepping/climbing onto an enemy, distToGround is ~3.5 to 5.0 studs.
	-- If the player did not jump and is within 5.2 studs of the ground, they are just stepping on an enemy mob: STAY IN GROUND COMBAT!
	if not recentJump and distToGround <= 5.2 then
		return false
	end

	-- Jumped recently and genuinely clearing the ground
	if recentJump and distToGround > 3.8 then
		return true
	end

	-- High freefall (falling off rooftop or out of swing)
	if distToGround > 5.5 then
		return true
	end

	return false
end

-- Character Utility Helper
local function getCharacterParts(): (Model?, BasePart?, Humanoid?)
	local character = LocalPlayer.Character
	if not character then return nil, nil, nil end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Prevent accidental physics tripping/ragdolling during ground combat maneuvers
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
	return character, rootPart, humanoid
end

-- Track Damage to drop combo on hit
local lastPlayerHealth = 100
local lastSuitSwapTime = 0

local function onCharacterSpawn(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	lastPlayerHealth = hum.Health
	hum.HealthChanged:Connect(function(newHealth)
		-- Ignore health drops caused by switching away from bonus-HP suits (MK IV)
		if (os.clock() - lastSuitSwapTime) < 0.45 then
			lastPlayerHealth = newHealth
			return
		end
		if newHealth < lastPlayerHealth then
			local damageTaken = lastPlayerHealth - newHealth
			local hasDefenseSuperArmor = (LocalPlayer:GetAttribute("SuitPerkType") == "Defense")
			if not (hasDefenseSuperArmor and damageTaken < 25) then
				CombatStyleHUD.onTakeDamage()
			end
			registerCombatAction()
		end
		lastPlayerHealth = newHealth
	end)
end

if LocalPlayer.Character then onCharacterSpawn(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(onCharacterSpawn)

-- Initialize Multiplayer VFX Listener
CombatVFXListener.init(CombatVFXRemote, Camera, getCharacterParts)
PlayerHealthHUD.init(PlayerGui, LocalPlayer)

-- Spider-Sense Threat Detection State
local activeThreatEnemy: Model? = nil
local lastThreatDetectionTime = 0

-- 🎬 Clean Recording Mode (Ctrl + H: Hide/Restore CoreGui Chat & PlayerList)
local isRecordingModeActive = false
local function toggleCleanRecordingMode()
	isRecordingModeActive = not isRecordingModeActive
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, not isRecordingModeActive)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not isRecordingModeActive)
	end)
end


--------------------------------------------------------------------------------
-- 🎮 USER INPUT HANDLING (Dedicated Controls: Left-Click, E, R, F, T, H)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- DISABLE DEFAULT BACKPACK GUI (Frees Keys 1-6 for Suit Shifting)
--------------------------------------------------------------------------------

task.spawn(function()
	for _ = 1, 10 do
		local success = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if success then break end
		task.wait(0.2)
	end
end)

--------------------------------------------------------------------------------
-- MID-COMBAT SUIT HOTKEYS (1-6 & V Cycle) & HOLOGRAPHIC SHIFT TOAST
--------------------------------------------------------------------------------

local SUIT_KEY_MAP: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "ClassicSuit",
	[Enum.KeyCode.Two] = "StarkTechSuit",
	[Enum.KeyCode.Three] = "MilesSpiderVerse",
	[Enum.KeyCode.Four] = "SymbioteBlack",
	[Enum.KeyCode.Five] = "ScarletSpider",
	[Enum.KeyCode.Six] = "Cyber2099",
}

local CANONICAL_SUIT_ORDER = {
	"ClassicSuit",
	"StarkTechSuit",
	"MilesSpiderVerse",
	"SymbioteBlack",
	"ScarletSpider",
	"Cyber2099",
}

local cachedUnlockedSuits: { [string]: boolean } = {
	["ClassicSuit"] = true,
}

local function refreshUnlockedSuits()
	task.spawn(function()
		local ok, unlocked = pcall(function()
			return GetSuitDataRF:InvokeServer()
		end)
		if ok and typeof(unlocked) == "table" then
			for suitId, isUnlocked in unlocked do
				if isUnlocked then
					cachedUnlockedSuits[suitId] = true
				end
			end
		end
		if RunService:IsStudio() then
			for _, id in CANONICAL_SUIT_ORDER do
				cachedUnlockedSuits[id] = true
			end
		end
	end)
end
refreshUnlockedSuits()

-- Holographic Shift Toast Singleton UI (DisplayOrder 45, Top-Center at Y: 85)
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "SuitShiftToastGui"
toastGui.ResetOnSpawn = false
toastGui.DisplayOrder = 45
toastGui.Parent = PlayerGui

local toastFrame = Instance.new("Frame")
toastFrame.Name = "ShiftToastFrame"
toastFrame.AnchorPoint = Vector2.new(0.5, 0)
toastFrame.Position = UDim2.new(0.5, 0, 0, 85)
toastFrame.Size = UDim2.new(0, 310, 0, 44)
toastFrame.BackgroundColor3 = Color3.fromRGB(10, 16, 26)
toastFrame.BackgroundTransparency = 1
toastFrame.BorderSizePixel = 0
toastFrame.Visible = false
toastFrame.Parent = toastGui

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 7)
toastCorner.Parent = toastFrame

local toastStroke = Instance.new("UIStroke")
toastStroke.Name = "ToastStroke"
toastStroke.Thickness = 1.4
toastStroke.Transparency = 1
toastStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
toastStroke.Parent = toastFrame

local accentBar = Instance.new("Frame")
accentBar.Name = "AccentBar"
accentBar.AnchorPoint = Vector2.new(0, 0.5)
accentBar.Position = UDim2.new(0, 6, 0.5, 0)
accentBar.Size = UDim2.new(0, 3.5, 1, -12)
accentBar.BorderSizePixel = 0
accentBar.BackgroundTransparency = 1
accentBar.Parent = toastFrame

local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(0, 2)
accentCorner.Parent = accentBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 16, 0, 6)
titleLabel.Size = UDim2.new(1, -22, 0, 15)
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextSize = 12
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextTransparency = 1
titleLabel.Parent = toastFrame

local perkLabel = Instance.new("TextLabel")
perkLabel.Name = "PerkLabel"
perkLabel.BackgroundTransparency = 1
perkLabel.Position = UDim2.new(0, 16, 0, 22)
perkLabel.Size = UDim2.new(1, -22, 0, 14)
perkLabel.Font = Enum.Font.GothamBold
perkLabel.TextSize = 9.5
perkLabel.TextColor3 = Color3.fromRGB(225, 235, 245)
perkLabel.TextXAlignment = Enum.TextXAlignment.Left
perkLabel.TextTransparency = 1
perkLabel.Parent = toastFrame

local activeToastToken = 0
local activeToastTweens: { Tween } = {}

local function cancelToastTweens()
	for _, tw in activeToastTweens do
		tw:Cancel()
	end
	table.clear(activeToastTweens)
end

local function showSuitShiftToast(suit: any)
	activeToastToken += 1
	local currentToken = activeToastToken
	cancelToastTweens()

	local themeColor = suit.ThemeColor or Color3.fromRGB(80, 220, 255)
	toastStroke.Color = themeColor
	accentBar.BackgroundColor3 = themeColor
	titleLabel.TextColor3 = themeColor
	titleLabel.Text = string.format("🧬 SUIT SHIFT // %s", string.upper(suit.Name))
	perkLabel.Text = string.format("● PERK: %s", suit.PerkDescription)

	-- Start state (offset upwards for dynamic slide-in)
	toastFrame.Position = UDim2.new(0.5, 0, 0, 72)
	toastFrame.BackgroundTransparency = 1
	toastStroke.Transparency = 1
	accentBar.BackgroundTransparency = 1
	titleLabel.TextTransparency = 1
	perkLabel.TextTransparency = 1
	toastFrame.Visible = true

	-- Phase 1: Animate In (0.2s)
	local tweenInfoIn = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local twPosIn = TweenService:Create(toastFrame, tweenInfoIn, { Position = UDim2.new(0.5, 0, 0, 85) })
	local twBgIn = TweenService:Create(toastFrame, tweenInfoIn, { BackgroundTransparency = 0.15 })
	local twStrokeIn = TweenService:Create(toastStroke, tweenInfoIn, { Transparency = 0.2 })
	local twAccentIn = TweenService:Create(accentBar, tweenInfoIn, { BackgroundTransparency = 0.1 })
	local twTitleIn = TweenService:Create(titleLabel, tweenInfoIn, { TextTransparency = 0 })
	local twPerkIn = TweenService:Create(perkLabel, tweenInfoIn, { TextTransparency = 0.05 })

	table.insert(activeToastTweens, twPosIn)
	table.insert(activeToastTweens, twBgIn)
	table.insert(activeToastTweens, twStrokeIn)
	table.insert(activeToastTweens, twAccentIn)
	table.insert(activeToastTweens, twTitleIn)
	table.insert(activeToastTweens, twPerkIn)

	twPosIn:Play()
	twBgIn:Play()
	twStrokeIn:Play()
	twAccentIn:Play()
	twTitleIn:Play()
	twPerkIn:Play()

	-- Phase 2: Hold for 0.8s, then Phase 3: Animate Out (0.2s) -> Total 1.2s lifespan
	task.delay(1.0, function()
		if activeToastToken ~= currentToken then return end
		cancelToastTweens()

		local tweenInfoOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local twPosOut = TweenService:Create(toastFrame, tweenInfoOut, { Position = UDim2.new(0.5, 0, 0, 75) })
		local twBgOut = TweenService:Create(toastFrame, tweenInfoOut, { BackgroundTransparency = 1 })
		local twStrokeOut = TweenService:Create(toastStroke, tweenInfoOut, { Transparency = 1 })
		local twAccentOut = TweenService:Create(accentBar, tweenInfoOut, { BackgroundTransparency = 1 })
		local twTitleOut = TweenService:Create(titleLabel, tweenInfoOut, { TextTransparency = 1 })
		local twPerkOut = TweenService:Create(perkLabel, tweenInfoOut, { TextTransparency = 1 })

		table.insert(activeToastTweens, twPosOut)
		table.insert(activeToastTweens, twBgOut)
		table.insert(activeToastTweens, twStrokeOut)
		table.insert(activeToastTweens, twAccentOut)
		table.insert(activeToastTweens, twTitleOut)
		table.insert(activeToastTweens, twPerkOut)

		twPosOut:Play()
		twBgOut:Play()
		twStrokeOut:Play()
		twAccentOut:Play()
		twTitleOut:Play()
		twPerkOut:Play()

		task.delay(0.22, function()
			if activeToastToken == currentToken then
				toastFrame.Visible = false
			end
		end)
	end)
end

local SUIT_SWAP_COOLDOWN = 0.75

local function requestSuitSwap(targetSuitId: string)
	local now = os.clock()
	if (now - lastSuitSwapTime) < SUIT_SWAP_COOLDOWN then
		return
	end

	local suitDef = SuitConfig.getSuitById(targetSuitId)
	if not suitDef then return end
	local canonicalTargetId = suitDef.Id

	local currentSuitId = LocalPlayer:GetAttribute("EquippedSuit") or SuitConfig.DefaultSuitId
	if currentSuitId == canonicalTargetId then
		return
	end

	lastSuitSwapTime = now

	-- Immediate Holographic Shift Toast
	showSuitShiftToast(suitDef)

	-- Asynchronous server equip invocation (Zero input or physics stalling)
	task.spawn(function()
		local ok, success, msg = pcall(function()
			return SuitEquipRF:InvokeServer(canonicalTargetId)
		end)
		if ok and success then
			cachedUnlockedSuits[canonicalTargetId] = true
		end
	end)
end

local function cycleNextOwnedSuit()
	local currentSuitId = LocalPlayer:GetAttribute("EquippedSuit") or SuitConfig.DefaultSuitId
	local suitDef = SuitConfig.getSuitById(currentSuitId)
	local currentCanonical = suitDef and suitDef.Id or SuitConfig.DefaultSuitId

	local currentIndex = 1
	for idx, id in CANONICAL_SUIT_ORDER do
		if id == currentCanonical then
			currentIndex = idx
			break
		end
	end

	for step = 1, #CANONICAL_SUIT_ORDER do
		local nextIdx = ((currentIndex - 1 + step) % #CANONICAL_SUIT_ORDER) + 1
		local candidateId = CANONICAL_SUIT_ORDER[nextIdx]
		if RunService:IsStudio() or cachedUnlockedSuits[candidateId] == true then
			requestSuitSwap(candidateId)
			break
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- 🎬 Clean Recording Mode Toggle (Ctrl + H)
	if input.KeyCode == Enum.KeyCode.H and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
		toggleCleanRecordingMode()
		return
	end

	if gameProcessed or SpiderPhoneHUD.isOpen then return end

	-- 🧬 Mid-Combat Direct Suit Selection (Keys 1-6) & Tactical Cycle Key (V)
	local mappedSuit = SUIT_KEY_MAP[input.KeyCode]
	if mappedSuit then
		requestSuitSwap(mappedSuit)
		return
	elseif input.KeyCode == Enum.KeyCode.V then
		cycleNextOwnedSuit()
		return
	end

	local character, rootPart, humanoid = getCharacterParts()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then return end

	-- 🥊 Left-Click: Tap for Combo (1-2-3), Hold for Uppercut, In-Air for Ground Slam
	if input.UserInputType == (CombatConfig.Keybinds.Attack or Enum.UserInputType.MouseButton1) then
		if isCombatBusy() or isTraversing(rootPart) then return end
		CombatWebs.isHoldingWebPellet = false
		registerCombatAction()

		local isAirborne = isTrulyAirborne(rootPart, character, humanoid)
		if isAirborne then
			CombatMelee.performAirGroundSlam(character, rootPart, humanoid, CombatWebs.createCombatWebLines)
		else
			CombatMelee.isHoldingAttack = true
			CombatMelee.attackPressStartTime = os.clock()
		end

	-- E Key -> Contextual Smart Web Shooters (Rapid Web Pellets / Disarm Snipers)
	elseif input.KeyCode == (CombatConfig.Keybinds.WebGadget or Enum.KeyCode.E) then
		if isCombatBusy() or isTraversing(rootPart) then return end
		if CombatMelee.isHoldingAttack or (os.clock() - CombatMelee.lastMeleeActionTime) < 0.22 then return end
		registerCombatAction()

		CombatWebs.performSmartWebGadget(character, rootPart, humanoid, Camera, CombatMelee.isHoldingAttack, CombatMelee.lastMeleeActionTime)

		-- Continuous rapid web shooting loop while holding E
		CombatWebs.isHoldingWebPellet = true
		task.spawn(function()
			while CombatWebs.isHoldingWebPellet do
				local isClassic = (LocalPlayer:GetAttribute("EquippedSuit") == "ClassicSuit")
				task.wait(if isClassic then 0.16 else (CombatConfig.Moves.WebPellet.Cooldown or 0.24))
				if CombatWebs.isHoldingWebPellet and not CombatMelee.isHoldingAttack and (os.clock() - CombatMelee.lastMeleeActionTime) >= 0.22 then
					local char, root, hum = getCharacterParts()
					if char and root and hum and hum.Health > 0 and not isCombatBusy() and not isTraversing(root) then
						CombatWebs.performWebPellet(char, root, hum, Camera, CombatMelee.isHoldingAttack, CombatMelee.lastMeleeActionTime)
					else
						CombatWebs.isHoldingWebPellet = false
						break
					end
				end
			end
		end)

	-- Q Key -> Contextual Web-Yank & Prop Throw (or Disarm Sniper)
	elseif input.KeyCode == (CombatConfig.Keybinds.PropThrow or Enum.KeyCode.Q) then
		if isCombatBusy() or isTraversing(rootPart) then return end
		if CombatMelee.isHoldingAttack or (os.clock() - CombatMelee.lastMeleeActionTime) < 0.22 then return end
		registerCombatAction()
		CombatWebs.performPropThrow(character, rootPart, humanoid, Camera)

	-- R Key -> Web-Strike Zip Dropkick (Target-Gated: Never cancels swing without a target!)
	elseif input.KeyCode == (CombatConfig.Keybinds.WebStrike or Enum.KeyCode.R) then
		if isCombatBusy() then return end

		local target = CombatReticle.getCurrentTarget()
		if not target then
			target = CombatWebs.findEnemyInCone(rootPart, Camera, 95, 0.40, false)
		end

		if target then
			if isTraversing(rootPart) then
				local swingVel = rootPart:FindFirstChild("WebSwingVelocity")
				if swingVel then swingVel:Destroy() end
				local slingVel = rootPart:FindFirstChild("SlingshotVelocity")
				if slingVel then slingVel:Destroy() end
				local glideVel = rootPart:FindFirstChild("WebGlideVelocity")
				if glideVel then glideVel:Destroy() end
			end
			registerCombatAction()
			CombatWebs.performWebStrike(character, rootPart, humanoid, Camera)
		end

	-- F Key -> Spider-Sense Perfect Dodge & Face-Web Counter (Ground Combat Only!)
	elseif input.KeyCode == (CombatConfig.Keybinds.Dodge or Enum.KeyCode.F) then
		if humanoid.FloorMaterial == Enum.Material.Air then return end
		if isCombatBusy() or isTraversing(rootPart) then return end
		registerCombatAction()
		activeThreatEnemy = CombatDodge.performSpiderSenseDodge(character, rootPart, humanoid, Camera, activeThreatEnemy)

	-- T Key -> Continuous 360-degree Web Cyclone DPS Blender
	elseif input.KeyCode == (CombatConfig.Keybinds.Ultimate or Enum.KeyCode.T) then
		if isCombatBusy() or isTraversing(rootPart) then return end
		registerCombatAction()
		CombatUltimate.performWebCyclone(character, rootPart, humanoid, Camera)
	end
end)

UserInputService.InputEnded:Connect(function(input, _)
	-- Left Click Released -> Check if Tap (Combo) or Hold (Uppercut)
	if input.UserInputType == (CombatConfig.Keybinds.Attack or Enum.UserInputType.MouseButton1) and CombatMelee.isHoldingAttack then
		CombatMelee.isHoldingAttack = false
		local holdDuration = os.clock() - CombatMelee.attackPressStartTime
		local character, rootPart, humanoid = getCharacterParts()
		if not character or not rootPart or not humanoid or humanoid.Health <= 0 then return end

		if holdDuration >= (CombatConfig.Targeting.HoldThreshold or 0.22) then
			CombatMelee.performUppercutLauncher(character, rootPart, humanoid)
		else
			CombatMelee.performKineticCombo(character, rootPart, humanoid, Camera)
		end

	-- E Key Released -> Stop continuous rapid web shooting
	elseif input.KeyCode == (CombatConfig.Keybinds.WebGadget or Enum.KeyCode.E) then
		CombatWebs.isHoldingWebPellet = false
	end
end)

--------------------------------------------------------------------------------
-- 🔄 RENDERSTEPPED LOOP (Combat State, Target HUD, Reticle & Spider-Sense)
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	local character, rootPart, humanoid = getCharacterParts()
	if rootPart and humanoid and humanoid.Health > 0 then
		Camera = Workspace.CurrentCamera or Camera
		local isPhoneOpen = SpiderPhoneHUD.isOpen
		local inCombat = (os.clock() - lastCombatActionTime) < 4.5 and not isPhoneOpen
		CameraController.setCombatLocked(inCombat)

		if not isPhoneOpen then
			CombatReticle.update(Camera, rootPart)
		end

		-- ⚡ Spider-Sense Threat Scanner (Checks all tagged enemies across Workspace)
		local nearestAttacker: Model? = nil
		local nearestAttackerDist = CombatConfig.Moves.SpiderSenseDodge.ThreatDetectionRadius or 45

		for _, enemy in CollectionService:GetTagged("Enemy") do
			if enemy:IsA("Model") and enemy.Parent and enemy:GetAttribute("IsAttacking") == true then
				local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				local eHum = enemy:FindFirstChildOfClass("Humanoid")
				if eRoot and eHum and eHum.Health > 0 then
					local d = (eRoot.Position - rootPart.Position).Magnitude
					if d < nearestAttackerDist then
						nearestAttackerDist = d
						nearestAttacker = enemy
					end
				end
			end
		end

		if nearestAttacker then
			activeThreatEnemy = nearestAttacker
			registerCombatAction()
			if (os.clock() - lastThreatDetectionTime) > 0.30 and character then
				lastThreatDetectionTime = os.clock()
				WebVisuals.createSpiderSenseSparks(character, true)
			end
		else
			activeThreatEnemy = nil
		end
	end
end)

print("🕷️ Spider-Man Modular Combat Architecture Online! (Melee, Webs, Dodge, VFX)")
