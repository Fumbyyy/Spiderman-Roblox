--!strict
--[[
	GrappleController.client.luau
	Main Spider-Man Web-Swinging & Traversal Coordinator.
	
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
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
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

	local currentVel = pendulumVelocity
	if rootPart and rootPart.AssemblyLinearVelocity.Magnitude > currentVel.Magnitude then
		currentVel = rootPart.AssemblyLinearVelocity
	end

	if activeBodyGyro then activeBodyGyro:Destroy(); activeBodyGyro = nil end
	if activeWebBeamLeft then activeWebBeamLeft:Destroy(); activeWebBeamLeft = nil end
	if activeWebBeamRight then activeWebBeamRight:Destroy(); activeWebBeamRight = nil end
	if activeWorldAttLeft then activeWorldAttLeft:Destroy(); activeWorldAttLeft = nil end
	if activeWorldAttRight then activeWorldAttRight:Destroy(); activeWorldAttRight = nil end
	currentAnchorPosition = nil

	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	if rootPart then
		local forwardFlat = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z).Unit

		if wasSlingshot then
			glideVelocity = currentVel
		elseif isJumpLaunch then
			local jumpDir = (forwardFlat * 0.65 + Vector3.new(0, 0.75, 0)).Unit
			glideVelocity = currentVel + (jumpDir * 32)
		else
			glideVelocity = currentVel * (GrappleConfig.Launch.VelocityPreservation or 0.98)
		end

		local minSpeed = GrappleConfig.Launch.MinimumFlingSpeed or 80
		if glideVelocity.Magnitude < minSpeed then
			glideVelocity = (forwardFlat * minSpeed) + Vector3.new(0, GrappleConfig.Launch.BottomUpwardLift or 30, 0)
		end

		if not activeBodyVelocity then
			activeBodyVelocity = Instance.new("BodyVelocity")
			activeBodyVelocity.Name = "WebGlideVelocity"
			activeBodyVelocity.Parent = rootPart
		end

		activeBodyVelocity.MaxForce = Vector3.new(1e6, 1e5, 1e6)
		activeBodyVelocity.P = 4000
		activeBodyVelocity.Velocity = glideVelocity
		isFreeGliding = true
	end

	GrappleEndRemote:FireServer()
end

local function startGroundSlingshot(character: Model, rootPart: BasePart, humanoid: Humanoid)
	isSlingshot = true
	isSwinging = false
	isFreeGliding = false
	swingStartTime = os.clock()

	local camCFrame = Camera.CFrame
	local forwardFlat = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z).Unit
	local rightFlat = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z).Unit
	local origin = rootPart.Position

	local skyLeft = origin + (forwardFlat * 45) - (rightFlat * GrappleConfig.Slingshot.SpreadWidth) + Vector3.new(0, GrappleConfig.Slingshot.SkyHeight, 0)
	local skyRight = origin + (forwardFlat * 45) + (rightFlat * GrappleConfig.Slingshot.SpreadWidth) + Vector3.new(0, GrappleConfig.Slingshot.SkyHeight, 0)

	local worldLeft = Instance.new("Attachment"); worldLeft.WorldPosition = skyLeft; worldLeft.Parent = Workspace.Terrain
	local worldRight = Instance.new("Attachment"); worldRight.WorldPosition = skyRight; worldRight.Parent = Workspace.Terrain
	activeWorldAttLeft = worldLeft; activeWorldAttRight = worldRight

	activeWebBeamLeft = WebVisuals.createWebBeam(WebVisuals.getHandAttachment(character, false), worldLeft, rootPart)
	activeWebBeamRight = WebVisuals.createWebBeam(WebVisuals.getHandAttachment(character, true), worldRight, rootPart)

	local launchVel = (forwardFlat * GrappleConfig.Slingshot.ForwardVelocity) + Vector3.new(0, GrappleConfig.Slingshot.UpwardVelocity, 0)
	pendulumVelocity = launchVel

	if not activeBodyVelocity then
		activeBodyVelocity = Instance.new("BodyVelocity")
		activeBodyVelocity.Name = "SlingshotVelocity"
		activeBodyVelocity.Parent = rootPart
	end
	activeBodyVelocity.MaxForce = Vector3.new(1e7, 1e7, 1e7)
	activeBodyVelocity.P = 5000
	activeBodyVelocity.Velocity = launchVel

	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bg.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + forwardFlat + Vector3.new(0, 0.45, 0))
	bg.Parent = rootPart
	activeBodyGyro = bg

	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	WebVisuals.playWebSound(rootPart)
	GrappleStartRemote:FireServer(skyLeft, false)
	GrappleStartRemote:FireServer(skyRight, true)
