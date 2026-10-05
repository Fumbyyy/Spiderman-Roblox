--!strict
--[[
	CombatService.server.luau
	Full Server Combat Authority for Spider-Man 6-Move Combat System.
	Validates damage, handles Air Launchers, Ground Slam AoE Shockwaves,
	Wall-Pinning, Weapon Hurl-Backs, Spider-Sense Dodges, and Ragdoll Physics.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

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
local PropThrowRemote = getOrCreateRemote("PropThrowRemote")
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
local function damageEnemy(enemyModel: Model, damageAmount: number, knockbackDir: Vector3?, attackingPlayer: Player?)
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
		applyRagdoll(enemyModel)

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
KineticComboRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, comboIndex: any, isAmbushArg: any)
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

	-- ⚡ Symbiote Black Suit Perk: +20% Punch & Cleave Damage
	local isSymbioteMelee = (player:GetAttribute("EquippedSuit") == "SymbioteBlack")
		or (char and char:GetAttribute("EquippedSuit") == "SymbioteBlack")
		or (player:GetAttribute("SuitPerkType") == "Damage")
	if isSymbioteMelee then
		damage = damage * 1.20
	end

	-- ⚡ Miles Morales Ambush Critical Strike: 1.5x Damage from Camouflage
	local isMilesPunch = (player:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
		or (char and char:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
	local isAmbushPunch = isMilesPunch and (
		isAmbushArg == true
		or player:GetAttribute("MilesCamouflaged") == true
		or (char and char:GetAttribute("MilesCamouflaged") == true)
	)
	if isAmbushPunch then
		damage = damage * 1.5
		player:SetAttribute("MilesCamouflaged", false)
		if char then char:SetAttribute("MilesCamouflaged", false) end

		-- ⚡ THE "HEY" AMBUSH NOVA: 14-stud Bio-Electric Stun Nova +50% critical AoE burst
		CombatVFXRemote:FireAllClients("VenomBlastVFX", player, playerRoot.Position, 14)
		CombatVFXRemote:FireAllClients("AmbushCritVFX", player, playerRoot.Position)

		local novaRadius = 14
		local candidateEnemies: { Model } = {}
		for _, enemy in CollectionService:GetTagged("Enemy") do
			if enemy:IsA("Model") and enemy.Parent then
				table.insert(candidateEnemies, enemy)
			end
		end
		if enemiesFolder then
			for _, enemy in enemiesFolder:GetChildren() do
				if enemy:IsA("Model") and not table.find(candidateEnemies, enemy) then
					table.insert(candidateEnemies, enemy)
				end
			end
		end

		for _, enemy in candidateEnemies do
			if enemy ~= char and enemy.Parent then
				local enemyHum = enemy:FindFirstChildOfClass("Humanoid")
				local enemyRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				if enemyHum and enemyHum.Health > 0 and enemyRoot then
					local offset = enemyRoot.Position - playerRoot.Position
					local dist = offset.Magnitude
					if dist <= novaRadius and dist > 0.1 then
						enemy:SetAttribute("IsAttacking", false)
						enemy:SetAttribute("AttackDodged", true)
						enemy:SetAttribute("VenomStunned", true)
						enemyHum.WalkSpeed = 0

						CombatVFXRemote:FireAllClients("VenomStunVFX", player, enemy, 2.0)
						damageEnemy(enemy, 18, Vector3.new(0, 6, 0), player)

						task.delay(2.0, function()
							if enemy.Parent and enemyHum and enemyHum.Health > 0 then
								enemy:SetAttribute("VenomStunned", false)
								if enemy:GetAttribute("IsPinned") ~= true and enemy:GetAttribute("IsWebbed") ~= true then
									enemyHum.WalkSpeed = 14
								end
							end
						end)
					end
				end
			end
		end
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
			if hitNum == 3 then
				knockback = punchDir * 10 + Vector3.new(0, 2, 0)
			else
				knockback = Vector3.zero
			end

			damageEnemy(enemyModel, damage, knockback, player)
			CombatVFXRemote:FireAllClients("KineticHit", player, enemyModel, hitNum, damage)

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


	-- ⚡ Symbiote Alien Suit: Brutal Dark Cleave & Parasitic Lifesteal (+6 HP) on Combo Step 3
	if hitNum == 3 then
		local isSymbioteFinisher = (player:GetAttribute("EquippedSuit") == "SymbioteBlack")
			or (char:GetAttribute("EquippedSuit") == "SymbioteBlack")
			or (player:GetAttribute("SuitPerkType") == "Damage")
		if isSymbioteFinisher then
			local cleavePos = playerRoot.Position + playerRoot.CFrame.LookVector * 3.5
			CombatVFXRemote:FireAllClients("SymbioteCleaveVFX", player, cleavePos)

			-- Parasitic Lifesteal: Heal player's Humanoid by +6 HP (clamped to MaxHealth) when hit lands
			local playerHum = char:FindFirstChildOfClass("Humanoid")
			if playerHum and playerHum.Health > 0 and next(hitEnemies) ~= nil then
				playerHum.Health = math.clamp(playerHum.Health + 6, 0, playerHum.MaxHealth)
			end
		end
	end

	-- ⚡ 2099 Cyber Suit: Claw Cross-Slash & Heavy Brute Armor Shred on Combo Step 3
	if hitNum == 3 then
		local is2099 = (player:GetAttribute("EquippedSuit") == "Cyber2099")
			or (char:GetAttribute("EquippedSuit") == "Cyber2099")
		if is2099 then
			local slashPos = playerRoot.Position + playerRoot.CFrame.LookVector * 3.5
			CombatVFXRemote:FireAllClients("CyberSlashVFX", player, slashPos)

			-- Instantly shatters Heavy Brute armor shields for hit enemies
			for enemyModel in hitEnemies do
				if enemyModel:IsA("Model") and enemyModel:GetAttribute("Archetype") == "Brute" then
					enemyModel:SetAttribute("GuardBroken", true)
					CombatVFXRemote:FireAllClients("GuardBreakVFX", enemyModel)
					local breakDuration = CombatConfig.Archetypes and CombatConfig.Archetypes.Brute and CombatConfig.Archetypes.Brute.GuardBreakDuration or 3.5
					task.delay(breakDuration, function()
						if enemyModel.Parent then
							local eHum = enemyModel:FindFirstChildOfClass("Humanoid")
							if eHum and eHum.Health > 0 then
								enemyModel:SetAttribute("GuardBroken", false)
							end
						end
					end)
				end
			end
		end
	end

	-- ⚡ Stark Tech Suit: Waldo Repulsor Shockwave Finisher on Combo Step 3
	if hitNum == 3 then
		local isStark = (player:GetAttribute("EquippedSuit") == "StarkTechSuit")
			or (char:GetAttribute("EquippedSuit") == "StarkTechSuit")
		if isStark then
			CombatVFXRemote:FireAllClients("WaldoRepulsorShockwave", player, playerRoot.Position, 14)

			local starkRadius = 14
			local candidateEnemies: { Model } = {}
			for _, enemy in CollectionService:GetTagged("Enemy") do
				if enemy:IsA("Model") and enemy.Parent then
					table.insert(candidateEnemies, enemy)
				end
			end
			if enemiesFolder then
				for _, enemy in enemiesFolder:GetChildren() do
					if enemy:IsA("Model") and not table.find(candidateEnemies, enemy) then
						table.insert(candidateEnemies, enemy)
					end
				end
			end

			for _, enemy in candidateEnemies do
				if enemy ~= char and enemy.Parent then
					local enemyHum = enemy:FindFirstChildOfClass("Humanoid")
					local enemyRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
					if enemyHum and enemyHum.Health > 0 and enemyRoot then
						local offset = enemyRoot.Position - playerRoot.Position
						local dist = offset.Magnitude
						if dist <= starkRadius and dist > 0.1 then
							local radialFlat = Vector3.new(offset.X, 0, offset.Z).Unit
							local impulseVel = (radialFlat * 45) + Vector3.new(0, 12, 0)

							-- Remove old knockback to guarantee instant radial blast
							local oldBv = enemyRoot:FindFirstChild("KnockbackImpulse")
							if oldBv then oldBv:Destroy() end

							local shockBv = Instance.new("BodyVelocity")
							shockBv.Name = "KnockbackImpulse"
							shockBv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
							shockBv.Velocity = impulseVel
							shockBv.Parent = enemyRoot
							Debris:AddItem(shockBv, 0.22)

							enemyRoot.AssemblyLinearVelocity = impulseVel

							-- Apply concussive AoE damage and attack interrupt
							damageEnemy(enemy, 15, Vector3.zero, player)
						end
					end
				end
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

						local upperDmg = 14
						local isSymbioteUpper = (player:GetAttribute("EquippedSuit") == "SymbioteBlack")
							or (char and char:GetAttribute("EquippedSuit") == "SymbioteBlack")
							or (player:GetAttribute("SuitPerkType") == "Damage")
						if isSymbioteUpper then
							upperDmg = upperDmg * 1.20 -- 16.8 base damage
						end
						damageEnemy(enemy, upperDmg, Vector3.zero, player)
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
local playerGroundSlamCooldowns: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	playerGroundSlamCooldowns[player] = nil
end)

GroundSlamRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, customImpactPos: any)
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not playerRoot then return end

	-- 🛡️ Server cooldown (80% tolerance for network jitter)
	local now = os.clock()
	local slamCooldown = (CombatConfig.Moves.AirGroundSlam.Cooldown or 1.4) * 0.8
	if now - (playerGroundSlamCooldowns[player] or 0) < slamCooldown then return end
	playerGroundSlamCooldowns[player] = now

	-- 🛡️ Never trust a client impact point more than 12 studs from the player's replicated root
	local impactPos = playerRoot.Position
	if typeof(customImpactPos) == "Vector3" and (customImpactPos - playerRoot.Position).Magnitude <= 12 then
		impactPos = customImpactPos
	end

	-- 1. If target enemy model is provided and in whip range, smash them down with heavy impact!
	local primaryHit = false
	local hitCount = 0
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
				local slamDmg = CombatConfig.Moves.AirGroundSlam.Damage or 24
				if player:GetAttribute("SuitPerkType") == "Damage" then slamDmg = slamDmg * 1.20 end
				damageEnemy(targetModel, slamDmg, Vector3.zero, player)
				impactPos = enemyRoot.Position
				primaryHit = true
				hitCount += 1
				CombatVFXRemote:FireAllClients("GroundSlamHit", player, targetModel, slamDmg)
				CombatVFXRemote:FireAllClients("GroundSlamWebs", player, targetModel)
			end
		end
	end

	-- 2. Trigger AoE Radial Shockwave to all surrounding enemies
	local isSymbioteSlam = (player:GetAttribute("EquippedSuit") == "SymbioteBlack")
		or (char and char:GetAttribute("EquippedSuit") == "SymbioteBlack")
		or (player:GetAttribute("SuitPerkType") == "Damage")

	local radius = if isSymbioteSlam then 18 else (CombatConfig.Moves.AirGroundSlam.ShockwaveRadius or 24)
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
					local shockDmg = if isSymbioteSlam then 30 else (CombatConfig.Moves.AirGroundSlam.ShockwaveDamage or 15)

					-- Symbiote tendril slam cancels enemy attacks and knocks mobs flat to the floor
					if isSymbioteSlam then
						otherEnemy:SetAttribute("IsAttacking", false)
						otherEnemy:SetAttribute("AttackDodged", true)
						otherHum.PlatformStand = true
						task.delay(1.2, function()
							if otherHum and otherHum.Parent then
								otherHum.PlatformStand = false
							end
						end)
					end

					damageEnemy(otherEnemy, shockDmg, pushDir * (if isSymbioteSlam then 22 else 18), player)
					hitCount += 1
				end
			end
		end
	end

	-- Replicate Shockwave VFX to all clients with total hit count for combo tracking
	if isSymbioteSlam then
		CombatVFXRemote:FireAllClients("TendrilGroundSlamVFX", player, impactPos, 18)

		-- Parasitic Lifesteal: Heal player's Humanoid by +8 HP (clamped to MaxHealth) when ground slam lands
		local playerHum = char:FindFirstChildOfClass("Humanoid")
		if playerHum and playerHum.Health > 0 and (hitCount > 0 or primaryHit) then
			playerHum.Health = math.clamp(playerHum.Health + 8, 0, playerHum.MaxHealth)
		end
	else
		-- Primary hit is already combo-registered by the attacker's client prediction
		CombatVFXRemote:FireAllClients("GroundSlamShockwave", player, impactPos, radius, hitCount - (if primaryHit then 1 else 0))
	end
end)

