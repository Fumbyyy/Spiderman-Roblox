--!strict
--[[
	CombatDodge.luau
	Handles Spider-Sense Acrobatic Dodge & Web-Counter:
	- Straight, flat athletic retreat slide (zero vertical lift)
	- Locks character orientation straight forward throughout the entire dodge (NO sideways twisting)
	- Point-blank face-web counter on attacking thugs
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local DodgeRemote = RemotesFolder:WaitForChild("SpiderSenseDodge") :: RemoteEvent

local ModulesFolder = script.Parent
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))

local CombatDodge = {}

CombatDodge.lastDodgeTime = 0
CombatDodge.isDodging = false

function CombatDodge.performSpiderSenseDodge(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera, activeThreatEnemy: Model?): Model?
	local now = os.clock()
	local cooldown = CombatConfig.Moves.SpiderSenseDodge.Cooldown or 0.35
	if CombatDodge.isDodging or (now - CombatDodge.lastDodgeTime) < cooldown then return activeThreatEnemy end

	CombatDodge.isDodging = true
	CombatDodge.lastDodgeTime = now

	-- 1. Determine straight camera forward vector on flat X/Z plane
	local camLook = camera.CFrame.LookVector
	local camLookFlat = Vector3.new(camLook.X, 0, camLook.Z)
	if camLookFlat.Magnitude < 0.1 then
		camLookFlat = rootPart.CFrame.LookVector
	else
		camLookFlat = camLookFlat.Unit
	end

	-- 2. Determine flat evasion slide direction
	local flatDir: Vector3
	if humanoid.MoveDirection.Magnitude > 0.1 then
		-- Directional evasion (A/D strafe slide or S backpedal)
		flatDir = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z).Unit
	else
		-- Neutral dodge = Clean straight backward step directly away from camera/enemy
		flatDir = -camLookFlat
	end

	-- Clean up any previous velocity constraints
	for _, oldObj in rootPart:GetChildren() do
		if oldObj.Name == "DodgeLinearVelocity" or oldObj.Name == "WebStrikeLinearVelocity" then
			oldObj:Destroy()
		end
	end

	-- 3. 🏃 Snappy Flat Ground Slide
	local att = rootPart:FindFirstChild("DodgeAttachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "DodgeAttachment"
		att.Parent = rootPart
	end

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DodgeLinearVelocity"
	lv.Attachment0 = att
	lv.MaxForce = 180000
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = flatDir * 38
	lv.Parent = rootPart

	WebVisuals.playWebSound(rootPart)

	local rollDuration = 0.20
	local rollStartTime = os.clock()
	local originalAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false

	-- 4. Maintain straight forward orientation every frame during slide
	local rollConn: RBXScriptConnection? = nil
	rollConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - rollStartTime
		local progress = math.clamp(elapsed / rollDuration, 0, 1)

		if rootPart and rootPart.Parent then
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + camLookFlat)
		end

		if progress >= 1 or not character.Parent or humanoid.Health <= 0 then
			if rollConn then rollConn:Disconnect() end
			if lv and lv.Parent then lv:Destroy() end
			if humanoid and humanoid.Parent then humanoid.AutoRotate = originalAutoRotate end
			CombatDodge.isDodging = false
		end
	end)

	-- 🕸️ Point-Blank Web-Counter: Shoot a web pellet into the attacker's face!
	local threat = activeThreatEnemy
	if threat and threat.Parent and threat:GetAttribute("IsAttacking") == true then
		local threatRoot = (threat:FindFirstChild("HumanoidRootPart") or threat:FindFirstChild("Torso")) :: BasePart?
		if threatRoot then
			local handAtt = WebVisuals.getHandAttachment(character, true)
			WebVisuals.launchWebPelletProjectile(handAtt, threatRoot.Position + Vector3.new(0, 1.0, 0))
		end
		DodgeRemote:FireServer(threat, true)
		return nil
	else
		DodgeRemote:FireServer(nil, false)
		return activeThreatEnemy
	end
end

return CombatDodge
