--!strict
--[[
	CombatService.server.luau
	Full Server Combat Authority for Spider-Man 6-Move Combat System.
	Validates damage, handles Air Launchers, Ground Slam AoE Shockwaves,
	Wall-Pinning, Weapon Hurl-Backs, Spider-Sense Dodges, and Ragdoll Physics.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

-- 📦 Create Combat Remotes Folder
local CombatRemotesFolder = ReplicatedStorage:FindFirstChild("CombatRemotes")
if not CombatRemotesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "CombatRemotes"
	folder.Parent = ReplicatedStorage
	CombatRemotesFolder = folder
end

local function getOrCreateRemote(name: string): RemoteEvent
	local remote = CombatRemotesFolder:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteEvent") then
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = name
		newRemote.Parent = CombatRemotesFolder
		return newRemote
	end
	return remote
end

local KineticComboRemote = getOrCreateRemote("KineticCombo")
local UppercutRemote = getOrCreateRemote("UppercutLauncher")
local GroundSlamRemote = getOrCreateRemote("AirGroundSlam")
local WebPelletRemote = getOrCreateRemote("WebPellet")
local DisarmThrowRemote = getOrCreateRemote("DisarmAndThrow")
local DodgeRemote = getOrCreateRemote("SpiderSenseDodge")
local WebStrikeRemote = getOrCreateRemote("WebStrike")
local WebCycloneRemote = getOrCreateRemote("WebCycloneRemote")
local QuickHealRemote = getOrCreateRemote("QuickHealRemote")
local CombatVFXRemote = getOrCreateRemote("CombatVFX")

-- 💀 Convert an NPC Model into a full Ragdoll on Defeat
local function applyRagdoll(enemyModel: Model)
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
local function damageEnemy(enemyModel: Model, damageAmount: number, knockbackDir: Vector3?)
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
		if clampedHoriz.Magnitude > 24 then
			clampedHoriz = clampedHoriz.Unit * 24
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
		Debris:AddItem(bv, 0.16)
	end

	if humanoid.Health <= 0 then
		enemyModel:SetAttribute("IsWebbed", false)
		enemyModel:SetAttribute("IsPinned", false)
		enemyModel:SetAttribute("WebStacks", 0)
		applyRagdoll(enemyModel)
	end
end

-- 📌 Helper to check if webbed enemy is near a wall and web-yank them into it
local function checkAndPinToWall(enemyModel: Model, impactForceDir: Vector3?): boolean
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

				enemyHum.PlatformStand = true
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

				CombatVFXRemote:FireAllClients("WallPinnedVFX", enemyModel, hit.Position, wallNormal, slideTime)

				-- Smoothly yank enemy into the wall
				local slideTween = TweenService:Create(enemyRoot, TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = targetCFrame,
				})
				slideTween:Play()

				slideTween.Completed:Connect(function()
					if enemyModel.Parent and enemyRoot then
						enemyRoot.Anchored = true
						enemyRoot.CFrame = targetCFrame
						damageEnemy(enemyModel, enemyHum.MaxHealth + 50, Vector3.zero) -- Clean wall knockout
					end
				end)

				return true
			end
		end
	end

	return false
end

-- 🛡️ Helper to check if Heavy Brute's armored shield blocks an incoming attack
local function isBruteBlockingFrontal(targetModel: Model, attackDir: Vector3): boolean
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

--------------------------------------------------------------------------------
-- 1. 🥊 KINETIC STRIKE COMBO (L-Click Tap - Multi-Target AoE Cleave)
--------------------------------------------------------------------------------
KineticComboRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, comboIndex: any)
	local hitNum = math.clamp(typeof(comboIndex) == "number" and comboIndex or 1, 1, 3)

	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not playerRoot then return end

	-- 💥 Correct Damage Calculation
	local damage: number
	if hitNum == 3 then
		damage = CombatConfig.Moves.KineticCombo.Hit3Damage or 18
	elseif hitNum == 2 then
		damage = CombatConfig.Moves.KineticCombo.Hit2Damage or 10
	else
		damage = CombatConfig.Moves.KineticCombo.Hit1Damage or 7
	end

	local forward = playerRoot.CFrame.LookVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z).Unit

	-- Cleave reach & angle
	local maxReach = (hitNum == 3) and (CombatConfig.Moves.KineticCombo.FinisherCleaveRadius or 8.2) or (CombatConfig.Moves.KineticCombo.CleaveRadius or 7.0)
	local cleaveAngle = CombatConfig.Moves.KineticCombo.CleaveConeAngle or 70
	local cosCleaveAngle = math.cos(math.rad(cleaveAngle))

	-- Collect all candidate enemies in the forward punch cleave arc
	local hitEnemies: { [Model]: boolean } = {}
	local enemiesFolder = Workspace:FindFirstChild("Enemies")

	if enemiesFolder then
		for _, enemy in enemiesFolder:GetChildren() do
			if enemy:IsA("Model") then
				local enemyHum = enemy:FindFirstChildOfClass("Humanoid")
				local enemyRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				if enemyHum and enemyHum.Health > 0 and enemyRoot then
					local toEnemy = enemyRoot.Position - playerRoot.Position
					local dist = toEnemy.Magnitude
					if dist <= maxReach then
						local flatToEnemy = Vector3.new(toEnemy.X, 0, toEnemy.Z).Unit
						local dot = flatForward:Dot(flatToEnemy)
						if enemy == targetModel or dot >= cosCleaveAngle or dist <= 3.8 then
							hitEnemies[enemy] = true
						end
					end
				end
			end
		end
	end

	-- Process damage and reactions for all hit enemies
	for enemyModel in hitEnemies do
		local enemyHum = enemyModel:FindFirstChildOfClass("Humanoid")
		local enemyRoot = (enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:FindFirstChild("Torso")) :: BasePart?
		if enemyHum and enemyHum.Health > 0 and enemyRoot then
			local punchDir = (enemyRoot.Position - playerRoot.Position).Unit

			-- 🛡️ Check if this specific enemy is a Heavy Brute blocking the frontal punch
			if isBruteBlockingFrontal(enemyModel, punchDir) then
				CombatVFXRemote:FireAllClients("BruteBlockVFX", enemyModel, punchDir)
				continue
			end

			local isFullyWebbed = enemyModel:GetAttribute("IsWebbed") == true or (enemyModel:GetAttribute("WebStacks") or 0) >= 3

			local knockback: Vector3
			if isFullyWebbed and hitNum < 3 then
				knockback = Vector3.zero
			elseif hitNum == 3 then
				knockback = punchDir * 22 + Vector3.new(0, 4, 0)
			else
				knockback = punchDir * 8
			end

			damageEnemy(enemyModel, damage, knockback)
			CombatVFXRemote:FireAllClients("KineticHit", player, enemyModel, hitNum)

			-- 💥 Wall-Pin Synergy on 3rd hit
			if hitNum == 3 and isFullyWebbed then
				task.delay(0.10, function()
					if enemyModel.Parent and enemyHum.Health > 0 then
						checkAndPinToWall(enemyModel, punchDir)
					end
				end)
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- 2. 🚀 UPPERCUT LAUNCHER (Hold L-Click - Multi-Target Launcher)
--------------------------------------------------------------------------------
UppercutRemote.OnServerEvent:Connect(function(player: Player, targetModel: any)
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not playerRoot then return end

	local launchY = CombatConfig.Moves.Uppercut.LaunchVelocity or 48
	local maxReach = 7.0
	local forward = playerRoot.CFrame.LookVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z).Unit

	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if not enemiesFolder then return end

	local hitAny = false
	for _, enemy in enemiesFolder:GetChildren() do
		if enemy:IsA("Model") then
			local enemyHum = enemy:FindFirstChildOfClass("Humanoid")
			local enemyRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
			if enemyHum and enemyHum.Health > 0 and enemyRoot then
				local toEnemy = enemyRoot.Position - playerRoot.Position
				local dist = toEnemy.Magnitude
				if dist <= maxReach then
					local flatToEnemy = Vector3.new(toEnemy.X, 0, toEnemy.Z).Unit
					local dot = flatForward:Dot(flatToEnemy)
					if enemy == targetModel or dot >= 0.35 or dist <= 4.0 then
						local punchDir = toEnemy.Unit
						if isBruteBlockingFrontal(enemy, punchDir) then
							CombatVFXRemote:FireAllClients("BruteBlockVFX", enemy, punchDir)
							continue
						end

						hitAny = true
						enemyHum.PlatformStand = true
						local launchBv = Instance.new("BodyVelocity")
						launchBv.Name = "EnemyLaunchBv"
						launchBv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
						launchBv.Velocity = Vector3.new(0, launchY, 0)
						launchBv.Parent = enemyRoot
						Debris:AddItem(launchBv, 0.32)

						task.delay(0.32, function()
							if enemyRoot and enemyHum and enemyHum.Health > 0 and enemy.Parent then
								local floatBv = Instance.new("BodyVelocity")
								floatBv.Name = "EnemyAirFloat"
								floatBv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
								floatBv.Velocity = Vector3.new(0, 2.5, 0)
								floatBv.Parent = enemyRoot
								Debris:AddItem(floatBv, 1.4)

								task.delay(1.4, function()
									if enemyHum and enemyHum.Parent then
										enemyHum.PlatformStand = false
									end
								end)
							end
						end)

						damageEnemy(enemy, CombatConfig.Moves.Uppercut.Damage or 16, Vector3.zero)
						CombatVFXRemote:FireAllClients("Uppercut", player, enemy)
					end
				end
			end
		end
	end

	if hitAny or targetModel then
		playerRoot.AssemblyLinearVelocity = Vector3.new(playerRoot.AssemblyLinearVelocity.X, launchY, playerRoot.AssemblyLinearVelocity.Z)
	end
