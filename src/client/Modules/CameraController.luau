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

-- 🔒 Instantaneous Reactive Cursor & Mouse Lock Controls (Eliminates click & window-focus glitches)
UserInputService:GetPropertyChangedSignal("MouseIconEnabled"):Connect(function()
	if not CameraController.isUIMode and UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = false
	end
end)

UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
	if not CameraController.isUIMode and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end)

UserInputService.WindowFocused:Connect(function()
	if not CameraController.isUIMode then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end)

UserInputService.InputBegan:Connect(function(input)
	if not CameraController.isUIMode and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2) then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	end
end)

-- Initial cursor lockdown on module load
task.defer(function()
	if not CameraController.isUIMode then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end)

-- 🎥 Setup character humanoid camera offset
function CameraController.setupCharacter(humanoid: Humanoid)
	humanoid.AutoRotate = true
	humanoid.CameraOffset = Vector3.new(0, 1.0, 0)
end

-- 🎥 RenderStepped Camera Update (Dynamic FOV & Action Camera)
function CameraController.update(deltaTime: number, camera: Camera, rootPart: BasePart?, humanoid: Humanoid?, isFreeMoving: boolean)
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

	-- 🔒 Action Camera Shift-Lock: Smoothly keep mouse locked and cursor hidden
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	if UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = false
	end

	if not rootPart or not humanoid or humanoid.Health <= 0 then return end

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
