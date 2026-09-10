--!strict
--[[
	GrappleController.client.luau
	Main Spider-Man Web-Swinging & Movement Coordinator.
	
	Modular Architecture:
	- 🎯 TargetFinder.luau   -> Smart forward-ledge building raycasting & hand matching
	- 🧗 WallMovement.luau   -> Spider-Man wall-running, crawling, and wall-jumping
	- ✨ WebVisuals.luau     -> Web silk beam rendering, audio & multiplayer replication
	- 🎥 CameraController.luau -> Hero over-shoulder view, Dynamic FOV & ShiftLock
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Shared Config & Remotes
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GrappleConfig = require(Shared:WaitForChild("GrappleConfig"))
local RemotesFolder = ReplicatedStorage:WaitForChild("GrappleRemotes")
local GrappleStartRemote = RemotesFolder:WaitForChild("GrappleStart") :: RemoteEvent
local GrappleEndRemote = RemotesFolder:WaitForChild("GrappleEnd") :: RemoteEvent

-- 📦 Client Modules
local ModulesFolder = script.Parent:WaitForChild("Modules")
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))
local TargetFinder = require(ModulesFolder:WaitForChild("TargetFinder"))
local WallMovement = require(ModulesFolder:WaitForChild("WallMovement"))
local CameraController = require(ModulesFolder:WaitForChild("CameraController"))
local CombatReticle = require(ModulesFolder:WaitForChild("CombatReticle"))

-- Movement States
local isSwinging = false
local isSlingshot = false
local isFreeGliding = false
local swingStartTime = 0
local lastSwingEndTime = 0
local currentRopeRadius = 0
local pendulumVelocity = Vector3.zero
local glideVelocity = Vector3.zero
local currentAnchorPosition: Vector3? = nil

-- Active Physics Movers & Visuals
local activeBodyVelocity: BodyVelocity? = nil
local activeBodyGyro: BodyGyro? = nil
local activeWebBeamLeft: Beam? = nil
local activeWebBeamRight: Beam? = nil
local activeWorldAttLeft: Attachment? = nil
local activeWorldAttRight: Attachment? = nil

--------------------------------------------------------------------------------
-- 🛠️ CHARACTER HELPERS
--------------------------------------------------------------------------------

local function getCharacterParts()
	local character = LocalPlayer.Character
	if not character then return nil, nil, nil end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character, rootPart, humanoid
end

--------------------------------------------------------------------------------
-- 🚀 SWING ATTACHMENT & RELEASE
--------------------------------------------------------------------------------

local function stopGrapple(isJumpLaunch: boolean)
	if not isSwinging and not isSlingshot then return end
	local wasSlingshot = isSlingshot
	isSwinging = false
	isSlingshot = false
	lastSwingEndTime = os.clock()

	local character, rootPart, humanoid = getCharacterParts()

	-- Read current velocity before web detach
	local currentVel = pendulumVelocity
	if rootPart and rootPart.AssemblyLinearVelocity.Magnitude > currentVel.Magnitude then
		currentVel = rootPart.AssemblyLinearVelocity
	end

	-- Clean up visuals & gyros
	if activeBodyGyro then
		activeBodyGyro:Destroy()
		activeBodyGyro = nil
	end
	if activeWebBeamLeft then activeWebBeamLeft:Destroy(); activeWebBeamLeft = nil end
	if activeWebBeamRight then activeWebBeamRight:Destroy(); activeWebBeamRight = nil end
	if activeWorldAttLeft then activeWorldAttLeft:Destroy(); activeWorldAttLeft = nil end
	if activeWorldAttRight then activeWorldAttRight:Destroy(); activeWorldAttRight = nil end
	currentAnchorPosition = nil

	-- Restore Humanoid state
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	-- 🍃 Controlled Momentum Inheritance into Mid-Air Aerodynamic Gliding
	if rootPart then
		local camLook = Camera.CFrame.LookVector
		local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit

		if wasSlingshot then
			glideVelocity = currentVel
		elseif isJumpLaunch then
			local jumpDir = (forwardFlat * 0.6 + Vector3.new(0, 0.8, 0)).Unit
			glideVelocity = currentVel + (jumpDir * 28)
		else
			glideVelocity = currentVel * GrappleConfig.Launch.VelocityPreservation
		end

		-- Guarantee minimum forward exit speed so you never stall
		local minSpeed = GrappleConfig.Launch.MinimumFlingSpeed or 80
		if glideVelocity.Magnitude < minSpeed then
			glideVelocity = (forwardFlat * minSpeed) + Vector3.new(0, GrappleConfig.Launch.BottomUpwardLift or 30, 0)
		end

		-- Cap maximum glide speed
		local maxSpeed = GrappleConfig.Gliding.MaxSpeed or 145
		if glideVelocity.Magnitude > maxSpeed then
			glideVelocity = glideVelocity.Unit * maxSpeed
		end

		if not activeBodyVelocity then
			local bv = Instance.new("BodyVelocity")
			bv.Name = "WebGlideVelocity"
			bv.Parent = rootPart
			activeBodyVelocity = bv
		end

		activeBodyVelocity.MaxForce = Vector3.new(1e6, 1e5, 1e6)
		activeBodyVelocity.P = 4000
		activeBodyVelocity.Velocity = glideVelocity
		isFreeGliding = true
	end

	GrappleEndRemote:FireServer()