end)

--------------------------------------------------------------------------------
-- 3. 💥 WEB-LINE GROUND SLAM (In-Air Finisher & AoE Shockwave)
--------------------------------------------------------------------------------
GroundSlamRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, customImpactPos: any)
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not playerRoot then return end

	local impactPos = typeof(customImpactPos) == "Vector3" and customImpactPos or playerRoot.Position

	-- 1. If target enemy model is provided and in whip range, smash them down with heavy impact!
	local primaryHit = false
	if typeof(targetModel) == "Instance" and targetModel:IsA("Model") and targetModel.Parent then
		local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
		local enemyHum = targetModel:FindFirstChildOfClass("Humanoid")
		if enemyRoot and enemyHum and enemyHum.Health > 0 then
			local dist = (enemyRoot.Position - playerRoot.Position).Magnitude
			if dist <= 35 then
				local floatBv = enemyRoot:FindFirstChild("EnemyAirFloat")
				if floatBv then floatBv:Destroy() end

				local slamSpeed = CombatConfig.Moves.AirGroundSlam.SlamSpeed or 95
				enemyRoot.AssemblyLinearVelocity = Vector3.new(0, -slamSpeed, 0)
				damageEnemy(targetModel, CombatConfig.Moves.AirGroundSlam.Damage or 24, Vector3.zero)
				impactPos = enemyRoot.Position
				primaryHit = true
				CombatVFXRemote:FireAllClients("GroundSlamWebs", player, targetModel)
			end
		end
	end

	-- 2. Trigger AoE Radial Shockwave to all surrounding enemies (radius = 24 studs)
	local radius = CombatConfig.Moves.AirGroundSlam.ShockwaveRadius or 24
	local allEnemies: { Model } = {}

	for _, enemy in CollectionService:GetTagged("Enemy") do
		if enemy:IsA("Model") and not table.find(allEnemies, enemy) then
			table.insert(allEnemies, enemy)
		end
	end
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if enemiesFolder then
		for _, enemy in enemiesFolder:GetChildren() do
			if enemy:IsA("Model") and not table.find(allEnemies, enemy) then
				table.insert(allEnemies, enemy)
			end
		end
	end

	for _, otherEnemy in allEnemies do
		if otherEnemy ~= targetModel or not primaryHit then
			local otherRoot = (otherEnemy:FindFirstChild("HumanoidRootPart") or otherEnemy:FindFirstChild("Torso")) :: BasePart?
			local otherHum = otherEnemy:FindFirstChildOfClass("Humanoid")
			if otherRoot and otherHum and otherHum.Health > 0 then
				local horizDist = Vector3.new(otherRoot.Position.X - impactPos.X, 0, otherRoot.Position.Z - impactPos.Z).Magnitude
				local vertDiff = math.abs(otherRoot.Position.Y - impactPos.Y)
				if horizDist <= radius and vertDiff <= 16 then
					local pushDir = Vector3.new(otherRoot.Position.X - impactPos.X, 0.4, otherRoot.Position.Z - impactPos.Z).Unit
					damageEnemy(otherEnemy, CombatConfig.Moves.AirGroundSlam.ShockwaveDamage or 15, pushDir * 18)
				end
			end
		end
	end

	CombatVFXRemote:FireAllClients("ShockwaveVFX", impactPos, radius)
