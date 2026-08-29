--!strict
--[[
	CombatMelee.luau
	Handles all close-quarters melee combat moves:
	1. 🥊 Kinetic Strike Combo (L-Click Tap 1-2-3)
	2. 🚀 Uppercut Launcher (L-Click Hold)
	3. 💥 Web Ground Slam (In-Air Attack)
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

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

	-- 1. Melee Target & Step-In Scan
	local maxMeleeRange = CombatConfig.Moves.KineticCombo.MaxMeleeRange or 5.8
	local stepInScanRange = 10.0
	local target = CombatReticle.getCurrentTarget()
	if target then
		local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
		if not targetRoot or (targetRoot.Position - rootPart.Position).Magnitude > stepInScanRange then
			target = nil
		end
	end

	-- 2. Forward combat step / lunge
	local camLook = camera.CFrame.LookVector
	local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit

	if target then
		local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
		if targetRoot then
			local toEnemy = (targetRoot.Position - rootPart.Position)
			if toEnemy.Magnitude > 0.5 then
				forwardFlat = Vector3.new(toEnemy.X, 0, toEnemy.Z).Unit
				rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + forwardFlat)
			end
		end
	end

	local lungeForce = CombatMelee.comboIndex == 3 and 14 or (CombatConfig.Moves.KineticCombo.LungeForce or 12)
	rootPart.AssemblyLinearVelocity = (forwardFlat * lungeForce) + Vector3.new(0, 1.5, 0)
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
	local slamCooldown = CombatConfig.Moves.AirGroundSlam.Cooldown or 2.0
	if (now - CombatMelee.lastGroundSlamTime) < slamCooldown then return end

	CombatMelee.lastGroundSlamTime = now
	CombatMelee.lastMeleeActionTime = now
	CombatMelee.comboIndex = 1

	-- Clean up any active air float
	local existingFloat = rootPart:FindFirstChild("AirJuggleFloat")
	if existingFloat then existingFloat:Destroy() end

	local target = CombatReticle.getCurrentTarget()
	local slamSpeed = CombatConfig.Moves.AirGroundSlam.SlamSpeed or 85

	if target then
		local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
		if not targetRoot or (targetRoot.Position - rootPart.Position).Magnitude > 22 then
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

	-- Execute shockwave on ground contact
	task.delay(0.10, function()
		if rootPart and rootPart.Parent then
			GroundSlamRemote:FireServer(target, rootPart.Position)
		end
	end)
end

return CombatMelee
