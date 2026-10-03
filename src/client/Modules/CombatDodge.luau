--!strict
--[[
	CombatDodge.luau
	Handles Spider-Sense Acrobatic Dodge & Web-Counter:
	- Straight, flat athletic retreat slide (zero vertical lift)
	- Snappy burst deceleration curve (72 -> 22 studs/s over 0.24s)
	- Temporary limb collision slip-through (prevent snagging on enemy hitboxes)
	- Stripped holographic neon decoy (zero humanoid/animator physics interference)
	- Dynamic camera evasion FOV kick (+4° with 0.22s quad ease-out)
	- Locks character orientation straight forward throughout the entire dodge (NO sideways twisting)
	- Point-blank face-web counter on attacking thugs
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local DodgeRemote = RemotesFolder:WaitForChild("SpiderSenseDodge") :: RemoteEvent

local ModulesFolder = script.Parent
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))
local CombatStyleHUD = require(ModulesFolder:WaitForChild("CombatStyleHUD"))

local CombatDodge = {}

-- ⚡ Miles Morales Camouflage Energy State Machine (5.0s Stealth Window, 8.0s Recharge)
CombatDodge.camoEnergy = 1.0 -- 0.0 to 1.0
CombatDodge.camoState = "Ready" -- "Ready" | "Active" | "Recharging"

local camoConn: RBXScriptConnection? = nil

function CombatDodge.dischargeCamo(character: Model?)
	CombatDodge.camoEnergy = 0
	CombatDodge.camoState = "Recharging"
	LocalPlayer:SetAttribute("MilesCamoEnergy", 0)
	LocalPlayer:SetAttribute("MilesCamoState", "Recharging")
	LocalPlayer:SetAttribute("MilesCamouflaged", false)

	if camoConn then camoConn:Disconnect() camoConn = nil end

	local char = character or (LocalPlayer and LocalPlayer.Character)
	if char then
		char:SetAttribute("MilesCamouflaged", false)
		for _, part in char:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			end
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			WebVisuals.createBioSparkBurst(root.Position)
		end
	end
end

-- Backward compatibility alias
CombatDodge.breakCamouflage = CombatDodge.dischargeCamo

function CombatDodge.activateCamouflage(character: Model)
	if camoConn then camoConn:Disconnect() camoConn = nil end

	CombatDodge.camoState = "Active"
	CombatDodge.camoEnergy = 1.0
	LocalPlayer:SetAttribute("MilesCamoState", "Active")
	LocalPlayer:SetAttribute("MilesCamoEnergy", 1.0)
	LocalPlayer:SetAttribute("MilesCamouflaged", true)
	character:SetAttribute("MilesCamouflaged", true)

	local parts: { BasePart } = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(parts, part)
			part.LocalTransparencyModifier = 0.85
		end
	end

	camoConn = RunService.RenderStepped:Connect(function()
		if not character.Parent or character:GetAttribute("MilesCamouflaged") ~= true or CombatDodge.camoState ~= "Active" then
			if camoConn then camoConn:Disconnect() camoConn = nil end
			return
		end
		for _, part in parts do
			if part.Parent then
				part.LocalTransparencyModifier = 0.85
			end
		end
	end)
end