end)

local playerWebPelletCooldowns: { [Player]: number } = {}
local enemyWebDecayTimers: { [Model]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	playerWebPelletCooldowns[player] = nil
end)

local function handleWebPelletHit(player: Player, targetModel: Model)
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
	local enemyHum = targetModel:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not enemyRoot or not enemyHum or enemyHum.Health <= 0 then return end

	-- 🛡️ Distance Check (Max 55 studs)
	local dist = (enemyRoot.Position - playerRoot.Position).Magnitude
	if dist > 55 then return end

	-- Interrupt enemy attack telegraph on hit (tactile staggering counter!)
	if targetModel:GetAttribute("IsAttacking") == true then
		targetModel:SetAttribute("IsAttacking", false)
	end

	local pushDir = (enemyRoot.Position - playerRoot.Position).Unit
	local wasAlreadyWebbed = targetModel:GetAttribute("IsWebbed") == true

	-- 🕸️ If enemy is ALREADY in a cocoon, check if this follow-up shot can yank them into a wall!
	if wasAlreadyWebbed then
		local isPinned = checkAndPinToWall(targetModel, pushDir)
		if not isPinned then
			-- Still in open space: apply damage without disjointing the cocoon
			damageEnemy(targetModel, CombatConfig.Moves.WebPellet.Damage or 4, Vector3.zero)
			CombatVFXRemote:FireAllClients("WebPelletHit", player, targetModel, 3)
		end
		return
	end

	-- Increment Web Stacks (1 -> 2 -> 3)
	local currentStacks = math.clamp((targetModel:GetAttribute("WebStacks") or 0) + 1, 1, 3)
	targetModel:SetAttribute("WebStacks", currentStacks)

	-- 🛡️ Brute Armor Shield Check: If Brute has active frontal guard, web strands stick and entangle him (building stacks) with 0 direct HP damage!
	local isBlockingFrontal = isBruteBlockingFrontal(targetModel, pushDir)
	local pelletDamage = isBlockingFrontal and 0 or (CombatConfig.Moves.WebPellet.Damage or 5)
	local pelletKnockback = isBlockingFrontal and Vector3.zero or (pushDir * 4)

	if pelletDamage > 0 or pelletKnockback.Magnitude > 0 then
		damageEnemy(targetModel, pelletDamage, pelletKnockback)
	end
	CombatVFXRemote:FireAllClients("WebPelletHit", player, targetModel, currentStacks)

	-- Apply Progressive Slowdown
	local stack1Speed = CombatConfig.Moves.WebPellet.Stack1SlowSpeed or 9
	local stack2Speed = CombatConfig.Moves.WebPellet.Stack2SlowSpeed or 3

	if currentStacks == 1 then
		enemyHum.WalkSpeed = stack1Speed
	elseif currentStacks == 2 then
		enemyHum.WalkSpeed = stack2Speed
	elseif currentStacks >= (CombatConfig.Moves.WebPellet.HitsToTrap or 3) then
		-- 3 Stacks Reached: Check for Wall-Pin vs Open Street Cocoon
		local isPinned = checkAndPinToWall(targetModel, pushDir)

		if not isPinned then
			-- Free-Standing Web Cocoon!
			targetModel:SetAttribute("IsWebbed", true)
			enemyHum.WalkSpeed = 0
			enemyHum.JumpPower = 0
			enemyRoot.AssemblyLinearVelocity = Vector3.zero
			CombatVFXRemote:FireAllClients("CocoonVFX", targetModel)

			task.delay(CombatConfig.Moves.WebPellet.TrapDuration or 5.0, function()
				if targetModel.Parent and enemyHum.Health > 0 and (targetModel:GetAttribute("IsPinned") ~= true) then
					enemyHum.WalkSpeed = 16
					enemyHum.JumpPower = 50
					targetModel:SetAttribute("IsWebbed", false)
					targetModel:SetAttribute("WebStacks", 0)
					CombatVFXRemote:FireAllClients("CocoonBreakVFX", targetModel)
				end
			end)
		end
	end

	-- ⏳ Web Stack Decay: Reset stacks back to 0 if not webbed further within 2.8s
	if currentStacks < 3 then
		local decayId = os.clock()
		enemyWebDecayTimers[targetModel] = decayId
		task.delay(2.8, function()
			if enemyWebDecayTimers[targetModel] == decayId and targetModel.Parent and enemyHum.Health > 0 and (targetModel:GetAttribute("IsWebbed") ~= true) and (targetModel:GetAttribute("IsPinned") ~= true) then
				targetModel:SetAttribute("WebStacks", 0)
				enemyHum.WalkSpeed = 16
				CombatVFXRemote:FireAllClients("CocoonBreakVFX", targetModel)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- 4. 🕸️ RAPID WEB-PELLETS & WALL-PINNING (E Key)
--------------------------------------------------------------------------------
WebPelletRemote.OnServerEvent:Connect(function(player: Player, targetModel: any)
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end

	-- 🛡️ Anti-Spam Rate Limit Validation
	local now = os.clock()
	local lastFired = playerWebPelletCooldowns[player] or 0
	if (now - lastFired) < 0.18 then return end
	playerWebPelletCooldowns[player] = now

	handleWebPelletHit(player, targetModel)
end)

local playerDisarmCooldowns: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	playerWebPelletCooldowns[player] = nil
	playerDisarmCooldowns[player] = nil
end)

