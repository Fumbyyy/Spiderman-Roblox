--!strict
--[[
	CombatMelee.luau
	Handles all close-quarters melee combat moves:
	1. 🥊 Kinetic Strike Combo (L-Click Tap 1-2-3)
	2. 🚀 Uppercut Launcher (L-Click Hold)
	3. 💥 Web Ground Slam (In-Air Attack)
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")

local KineticComboRemote = RemotesFolder:WaitForChild("KineticCombo") :: RemoteEvent
local UppercutRemote = RemotesFolder:WaitForChild("UppercutLauncher") :: RemoteEvent
local GroundSlamRemote = RemotesFolder:WaitForChild("AirGroundSlam") :: RemoteEvent

local ModulesFolder = script.Parent
local CombatReticle = require(ModulesFolder:WaitForChild("CombatReticle"))
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))

local CombatMelee = {}

-- State
CombatMelee.comboIndex = 1
CombatMelee.lastHitTime = 0
CombatMelee.lastUppercutTime = 0
CombatMelee.lastGroundSlamTime = 0
CombatMelee.lastMeleeActionTime = 0
CombatMelee.isHoldingAttack = false
CombatMelee.attackPressStartTime = 0

-- 🛡️ Super-Armor Protection: Spider-Armor MK IV grants immunity to flinching & interruptions
function CombatMelee.checkSuperArmor(): boolean
	return LocalPlayer and LocalPlayer:GetAttribute("SuitPerkType") == "Defense"
end


-- 1. 🥊 KINETIC STRIKE COMBO (L-Click Tap on Ground)
function CombatMelee.performKineticCombo(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera)
	local now = os.clock()
	local requiredCooldown = (CombatMelee.comboIndex == 1) and (CombatConfig.Moves.KineticCombo.FinisherCooldown or 0.55) or (CombatConfig.Moves.KineticCombo.HitCooldown or 0.28)
	if (now - CombatMelee.lastHitTime) < requiredCooldown then return end

	if (now - CombatMelee.lastHitTime) > (CombatConfig.Moves.KineticCombo.ComboResetTime or 1.10) then
		CombatMelee.comboIndex = 1
	end

	CombatMelee.lastHitTime = now
	CombatMelee.lastMeleeActionTime = now

	-- 1. Melee Target & Step-In Scan (Reticle target or nearest forward enemy within 8.5 studs)
	local stepInScanRange = (CombatConfig.Moves.KineticCombo.MagneticSnapMaxDist or 8.5)
	local target = CombatReticle.getCurrentTarget()
	if target then
		local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
		local targetHum = target:FindFirstChildOfClass("Humanoid")
		if not targetRoot or not targetHum or targetHum.Health <= 0 or (targetRoot.Position - rootPart.Position).Magnitude > stepInScanRange then
			target = nil
		end
	end

	-- Fallback cone search if no reticle target is locked
	if not target then
		local enemies = CollectionService:GetTagged("Enemy")
		local camLook = camera.CFrame.LookVector
		local bestDist = stepInScanRange
		for _, enemy in enemies do
			if enemy:IsA("Model") then
				local eHum = enemy:FindFirstChildOfClass("Humanoid")
				local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				if eHum and eHum.Health > 0 and eRoot then
					local toEnemy = eRoot.Position - rootPart.Position
					local dist = toEnemy.Magnitude
					if dist <= stepInScanRange and dist < bestDist then
						local flatToEnemy = Vector3.new(toEnemy.X, 0, toEnemy.Z).Unit
						local dot = camLook:Dot(flatToEnemy)
						if dot >= 0.25 or dist <= 4.5 then
							target = enemy
							bestDist = dist
						end
					end
				end
			end
		end
	end

	-- 2. 🥋 Natural Grounded Step & Auto-Facing (Option 1: Zero Ice-Skating)
	local camLook = camera.CFrame.LookVector
	local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit
	local targetRoot = target and ((target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?)

	if target and targetRoot then
		local enemyPos = targetRoot.Position
		local offset = enemyPos - rootPart.Position
		local horizDist = Vector3.new(offset.X, 0, offset.Z).Magnitude

		if horizDist > 0.1 then
			forwardFlat = Vector3.new(offset.X, 0, offset.Z).Unit
		end

		-- Clean auto-facing: Spider-Man turns to face his target without moving his position artificially
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(enemyPos.X, rootPart.Position.Y, enemyPos.Z))

		-- Natural grounded step: Uses normal velocity impulse so feet stay on the pavement
		local stepForce: number
		if horizDist > 4.2 then
			stepForce = CombatMelee.comboIndex == 3 and 14 or (CombatConfig.Moves.KineticCombo.LungeForce or 11)
		else
			-- Close contact punch: subtle contact nudge so player doesn't clip into enemy
			stepForce = 4.0
		end

		rootPart.AssemblyLinearVelocity = (forwardFlat * stepForce) + Vector3.new(0, 0.4, 0)
	else
		-- Free punch without target: forward momentum step aligned with camera
		local lungeForce = CombatMelee.comboIndex == 3 and 14 or (CombatConfig.Moves.KineticCombo.LungeForce or 12)
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + forwardFlat)
		rootPart.AssemblyLinearVelocity = (forwardFlat * lungeForce) + Vector3.new(0, 1.2, 0)
	end

	WebVisuals.playWebSound(rootPart)

	-- 3. Melee AoE Cleave Hitbox: Fires to server with target (if any); server validates forward cone cleave for all clumped mobs!
	local currentHit = math.clamp(CombatMelee.comboIndex, 1, 3)
	KineticComboRemote:FireServer(target, currentHit)

	if target then
		local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
		if targetRoot then
			local dist = (targetRoot.Position - rootPart.Position).Magnitude
			if dist <= ((currentHit == 3) and 8.2 or 7.0) then
				WebVisuals.createMeleeHitSparks(targetRoot.Position + Vector3.new(0, 0.5, 0), currentHit == 3)
			end
		end
	end

	-- Progress Combo: Hit 1 -> Hit 2 -> Hit 3 (Ready for 4th Jump Slam!)
	if CombatMelee.comboIndex == 3 then
		CombatMelee.comboIndex = 4
	elseif CombatMelee.comboIndex >= 4 then
		CombatMelee.comboIndex = 1
	else
		CombatMelee.comboIndex = CombatMelee.comboIndex + 1
	end