end

local function startAirSwing(character: Model, rootPart: BasePart, humanoid: Humanoid, anchorPos: Vector3, isRight: boolean)
	local ropeRadius = math.max((rootPart.Position - anchorPos).Magnitude, GrappleConfig.Physics.MinRopeLength)
	isSwinging = true
	isSlingshot = false
	isFreeGliding = false
	swingStartTime = os.clock()
	currentAnchorPosition = anchorPos
	currentRopeRadius = ropeRadius

	local camLook = Camera.CFrame.LookVector
	local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit

	local incomingVel = isFreeGliding and glideVelocity or rootPart.AssemblyLinearVelocity
	local incomingSpeed = incomingVel.Magnitude

	local startSpeed = math.clamp(
		math.max(incomingSpeed * 1.05, GrappleConfig.Physics.InitialSwingSpeed),
		GrappleConfig.Physics.InitialSwingSpeed,
		GrappleConfig.Physics.MaxSpeed
	)

	local entryY = math.clamp(incomingVel.Y * 0.5, -20, 25)
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
	bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bg.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + pendulumVelocity.Unit)
	bg.Parent = rootPart
	activeBodyGyro = bg

	local worldAtt = Instance.new("Attachment"); worldAtt.WorldPosition = anchorPos; worldAtt.Parent = Workspace.Terrain
	local beam = WebVisuals.createWebBeam(WebVisuals.getHandAttachment(character, isRight), worldAtt, rootPart)

	if isRight then activeWorldAttRight = worldAtt; activeWebBeamRight = beam else activeWorldAttLeft = worldAtt; activeWebBeamLeft = beam end

	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	WebVisuals.playWebSound(rootPart)
	GrappleStartRemote:FireServer(anchorPos, isRight)
end