--------------------------------------------------------------------------------
-- 5. 🔫 WEB-YANK DISARM & WEAPON THROW (Q Key)
--------------------------------------------------------------------------------
DisarmThrowRemote.OnServerEvent:Connect(function(player: Player, targetModel: any)
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end

	local now = os.clock()
	local lastDisarm = playerDisarmCooldowns[player] or 0
	local cooldown = CombatConfig.Moves.DisarmAndThrow.Cooldown or 3.5
	if (now - lastDisarm) < cooldown then return end

	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
	local enemyHum = targetModel:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not enemyRoot or not enemyHum or enemyHum.Health <= 0 then return end

	local dist = (enemyRoot.Position - playerRoot.Position).Magnitude
	local maxDist = CombatConfig.Moves.DisarmAndThrow.MaxDistance or 45
	if dist > maxDist then return end

	-- Find and detach weapon
	local weaponHandle: BasePart? = nil
	local rightArm = targetModel:FindFirstChild("Right Arm") or targetModel:FindFirstChild("RightHand")
	if rightArm then
		for _, child in rightArm:GetChildren() do
			if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
				if child.Part1 and child.Part1 ~= rightArm then
					weaponHandle = child.Part1
					child:Destroy()
					break
				end
			end
		end
	end

	if not weaponHandle then
		weaponHandle = targetModel:FindFirstChild("Gun") :: BasePart?
	end

	if weaponHandle and weaponHandle:IsA("BasePart") then
		playerDisarmCooldowns[player] = now

		-- Strip weapon & disarm enemy permanently
		targetModel:SetAttribute("IsArmed", false)
		targetModel:SetAttribute("IsAttacking", false)
		weaponHandle.Parent = Workspace
		weaponHandle.CanCollide = false
		weaponHandle.Anchored = true

		-- 🏃 Physical Snatch Reaction: Thug gets yanked forward from the web tension!
		local pullDir = (playerRoot.Position - enemyRoot.Position).Unit
		damageEnemy(targetModel, 0, pullDir * 12 + Vector3.new(0, 2, 0))

		-- 1. Web Snatch & Overhead Whip Arc
		CombatVFXRemote:FireAllClients("DisarmYankVFX", player, weaponHandle)

		local sideApex = playerRoot.Position + (playerRoot.CFrame.RightVector * 3.4) + Vector3.new(0, 2.6, 0)
		local tweenSnatch = TweenService:Create(weaponHandle, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = sideApex,
			Orientation = Vector3.new(35, 120, 65),
		})
		tweenSnatch:Play()

		-- 2. Sweeping Circular Orbit around Spider-Man
		tweenSnatch.Completed:Connect(function()
			if not weaponHandle or not weaponHandle.Parent then return end

			local forwardRelease = playerRoot.Position + (playerRoot.CFrame.LookVector * 2.0) + (playerRoot.CFrame.RightVector * 1.2) + Vector3.new(0, 1.4, 0)
			local tweenOrbit = TweenService:Create(weaponHandle, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
				Position = forwardRelease,
				Orientation = Vector3.new(0, 260, 90),
			})
			tweenOrbit:Play()

			-- 3. High-Velocity Slingshot Hurl into Enemy
			tweenOrbit.Completed:Connect(function()
				if not weaponHandle or not weaponHandle.Parent then return end

				local throwTargetPos = enemyRoot.Position + Vector3.new(0, 1.0, 0)
				local tweenHurl = TweenService:Create(weaponHandle, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = throwTargetPos,
					Orientation = Vector3.new(math.random(-360, 360), math.random(-360, 360), math.random(-360, 360)),
				})
				tweenHurl:Play()

				tweenHurl.Completed:Connect(function()
					if not weaponHandle or not weaponHandle.Parent then return end

					local throwDir = (throwTargetPos - forwardRelease).Unit
					weaponHandle.Anchored = false
					weaponHandle.CanCollide = true
					weaponHandle.AssemblyLinearVelocity = throwDir * 18 + Vector3.new(0, 10, 0)
					weaponHandle.AssemblyAngularVelocity = Vector3.new(math.random(-25, 25), math.random(-25, 25), math.random(-25, 25))
					Debris:AddItem(weaponHandle, 4.0)

					-- Heavy projectile damage & physical knockback
					if targetModel.Parent and enemyHum.Health > 0 then
						damageEnemy(targetModel, CombatConfig.Moves.DisarmAndThrow.Damage or 28, throwDir * (CombatConfig.Moves.DisarmAndThrow.KnockbackForce or 18))
					end

					CombatVFXRemote:FireAllClients("WeaponImpactVFX", throwTargetPos, throwDir)
				end)
			end)
		end)
	end
