--!strict
--[[
	CombatDamage.luau
	Authoritative enemy damage, knockback calculations, brute shield blocking,
	wall-pin slide physics, and defeat ragdoll conversion.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local CombatDamage = {}

-- 💀 Convert an NPC Model into a full Ragdoll on Defeat
function CombatDamage.applyRagdoll(enemyModel: Model)
	local head = enemyModel:FindFirstChild("Head") :: BasePart?
	if head then
		local gui = head:FindFirstChild("HealthGui")
		if gui then gui:Destroy() end
	end

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
	end

	for _, descendant in enemyModel:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name ~= "RootJoint" then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 and part1 then
				local att0 = Instance.new("Attachment")
				att0.CFrame = descendant.C0
				att0.Parent = part0

				local att1 = Instance.new("Attachment")
				att1.CFrame = descendant.C1
				att1.Parent = part1

				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = att0
				socket.Attachment1 = att1
				socket.LimitsEnabled = true
				socket.TwistLimitsEnabled = true
				socket.Parent = part0

				descendant:Destroy()
			end
		end
	end

	Debris:AddItem(enemyModel, CombatConfig.Enemies.RespawnDelay)
end

-- 💥 Apply Damage & Controlled Knockback (Zero Extreme Flinging!)
function CombatDamage.damageEnemy(enemyModel: Model, damageAmount: number, knockbackDir: Vector3?, attackingPlayer: Player?)
	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	local rootPart = (enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:FindFirstChild("Torso")) :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not rootPart then return end

	local validDamage = (typeof(damageAmount) == "number" and damageAmount > 0) and damageAmount or 6
	humanoid:TakeDamage(validDamage)

	-- Stagger active enemy attack on impact
	if enemyModel:GetAttribute("IsAttacking") == true then
		enemyModel:SetAttribute("IsAttacking", false)
		enemyModel:SetAttribute("AttackDodged", true)
	end

	-- Visible physical knockback impulse
	if knockbackDir and knockbackDir.Magnitude > 0 and (enemyModel:GetAttribute("IsPinned") ~= true) then
		local clampedHoriz = Vector3.new(knockbackDir.X, 0, knockbackDir.Z)
		if clampedHoriz.Magnitude > 22 then
			clampedHoriz = clampedHoriz.Unit * 22
		end
		local clampedY = math.clamp(knockbackDir.Y, -25, 18)
		local finalVel = Vector3.new(clampedHoriz.X, clampedY, clampedHoriz.Z)

		local existingBv = rootPart:FindFirstChild("KnockbackImpulse")
		if existingBv then existingBv:Destroy() end

		local bv = Instance.new("BodyVelocity")
		bv.Name = "KnockbackImpulse"
		bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		bv.Velocity = finalVel
		bv.Parent = rootPart
		Debris:AddItem(bv, 0.26)

		-- True Knockdown on heavy finishers and dropkicks
		if clampedHoriz.Magnitude >= 18 then
			humanoid.PlatformStand = true
			task.delay(0.65, function()
				if enemyModel.Parent and humanoid and humanoid.Health > 0 then
					humanoid.PlatformStand = false
				end
			end)
		end
	end

	-- TSB Hitstun: Freeze thug movement during melee combos
	if enemyModel:GetAttribute("IsPinned") ~= true and enemyModel:GetAttribute("IsWebbed") ~= true and enemyModel:GetAttribute("VenomStunned") ~= true then
		humanoid.WalkSpeed = 0
		task.delay(0.40, function()
			if enemyModel.Parent and humanoid and humanoid.Health > 0 then
				if enemyModel:GetAttribute("IsPinned") ~= true and enemyModel:GetAttribute("IsWebbed") ~= true and enemyModel:GetAttribute("VenomStunned") ~= true then
					humanoid.WalkSpeed = 14
				end
			end
		end)
	end

	if attackingPlayer then
		enemyModel:SetAttribute("LastAttackerUserId", attackingPlayer.UserId)
	end

	if humanoid.Health <= 0 then
		enemyModel:SetAttribute("IsWebbed", false)
		enemyModel:SetAttribute("IsPinned", false)
		enemyModel:SetAttribute("WebStacks", 0)
		CombatDamage.applyRagdoll(enemyModel)

		-- Adrenaline Survival: +5 HP on enemy kill!
		local killer = attackingPlayer
		if not killer then
			local lastUid = enemyModel:GetAttribute("LastAttackerUserId")
			if typeof(lastUid) == "number" then
				killer = Players:GetPlayerByUserId(lastUid)
			end
		end

		if killer and killer.Character then
			local kHum = killer.Character:FindFirstChildOfClass("Humanoid")
			if kHum and kHum.Health > 0 then
				kHum.Health = math.clamp(kHum.Health + 5, 0, kHum.MaxHealth)
			end
		end
	end
end

-- 📌 Helper to check if webbed enemy is near a wall and web-yank them into it
function CombatDamage.checkAndPinToWall(enemyModel: Model, impactForceDir: Vector3?, combatVFXRemote: RemoteEvent?): boolean
	local enemyRoot = (enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:FindFirstChild("Torso")) :: BasePart?
	local enemyHum = enemyModel:FindFirstChildOfClass("Humanoid")
	if not enemyRoot or enemyModel:GetAttribute("IsPinned") == true then return false end

	-- 🕸️ STRICT: ONLY enemies with web stacks / cocoon can be pinned to walls!
	local isFullyWebbed = enemyModel:GetAttribute("IsWebbed") == true or (enemyModel:GetAttribute("WebStacks") or 0) >= 2
	if not isFullyWebbed then return false end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Filter out all characters (enemies and players) so only building walls/geometry are detected
	local excludeList: { Instance } = { enemyModel }
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if enemiesFolder then
		table.insert(excludeList, enemiesFolder)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excludeList, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = excludeList

	local maxDist = 8.0 -- Tight 8-stud proximity to wall required (not across the street!)

	-- Determine primary push direction (from attacker through enemy)
	local primaryDir: Vector3
	if impactForceDir and impactForceDir.Magnitude > 0.1 then
		primaryDir = Vector3.new(impactForceDir.X, 0, impactForceDir.Z).Unit
	else
		primaryDir = -enemyRoot.CFrame.LookVector
	end

	-- Check multiple candidate directions: direct push, angled cone, and behind enemy
	local checkDirs: { Vector3 } = {
		primaryDir,
		(CFrame.Angles(0, math.rad(28), 0):VectorToWorldSpace(primaryDir)),
		(CFrame.Angles(0, math.rad(-28), 0):VectorToWorldSpace(primaryDir)),
		(CFrame.Angles(0, math.rad(45), 0):VectorToWorldSpace(primaryDir)),
		(CFrame.Angles(0, math.rad(-45), 0):VectorToWorldSpace(primaryDir)),
		-enemyRoot.CFrame.LookVector,
		enemyRoot.CFrame.RightVector,
		-enemyRoot.CFrame.RightVector,
	}

	local rayOrigins: { Vector3 } = {
		enemyRoot.Position,
		enemyRoot.Position + Vector3.new(0, 1.2, 0), -- Chest / upper body height
	}

	for _, origin in rayOrigins do
		for _, dir in checkDirs do
			local hit = Workspace:Raycast(origin, dir.Unit * maxDist, rayParams)
			if hit and hit.Instance and not hit.Instance:IsA("Terrain") and math.abs(hit.Normal.Y) < 0.65 then
				-- 📌 Vertical building wall found -> Web-Yank Slide and Pin to Wall!
				enemyModel:SetAttribute("IsPinned", true)
				enemyModel:SetAttribute("IsWebbed", true)
				enemyModel:SetAttribute("WebStacks", 3)

				if enemyHum then
					enemyHum.PlatformStand = true
				end
				enemyRoot.AssemblyLinearVelocity = Vector3.zero
				enemyRoot.AssemblyAngularVelocity = Vector3.zero

				-- Clean up any existing body velocities
				for _, child in enemyRoot:GetChildren() do
					if child:IsA("BodyVelocity") then
						child:Destroy()
					end
				end

				-- Calculate snap CFrame flush against the wall facing outward
				local wallNormal = hit.Normal
				local snapPos = hit.Position + (wallNormal * 1.35)
				local targetCFrame = CFrame.lookAt(snapPos, snapPos + wallNormal)

				-- Slide duration scales with distance (0.15s - 0.24s)
				local slideDist = (snapPos - enemyRoot.Position).Magnitude
				local slideTime = math.clamp(slideDist / 60, 0.15, 0.25)

				if combatVFXRemote then
					combatVFXRemote:FireAllClients("WallPinnedVFX", enemyModel, hit.Position, wallNormal, slideTime)
				end

				-- Smoothly yank enemy into the wall
				local slideTween = TweenService:Create(enemyRoot, TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = targetCFrame,
				})
				slideTween:Play()

				slideTween.Completed:Connect(function()
					if enemyModel.Parent and enemyRoot then
						enemyRoot.Anchored = true
						enemyRoot.CFrame = targetCFrame
						local maxH = enemyHum and enemyHum.MaxHealth or 100
						CombatDamage.damageEnemy(enemyModel, maxH + 50, Vector3.zero) -- Clean wall knockout
					end
				end)

				return true
			end
		end
	end

	return false
end

-- 🛡️ Helper to check if Heavy Brute's armored shield blocks an incoming attack
function CombatDamage.isBruteBlockingFrontal(targetModel: Model, attackDir: Vector3): boolean
	local archetype = targetModel:GetAttribute("Archetype")
	if archetype ~= "Brute" then return false end
	if targetModel:GetAttribute("GuardBroken") == true then return false end
	if targetModel:GetAttribute("IsWebbed") == true or (targetModel:GetAttribute("WebStacks") or 0) >= 3 then return false end

	local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
	if not enemyRoot then return false end

	-- Flatten attackDir and enemy look vector to purely compare horizontal angles
	local flatAttack = Vector3.new(attackDir.X, 0, attackDir.Z)
	local flatLook = Vector3.new(enemyRoot.CFrame.LookVector.X, 0, enemyRoot.CFrame.LookVector.Z)
	if flatAttack.Magnitude < 0.01 or flatLook.Magnitude < 0.01 then return true end

	local dot = flatAttack.Unit:Dot(flatLook.Unit)
	-- Attack from front and sides hits shield (dot <= 0.35). Only attacks directly from behind (dot > 0.35) bypass shield!
	return dot <= 0.35
end

return CombatDamage