local playerWebPelletCooldowns: { [Player]: number } = {}
local enemyWebDecayTimers: { [Model]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	playerWebPelletCooldowns[player] = nil
end)

local function handleWebPelletHit(player: Player, targetModel: Model, isImpact: boolean?)
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
			damageEnemy(targetModel, CombatConfig.Moves.WebPellet.Damage or 4, Vector3.zero, player)
			CombatVFXRemote:FireAllClients("WebPelletHit", player, targetModel, 3)
		end
		return
	end

	local isScarletSuit = (player:GetAttribute("EquippedSuit") == "ScarletSpider")
		or (char and char:GetAttribute("EquippedSuit") == "ScarletSpider")

	-- 💥 Scarlet Spider Impact Web Blast: 10-stud AoE, 2 Web Stacks & 18 studs/s outward impulse
	if isImpact == true and isScarletSuit then
		damageEnemy(targetModel, 8, pushDir * 18, player)
		local curStacks = math.clamp(math.max(targetModel:GetAttribute("WebStacks") or 0, 2), 2, 3)
		targetModel:SetAttribute("WebStacks", curStacks)
		enemyHum.WalkSpeed = 3

		local impactPos = enemyRoot.Position
		local candidateMobs: { Model } = {}
		for _, enemy in CollectionService:GetTagged("Enemy") do
			if enemy:IsA("Model") and enemy.Parent then
				table.insert(candidateMobs, enemy)
			end
		end
		local enemiesFolder = Workspace:FindFirstChild("Enemies")
		if enemiesFolder then
			for _, enemy in enemiesFolder:GetChildren() do
				if enemy:IsA("Model") and not table.find(candidateMobs, enemy) then
					table.insert(candidateMobs, enemy)
				end
			end
		end

		for _, mob in candidateMobs do
			if mob ~= char and mob.Parent then
				local mRoot = (mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso")) :: BasePart?
				local mHum = mob:FindFirstChildOfClass("Humanoid")
				if mRoot and mHum and mHum.Health > 0 then
					local offset = mRoot.Position - impactPos
					if offset.Magnitude <= 10 and offset.Magnitude > 0.1 then
						mob:SetAttribute("IsAttacking", false)
						mob:SetAttribute("AttackDodged", true)
						local mStacks = math.clamp(math.max(mob:GetAttribute("WebStacks") or 0, 2), 2, 3)
						mob:SetAttribute("WebStacks", mStacks)
						mHum.WalkSpeed = 3
						local pushOut = (offset.Unit + Vector3.new(0, 0.25, 0)).Unit
						damageEnemy(mob, 8, pushOut * 18, player)

						local decayId = os.clock()
						enemyWebDecayTimers[mob] = decayId
						task.delay(2.8, function()
							if enemyWebDecayTimers[mob] == decayId and mob.Parent and mHum.Health > 0 and (mob:GetAttribute("IsWebbed") ~= true) and (mob:GetAttribute("IsPinned") ~= true) then
								mob:SetAttribute("WebStacks", 0)
								mHum.WalkSpeed = 16
								CombatVFXRemote:FireAllClients("CocoonBreakVFX", mob)
							end
						end)
					end
				end
			end
		end

		CombatVFXRemote:FireAllClients("ImpactWebExplosionVFX", player, impactPos, 10)
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
		damageEnemy(targetModel, pelletDamage, pelletKnockback, player)
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
WebPelletRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, isImpactArg: any)
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end

	-- 🛡️ Anti-Spam Rate Limit Validation
	local now = os.clock()
	local lastFired = playerWebPelletCooldowns[player] or 0
	if (now - lastFired) < 0.18 then return end
	playerWebPelletCooldowns[player] = now

	handleWebPelletHit(player, targetModel, isImpactArg == true)