end)

--------------------------------------------------------------------------------
-- 6. ⚡ SPIDER-SENSE PERFECT DODGE & ZZZ COUNTER (F Key)
--------------------------------------------------------------------------------
DodgeRemote.OnServerEvent:Connect(function(player: Player, attackerModel: any, isPerfect: any)
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not playerRoot then return end

	local iFrameDuration = 0.85

	-- 🛡️ Grant full AoE invulnerability frames (i-frames) against all mob attacks
	char:SetAttribute("IsInvulnerable", true)

	task.delay(iFrameDuration, function()
		if char and char.Parent then
			char:SetAttribute("IsInvulnerable", false)
		end
	end)

	-- 🕸️ Point-Blank Web-Counter: Shoots web splat and applies progressive web cocooning!
	if isPerfect == true and typeof(attackerModel) == "Instance" and attackerModel:IsA("Model") and attackerModel.Parent then
		local attackerRoot = (attackerModel:FindFirstChild("HumanoidRootPart") or attackerModel:FindFirstChild("Torso")) :: BasePart?
		local attackerHum = attackerModel:FindFirstChildOfClass("Humanoid")

		if attackerRoot and attackerHum and attackerHum.Health > 0 then
			local dist = (attackerRoot.Position - playerRoot.Position).Magnitude
			if dist <= (CombatConfig.Moves.SpiderSenseDodge.ThreatDetectionRadius or 45) then
				-- 1. Interrupt and cancel attacker strike
				attackerModel:SetAttribute("AttackDodged", true)
				attackerModel:SetAttribute("IsAttacking", false)

				-- 2. Apply Web-Counter Shot (Deals damage + Web Stacks towards Cocoon!)
				handleWebPelletHit(player, attackerModel)
				return
			end
		end
	end

	-- Normal Evasion VFX
	CombatVFXRemote:FireAllClients("SpiderSenseDodgeVFX", player)
end)

