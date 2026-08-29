--!strict
--[[
	CameraController.luau
	Handles over-the-shoulder hero camera, Dynamic FOV speed zooming,
	Auto-ShiftLock, and ground character rotation alignment.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GrappleConfig = require(Shared:WaitForChild("GrappleConfig"))

local CameraController = {}

-- 🎥 Setup character humanoid camera offset
function CameraController.setupCharacter(humanoid: Humanoid)
	if GrappleConfig.Camera.AutoShiftLock then
		humanoid.AutoRotate = false
		humanoid.CameraOffset = GrappleConfig.Camera.OverShoulderOffset
	end
end

-- 🎥 RenderStepped Camera Update (Dynamic FOV & ShiftLock)
function CameraController.update(deltaTime: number, camera: Camera, rootPart: BasePart?, humanoid: Humanoid?, isFreeMoving: boolean)
	if not GrappleConfig.Camera.AutoShiftLock then return end

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	if GrappleConfig.Camera.HideCursor then
		UserInputService.MouseIconEnabled = false
	end

	if not rootPart or not humanoid or humanoid.Health <= 0 then return end

	-- 💨 Dynamic FOV: Smoothly zoom out as you move faster (Web Rush action feeling)
	if GrappleConfig.Camera.DynamicFOV and GrappleConfig.Camera.DynamicFOV.Enabled then
		local currentSpeed = rootPart.AssemblyLinearVelocity.Magnitude
		local speedRatio = math.clamp((currentSpeed - 35) / 100, 0, 1)
		local targetFOV = GrappleConfig.Camera.DynamicFOV.BaseFOV + (speedRatio * (GrappleConfig.Camera.DynamicFOV.MaxFOV - GrappleConfig.Camera.DynamicFOV.BaseFOV))
		local fovLerp = math.clamp(GrappleConfig.Camera.DynamicFOV.LerpSpeed * deltaTime, 0, 1)
		camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * fovLerp
	end

	-- Ground ShiftLock alignment ONLY when touching ground (never interrupts mid-air physics!)
	if isFreeMoving and humanoid.FloorMaterial ~= Enum.Material.Air then
		if humanoid.AutoRotate ~= false then
			humanoid.AutoRotate = false
		end
		local camLookFlat = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z).Unit
		if camLookFlat.Magnitude > 0.05 then
			local currentPos = rootPart.Position
			local currentLook = rootPart.CFrame.LookVector
			local targetLook = currentLook:Lerp(camLookFlat, math.clamp(25 * deltaTime, 0.25, 0.85))
			rootPart.CFrame = CFrame.lookAt(currentPos, currentPos + targetLook)
		end
	end
end

return CameraController