end

-- 2. 🚀 UPPERCUT LAUNCHER (Hold L-Click)
function CombatMelee.performUppercutLauncher(character: Model, rootPart: BasePart, humanoid: Humanoid)
	local now = os.clock()
	if (now - CombatMelee.lastUppercutTime) < (CombatConfig.Moves.Uppercut.Cooldown or 3.5) then return end

	-- Close Range Melee Check (Strict 6.0 studs chin reach!)
	local maxUppercutRange = CombatConfig.Moves.Uppercut.MaxMeleeRange or 6.0
	local target = CombatReticle.getCurrentTarget()
	if target then
		local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
		if not targetRoot or (targetRoot.Position - rootPart.Position).Magnitude > maxUppercutRange then
			target = nil
		end
	end

	CombatMelee.lastUppercutTime = now
	CombatMelee.lastMeleeActionTime = now

	local launchY = CombatConfig.Moves.Uppercut.LaunchVelocity or 48
	rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, launchY, rootPart.AssemblyLinearVelocity.Z)
	WebVisuals.playWebSound(rootPart)

	-- Brief Aerial Float Suspension at apex
	task.delay(0.32, function()
		if rootPart and humanoid and humanoid.FloorMaterial == Enum.Material.Air then
			local floatBv = Instance.new("BodyVelocity")
			floatBv.Name = "AirJuggleFloat"
			floatBv.MaxForce = Vector3.new(0, 1e5, 0)
			floatBv.Velocity = Vector3.new(0, 4, 0)
			floatBv.Parent = rootPart
			Debris:AddItem(floatBv, 0.75)
		end
	end)

	if target then
		UppercutRemote:FireServer(target)
	end
end

-- 3. 💥 WEB-LINE GROUND SLAM (In-Air Attack / 4th Attack after 1-2-3 Combo)
function CombatMelee.performAirGroundSlam(character: Model, rootPart: BasePart, humanoid: Humanoid, createWebLinesFunc: ((Model, Model, boolean, number) -> ())?)
	local now = os.clock()
	local slamCooldown = CombatConfig.Moves.AirGroundSlam.Cooldown or 1.4
	if (now - CombatMelee.lastGroundSlamTime) < slamCooldown then return end

	CombatMelee.lastGroundSlamTime = now
	CombatMelee.lastMeleeActionTime = now
	CombatMelee.comboIndex = 1

	-- Clean up any active air float
	local existingFloat = rootPart:FindFirstChild("AirJuggleFloat")
	if existingFloat then existingFloat:Destroy() end

	local target = CombatReticle.getCurrentTarget()
	local slamSpeed = CombatConfig.Moves.AirGroundSlam.SlamSpeed or 95

	if target then
		local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
		if not targetRoot or (targetRoot.Position - rootPart.Position).Magnitude > 35 then
			target = nil
		end
	end

	if target and createWebLinesFunc then
		-- Shoot twin webs and whip close enemy down
		createWebLinesFunc(character, target, true, 0.45)
		rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X * 0.2, -slamSpeed, rootPart.AssemblyLinearVelocity.Z * 0.2)
	else
		-- Solo air dive slam directly downward
		rootPart.AssemblyLinearVelocity = Vector3.new(0, -slamSpeed, 0)
		WebVisuals.playWebSound(rootPart)
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	-- Monitor descent and trigger shockwave as soon as floor is reached
	local slamStartTime = os.clock()
	local landed = false

	local landingConn: RBXScriptConnection? = nil
	local function triggerLandingImpact()
		if landed then return end
		landed = true
		if landingConn then landingConn:Disconnect() end

		local finalPos = rootPart.Position
		local curGroundRay = Workspace:Raycast(rootPart.Position, Vector3.new(0, -8, 0), rayParams)
		if curGroundRay then
			finalPos = curGroundRay.Position
		end

		GroundSlamRemote:FireServer(target, finalPos)
		WebVisuals.createWeaponImpactSparks(finalPos, Vector3.new(0, 1, 0))
	end

	landingConn = RunService.Heartbeat:Connect(function()
		if not rootPart.Parent or humanoid.Health <= 0 then
			if landingConn then landingConn:Disconnect() end
			return
		end

		if humanoid.FloorMaterial ~= Enum.Material.Air or (os.clock() - slamStartTime) > 0.60 then
			triggerLandingImpact()
		else
			local checkRay = Workspace:Raycast(rootPart.Position, Vector3.new(0, -5, 0), rayParams)
			if checkRay then
				triggerLandingImpact()
			end
		end
	end)
end

return CombatMelee