end)

local playerDisarmCooldowns: { [Player]: number } = {}
local playerPropThrowCooldowns: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	playerWebPelletCooldowns[player] = nil
	playerDisarmCooldowns[player] = nil
	playerPropThrowCooldowns[player] = nil
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
		damageEnemy(targetModel, 0, pullDir * 12 + Vector3.new(0, 2, 0), player)

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
						damageEnemy(targetModel, CombatConfig.Moves.DisarmAndThrow.Damage or 28, throwDir * (CombatConfig.Moves.DisarmAndThrow.KnockbackForce or 18), player)
					end

					CombatVFXRemote:FireAllClients("WeaponImpactVFX", throwTargetPos, throwDir)
				end)
			end)
		end)
	end
end)

--------------------------------------------------------------------------------
-- 5b. 📦 CONTEXTUAL WEB-YANK & PROP THROW (Q Key)
--------------------------------------------------------------------------------
PropThrowRemote.OnServerEvent:Connect(function(player: Player, propInstance: any, targetModel: any, secondaryTargetArg: any?)
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

		-- Authoritatively validate distance (<= 45 studs from player)
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
			CombatVFXRemote:FireAllClients("GuardBreakVFX", enemyA)
			task.delay(4.0, function()
				if enemyA.Parent and aHum and aHum.Health > 0 then
					enemyA:SetAttribute("GuardBroken", false)
				end
			end)
		end
		if enemyB:GetAttribute("Archetype") == "Brute" then
			enemyB:SetAttribute("GuardBroken", true)
			CombatVFXRemote:FireAllClients("GuardBreakVFX", enemyB)
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
		damageEnemy(enemyA, 32, pullA.Unit * 14, player)
		damageEnemy(enemyB, 32, pullB.Unit * 14, player)

		-- Broadcast WeaponImpactSparks at midPos
		CombatVFXRemote:FireAllClients("WeaponImpactSparks", midPos)
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
	CombatVFXRemote:FireAllClients("PropThrowVFX", player, propInstance, targetModel)

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
					CombatVFXRemote:FireAllClients("GuardBreakVFX", targetModel)
					task.delay(guardBreakDuration, function()
						if targetModel.Parent and targetHum.Health > 0 then
							targetModel:SetAttribute("GuardBroken", false)
						end
					end)
				end

				-- Apply heavy damage & physical knockback
				local flingVec = impactDir * knockbackForce + Vector3.new(0, 5, 0)
				damageEnemy(targetModel, throwDamage, flingVec, player)
				CombatVFXRemote:FireAllClients("WeaponImpactVFX", destPos, impactDir, throwDamage)
			else
				CombatVFXRemote:FireAllClients("WeaponImpactVFX", destPos, impactDir)
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
								CombatVFXRemote:FireAllClients("GuardBreakVFX", otherEnemy)
							end
							damageEnemy(otherEnemy, splashDamage, splashDir * 16 + Vector3.new(0, 4, 0), player)
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
end)