end

-- 🚀 Ground Double-Web Slingshot
local function startGroundSlingshot(character: Model, rootPart: BasePart, humanoid: Humanoid)
	isSlingshot = true
	isSwinging = false
	isFreeGliding = false
	swingStartTime = os.clock()

	local camCFrame = Camera.CFrame
	local camLook = camCFrame.LookVector
	local camRight = camCFrame.RightVector
	local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit
	local origin = rootPart.Position

	local skyLeft = origin + (forwardFlat * 45) - (camRight * GrappleConfig.Slingshot.SpreadWidth) + Vector3.new(0, GrappleConfig.Slingshot.SkyHeight, 0)
	local skyRight = origin + (forwardFlat * 45) + (camRight * GrappleConfig.Slingshot.SpreadWidth) + Vector3.new(0, GrappleConfig.Slingshot.SkyHeight, 0)

	local worldLeft = Instance.new("Attachment")
	worldLeft.Name = "SlingshotAnchor_L"
	worldLeft.WorldPosition = skyLeft
	worldLeft.Parent = Workspace.Terrain
	activeWorldAttLeft = worldLeft

	local worldRight = Instance.new("Attachment")
	worldRight.Name = "SlingshotAnchor_R"
	worldRight.WorldPosition = skyRight
	worldRight.Parent = Workspace.Terrain
	activeWorldAttRight = worldRight

	local handLeft = WebVisuals.getHandAttachment(character, false)
	local handRight = WebVisuals.getHandAttachment(character, true)

	activeWebBeamLeft = WebVisuals.createWebBeam(handLeft, worldLeft, rootPart, character)
	activeWebBeamRight = WebVisuals.createWebBeam(handRight, worldRight, rootPart, character)

	local isVelocitySuit = (LocalPlayer:GetAttribute("SuitPerkType") == "Velocity")
	local forwardSpeed = GrappleConfig.Slingshot.ForwardVelocity * (if isVelocitySuit then 1.15 else 1.0)
	local launchVel = (forwardFlat * forwardSpeed) + Vector3.new(0, GrappleConfig.Slingshot.UpwardVelocity, 0)
	pendulumVelocity = launchVel

	-- 🚀 Velocity Suit Perk: Cyan Rocket Booster Particle Trails on Feet for 1.2s
	if isVelocitySuit then
		local function attachBooster(parentPart: BasePart?)
			if not parentPart then return end
			local att = Instance.new("Attachment")
			att.Name = "RocketBoosterAtt"
			att.Position = Vector3.new(0, -0.6, 0)
			att.Parent = parentPart

			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "RocketBoosterTrail"
			emitter.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 235, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 140, 255)),
			})
			emitter.LightEmission = 1.0
			emitter.LightInfluence = 0
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.7),
				NumberSequenceKeypoint.new(1, 0.0),
			})
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 1.0),
			})
			emitter.Rate = 65
			emitter.Speed = NumberRange.new(15, 25)
			emitter.Lifetime = NumberRange.new(0.25, 0.5)
			emitter.SpreadAngle = Vector2.new(12, 12)
			emitter.Acceleration = Vector3.new(0, -25, 0)
			emitter.EmissionDirection = Enum.NormalId.Bottom
			emitter.Parent = att

			task.delay(1.2, function()
				if emitter and emitter.Parent then
					emitter.Enabled = false
				end
				task.delay(0.6, function()
					if att and att.Parent then
						att:Destroy()
					end
				end)
			end)
		end

		local leftFoot = (character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")) :: BasePart?
		local rightFoot = (character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")) :: BasePart?
		attachBooster(leftFoot)
		attachBooster(rightFoot)
	end

	if not activeBodyVelocity then
		activeBodyVelocity = Instance.new("BodyVelocity")
		activeBodyVelocity.Name = "SlingshotVelocity"
		activeBodyVelocity.Parent = rootPart
	end
	activeBodyVelocity.MaxForce = Vector3.new(1e7, 1e7, 1e7)
	activeBodyVelocity.P = 5000
	activeBodyVelocity.Velocity = launchVel

	local bg = Instance.new("BodyGyro")
	bg.Name = "SlingshotGyro"
	bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bg.P = 3500
	bg.D = 250
	bg.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + forwardFlat + Vector3.new(0, 0.45, 0))
	bg.Parent = rootPart
	activeBodyGyro = bg

	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	WebVisuals.playWebSound(rootPart)
	GrappleStartRemote:FireServer(skyLeft, false)
	GrappleStartRemote:FireServer(skyRight, true)
end

-- 🕸️ Air Real Spherical Pendulum Swing
local function startAirSwing(character: Model, rootPart: BasePart, humanoid: Humanoid, anchorPos: Vector3, isRight: boolean)
	local initialVector = rootPart.Position - anchorPos
	local ropeRadius = math.max(initialVector.Magnitude, GrappleConfig.Physics.MinRopeLength)

	isSwinging = true
	isSlingshot = false
	isFreeGliding = false
	swingStartTime = os.clock()
	currentAnchorPosition = anchorPos
	currentRopeRadius = ropeRadius

	-- Calculate clean forward swing velocity (Zero opposite-side sideways drift!)
	local camLook = Camera.CFrame.LookVector
	local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit

	local incomingVel = isFreeGliding and glideVelocity or rootPart.AssemblyLinearVelocity
	local incomingSpeed = incomingVel.Magnitude
	local isVelocityPerk = (LocalPlayer:GetAttribute("SuitPerkType") == "Velocity")
	local effectiveMaxSpeed = if isVelocityPerk then math.floor(GrappleConfig.Physics.MaxSpeed * 1.15) else GrappleConfig.Physics.MaxSpeed
	local startSpeed = math.clamp(
		math.max(incomingSpeed * 1.05, GrappleConfig.Physics.InitialSwingSpeed),
		GrappleConfig.Physics.InitialSwingSpeed,
		effectiveMaxSpeed
	)

	local entryY = math.clamp(incomingVel.Y * 0.5, -15, 25)
	pendulumVelocity = (forwardFlat * startSpeed) + Vector3.new(0, entryY, 0)

	if not activeBodyVelocity then
		activeBodyVelocity = Instance.new("BodyVelocity")
		activeBodyVelocity.Name = "WebSwingVelocity"
		activeBodyVelocity.Parent = rootPart
	end
	activeBodyVelocity.MaxForce = Vector3.new(1e7, 1e7, 1e7)
	activeBodyVelocity.P = 5000
	activeBodyVelocity.Velocity = pendulumVelocity

	local bg = Instance.new("BodyGyro")
	bg.Name = "WebSwingGyro"
	bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bg.P = 3500
	bg.D = 250
	bg.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + pendulumVelocity.Unit)
	bg.Parent = rootPart
	activeBodyGyro = bg

	-- Web Beam & Attachments
	local worldAtt = Instance.new("Attachment")
	worldAtt.Name = isRight and "WebWorldAnchor_R" or "WebWorldAnchor_L"
	worldAtt.WorldPosition = anchorPos
	worldAtt.Parent = Workspace.Terrain

	local playerAtt = WebVisuals.getHandAttachment(character, isRight)
	local beam = WebVisuals.createWebBeam(playerAtt, worldAtt, rootPart, character)

	if isRight then
		activeWorldAttRight = worldAtt
		activeWebBeamRight = beam
	else
		activeWorldAttLeft = worldAtt
		activeWebBeamLeft = beam
	end

	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	WebVisuals.playWebSound(rootPart)
	GrappleStartRemote:FireServer(anchorPos, isRight)