-- Continuous energy drain (5.0s) & refill (8.0s) state machine loop
RunService.Heartbeat:Connect(function(dt)
	local isMiles = (LocalPlayer:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
	if not isMiles then
		if CombatDodge.camoState == "Active" then
			CombatDodge.dischargeCamo(LocalPlayer.Character)
		end
		return
	end

	if CombatDodge.camoState == "Active" then
		CombatDodge.camoEnergy = math.clamp(CombatDodge.camoEnergy - (dt / 5.0), 0, 1)
		LocalPlayer:SetAttribute("MilesCamoEnergy", CombatDodge.camoEnergy)
		if CombatDodge.camoEnergy <= 0 then
			CombatDodge.dischargeCamo(LocalPlayer.Character)
		end
	elseif CombatDodge.camoState == "Recharging" then
		CombatDodge.camoEnergy = math.clamp(CombatDodge.camoEnergy + (dt / 8.0), 0, 1)
		LocalPlayer:SetAttribute("MilesCamoEnergy", CombatDodge.camoEnergy)
		if CombatDodge.camoEnergy >= 1 then
			CombatDodge.camoState = "Ready"
			LocalPlayer:SetAttribute("MilesCamoState", "Ready")
		end
	end
end)



CombatDodge.lastDodgeTime = 0
CombatDodge.isDodging = false

function CombatDodge.performSpiderSenseDodge(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera, activeThreatEnemy: Model?): Model?
	local now = os.clock()
	local cooldown = CombatConfig.Moves.SpiderSenseDodge.Cooldown or 0.35
	if CombatDodge.isDodging or (now - CombatDodge.lastDodgeTime) < cooldown then return activeThreatEnemy end

	CombatDodge.isDodging = true
	CombatDodge.lastDodgeTime = now

	-- 🕷️ Universal Comic Spider-Sense Warning Squiggles (\/\/\) for ALL suits
	WebVisuals.createSpiderSenseSquiggles(character)

	-- 🎥 Camera Evasion Kick: Punch FOV outward by +4° with 0.22s quad ease-out back to base FOV
	local baseFov = camera.FieldOfView
	camera.FieldOfView = baseFov + 4
	local fovTween = TweenService:Create(camera, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = baseFov,
	})
	fovTween:Play()

	-- 🛡️ Stealth Big Time Suit Perk: +0.25s Invulnerability (0.45s -> 0.70s) & Neon Holographic Decoy
	local isDodgePerk = (LocalPlayer:GetAttribute("SuitPerkType") == "Dodge")
	local iframeDuration = if isDodgePerk then 0.70 else 0.45
	character:SetAttribute("IsInvulnerable", true)
	task.delay(iframeDuration, function()
		if character and character.Parent then
			character:SetAttribute("IsInvulnerable", false)
		end
	end)

	local isMiles = (LocalPlayer:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
		or (character:GetAttribute("EquippedSuit") == "MilesSpiderVerse")

	local isGrounded = (humanoid.FloorMaterial ~= Enum.Material.Air)
	local isCamoActivation = false

	-- Miles Morales: Spider-Verse Chromatic Glitch Decoy & Camouflage Mode (5.0s window when Ready and Grounded)
	if isMiles and CombatDodge.camoState == "Ready" and isGrounded then
		isCamoActivation = true
		WebVisuals.createChromaticGlitchDecoy(character, rootPart.CFrame)
		CombatDodge.activateCamouflage(character)
	end

	if isDodgePerk and not isMiles then
		local wasArchivable = character.Archivable
		character.Archivable = true
		local decoy = character:Clone()
		character.Archivable = wasArchivable

		if decoy then
			decoy.Name = "StealthNeonDecoy"

			-- Strip Humanoid and Animator to eliminate physics, camera occlusion, and animation processing
			local dHum = decoy:FindFirstChildOfClass("Humanoid")
			if dHum then dHum:Destroy() end
			local dAnim = decoy:FindFirstChildOfClass("Animator")
			if dAnim then dAnim:Destroy() end

			-- Strip accessories, clothing, joints, decals, and scripts
			for _, desc in decoy:GetDescendants() do
				if desc:IsA("Humanoid") or desc:IsA("Animator")
					or desc:IsA("Accessory") or desc:IsA("Shirt") or desc:IsA("Pants") or desc:IsA("ShirtGraphic")
					or desc:IsA("Motor6D") or desc:IsA("JointInstance")
					or desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("Sound")
					or desc:IsA("UIComponent") or desc:IsA("BillboardGui") or desc:IsA("Decal") then
					desc:Destroy()
				elseif desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
					desc.CanTouch = false
					desc.CanQuery = false
					desc.Material = Enum.Material.Neon
					local isMiles = (LocalPlayer:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
					desc.Color = if isMiles then Color3.fromRGB(225, 35, 45) else Color3.fromRGB(0, 255, 128)
					desc.Transparency = 0.45
				end
			end

			decoy:PivotTo(rootPart.CFrame)
			decoy.Parent = Workspace

			task.spawn(function()
				local elapsed = 0
				local fadeDuration = 1.0
				local parts: {BasePart} = {}
				for _, part in decoy:GetDescendants() do
					if part:IsA("BasePart") then
						table.insert(parts, part)
					end
				end
				local conn: RBXScriptConnection? = nil
				conn = RunService.RenderStepped:Connect(function(dt)
					elapsed = elapsed + dt
					local alpha = math.clamp(elapsed / fadeDuration, 0, 1)
					for _, part in parts do
						part.Transparency = 0.45 + (0.55 * alpha)
					end
					if elapsed >= fadeDuration then
						if conn then conn:Disconnect() end
						if decoy and decoy.Parent then
							decoy:Destroy()
						end
					end
				end)
			end)
		end
	end

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

	-- 3. 🏃 Snappy Flat Ground Slide with Easing Curve
	local att = rootPart:FindFirstChild("DodgeAttachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "DodgeAttachment"
		att.Parent = rootPart
	end

	local initialSpeed = 72 -- Initial burst speed (studs/s)
	local finalSpeed = 22   -- Terminal deceleration floor (studs/s)

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DodgeLinearVelocity"
	lv.Attachment0 = att
	lv.MaxForce = 220000
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = flatDir * initialSpeed
	lv.Parent = rootPart

	WebVisuals.playWebSound(rootPart)

	-- 🛡️ Limb Evasion Slip-Through: Disable collisions on limbs/torsos so Spider-Man doesn't snag on enemy mobs
	local savedCollisions: { [BasePart]: boolean } = {}
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			savedCollisions[part] = part.CanCollide
			part.CanCollide = false
		end
	end

	local function restoreCollisions()
		for part, wasCollidable in savedCollisions do
			if part and part.Parent then
				part.CanCollide = wasCollidable
			end
		end
		table.clear(savedCollisions)
	end

	local rollDuration = 0.24
	local rollStartTime = os.clock()
	local originalAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false

	-- 4. Maintain straight forward orientation & ease-out deceleration curve every frame
	local rollConn: RBXScriptConnection? = nil
	local diedConn: RBXScriptConnection? = nil

	local function cleanupDodge()
		if rollConn then
			rollConn:Disconnect()
			rollConn = nil
		end
		if diedConn then
			diedConn:Disconnect()
			diedConn = nil
		end
		if lv and lv.Parent then lv:Destroy() end
		if humanoid and humanoid.Parent then humanoid.AutoRotate = originalAutoRotate end
		restoreCollisions()
		CombatDodge.isDodging = false
	end

	diedConn = humanoid.Died:Connect(cleanupDodge)

	rollConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - rollStartTime
		local progress = math.clamp(elapsed / rollDuration, 0, 1)

		-- Ease-out deceleration from 72 down to 22 studs/s
		local easeOut = 1 - (1 - progress) * (1 - progress)
		local currentSpeed = initialSpeed - ((initialSpeed - finalSpeed) * easeOut)
		if lv and lv.Parent then
			lv.VectorVelocity = flatDir * currentSpeed
		end

		if rootPart and rootPart.Parent then
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + camLookFlat)
		end

		if progress >= 1 or not character.Parent or humanoid.Health <= 0 then
			cleanupDodge()
		end
	end)

	-- 🕸️ Point-Blank Web-Counter: Shoot a web pellet into the attacker's face!
	local threat = activeThreatEnemy
	if not threat or not threat.Parent or threat:GetAttribute("IsAttacking") ~= true then
		local enemiesFolder = Workspace:FindFirstChild("Enemies")
		if enemiesFolder and rootPart then
			local bestDist = 55
			for _, enemy in enemiesFolder:GetChildren() do
				if enemy:IsA("Model") and enemy:GetAttribute("IsAttacking") == true then
					local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
					local eHum = enemy:FindFirstChildOfClass("Humanoid")
					if eRoot and eHum and eHum.Health > 0 then
						local d = (eRoot.Position - rootPart.Position).Magnitude
						if d < bestDist then
							bestDist = d
							threat = enemy
						end
					end
				end
			end
		end
	end

	if threat and threat.Parent then
		local threatRoot = (threat:FindFirstChild("HumanoidRootPart") or threat:FindFirstChild("Torso")) :: BasePart?
		if threatRoot then
			local handAtt = WebVisuals.getHandAttachment(character, true)
			WebVisuals.launchWebPelletProjectile(handAtt, threatRoot.Position + Vector3.new(0, 1.0, 0))
		end

		CombatStyleHUD.registerHit(12)
		DodgeRemote:FireServer(threat, true, isCamoActivation)
		return nil
	else
		DodgeRemote:FireServer(nil, false, isCamoActivation)
		return nil
	end
end

return CombatDodge
