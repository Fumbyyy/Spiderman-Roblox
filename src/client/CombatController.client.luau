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

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Config & Remotes
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local CombatVFXRemote = RemotesFolder:WaitForChild("CombatVFX") :: RemoteEvent

-- Modular Combat Sub-Controllers
local ModulesFolder = script.Parent:WaitForChild("Modules")
local CombatReticle = require(ModulesFolder:WaitForChild("CombatReticle"))
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))
local CombatMelee = require(ModulesFolder:WaitForChild("CombatMelee"))
local CombatWebs = require(ModulesFolder:WaitForChild("CombatWebs"))
local CombatDodge = require(ModulesFolder:WaitForChild("CombatDodge"))
local CombatVFXListener = require(ModulesFolder:WaitForChild("CombatVFXListener"))

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

-- Initialize Multiplayer VFX Listener
CombatVFXListener.init(CombatVFXRemote, Camera, getCharacterParts)

-- Spider-Sense Threat Detection State
local activeThreatEnemy: Model? = nil
local lastThreatDetectionTime = 0

--------------------------------------------------------------------------------
-- 🎮 USER INPUT HANDLING (Streamlined 4-Button Kit: Left-Click, E, F & R Keys)
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, _)
	local character, rootPart, humanoid = getCharacterParts()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then return end

	-- 🥊 Left-Click: Tap for Combo (1-2-3), Hold for Uppercut, In-Air for Ground Slam
	if input.UserInputType == (CombatConfig.Keybinds.Attack or Enum.UserInputType.MouseButton1) then
		CombatWebs.isHoldingWebPellet = false

		if humanoid.FloorMaterial == Enum.Material.Air then
			CombatMelee.performAirGroundSlam(character, rootPart, humanoid, CombatWebs.createCombatWebLines)
		else
			CombatMelee.isHoldingAttack = true
			CombatMelee.attackPressStartTime = os.clock()
		end

	-- 🕸️ E Key -> Contextual Smart Web Gadget (Disarm Armed Mobs / Rapid Web Pellets)
	elseif input.KeyCode == (CombatConfig.Keybinds.WebGadget or Enum.KeyCode.E) then
		if CombatMelee.isHoldingAttack or (os.clock() - CombatMelee.lastMeleeActionTime) < 0.22 then return end

		local target = CombatReticle.getCurrentTarget()
		if target then
			local isArmed = (target:GetAttribute("IsArmed") == true) or (target:FindFirstChild("Gun") ~= nil)
			CombatWebs.performSmartWebGadget(character, rootPart, humanoid, Camera, CombatMelee.isHoldingAttack, CombatMelee.lastMeleeActionTime)

			-- If unarmed, start rapid web-fire loop while holding E
			if not isArmed then
				CombatWebs.isHoldingWebPellet = true
				task.spawn(function()
					while CombatWebs.isHoldingWebPellet do
						task.wait(CombatConfig.Moves.WebPellet.Cooldown or 0.24)
						if CombatWebs.isHoldingWebPellet and not CombatMelee.isHoldingAttack and (os.clock() - CombatMelee.lastMeleeActionTime) >= 0.22 then
							local char, root, hum = getCharacterParts()
							local currentTgt = CombatReticle.getCurrentTarget()
							if char and root and hum and hum.Health > 0 and currentTgt and currentTgt:GetAttribute("IsArmed") ~= true then
								CombatWebs.performWebPellet(char, root, hum, Camera, CombatMelee.isHoldingAttack, CombatMelee.lastMeleeActionTime)
							else
								CombatWebs.isHoldingWebPellet = false
								break
							end
						end
					end
				end)
			end
		end

	-- ⚡ F Key -> Spider-Sense Perfect Dodge & Face-Web Counter (Ground Combat Only!)
	elseif input.KeyCode == (CombatConfig.Keybinds.Dodge or Enum.KeyCode.F) then
		-- Prevent dodging while in mid-air, swinging, slingshotting, or wall-running!
		if humanoid.FloorMaterial == Enum.Material.Air then return end
		if rootPart:FindFirstChild("WebSwingVelocity") or rootPart:FindFirstChild("SlingshotVelocity") or rootPart:FindFirstChild("WallRunVelocity") or rootPart:FindFirstChild("GlidingVelocity") then
			return
		end
		activeThreatEnemy = CombatDodge.performSpiderSenseDodge(character, rootPart, humanoid, Camera, activeThreatEnemy)

	-- 🚀 R Key -> 65-Stud Web-Strike Zip Kick!
	elseif input.KeyCode == (CombatConfig.Keybinds.WebStrike or Enum.KeyCode.R) then
		CombatWebs.performWebStrike(character, rootPart, humanoid, Camera)
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
-- 🔄 RENDERSTEPPED LOOP (Target HUD, Reticle & Spider-Sense Threat Scanner)
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	local character, rootPart, humanoid = getCharacterParts()
	if rootPart and humanoid and humanoid.Health > 0 then
		CombatReticle.update(Camera, rootPart)

		-- ⚡ Spider-Sense Threat Scanner
		local nearestAttacker: Model? = nil
		local nearestAttackerDist = CombatConfig.Moves.SpiderSenseDodge.ThreatDetectionRadius or 45

		local enemiesFolder = Workspace:FindFirstChild("Enemies")
		if enemiesFolder then
			for _, enemy in enemiesFolder:GetChildren() do
				if enemy:IsA("Model") and enemy:GetAttribute("IsAttacking") == true then
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
		end

		if nearestAttacker then
			activeThreatEnemy = nearestAttacker
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