local function startGrapple()
	if WallMovement.isActive() then
		local _, _, humanoid = getCharacterParts()
		local launchVel = WallMovement.stopWallRun(humanoid, true, Camera)
		glideVelocity = launchVel; isFreeGliding = true
		if activeBodyVelocity then activeBodyVelocity.Velocity = launchVel end
		return
	end

	if (os.clock() - lastSwingEndTime) < (GrappleConfig.Cooldown.SwingCooldown or 0.22) then return end

	local character, rootPart, humanoid = getCharacterParts()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then return end

	if GrappleConfig.Slingshot.Enabled and TargetFinder.isNearGround(rootPart, character) then
		local lockedEnemy = CombatReticle.getCurrentTarget()
		if lockedEnemy and lockedEnemy.Parent then
			local enemyRoot = (lockedEnemy:FindFirstChild("HumanoidRootPart") or lockedEnemy:FindFirstChild("Torso")) :: BasePart?
			if enemyRoot and (enemyRoot.Position - rootPart.Position).Magnitude <= 35 then return end
		end
		startGroundSlingshot(character, rootPart, humanoid)
	else
		local anchorPos, isRight = TargetFinder.findBuildingAnchor(character, rootPart, Camera)
		if anchorPos then startAirSwing(character, rootPart, humanoid, anchorPos, isRight) end
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	local character, rootPart, humanoid = getCharacterParts()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
		if isSwinging or isSlingshot then stopGrapple(false) end
		return
	end

	local currentPos = rootPart.Position
	local elapsedTime = os.clock() - swingStartTime

	-- 1. Wall Movement
	if WallMovement.isActive() then
		if not WallMovement.update(rootPart, character, humanoid, Camera) then
			WallMovement.stopWallRun(humanoid, false, Camera)
		end
		return
	end

	-- 2. Slingshot Update
	if isSlingshot then
		if elapsedTime >= GrappleConfig.Slingshot.Duration then
			stopGrapple(false)
		end
		return
	end

	-- 3. Web Swing Spherical Pendulum Physics
	if isSwinging and currentAnchorPosition and activeBodyVelocity then
		-- Check wall contact for auto wall-run
		local wallHit, wallNorm = WallMovement.checkWallContact(rootPart, character, Camera)
		if wallHit and (os.clock() - WallMovement.getLastJumpTime() > 0.4) then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				stopGrapple(false)
				WallMovement.startWallRun(character, rootPart, humanoid, wallNorm)
				return
			end
		end

		local radialVector = currentPos - currentAnchorPosition
		local radialUnit = radialVector.Unit

		local forwardFlat = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z).Unit
		local rightFlat = Vector3.new(Camera.CFrame.RightVector.X, 0, Camera.CFrame.RightVector.Z).Unit

		local horizVel = Vector3.new(pendulumVelocity.X, 0, pendulumVelocity.Z)
		local horizSpeed = math.max(horizVel.Magnitude, GrappleConfig.Physics.MinSpeed)

		local isHoldingW = UserInputService:IsKeyDown(Enum.KeyCode.W)
		local isHoldingS = UserInputService:IsKeyDown(Enum.KeyCode.S)
		local isHoldingA = UserInputService:IsKeyDown(Enum.KeyCode.A)
		local isHoldingD = UserInputService:IsKeyDown(Enum.KeyCode.D)

		local moveIntent = Vector3.zero
		if isHoldingW then moveIntent = moveIntent + forwardFlat end
		if isHoldingS then moveIntent = moveIntent - forwardFlat end
		if isHoldingA then moveIntent = moveIntent - rightFlat end
		if isHoldingD then moveIntent = moveIntent + rightFlat end

		local targetDir = forwardFlat
		if moveIntent.Magnitude > 0.1 then
			targetDir = moveIntent.Unit
		end

		local steerRate = (moveIntent.Magnitude > 0.1) and 10.5 or 4.5
		horizVel = horizVel:Lerp(targetDir * horizSpeed, math.clamp(steerRate * deltaTime, 0, 1))

		-- Forward pump on W, brake on S
		if isHoldingW then
			local pumpAccel = (GrappleConfig.Physics.ForwardPumpForce or 75) * deltaTime
			horizSpeed = math.clamp(horizSpeed + pumpAccel, GrappleConfig.Physics.MinSpeed, GrappleConfig.Physics.MaxSpeed)
		elseif isHoldingS then
			horizSpeed = math.max(horizSpeed - (40 * deltaTime), GrappleConfig.Physics.MinSpeed)
		end

		-- Lateral banking with A / D
		if isHoldingA then
			horizVel = horizVel - (rightFlat * ((GrappleConfig.Physics.AirSteerForce or 70) * deltaTime))
		elseif isHoldingD then
			horizVel = horizVel + (rightFlat * ((GrappleConfig.Physics.AirSteerForce or 70) * deltaTime))
		end

		-- Harmonic pendulum arc velocity (swoop down, launch up)
		local forwardRel = (currentPos - currentAnchorPosition):Dot(forwardFlat)
		local verticalDepth = math.max(currentAnchorPosition.Y - currentPos.Y, 15)
		local theta = math.atan2(forwardRel, verticalDepth)

		local targetY = (horizSpeed * math.sin(theta)) + ((isHoldingW and (GrappleConfig.Physics.UpwardClimbLift or 65) or 40) * 0.5)
		local currentY = pendulumVelocity.Y
		local newY = currentY + (targetY - currentY) * math.clamp(12 * deltaTime, 0, 1)

		-- Wall Deflection
		if wallHit and wallNorm then
			local velIntoWall = horizVel:Dot(wallNorm)
			if velIntoWall < 0 then
				horizVel = horizVel - (wallNorm * velIntoWall) + (wallNorm * 15 * deltaTime)
			end
		end

		pendulumVelocity = Vector3.new(horizVel.X, newY, horizVel.Z)

		local totalSpeed = pendulumVelocity.Magnitude
		if totalSpeed > GrappleConfig.Physics.MaxSpeed then
			pendulumVelocity = pendulumVelocity.Unit * GrappleConfig.Physics.MaxSpeed
		elseif totalSpeed < GrappleConfig.Physics.MinSpeed and totalSpeed > 0.1 then
			pendulumVelocity = pendulumVelocity.Unit * GrappleConfig.Physics.MinSpeed
		end

		activeBodyVelocity.Velocity = pendulumVelocity
		if activeBodyGyro and pendulumVelocity.Magnitude > 5 then
			activeBodyGyro.CFrame = CFrame.lookAt(currentPos, currentPos + pendulumVelocity.Unit)
		end

		-- Apex Auto-Release
		local downwardVector = Vector3.new(0, -1, 0)
		local dotDown = math.clamp(radialUnit:Dot(downwardVector), -1, 1)
		local angleDeg = math.deg(math.acos(dotDown))

		local isMovingForward = pendulumVelocity:Dot(forwardFlat) > 5
		local isClimbing = pendulumVelocity.Y > 0

		if GrappleConfig.AutoRelease.Enabled and elapsedTime >= (GrappleConfig.AutoRelease.MinSwingDuration or 0.45) then
			local reachedApex = (angleDeg >= (GrappleConfig.AutoRelease.ApexAngleThreshold or 68) and isClimbing and isMovingForward)
			local reachedApexCeiling = (angleDeg >= 78)
			local reachedTimeout = (elapsedTime >= (GrappleConfig.AutoRelease.MaxSwingDuration or 3.5))

			if reachedApex or reachedApexCeiling or reachedTimeout then
				stopGrapple(false)
			end
		elseif elapsedTime >= (GrappleConfig.AutoRelease.MaxSwingDuration or 3.5) then
			stopGrapple(false)
		end
		return
	end

	-- 4. Mid-Air Gliding
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
				local forwardFlat = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z).Unit
				local rightFlat = Vector3.new(Camera.CFrame.RightVector.X, 0, Camera.CFrame.RightVector.Z).Unit

				local isHoldingW = UserInputService:IsKeyDown(Enum.KeyCode.W)
				local isHoldingS = UserInputService:IsKeyDown(Enum.KeyCode.S)
				local isHoldingA = UserInputService:IsKeyDown(Enum.KeyCode.A)
				local isHoldingD = UserInputService:IsKeyDown(Enum.KeyCode.D)

				local moveIntent = Vector3.zero
				if isHoldingW then moveIntent = moveIntent + forwardFlat end
				if isHoldingS then moveIntent = moveIntent - forwardFlat end
				if isHoldingA then moveIntent = moveIntent - rightFlat end
				if isHoldingD then moveIntent = moveIntent + rightFlat end

				if moveIntent.Magnitude > 0.1 then
					horizVel = horizVel:Lerp(moveIntent.Unit * horizSpeed, math.clamp(9.5 * deltaTime, 0, 1))
				else
					horizVel = horizVel:Lerp(forwardFlat * horizSpeed, math.clamp(5.5 * deltaTime, 0, 1))
				end

				if isHoldingW then
					horizSpeed = math.min(horizSpeed + (20 * deltaTime), GrappleConfig.Gliding.MaxSpeed or 145)
				elseif isHoldingS then
					horizSpeed = math.max(horizSpeed - (30 * deltaTime), 15)
				end

				local decay = isHoldingW and (GrappleConfig.Gliding.DecayRate * 0.4) or (GrappleConfig.Gliding.DecayRate or 14)
				local decayedSpeed = math.max(horizSpeed - (decay * deltaTime), 15)
				local newHoriz = (horizVel.Magnitude > 0.1) and (horizVel.Unit * decayedSpeed) or (forwardFlat * decayedSpeed)

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

	-- Wind Rush audio loop update
	WebVisuals.updateWindSound(rootPart, rootPart.AssemblyLinearVelocity.Magnitude)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == (GrappleConfig.Keybinds.Swing or Enum.UserInputType.MouseButton2) then
		startGrapple()
	elseif input.KeyCode == GrappleConfig.Keybinds.JumpKey then
		if WallMovement.isActive() then
			local _, rootPart, humanoid = getCharacterParts()
			glideVelocity = WallMovement.stopWallRun(humanoid, true, Camera)
			isFreeGliding = true
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

local function onCharacterAdded(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	CameraController.setupCharacter(hum)
	hum.Died:Connect(function() stopGrapple(false) end)
end

if LocalPlayer.Character then onCharacterAdded(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

WebVisuals.initMultiplayerReplication(RemotesFolder)

RunService.RenderStepped:Connect(function(deltaTime)
	local _, rootPart, humanoid = getCharacterParts()
	CameraController.update(deltaTime, Camera, rootPart, humanoid, not isSwinging and not isSlingshot and not isFreeGliding and not WallMovement.isActive())
end)

print("🕸️ Spider-Man Movement Engine active! Pure, Solid & Fluid Pendulum Physics Online.")
