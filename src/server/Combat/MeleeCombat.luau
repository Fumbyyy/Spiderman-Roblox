--!strict
--[[
	MeleeCombat.luau
	Handles Kinetic Strike Combo (L-Click), Uppercut Launcher (Hold L-Click),
	In-Air Ground Slam AoE Shockwaves, and Spider-Sense Dodge evasion/counters.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local CombatDamage = require(script.Parent.CombatDamage)

local MeleeCombat = {}

local playerGroundSlamCooldowns: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	playerGroundSlamCooldowns[player] = nil
end)

-- 1. 🥊 KINETIC STRIKE COMBO (L-Click Tap - Multi-Target AoE Cleave)
function MeleeCombat.handleKineticCombo(player: Player, targetModel: any, comboIndex: any, isAmbushArg: any, combatVFXRemote: RemoteEvent)
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

	local enemiesFolder = Workspace:FindFirstChild("Enemies")

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
		combatVFXRemote:FireAllClients("VenomBlastVFX", player, playerRoot.Position, 14)
		combatVFXRemote:FireAllClients("AmbushCritVFX", player, playerRoot.Position)

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

						combatVFXRemote:FireAllClients("VenomStunVFX", player, enemy, 2.0)
						CombatDamage.damageEnemy(enemy, 18, Vector3.new(0, 6, 0), player)

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
			if CombatDamage.isBruteBlockingFrontal(enemyModel, punchDir) then
				combatVFXRemote:FireAllClients("BruteBlockVFX", enemyModel, punchDir)
				continue
			end

			local isFullyWebbed = enemyModel:GetAttribute("IsWebbed") == true or (enemyModel:GetAttribute("WebStacks") or 0) >= 3

			local knockback: Vector3
			if hitNum == 3 then
				knockback = punchDir * 10 + Vector3.new(0, 2, 0)
			else
				knockback = Vector3.zero
			end

			CombatDamage.damageEnemy(enemyModel, damage, knockback, player)
			combatVFXRemote:FireAllClients("KineticHit", player, enemyModel, hitNum, damage)

			-- 💥 Wall-Pin Synergy on 3rd hit
			if hitNum == 3 and isFullyWebbed then
				task.delay(0.10, function()
					if enemyModel.Parent and enemyHum.Health > 0 then
						CombatDamage.checkAndPinToWall(enemyModel, punchDir, combatVFXRemote)
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
			combatVFXRemote:FireAllClients("SymbioteCleaveVFX", player, cleavePos)

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
			combatVFXRemote:FireAllClients("CyberSlashVFX", player, slashPos)

			-- Instantly shatters Heavy Brute armor shields for hit enemies
			for enemyModel in hitEnemies do
				if enemyModel:IsA("Model") and enemyModel:GetAttribute("Archetype") == "Brute" then
					enemyModel:SetAttribute("GuardBroken", true)
					combatVFXRemote:FireAllClients("GuardBreakVFX", enemyModel)
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
			combatVFXRemote:FireAllClients("WaldoRepulsorShockwave", player, playerRoot.Position, 14)

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
							CombatDamage.damageEnemy(enemy, 15, Vector3.zero, player)
						end
					end
				end
			end
		end
	end
end

-- 2. 🚀 UPPERCUT LAUNCHER (Hold L-Click - Multi-Target Launcher)
function MeleeCombat.handleUppercut(player: Player, targetModel: any, combatVFXRemote: RemoteEvent)
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
						if CombatDamage.isBruteBlockingFrontal(enemy, punchDir) then
							combatVFXRemote:FireAllClients("BruteBlockVFX", enemy, punchDir)
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
						CombatDamage.damageEnemy(enemy, upperDmg, Vector3.zero, player)
						combatVFXRemote:FireAllClients("Uppercut", player, enemy)
					end
				end
			end
		end
	end

	if hitAny or targetModel then
		playerRoot.AssemblyLinearVelocity = Vector3.new(playerRoot.AssemblyLinearVelocity.X, launchY, playerRoot.AssemblyLinearVelocity.Z)
	end
end

-- 3. 💥 WEB-LINE GROUND SLAM (In-Air Finisher & AoE Shockwave)
function MeleeCombat.handleGroundSlam(player: Player, targetModel: any, customImpactPos: any, combatVFXRemote: RemoteEvent)
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
				CombatDamage.damageEnemy(targetModel, slamDmg, Vector3.zero, player)
				impactPos = enemyRoot.Position
				primaryHit = true
				hitCount += 1
				combatVFXRemote:FireAllClients("GroundSlamHit", player, targetModel, slamDmg)
				combatVFXRemote:FireAllClients("GroundSlamWebs", player, targetModel)
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

					CombatDamage.damageEnemy(otherEnemy, shockDmg, pushDir * (if isSymbioteSlam then 22 else 18), player)
					hitCount += 1
				end
			end
		end
	end

	-- Replicate Shockwave VFX to all clients with total hit count for combo tracking
	if isSymbioteSlam then
		combatVFXRemote:FireAllClients("TendrilGroundSlamVFX", player, impactPos, 18)

		-- Parasitic Lifesteal: Heal player's Humanoid by +8 HP (clamped to MaxHealth) when ground slam lands
		local playerHum = char:FindFirstChildOfClass("Humanoid")
		if playerHum and playerHum.Health > 0 and (hitCount > 0 or primaryHit) then
			playerHum.Health = math.clamp(playerHum.Health + 8, 0, playerHum.MaxHealth)
		end
	else
		-- Primary hit is already combo-registered by the attacker's client prediction
		combatVFXRemote:FireAllClients("GroundSlamShockwave", player, impactPos, radius, hitCount - (if primaryHit then 1 else 0))
	end
end

-- 4. ⚡ SPIDER-SENSE PERFECT DODGE (Primary)
function MeleeCombat.handleDodge(
	player: Player,
	attackerModel: any,
	isPerfect: any,
	isCamoActivation: any,
	combatVFXRemote: RemoteEvent,
	webPelletHandler: ((Player, Model) -> ())?
)
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
				if webPelletHandler then
					webPelletHandler(player, attackerModel)
				end
				return
			end
		end
	end

	-- Normal Evasion VFX
	combatVFXRemote:FireAllClients("SpiderSenseDodgeVFX", player)
end

-- 5. ⚡ SPIDER-SENSE DODGE (Secondary Listener - i-Frames, Attack-Cancels & Face-Web Counter)
function MeleeCombat.handleDodgeSecondary(player: Player, targetEnemy: any, isCounter: any, combatVFXRemote: RemoteEvent)
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
			CombatDamage.damageEnemy(targetEnemy, counterDmg, -enemyRoot.CFrame.LookVector * 14, player)

			-- Add web stack on face-web counter
			local curStacks = (targetEnemy:GetAttribute("WebStacks") or 0) + 1
			targetEnemy:SetAttribute("WebStacks", curStacks)
			combatVFXRemote:FireAllClients("WebPelletHit", player, targetEnemy, curStacks)
		end
	end
end

return MeleeCombat
