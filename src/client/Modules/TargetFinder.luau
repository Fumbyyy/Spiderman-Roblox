--!strict
--[[
	TargetFinder.luau
	Handles smart building targeting, forward-ledge raycasting along street corridors,
	ground proximity checks, and object-space hand matching.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GrappleConfig = require(Shared:WaitForChild("GrappleConfig"))

local TargetFinder = {}

-- 🔍 Check if the character is standing on the ground
function TargetFinder.isNearGround(rootPart: BasePart, character: Model): boolean
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local hit = Workspace:Raycast(
		rootPart.Position,
		Vector3.new(0, -7.5, 0),
		rayParams
	)
	return hit ~= nil
end

-- 🎯 Find the best elevated building anchor ahead of the player in the street corridor
function TargetFinder.findBuildingAnchor(character: Model, rootPart: BasePart, camera: Camera): (Vector3?, boolean)
	local camCFrame = camera.CFrame
	local origin = rootPart.Position
	local camLook = camCFrame.LookVector
	local forwardFlat = Vector3.new(camLook.X, 0, camLook.Z).Unit

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local maxDist = GrappleConfig.Targeting.MaxDistance or 135
	local minDist = GrappleConfig.Targeting.MinDistance or 25
	local minForward = GrappleConfig.Targeting.MinForwardDistance or 15
	local scanAngles = {-30, 30, -45, 45, -15, 15, -60, 60}
	local scanHeights = {20, 40, 65, 90}

	local bestAnchor: Vector3? = nil
	local bestScore = -999999

	for _, angle in scanAngles do
		local angleDir = (camCFrame * CFrame.Angles(0, math.rad(angle), 0)).LookVector
		for _, height in scanHeights do
			local targetDir = (angleDir * 100 + Vector3.new(0, height, 0)).Unit
			local hit = Workspace:Raycast(origin, targetDir * maxDist, rayParams)

			if hit and hit.Instance and not hit.Instance:IsA("Terrain") then
				local hitVector = hit.Position - origin
				local forwardDist = hitVector:Dot(forwardFlat)
				local totalDist = hitVector.Magnitude

				-- Must be forward of player and at least minDist away (never behind or at waist)
				if forwardDist >= minForward and totalDist >= minDist and totalDist <= maxDist then
					local hitPart = hit.Instance
					local anchorY = hit.Position.Y + 20

					-- Place anchor cleanly near upper roofline of building
					if hitPart:IsA("BasePart") then
						local partTopY = hitPart.Position.Y + (hitPart.Size.Y * 0.5)
						anchorY = math.clamp(partTopY, hit.Position.Y + 15, hit.Position.Y + 55)
					end

					-- Ensure anchor is naturally elevated above the player
					anchorY = math.clamp(anchorY, origin.Y + 28, origin.Y + 75)
					local anchorPos = Vector3.new(hit.Position.X, anchorY, hit.Position.Z)

					-- Prefer forward-facing, elevated anchors at balanced swinging distance (40-80 studs)
					local score = (forwardDist * 2.0) + ((anchorY - origin.Y) * 1.5) - (math.abs(totalDist - 60) * 0.4)
					if score > bestScore then
						bestScore = score
						bestAnchor = anchorPos
					end
				end
			end
		end
	end

	if bestAnchor then
		-- Positive X in character space is always physically to the RIGHT!
		local localPoint = rootPart.CFrame:PointToObjectSpace(bestAnchor)
		local isRight = (localPoint.X >= 0)
		return bestAnchor, isRight
	end

	return nil, true -- No valid nearby building in range
end

return TargetFinder