-- ⚡ Web-Strike Remote (60-Stud Zip Dropkick)
WebStrikeRemote.OnServerEvent:Connect(function(player: Player, targetModel: any)
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
	local enemyHum = targetModel:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not enemyRoot or not enemyHum or enemyHum.Health <= 0 then return end

	local dist = (enemyRoot.Position - playerRoot.Position).Magnitude
	local maxDist = (CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.MaxDistance or 65) + 10
	if dist > maxDist then return end

	local strikeDir = (enemyRoot.Position - playerRoot.Position).Unit
	local damage = CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.ImpactDamage or 22
	local knockback = strikeDir * (CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.KnockbackForce or 26) + Vector3.new(0, 4, 0)

	-- 💥 Guard Break Synergy: Web-Strike breaks Heavy Brute's guard stance!
	local isBrute = targetModel:GetAttribute("Archetype") == "Brute"
	if isBrute then
		targetModel:SetAttribute("GuardBroken", true)
		CombatVFXRemote:FireAllClients("GuardBreakVFX", targetModel)
		local breakDuration = CombatConfig.Archetypes and CombatConfig.Archetypes.Brute and CombatConfig.Archetypes.Brute.GuardBreakDuration or 3.5
		task.delay(breakDuration, function()
			if targetModel.Parent and enemyHum.Health > 0 then
				targetModel:SetAttribute("GuardBroken", false)
			end
		end)
	end

	damageEnemy(targetModel, damage, knockback)
	CombatVFXRemote:FireAllClients("WebStrikeHit", player, targetModel)

	-- 💥 AoE Crowd Splash: Blast all nearby clumped enemies in the impact zone!
	local splashRadius = CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.SplashRadius or 8.0
	local splashDamage = CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.SplashDamage or 14
	local enemiesFolder = Workspace:FindFirstChild("Enemies")

	if enemiesFolder then
		for _, otherEnemy in enemiesFolder:GetChildren() do
			if otherEnemy:IsA("Model") and otherEnemy ~= targetModel then
				local oRoot = (otherEnemy:FindFirstChild("HumanoidRootPart") or otherEnemy:FindFirstChild("Torso")) :: BasePart?
				local oHum = otherEnemy:FindFirstChildOfClass("Humanoid")
				if oRoot and oHum and oHum.Health > 0 then
					local offset = oRoot.Position - enemyRoot.Position
					if offset.Magnitude <= splashRadius then
						local pushOutDir = (offset.Magnitude > 0.1) and (offset.Unit + Vector3.new(0, 0.35, 0)).Unit or strikeDir
						if otherEnemy:GetAttribute("Archetype") == "Brute" and otherEnemy:GetAttribute("GuardBroken") ~= true then
							otherEnemy:SetAttribute("GuardBroken", true)
							CombatVFXRemote:FireAllClients("GuardBreakVFX", otherEnemy)
							local breakDuration = CombatConfig.Archetypes and CombatConfig.Archetypes.Brute and CombatConfig.Archetypes.Brute.GuardBreakDuration or 3.5
							task.delay(breakDuration, function()
								if otherEnemy.Parent and oHum.Health > 0 then
									otherEnemy:SetAttribute("GuardBroken", false)
								end
							end)
						end
						damageEnemy(otherEnemy, splashDamage, pushOutDir * 18)
					end
				end
			end
		end
	end

	-- 💥 Wall-Pin Synergy on Web-Strike: If target is webbed/cocooned, launching them into a wall pins them!
	local isFullyWebbed = targetModel:GetAttribute("IsWebbed") == true or (targetModel:GetAttribute("WebStacks") or 0) >= 2
	if isFullyWebbed then
		task.delay(0.10, function()
			if targetModel.Parent and enemyHum.Health > 0 then
				checkAndPinToWall(targetModel, strikeDir)
			end
		end)
	end
end)

