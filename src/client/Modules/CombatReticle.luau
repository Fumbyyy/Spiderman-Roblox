--!strict
--[[
	CombatReticle.luau
	Fluid Freeflow Targeting Engine for Spider-Man Combat:
	- Dynamic soft-target evaluation (angle, distance, proximity)
	- Returns current optimal target in crosshairs
	- Clean & UI-free (zero on-screen text clutter)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local CombatReticle = {}

local currentTarget: Model? = nil

-- 🔍 Dynamic Freeflow Update Loop (Runs in RenderStepped)
function CombatReticle.update(camera: Camera, rootPart: BasePart?): Model?
	if not rootPart then
		currentTarget = nil
		return nil
	end

	local camCFrame = camera.CFrame
	local camPos = camCFrame.Position
	local camLook = camCFrame.LookVector
	local playerPos = rootPart.Position

	local maxDist = CombatConfig.Targeting.MaxLockDistance or 65
	local maxAngle = math.rad(CombatConfig.Targeting.LockConeAngle or 45)
	local cosMaxAngle = math.cos(maxAngle)

	local bestEnemy: Model? = nil
	local bestScore = -999999

	local enemies = CollectionService:GetTagged("Enemy")
	for _, enemy in enemies do
		if enemy:IsA("Model") then
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			local enemyRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso") or enemy:FindFirstChild("Head")) :: BasePart?

			if humanoid and humanoid.Health > 0 and enemyRoot then
				local enemyPos = enemyRoot.Position
				local toEnemy = enemyPos - camPos
				local distance = (enemyPos - playerPos).Magnitude

				if distance <= maxDist then
					local dot = math.clamp(camLook:Dot(toEnemy.Unit), -1, 1)
					local angle = math.acos(dot)

					if angle <= maxAngle then
						local _, onScreen = camera:WorldToViewportPoint(enemyPos + Vector3.new(0, 0.5, 0))
						if onScreen then
							-- 🎯 1. Aim Accuracy (Crosshair Alignment): Looking directly at an enemy gives dominant score!
							local aimAccuracy = math.clamp((dot - cosMaxAngle) / (1 - cosMaxAngle), 0, 1)
							local aimScore = (aimAccuracy ^ 2.2) * 350

							-- ⚡ 2. Active Threat & Armed Priority (Snipers/Gunners & Attackers)
							local isArmed = (enemy:GetAttribute("IsArmed") == true) or (enemy:FindFirstChild("Gun") ~= nil)
							local isAttacking = enemy:GetAttribute("IsAttacking") == true
							local threatScore = 0
							if isAttacking then threatScore += 140 end
							if isArmed then threatScore += 90 end

							-- 📏 3. Gentle Proximity Base
							local proximityScore = (1.0 - (distance / maxDist)) * 80

							-- 🔒 4. Target Stickiness (prevents camera target jitter)
							local stickiness = (enemy == currentTarget) and 45 or 0

							local totalScore = aimScore + threatScore + proximityScore + stickiness

							if totalScore > bestScore then
								bestScore = totalScore
								bestEnemy = enemy
							end
						end
					end
				end
			end
		end
	end

	currentTarget = bestEnemy
	return currentTarget
end

function CombatReticle.getCurrentTarget(): Model?
	return currentTarget
end

return CombatReticle
