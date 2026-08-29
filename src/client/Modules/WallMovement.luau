--!strict
--[[
	WallMovement.luau
	Handles Spider-Man Wall-Running, Wall-Crawling, and Wall-Jumping mechanics.
]]

local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GrappleConfig = require(Shared:WaitForChild("GrappleConfig"))

local WallMovement = {}

-- Active wall-running physics state
local activeBodyVelocity: BodyVelocity? = nil
local activeBodyGyro: BodyGyro? = nil
local currentWallNormal = Vector3.new(0, 0, 1)
local isWallRunning = false
local lastWallJumpTime = 0

-- 🔍 Check if the character is in contact with a vertical building wall
function WallMovement.checkWallContact(rootPart: BasePart, character: Model, camera: Camera): (RaycastResult?, Vector3)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local origin = rootPart.Position
	local scanRadius = GrappleConfig.WallMovement.WallDetectionRadius or 4.5
	local camCFrame = camera.CFrame
	local lookFlat = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z).Unit
	local rightFlat = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z).Unit

	local directions = {
		lookFlat,
		-lookFlat,
		rightFlat,
		-rightFlat,
		(lookFlat + rightFlat).Unit,
		(lookFlat - rightFlat).Unit,
	}

	for _, dir in directions do
		local hit = Workspace:Raycast(origin, dir * scanRadius, rayParams)
		if hit and hit.Instance and not hit.Instance:IsA("Terrain") then
			-- Ensure it is a vertical wall surface (not floor or ceiling)
			if math.abs(hit.Normal.Y) < 0.40 then
				return hit, hit.Normal
			end
		end
	end

	return nil, Vector3.zero
end

function WallMovement.isActive(): boolean
	return isWallRunning
end

function WallMovement.getLastJumpTime(): number
	return lastWallJumpTime
end

-- 🕷️ Start Wall-Running Mode
function WallMovement.startWallRun(character: Model, rootPart: BasePart, humanoid: Humanoid, wallNormal: Vector3)
	isWallRunning = true
	currentWallNormal = wallNormal

	if not activeBodyVelocity then
		activeBodyVelocity = Instance.new("BodyVelocity")
		activeBodyVelocity.Name = "WallRunVelocity"
		activeBodyVelocity.Parent = rootPart
	end
	activeBodyVelocity.MaxForce = Vector3.new(1e7, 1e7, 1e7)
	activeBodyVelocity.P = 5000

	if not activeBodyGyro then
		activeBodyGyro = Instance.new("BodyGyro")
		activeBodyGyro.Name = "WallRunGyro"
		activeBodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
		activeBodyGyro.P = 5000
		activeBodyGyro.D = 300
		activeBodyGyro.Parent = rootPart
	end

	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
end

-- 🕷️ Update Wall-Run movement every frame
function WallMovement.update(rootPart: BasePart, character: Model, humanoid: Humanoid, camera: Camera): boolean
	if not isWallRunning or not activeBodyVelocity or not activeBodyGyro then
		return false
	end

	local wallHit, wallNorm = WallMovement.checkWallContact(rootPart, character, camera)
	if not wallHit or (humanoid.FloorMaterial ~= Enum.Material.Air) then
		-- Reached roof ledge or ground: dismount
		return false
	end

	currentWallNormal = wallNorm
	local currentPos = rootPart.Position

	local isHoldingW = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local isHoldingS = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local isHoldingA = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local isHoldingD = UserInputService:IsKeyDown(Enum.KeyCode.D)

	if isHoldingS then
		return false
	end

	-- Compute wall surface directional vectors
	local wallUp = Vector3.new(0, 1, 0)
	local wallRight = wallNorm:Cross(wallUp).Unit

	local moveY = 0
	local moveX = 0

	if isHoldingW then
		moveY = GrappleConfig.WallMovement.WallRunSpeed or 52
	else
		moveY = (GrappleConfig.WallMovement.WallClimbSpeed or 30) * 0.5
	end

	if isHoldingA then
		moveX = -(GrappleConfig.WallMovement.WallLateralSpeed or 35)
	elseif isHoldingD then
		moveX = (GrappleConfig.WallMovement.WallLateralSpeed or 35)
	end

	-- Suction to wall while sprinting up and across
	local stickForce = -wallNorm * 12
	local wallVelocity = (wallUp * moveY) + (wallRight * moveX) + stickForce

	activeBodyVelocity.Velocity = wallVelocity
	activeBodyGyro.CFrame = CFrame.lookAt(currentPos, currentPos - wallNorm, wallUp)
	return true
end

-- 🕷️ Stop Wall-Run and return launch velocity if jump-cancelling
function WallMovement.stopWallRun(humanoid: Humanoid?, launchOff: boolean, camera: Camera): Vector3
	isWallRunning = false

	if activeBodyVelocity then
		activeBodyVelocity:Destroy()
		activeBodyVelocity = nil
	end
	if activeBodyGyro then
		activeBodyGyro:Destroy()
		activeBodyGyro = nil
	end

	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	if launchOff then
		lastWallJumpTime = os.clock()
		local jumpForce = GrappleConfig.WallMovement.WallJumpForce or 75
		local camLook = camera.CFrame.LookVector
		local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit

		-- Spring off the wall into the sky
		return (currentWallNormal * (jumpForce * 0.55)) + (forwardFlat * (jumpForce * 0.45)) + Vector3.new(0, jumpForce * 0.75, 0)
	else
		return Vector3.new(0, 15, 0)
	end
end

return WallMovement