-- 🌪️ 360° Web Cyclone Finisher Remote Listener (Continuous Multi-Hit AoE DPS)
WebCycloneRemote.OnServerEvent:Connect(function(player: Player, actionType: any, targetModel: any, extraData: any)
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not playerRoot then return end

	if (actionType == "CycloneTick" or actionType == "StartCyclone") and typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
		local cycloneRadius = 14.5
		local tickDamage = 6 -- Ticking damage per 0.20s revolution (60 total DPS across 10 ticks)
		local enemiesFolder = Workspace:FindFirstChild("Enemies")

		if enemiesFolder then
			for _, enemy in enemiesFolder:GetChildren() do
				if enemy:IsA("Model") then
					local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
					local eHum = enemy:FindFirstChildOfClass("Humanoid")
					if eRoot and eHum and eHum.Health > 0 then
						local dist = (eRoot.Position - playerRoot.Position).Magnitude
						if dist <= cycloneRadius then
							local flingDir = (eRoot.Position - playerRoot.Position).Magnitude > 0.1 and (eRoot.Position - playerRoot.Position).Unit + Vector3.new(0, 0.25, 0) or Vector3.new(0, 1, 0)
							if enemy:GetAttribute("Archetype") == "Brute" then
								enemy:SetAttribute("GuardBroken", true)
								CombatVFXRemote:FireAllClients("GuardBreakVFX", enemy)
							end
							damageEnemy(enemy, tickDamage, flingDir * 12)
							CombatVFXRemote:FireAllClients("KineticHit", player, enemy, 1)
						end
					end
				end
			end
		end

	elseif actionType == "ThrowTarget" and typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
		local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
		local enemyHum = targetModel:FindFirstChildOfClass("Humanoid")
		if not enemyRoot then return end

		local throwDir = typeof(extraData) == "Vector3" and extraData or playerRoot.CFrame.LookVector
		local throwSpeed = 135

		-- Mark as webbed so wall-pinning matrix can trigger on wall impact
		targetModel:SetAttribute("IsWebbed", true)
		targetModel:SetAttribute("WebStacks", 3)

		-- Launch target into wall with finisher damage & velocity
		if enemyHum and enemyHum.Health > 0 then
			damageEnemy(targetModel, 25, throwDir * throwSpeed)
		else
			-- Enemy was defeated mid-spin: still physically rocket ragdoll into the wall!
			local existingBv = enemyRoot:FindFirstChild("CycloneThrowImpulse")
			if existingBv then existingBv:Destroy() end
			local bv = Instance.new("BodyVelocity")
			bv.Name = "CycloneThrowImpulse"
			bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			bv.Velocity = throwDir * throwSpeed
			bv.Parent = enemyRoot
			Debris:AddItem(bv, 0.45)
		end

		CombatVFXRemote:FireAllClients("WebStrikeHit", player, targetModel)

		-- Check Wall Pin after high-speed flight
		task.delay(0.10, function()
			if targetModel.Parent then
				checkAndPinToWall(targetModel, throwDir)
			end
		end)
	end
end)