--------------------------------------------------------------------------------
-- 6. ⚡ SPIDER-SENSE PERFECT DODGE & ZZZ COUNTER (F Key)
--------------------------------------------------------------------------------
DodgeRemote.OnServerEvent:Connect(function(player: Player, attackerModel: any, isPerfect: any, isCamoActivation: any)
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not playerRoot then return end

	local iFrameDuration = 0.85

	-- 🛡️ Grant full AoE invulnerability frames (i-frames) against all mob attacks
	char:SetAttribute("IsInvulnerable", true)

	local isMilesDodge = (player:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
		or (char:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
	if isMilesDodge and isCamoActivation == true then
		player:SetAttribute("MilesCamouflaged", true)
		char:SetAttribute("MilesCamouflaged", true)

		-- 👤 Drop enemy aggro & cancel laser/melee attacks on all mobs threatening cloaked player
		local enemiesFolder = Workspace:FindFirstChild("Enemies")
		if enemiesFolder and playerRoot then
			for _, enemy in enemiesFolder:GetChildren() do
				if enemy:IsA("Model") then
					local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
					if eRoot and (eRoot.Position - playerRoot.Position).Magnitude <= 80 then
						enemy:SetAttribute("IsAttacking", false)
						enemy:SetAttribute("AttackDodged", true)
						local eHum = enemy:FindFirstChildOfClass("Humanoid")
						if eHum then
							eHum:MoveTo(eRoot.Position)
						end
					end
				end
			end
		end

		task.delay(5.0, function()
			if player and player:GetAttribute("MilesCamouflaged") == true then
				player:SetAttribute("MilesCamouflaged", false)
			end
			if char and char.Parent and char:GetAttribute("MilesCamouflaged") == true then
				char:SetAttribute("MilesCamouflaged", false)
			end
		end)
	end

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
WebStrikeRemote.OnServerEvent:Connect(function(player: Player, targetModel: any, isAmbushArg: any)
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart")
		or targetModel:FindFirstChild("Torso")
		or targetModel.PrimaryPart
		or targetModel:FindFirstChildWhichIsA("BasePart")) :: BasePart?
	local enemyHum = targetModel:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not enemyRoot or not enemyHum or enemyHum.Health <= 0 then return end

	local dist = (enemyRoot.Position - playerRoot.Position).Magnitude
	local maxDist = 120 -- Generous replication buffer so high-speed client zip replication lag never drops a hit
	if dist > maxDist then return end

	local isStark = (player:GetAttribute("EquippedSuit") == "StarkTechSuit")
		or (char and char:GetAttribute("EquippedSuit") == "StarkTechSuit")
	local is2099 = (player:GetAttribute("EquippedSuit") == "Cyber2099")
		or (char and char:GetAttribute("EquippedSuit") == "Cyber2099")

	local strikeDir = (enemyRoot.Position - playerRoot.Position).Unit
	-- Overcharged Stark Tech Impact (35 HP) / 2099 Cyber Strike (32 HP) vs 22 base
	local damage = if isStark then 35
		elseif is2099 then 32
		else (CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.ImpactDamage or 22)

	-- ⚡ Miles Morales Ambush Critical Strike: 1.5x Damage from Camouflage on Web-Strike
	local isMilesStrike = (player:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
		or (char and char:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
	local isAmbushStrike = isMilesStrike and (
		isAmbushArg == true
		or player:GetAttribute("MilesCamouflaged") == true
		or (char and char:GetAttribute("MilesCamouflaged") == true)
	)
	if isAmbushStrike then
		damage = damage * 1.5
		player:SetAttribute("MilesCamouflaged", false)
		if char then char:SetAttribute("MilesCamouflaged", false) end
		CombatVFXRemote:FireAllClients("VenomBlastVFX", player, enemyRoot.Position, 14)
		CombatVFXRemote:FireAllClients("AmbushCritVFX", player, enemyRoot.Position)
	end
	local punchDir = strikeDir
	-- Tight Intimate Stagger: Leaves the enemy right in Spidey's face for melee follow-up!
	local knockback = punchDir * 4

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

	damageEnemy(targetModel, damage, knockback, player)
	CombatVFXRemote:FireAllClients("WebStrikeHit", player, targetModel, damage)

	if is2099 then
		CombatVFXRemote:FireAllClients("CyberStrikeVFX", player, enemyRoot.Position)
	end

	-- ⚡ Miles Morales: Electric Web-Strike 2.0s Paralyzing Stun (Strictly on Camo Ambush)
	if isMilesStrike then
		if isAmbushStrike then
			targetModel:SetAttribute("IsAttacking", false)
			targetModel:SetAttribute("AttackDodged", true)
			targetModel:SetAttribute("VenomStunned", true)
			enemyHum.WalkSpeed = 0
			CombatVFXRemote:FireAllClients("VenomStunVFX", player, targetModel, 2.0)
			CombatVFXRemote:FireAllClients("VenomBlastVFX", player, enemyRoot.Position, 10)

			task.delay(2.0, function()
				if targetModel.Parent and enemyHum and enemyHum.Health > 0 then
					targetModel:SetAttribute("VenomStunned", false)
					if targetModel:GetAttribute("IsPinned") ~= true and targetModel:GetAttribute("IsWebbed") ~= true then
						enemyHum.WalkSpeed = 14
					end
				end
			end)
		else
			-- Non-ambush Web-Strike: +8 electric shock bonus damage and spark VFX without paralyzing stun
			damageEnemy(targetModel, 8, Vector3.zero, player)
			CombatVFXRemote:FireAllClients("VenomBlastVFX", player, enemyRoot.Position, 8)
		end
	end

	if isStark then
		-- Trigger cyan repulsor shockwave VFX at point of impact
		CombatVFXRemote:FireAllClients("WaldoRepulsorShockwave", player, enemyRoot.Position, 10)
	end

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
						damageEnemy(otherEnemy, splashDamage, pushOutDir * 18, player)

						-- ⚡ Miles Morales Splash Electric Stun (Strictly on Camo Ambush)
						if isMilesStrike and isAmbushStrike and otherEnemy:GetAttribute("VenomStunned") ~= true then
							otherEnemy:SetAttribute("IsAttacking", false)
							otherEnemy:SetAttribute("AttackDodged", true)
							otherEnemy:SetAttribute("VenomStunned", true)
							oHum.WalkSpeed = 0
							CombatVFXRemote:FireAllClients("VenomStunVFX", player, otherEnemy, 2.0)

							task.delay(2.0, function()
								if otherEnemy.Parent and oHum and oHum.Health > 0 then
									otherEnemy:SetAttribute("VenomStunned", false)
									if otherEnemy:GetAttribute("IsPinned") ~= true and otherEnemy:GetAttribute("IsWebbed") ~= true then
										oHum.WalkSpeed = 14
									end
								end
							end)
						end
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

	-- 🛡️ Zero-Trust Server Authority: Web Cyclone requires Level >= 2 (or Studio testing)
	local leaderstats = player:FindFirstChild("leaderstats")
	local playerLevel = leaderstats and leaderstats:FindFirstChild("Level") and (leaderstats.Level :: IntValue).Value or 1
	if playerLevel < 2 and not RunService:IsStudio() then return end

	if (actionType == "CycloneTick" or actionType == "StartCyclone") and typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
		local is2099Suit = (player:GetAttribute("EquippedSuit") == "Cyber2099")
			or (character and character:GetAttribute("EquippedSuit") == "Cyber2099")
		local isAcrobatic = is2099Suit or (player:GetAttribute("SuitPerkType") == "Acrobatic")
		local cycloneRadius = if isAcrobatic then 18.85 else 14.5
		local tickDamage = if isAcrobatic then 8 else 6 -- Ticking damage per 0.20s revolution (80 total DPS across 10 ticks for 2099, 60 base)

		-- 🌪️ Universal Black Hole Gravitational Vortex: ALL players pull tagged enemies within 25 studs toward the cyclone center
		for _, enemy in CollectionService:GetTagged("Enemy") do
			if enemy ~= targetModel and enemy:IsA("Model") and enemy.Parent then
				local eHum = enemy:FindFirstChildOfClass("Humanoid")
				local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				if eHum and eHum.Health > 0 and eRoot then
					local toPlayer = playerRoot.Position - eRoot.Position
					local dist = toPlayer.Magnitude
					if dist > 3 and dist <= 25 then
						local pullDir = toPlayer.Unit
						eRoot.AssemblyLinearVelocity = Vector3.new(pullDir.X * 32, eRoot.AssemblyLinearVelocity.Y, pullDir.Z * 32)
					end
				end
			end
		end

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
							damageEnemy(enemy, tickDamage, flingDir * 12, player)
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

		-- 🛡️ Zero-Trust Security: Ensure player is within reasonable throw proximity (<= 35 studs)
		if (enemyRoot.Position - playerRoot.Position).Magnitude > 35 then return end

		local throwDir = typeof(extraData) == "Vector3" and extraData or playerRoot.CFrame.LookVector
		local throwSpeed = 135

		-- Mark as webbed so wall-pinning matrix can trigger on wall impact
		targetModel:SetAttribute("IsWebbed", true)
		targetModel:SetAttribute("WebStacks", 3)

		-- Launch target into wall with finisher damage & velocity
		if enemyHum and enemyHum.Health > 0 then
			damageEnemy(targetModel, 25, throwDir * throwSpeed, player)
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

	-- 1. 🛡️ Grant Player True Invulnerability Frames (0.45s or 0.70s with Stealth Big Time)
	local isDodgeSuit = (player:GetAttribute("SuitPerkType") == "Dodge")
	local iframeDuration = if isDodgeSuit then 0.70 else 0.45
	character:SetAttribute("IsInvulnerable", true)
	task.delay(iframeDuration, function()
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
			damageEnemy(targetEnemy, counterDmg, -enemyRoot.CFrame.LookVector * 14, player)

			-- Add web stack on face-web counter
			local curStacks = (targetEnemy:GetAttribute("WebStacks") or 0) + 1
			targetEnemy:SetAttribute("WebStacks", curStacks)
			CombatVFXRemote:FireAllClients("WebPelletHit", player, targetEnemy, curStacks)
		end
	end
end)

-- 📦 Auto-tag creator-placed throwable props (military crates, manhole covers, etc.)
local function registerThrowableCandidate(instance: Instance)
	if instance:IsA("BasePart") or instance:IsA("Model") then
		local nameLower = string.lower(instance.Name)
		if string.find(nameLower, "throwable") or string.find(nameLower, "militarytechcrate") or string.find(nameLower, "manhole") then
			if not CollectionService:HasTag(instance, "ThrowableObject") then
				CollectionService:AddTag(instance, "ThrowableObject")
			end
		end
	end
end

for _, descendant in Workspace:GetDescendants() do
	registerThrowableCandidate(descendant)
end

Workspace.DescendantAdded:Connect(registerThrowableCandidate)

print("⚔️ Spider-Man Combat Service (with Prop Throwing, Soft Melee Snapping, 360° Cyclone, Dodge & Adrenaline Survival) online!")