end

-- 🎮 Main Grapple Trigger
local function startGrapple()
	if WallMovement.isActive() then
		local _, _, humanoid = getCharacterParts()
		local launchVel = WallMovement.stopWallRun(humanoid, true, Camera)
		glideVelocity = launchVel
		isFreeGliding = true
		if activeBodyVelocity then activeBodyVelocity.Velocity = launchVel end
		return
	end

	-- Cooldown Check
	if (os.clock() - lastSwingEndTime) < (GrappleConfig.Cooldown.SwingCooldown or 0.22) then
		return
	end

	if isSwinging or isSlingshot then
		stopGrapple(false)
	end

	local character, rootPart, humanoid = getCharacterParts()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then return end

	-- 🛡️ Combat Guard: If actively locked on to an enemy in close combat, suppress web swinging!
	local lockedEnemy = CombatReticle.getCurrentTarget()
	if lockedEnemy and lockedEnemy.Parent then
		local enemyRoot = (lockedEnemy:FindFirstChild("HumanoidRootPart") or lockedEnemy:FindFirstChild("Torso")) :: BasePart?
		if enemyRoot and (enemyRoot.Position - rootPart.Position).Magnitude <= 45 then
			return
		end
	end

	-- Ground -> Slingshot Launch!
	if GrappleConfig.Slingshot.Enabled and TargetFinder.isNearGround(rootPart, character) then
		startGroundSlingshot(character, rootPart, humanoid)
	else
		-- Air -> Building Swing!
		local anchorPos, isRight = TargetFinder.findBuildingAnchor(character, rootPart, Camera)
		if anchorPos then
			startAirSwing(character, rootPart, humanoid, anchorPos, isRight)
		end
	end