-- ⚡ Spider-Sense Dodge Server Listener (i-Frames, Attack-Cancels & Face-Web Counter)
DodgeRemote.OnServerEvent:Connect(function(player: Player, targetEnemy: any, isCounter: any)
	local character = player.Character
	if not character then return end
	local rootPart = (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")) :: BasePart?
	if not rootPart then return end

	-- 1. 🛡️ Grant Player True Invulnerability Frames (0.45s i-Frames)
	character:SetAttribute("IsInvulnerable", true)
	task.delay(0.45, function()
		if character and character.Parent then
			character:SetAttribute("IsInvulnerable", false)
		end
	end)

	-- 2. ⚡ Cancel attacks & laser telegraphs on all mobs threatening this player within 60 studs!
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if enemiesFolder then
		for _, enemy in enemiesFolder:GetChildren() do
			if enemy:IsA("Model") then
				local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				local isAttacking = enemy:GetAttribute("IsAttacking") == true
				if eRoot and isAttacking and (eRoot.Position - rootPart.Position).Magnitude <= 60 then
					enemy:SetAttribute("AttackDodged", true)
					enemy:SetAttribute("IsAttacking", false)
				end
			end
		end
	end

	-- 3. 🕸️ Apply Face-Web Counter & Stagger to the primary attacking threat
	if typeof(targetEnemy) == "Instance" and targetEnemy:IsA("Model") then
		local enemyHum = targetEnemy:FindFirstChildOfClass("Humanoid")
		local enemyRoot = (targetEnemy:FindFirstChild("HumanoidRootPart") or targetEnemy:FindFirstChild("Torso")) :: BasePart?
		if enemyHum and enemyHum.Health > 0 and enemyRoot then
			targetEnemy:SetAttribute("AttackDodged", true)
			targetEnemy:SetAttribute("IsAttacking", false)

			-- Point-Blank Web Counter Damage & Knockback
			local counterDmg = CombatConfig.Moves.SpiderSenseDodge and CombatConfig.Moves.SpiderSenseDodge.CounterDamage or 12
			damageEnemy(targetEnemy, counterDmg, -enemyRoot.CFrame.LookVector * 14)

			-- Add web stack on face-web counter
			local curStacks = (targetEnemy:GetAttribute("WebStacks") or 0) + 1
			targetEnemy:SetAttribute("WebStacks", curStacks)
			CombatVFXRemote:FireAllClients("WebPelletHit", player, targetEnemy, curStacks)
		end
	end
end)

-- 💚 Quick-Heal Remote Listener
QuickHealRemote.OnServerEvent:Connect(function(player: Player, healAmount: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local amount = typeof(healAmount) == "number" and math.clamp(healAmount, 10, 50) or 35
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end)

print("⚔️ Spider-Man Combat Service (with 360° Web Cyclone, Spider-Sense Dodge & Quick-Heal) online!")
