--!strict
--[[
	CameraController.luau
	Web Rush Style Butter-Smooth Action Camera & Dynamic FOV System.
	- Free Cam for traversal, parkour & movement exploration
	- Snappy ShiftLock strictly when actively engaging in combat
	- Zero micro-stutters: Stable eye-level camera pivot without lateral wobble
	- Dynamic FOV: Smoothly expands with high-speed swinging and dives
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GrappleConfig = require(Shared:WaitForChild("GrappleConfig"))

local CameraController = {
	isCombatLocked = false,
	isUIMode = false,
}

function CameraController.setCombatLocked(locked: boolean)
	CameraController.isCombatLocked = locked
end

function CameraController.setUIMode(enabled: boolean)
	CameraController.isUIMode = enabled
	if enabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		if GrappleConfig.Camera.HideCursor then
			UserInputService.MouseIconEnabled = false
		end
	end
end

-- 🎥 Setup character humanoid camera offset
function CameraController.setupCharacter(humanoid: Humanoid)
	humanoid.AutoRotate = true
	humanoid.CameraOffset = Vector3.new(0, 1.0, 0)
end

-- 🎥 RenderStepped Camera Update (Dynamic FOV & Action Camera)
function CameraController.update(deltaTime: number, camera: Camera, rootPart: BasePart?, humanoid: Humanoid?, isFreeMoving: boolean)
	if not rootPart or not humanoid or humanoid.Health <= 0 then return end

	-- 🔓 UI Mode: Release mouse lock so player can freely click menus & phone
	if CameraController.isUIMode then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
		return
	end

	-- 🔒 Action Camera Shift-Lock: Smoothly keep mouse locked without constant property re-assignment flickering
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	if GrappleConfig.Camera.HideCursor and UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = false
	end

	-- Smooth character body rotation towards camera look direction when on the ground & moving freely
	if isFreeMoving and humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid.AutoRotate = false
		local camLookFlat = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z).Unit
		if camLookFlat.Magnitude > 0.05 then
			local currentPos = rootPart.Position
			local currentLook = rootPart.CFrame.LookVector
			local targetLook = currentLook:Lerp(camLookFlat, math.clamp(20 * deltaTime, 0.2, 0.8))
			rootPart.CFrame = CFrame.lookAt(currentPos, currentPos + targetLook)
		end
	end

	-- 💨 Dynamic FOV: Smoothly expand FOV with high-speed swinging (70 to 82)
	if GrappleConfig.Camera.DynamicFOV and GrappleConfig.Camera.DynamicFOV.Enabled then
		local currentSpeed = rootPart.AssemblyLinearVelocity.Magnitude
		local speedRatio = math.clamp((currentSpeed - 35) / 90, 0, 1)
		local targetFOV = GrappleConfig.Camera.DynamicFOV.BaseFOV + (speedRatio * (GrappleConfig.Camera.DynamicFOV.MaxFOV - GrappleConfig.Camera.DynamicFOV.BaseFOV))
		local fovLerp = math.clamp(GrappleConfig.Camera.DynamicFOV.LerpSpeed * deltaTime, 0, 1)
		camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * fovLerp
	end
end

return CameraController