end

--------------------------------------------------------------------------------
-- 🔄 MAIN RUNSERVICE LOOPS
--------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(deltaTime)
	local character, rootPart, humanoid = getCharacterParts()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
		if isSwinging or isSlingshot then stopGrapple(false) end
		if WallMovement.isActive() then WallMovement.stopWallRun(humanoid, false, Camera) end
		return
	end

	local currentPos = rootPart.Position
	local elapsedTime = os.clock() - swingStartTime

	-- 🕷️ 1. Wall-Running Update
	if WallMovement.isActive() then
		local isStillOnWall = WallMovement.update(rootPart, character, humanoid, Camera)
		if not isStillOnWall then
			WallMovement.stopWallRun(humanoid, false, Camera)
		end
		return
	end

	-- 🚀 2. Ground Slingshot Update
	if isSlingshot then
		if elapsedTime >= GrappleConfig.Slingshot.Duration then
			stopGrapple(false)
		end
		return
	end

	-- 🕸️ 3. Street Corridor Spherical Pendulum Update
	if isSwinging and currentAnchorPosition and activeBodyVelocity then
		-- Check for wall contact -> Auto-trigger Wall-Run!
		local wallHit, wallNorm = WallMovement.checkWallContact(rootPart, character, Camera)
		if wallHit and (os.clock() - WallMovement.getLastJumpTime() > 0.4) then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				stopGrapple(false)
				WallMovement.startWallRun(character, rootPart, humanoid, wallNorm)
				return
			end
		end

		local radialVector = currentPos - currentAnchorPosition
		local currentDist = radialVector.Magnitude
		local radialUnit = radialVector.Unit

		-- 🎯 Forward Corridor Direction & Look Steering
		local camLook = Camera.CFrame.LookVector
		local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit
		local isHoldingW = UserInputService:IsKeyDown(Enum.KeyCode.W)

		local horizVel = Vector3.new(pendulumVelocity.X, 0, pendulumVelocity.Z)
		local horizSpeed = math.max(horizVel.Magnitude, GrappleConfig.Physics.MinSpeed)

		local steerRate = isHoldingW and GrappleConfig.Physics.CameraSteerResponsiveness or (GrappleConfig.Physics.CameraSteerResponsiveness * 0.5)
		local targetHoriz = forwardFlat * horizSpeed
		horizVel = horizVel:Lerp(targetHoriz, math.clamp(steerRate * deltaTime, 0, 1))

		-- Lateral banking with A / D
		local camRight = Camera.CFrame.RightVector
		local rightFlat = Vector3.new(camRight.X, 0, camRight.Z).Unit
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			horizVel = horizVel - (rightFlat * (GrappleConfig.Physics.AirSteerForce * deltaTime))
		elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then
			horizVel = horizVel + (rightFlat * (GrappleConfig.Physics.AirSteerForce * deltaTime))
		end

		-- 🎢 True Pendulum Arc Velocity (Gravity swoop & skyward climb)
		local forwardRel = (currentPos - currentAnchorPosition):Dot(forwardFlat)
		local verticalDepth = math.max(currentAnchorPosition.Y - currentPos.Y, 15)
		local theta = math.atan2(forwardRel, verticalDepth)

		local pumpAccel = (isHoldingW and GrappleConfig.Physics.ForwardPumpForce or 25) * deltaTime
		local isVelocityPerk = (LocalPlayer:GetAttribute("SuitPerkType") == "Velocity")
		local effectiveMaxSpeed = if isVelocityPerk then math.floor(GrappleConfig.Physics.MaxSpeed * 1.15) else GrappleConfig.Physics.MaxSpeed
		horizSpeed = math.clamp(horizSpeed + pumpAccel, GrappleConfig.Physics.MinSpeed, effectiveMaxSpeed)

		local targetY = (horizSpeed * math.sin(theta)) + ((isHoldingW and GrappleConfig.Physics.UpwardClimbLift or 35) * 0.4)
		local currentY = pendulumVelocity.Y
		local newY = currentY + (targetY - currentY) * math.clamp(14 * deltaTime, 0, 1)

		-- 🛡️ Zero-Friction Wall Deflection
		if wallHit and wallNorm then
			local velIntoWall = horizVel:Dot(wallNorm)
			if velIntoWall < 0 then
				horizVel = horizVel - (wallNorm * velIntoWall) + (wallNorm * 15 * deltaTime)
			end
		end

		pendulumVelocity = Vector3.new(horizVel.X, newY, horizVel.Z)

		local totalSpeed = pendulumVelocity.Magnitude
		if totalSpeed > effectiveMaxSpeed then
			pendulumVelocity = pendulumVelocity.Unit * effectiveMaxSpeed
		elseif totalSpeed < GrappleConfig.Physics.MinSpeed and totalSpeed > 0.1 then
			pendulumVelocity = pendulumVelocity.Unit * GrappleConfig.Physics.MinSpeed
		end

		-- 🛣️ Dynamic Rope Elasticity & Vertical Weight Support
		currentRopeRadius = math.max(currentRopeRadius, currentDist * 0.94)
		local radialError = math.max(currentDist - currentRopeRadius, 0)
		local tensionY = -radialUnit.Y * (radialError * GrappleConfig.Physics.TensionStiffness)
		local tensionHoriz = Vector3.new(-radialUnit.X, 0, -radialUnit.Z) * (radialError * (GrappleConfig.Physics.TensionStiffness * 0.20))

		activeBodyVelocity.Velocity = pendulumVelocity + Vector3.new(tensionHoriz.X, tensionY, tensionHoriz.Z)
		if activeBodyGyro and pendulumVelocity.Magnitude > 5 then
			activeBodyGyro.CFrame = CFrame.lookAt(currentPos, currentPos + pendulumVelocity.Unit)
		end

		-- 🚀 70-Degree Apex Auto-Release
		local downwardVector = Vector3.new(0, -1, 0)
		local dotDown = math.clamp(radialUnit:Dot(downwardVector), -1, 1)
		local angleDeg = math.deg(math.acos(dotDown))

		local isMovingForward = pendulumVelocity:Dot(forwardFlat) > 5
		local isClimbing = pendulumVelocity.Y > 0
		local isForwardOfAnchor = (currentPos - currentAnchorPosition):Dot(forwardFlat) > 10

		if GrappleConfig.AutoRelease.Enabled and elapsedTime >= (GrappleConfig.AutoRelease.MinSwingDuration or 0.55) then
			local reached72Degrees = (angleDeg >= (GrappleConfig.AutoRelease.ApexAngleThreshold or 72) and isForwardOfAnchor and isClimbing and isMovingForward)
			local reachedApexCeiling = (angleDeg >= 82 and isForwardOfAnchor)
			local reachedTimeout = (elapsedTime >= (GrappleConfig.AutoRelease.MaxSwingDuration or 4.0))

			if reached72Degrees or reachedApexCeiling or reachedTimeout then
				stopGrapple(false)
			end
		elseif elapsedTime >= (GrappleConfig.AutoRelease.MaxSwingDuration or 4.0) then
			stopGrapple(false)
		end
		return
	end

	-- 🍃 4. Mid-Air Aerodynamic Gliding
	if isFreeGliding and not isSwinging and not isSlingshot and not WallMovement.isActive() then
		local wallHit, wallNorm = WallMovement.checkWallContact(rootPart, character, Camera)
		if wallHit and (os.clock() - WallMovement.getLastJumpTime() > 0.4) then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				WallMovement.startWallRun(character, rootPart, humanoid, wallNorm)
				return
			end
		end

		if TargetFinder.isNearGround(rootPart, character) or (humanoid.FloorMaterial ~= Enum.Material.Air) then
			isFreeGliding = false
			if activeBodyVelocity then
				activeBodyVelocity:Destroy()
				activeBodyVelocity = nil
			end
		else
			local horizVel = Vector3.new(glideVelocity.X, 0, glideVelocity.Z)
			local horizSpeed = horizVel.Magnitude

			if horizSpeed > 15 then
				local camLook = Camera.CFrame.LookVector
				local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit

				if UserInputService:IsKeyDown(Enum.KeyCode.W) then
					local steerSpeed = GrappleConfig.Gliding.SteerResponsiveness or 5.5
					horizVel = horizVel:Lerp(forwardFlat * horizSpeed, math.clamp(steerSpeed * deltaTime, 0, 1))
				end

				local decay = GrappleConfig.Gliding.DecayRate or 14
				local decayedSpeed = math.max(horizSpeed - (decay * deltaTime), 15)
				local newHoriz = horizVel.Unit * decayedSpeed

				local gravMult = GrappleConfig.Gliding.GravityMultiplier or 0.45
				local newY = glideVelocity.Y - (Workspace.Gravity * gravMult * deltaTime)
				glideVelocity = Vector3.new(newHoriz.X, newY, newHoriz.Z)

				if wallHit and wallNorm then
					local velIntoWall = glideVelocity:Dot(wallNorm)
					if velIntoWall < 0 then
						glideVelocity = glideVelocity - (wallNorm * velIntoWall) + (wallNorm * 2.0)
					end
				end

				if activeBodyVelocity then
					activeBodyVelocity.Velocity = glideVelocity
				end
			else
				isFreeGliding = false
				if activeBodyVelocity then
					activeBodyVelocity:Destroy()
					activeBodyVelocity = nil
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- 🎮 USER INPUT HANDLING
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or CameraController.isUIMode then return end

	if input.UserInputType == (GrappleConfig.Keybinds.Swing or Enum.UserInputType.MouseButton2) then
		startGrapple()
	elseif input.KeyCode == GrappleConfig.Keybinds.JumpKey then
		if WallMovement.isActive() then
			local _, rootPart, humanoid = getCharacterParts()
			local launchVel = WallMovement.stopWallRun(humanoid, true, Camera)
			glideVelocity = launchVel
			isFreeGliding = true
			if activeBodyVelocity then activeBodyVelocity.Velocity = launchVel end
			if rootPart then WebVisuals.playWebSound(rootPart) end
		elseif isSwinging or isSlingshot then
			stopGrapple(true)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, _)
	if input.UserInputType == (GrappleConfig.Keybinds.Swing or Enum.UserInputType.MouseButton2) and (isSwinging or isSlingshot) then
		stopGrapple(false)
	end
end)

-- Character setup
local function onCharacterAdded(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	CameraController.setupCharacter(hum)
	hum.Died:Connect(function()
		stopGrapple(false)
		if WallMovement.isActive() then WallMovement.stopWallRun(hum, false, Camera) end
	end)
end

if LocalPlayer.Character then onCharacterAdded(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- Init multiplayer replication
WebVisuals.initMultiplayerReplication(RemotesFolder)

-- 🎥 Camera RenderStepped Loop
RunService.RenderStepped:Connect(function(deltaTime)
	local _, rootPart, humanoid = getCharacterParts()
	local isFreeMoving = not isSwinging and not isSlingshot and not isFreeGliding and not WallMovement.isActive()
	CameraController.update(deltaTime, Camera, rootPart, humanoid, isFreeMoving)
end)

print("🕸️ Spider-Man Movement Engine active! Clean Modular Architecture online.")
