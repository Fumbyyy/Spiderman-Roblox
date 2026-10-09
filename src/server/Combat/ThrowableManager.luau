--!strict
--[[
	ThrowableManager.luau
	Handles Contextual Web-Yank Prop Throwing (Q Key), Double Web-Slam,
	auto-tagging of environmental props, and projectile trajectory physics.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local CombatDamage = require(script.Parent.CombatDamage)

local ThrowableManager = {}

local playerPropThrowCooldowns: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	playerPropThrowCooldowns[player] = nil
end)

-- 📦 Auto-tag creator-placed throwable props (military crates, manhole covers, etc.)
function ThrowableManager.registerThrowableCandidate(instance: Instance)
	if instance:IsA("BasePart") or instance:IsA("Model") then
		local nameLower = string.lower(instance.Name)
		if string.find(nameLower, "throwable") or string.find(nameLower, "militarytechcrate") or string.find(nameLower, "manhole") then
			if not CollectionService:HasTag(instance, "ThrowableObject") then
				CollectionService:AddTag(instance, "ThrowableObject")
			end
		end
	end
end

function ThrowableManager.init()
	for _, descendant in Workspace:GetDescendants() do
		ThrowableManager.registerThrowableCandidate(descendant)
	end
	Workspace.DescendantAdded:Connect(ThrowableManager.registerThrowableCandidate)
end

-- 📦 CONTEXTUAL WEB-YANK & PROP THROW / DOUBLE WEB SLAM (Q Key)
function ThrowableManager.handlePropThrow(
	player: Player,
	propInstance: any,
	targetModel: any,
	secondaryTargetArg: any?,
	combatVFXRemote: RemoteEvent
)
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local playerHum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not playerRoot or not playerHum or playerHum.Health <= 0 then return end

	-- 🕸️ Classic Peter Parker: Double Web-Slam
	if propInstance == "DoubleWebSlam" then
		local enemyA = targetModel
		local enemyB = secondaryTargetArg
		if typeof(enemyA) ~= "Instance" or not enemyA:IsA("Model") or not enemyA.Parent then return end
		if typeof(enemyB) ~= "Instance" or not enemyB:IsA("Model") or not enemyB.Parent then return end

		local aRoot = (enemyA:FindFirstChild("HumanoidRootPart") or enemyA:FindFirstChild("Torso")) :: BasePart?
		local aHum = enemyA:FindFirstChildOfClass("Humanoid")
		local bRoot = (enemyB:FindFirstChild("HumanoidRootPart") or enemyB:FindFirstChild("Torso")) :: BasePart?
		local bHum = enemyB:FindFirstChildOfClass("Humanoid")

		if not aRoot or not aHum or aHum.Health <= 0 or not bRoot or not bHum or bHum.Health <= 0 then return end

		-- Authoritatively validate distance (<= 48 studs from player)
		local distA = (aRoot.Position - playerRoot.Position).Magnitude
		local distB = (bRoot.Position - playerRoot.Position).Magnitude
		if distA > 48 or distB > 48 then return end

		local midPos = (aRoot.Position + bRoot.Position) * 0.5
		local dirA = (midPos - aRoot.Position)
		local dirB = (midPos - bRoot.Position)

		local pullA = (if dirA.Magnitude > 0.1 then dirA.Unit else playerRoot.CFrame.LookVector) * 38 + Vector3.new(0, 4, 0)
		local pullB = (if dirB.Magnitude > 0.1 then dirB.Unit else -playerRoot.CFrame.LookVector) * 38 + Vector3.new(0, 4, 0)

		-- Pull both enemies inward toward each other with 38 studs/s impulse
		aRoot.AssemblyLinearVelocity = pullA
		bRoot.AssemblyLinearVelocity = pullB

		-- Break Brute guard stances
		if enemyA:GetAttribute("Archetype") == "Brute" then
			enemyA:SetAttribute("GuardBroken", true)
			combatVFXRemote:FireAllClients("GuardBreakVFX", enemyA)
			task.delay(4.0, function()
				if enemyA.Parent and aHum and aHum.Health > 0 then
					enemyA:SetAttribute("GuardBroken", false)
				end
			end)
		end
		if enemyB:GetAttribute("Archetype") == "Brute" then
			enemyB:SetAttribute("GuardBroken", true)
			combatVFXRemote:FireAllClients("GuardBreakVFX", enemyB)
			task.delay(4.0, function()
				if enemyB.Parent and bHum and bHum.Health > 0 then
					enemyB:SetAttribute("GuardBroken", false)
				end
			end)
		end

		-- Apply 2 web stacks to both
		local stacksA = (enemyA:GetAttribute("WebStacks") or 0) + 2
		enemyA:SetAttribute("WebStacks", stacksA)
		if stacksA >= 3 then
			enemyA:SetAttribute("IsWebbed", true)
			aHum.WalkSpeed = 0
		end

		local stacksB = (enemyB:GetAttribute("WebStacks") or 0) + 2
		enemyB:SetAttribute("WebStacks", stacksB)
		if stacksB >= 3 then
			enemyB:SetAttribute("IsWebbed", true)
			bHum.WalkSpeed = 0
		end

		-- Deal 32 impact damage to both enemies
		CombatDamage.damageEnemy(enemyA, 32, pullA.Unit * 14, player)
		CombatDamage.damageEnemy(enemyB, 32, pullB.Unit * 14, player)

		-- Broadcast WeaponImpactSparks at midPos
		combatVFXRemote:FireAllClients("WeaponImpactSparks", midPos)
		return
	end

	-- Anti-Spam Rate Limit Validation
	local now = os.clock()
	local lastThrow = playerPropThrowCooldowns[player] or 0
	local cooldown = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.Cooldown) or 2.0
	if (now - lastThrow) < (cooldown - 0.25) then return end
	playerPropThrowCooldowns[player] = now

	-- Validate Prop
	if typeof(propInstance) ~= "Instance" or not propInstance.Parent then return end
	local propPart: BasePart? = nil
	if propInstance:IsA("BasePart") then
		propPart = propInstance
	elseif propInstance:IsA("Model") then
		propPart = propInstance.PrimaryPart or propInstance:FindFirstChildWhichIsA("BasePart")
	end
	if not propPart or not propPart.Parent then return end

	-- Distance Check (Max 55 studs with latency buffer)
	local distToProp = (propPart.Position - playerRoot.Position).Magnitude
	if distToProp > 55 then return end

	-- Anti-dupe: Check if already thrown
	if propInstance:GetAttribute("IsThrown") == true or propPart:GetAttribute("IsThrown") == true then
		return
	end
	propInstance:SetAttribute("IsThrown", true)
	propPart:SetAttribute("IsThrown", true)

	-- Replicate PropThrowVFX to all clients for multiplayer synchronization
	combatVFXRemote:FireAllClients("PropThrowVFX", player, propInstance, targetModel)

	-- Target Enemy Validation
	local targetRoot: BasePart? = nil
	local targetHum: Humanoid? = nil
	local hasValidTarget = false

	if typeof(targetModel) == "Instance" and targetModel:IsA("Model") and targetModel.Parent then
		targetRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
		targetHum = targetModel:FindFirstChildOfClass("Humanoid")
		if targetRoot and targetHum and targetHum.Health > 0 then
			local distToEnemy = (targetRoot.Position - playerRoot.Position).Magnitude
			if distToEnemy <= 75 then
				hasValidTarget = true
			end
		end
	end

	-- Kinetic Timing: 0.16s lift + 0.26s overhead arc = 0.42s until slingshot release
	local arcTotalTime = 0.42
	local throwSpeed = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.ThrowSpeed) or 125
	local throwDamage = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.Damage) or 35
	local knockbackForce = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.KnockbackForce) or 24
	local splashRadius = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.SplashRadius) or 10.0
	local splashDamage = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.SplashDamage) or 16
	local guardBreakDuration = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.GuardBreakDuration) or 4.0

	task.delay(arcTotalTime, function()
		if not playerRoot.Parent then return end

		local destPos: Vector3
		local impactDir: Vector3
		if hasValidTarget and targetRoot and targetModel.Parent then
			destPos = targetRoot.Position + Vector3.new(0, 1.0, 0)
			impactDir = (destPos - playerRoot.Position).Unit
		else
			impactDir = playerRoot.CFrame.LookVector
			destPos = playerRoot.Position + impactDir * 40
		end

		local flightDist = (destPos - playerRoot.Position).Magnitude
		local flightTime = math.clamp(flightDist / throwSpeed, 0.12, 0.32)

		task.delay(flightTime, function()
			-- 💥 Impact point execution
			if hasValidTarget and targetModel.Parent and targetHum and targetHum.Health > 0 and targetRoot then
				-- 🛡️ SHATTER GUARD ON BRUTE: Direct prop impact instantly shatters defensive guard!
				if targetModel:GetAttribute("Archetype") == "Brute" then
					targetModel:SetAttribute("GuardBroken", true)
					combatVFXRemote:FireAllClients("GuardBreakVFX", targetModel)
					task.delay(guardBreakDuration, function()
						if targetModel.Parent and targetHum.Health > 0 then
							targetModel:SetAttribute("GuardBroken", false)
						end
					end)
				end

				-- Apply heavy damage & physical knockback
				local flingVec = impactDir * knockbackForce + Vector3.new(0, 5, 0)
				CombatDamage.damageEnemy(targetModel, throwDamage, flingVec, player)
				combatVFXRemote:FireAllClients("WeaponImpactVFX", destPos, impactDir, throwDamage)
			else
				combatVFXRemote:FireAllClients("WeaponImpactVFX", destPos, impactDir)
			end

			-- AoE splash around impact point for clumped thugs (Checks all tagged enemies)
			for _, otherEnemy in CollectionService:GetTagged("Enemy") do
				if otherEnemy:IsA("Model") and otherEnemy ~= targetModel and otherEnemy.Parent then
					local oRoot = (otherEnemy:FindFirstChild("HumanoidRootPart") or otherEnemy:FindFirstChild("Torso")) :: BasePart?
					local oHum = otherEnemy:FindFirstChildOfClass("Humanoid")
					if oRoot and oHum and oHum.Health > 0 then
						local dist = (oRoot.Position - destPos).Magnitude
						if dist <= splashRadius then
							local splashDir = dist > 0.1 and (oRoot.Position - destPos).Unit or impactDir
							if otherEnemy:GetAttribute("Archetype") == "Brute" then
								otherEnemy:SetAttribute("GuardBroken", true)
								combatVFXRemote:FireAllClients("GuardBreakVFX", otherEnemy)
							end
							CombatDamage.damageEnemy(otherEnemy, splashDamage, splashDir * 16 + Vector3.new(0, 4, 0), player)
						end
					end
				end
			end

			-- Clean up prop with realistic physical tumble into Debris
			if propPart and propPart.Parent then
				propPart.Anchored = false
				propPart.CanCollide = true
				propPart.AssemblyLinearVelocity = impactDir * 18 + Vector3.new(0, 8, 0)
				propPart.AssemblyAngularVelocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))
				Debris:AddItem(propInstance, 3.5)
			end
		end)
	end)
end

return ThrowableManager
