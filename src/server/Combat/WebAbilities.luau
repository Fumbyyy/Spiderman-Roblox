--!strict
--[[
	WebAbilities.luau
	Handles Rapid Web Pellets, Progressive Web Cocooning, Disarm & Weapon Hurl,
	60-Stud Zip Web-Strike Dropkick, and 360° Gravitational Web Cyclone.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local CombatDamage = require(script.Parent.CombatDamage)

local WebAbilities = {}

local playerWebPelletCooldowns: { [Player]: number } = {}
local playerDisarmCooldowns: { [Player]: number } = {}
local enemyWebDecayTimers: { [Model]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	playerWebPelletCooldowns[player] = nil
	playerDisarmCooldowns[player] = nil
end)

-- 🕸️ RAPID WEB-PELLETS HIT PROCESSING (Also called by Spider-Sense Perfect Dodge)
function WebAbilities.handleWebPelletHit(player: Player, targetModel: Model, isImpact: boolean?, combatVFXRemote: RemoteEvent)
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
		local isPinned = CombatDamage.checkAndPinToWall(targetModel, pushDir, combatVFXRemote)
		if not isPinned then
			-- Still in open space: apply damage without disjointing the cocoon
			CombatDamage.damageEnemy(targetModel, CombatConfig.Moves.WebPellet.Damage or 4, Vector3.zero, player)
			combatVFXRemote:FireAllClients("WebPelletHit", player, targetModel, 3)
		end
		return
	end

	local isScarletSuit = (player:GetAttribute("EquippedSuit") == "ScarletSpider")
		or (char and char:GetAttribute("EquippedSuit") == "ScarletSpider")

	-- 💥 Scarlet Spider Impact Web Blast: 10-stud AoE, 2 Web Stacks & 18 studs/s outward impulse
	if isImpact == true and isScarletSuit then
		CombatDamage.damageEnemy(targetModel, 8, pushDir * 18, player)
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
						CombatDamage.damageEnemy(mob, 8, pushOut * 18, player)

						local decayId = os.clock()
						enemyWebDecayTimers[mob] = decayId
						task.delay(2.8, function()
							if enemyWebDecayTimers[mob] == decayId and mob.Parent and mHum.Health > 0 and (mob:GetAttribute("IsWebbed") ~= true) and (mob:GetAttribute("IsPinned") ~= true) then
								mob:SetAttribute("WebStacks", 0)
								mHum.WalkSpeed = 16
								combatVFXRemote:FireAllClients("CocoonBreakVFX", mob)
							end
						end)
					end
				end
			end
		end

		combatVFXRemote:FireAllClients("ImpactWebExplosionVFX", player, impactPos, 10)
		return
	end

	-- Increment Web Stacks (1 -> 2 -> 3)
	local currentStacks = math.clamp((targetModel:GetAttribute("WebStacks") or 0) + 1, 1, 3)
	targetModel:SetAttribute("WebStacks", currentStacks)

	-- 🛡️ Brute Armor Shield Check: If Brute has active frontal guard, web strands stick with 0 direct HP damage
	local isBlockingFrontal = CombatDamage.isBruteBlockingFrontal(targetModel, pushDir)
	local pelletDamage = isBlockingFrontal and 0 or (CombatConfig.Moves.WebPellet.Damage or 5)
	local pelletKnockback = isBlockingFrontal and Vector3.zero or (pushDir * 4)

	if pelletDamage > 0 or pelletKnockback.Magnitude > 0 then
		CombatDamage.damageEnemy(targetModel, pelletDamage, pelletKnockback, player)
	end
	combatVFXRemote:FireAllClients("WebPelletHit", player, targetModel, currentStacks)

	-- Apply Progressive Slowdown
	local stack1Speed = CombatConfig.Moves.WebPellet.Stack1SlowSpeed or 9
	local stack2Speed = CombatConfig.Moves.WebPellet.Stack2SlowSpeed or 3

	if currentStacks == 1 then
		enemyHum.WalkSpeed = stack1Speed
	elseif currentStacks == 2 then
		enemyHum.WalkSpeed = stack2Speed
	elseif currentStacks >= (CombatConfig.Moves.WebPellet.HitsToTrap or 3) then
		-- 3 Stacks Reached: Check for Wall-Pin vs Open Street Cocoon
		local isPinned = CombatDamage.checkAndPinToWall(targetModel, pushDir, combatVFXRemote)

		if not isPinned then
			-- Free-Standing Web Cocoon!
			targetModel:SetAttribute("IsWebbed", true)
			enemyHum.WalkSpeed = 0
			enemyHum.JumpPower = 0
			enemyRoot.AssemblyLinearVelocity = Vector3.zero
			combatVFXRemote:FireAllClients("CocoonVFX", targetModel)

			task.delay(CombatConfig.Moves.WebPellet.TrapDuration or 5.0, function()
				if targetModel.Parent and enemyHum.Health > 0 and (targetModel:GetAttribute("IsPinned") ~= true) then
					enemyHum.WalkSpeed = 16
					enemyHum.JumpPower = 50
					targetModel:SetAttribute("IsWebbed", false)
					targetModel:SetAttribute("WebStacks", 0)
					combatVFXRemote:FireAllClients("CocoonBreakVFX", targetModel)
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
				combatVFXRemote:FireAllClients("CocoonBreakVFX", targetModel)
			end
		end)
	end
end

-- 4. 🕸️ RAPID WEB-PELLETS (E Key Remote Listener)
function WebAbilities.handleWebPellet(player: Player, targetModel: any, isImpactArg: any, combatVFXRemote: RemoteEvent)
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end

	-- 🛡️ Anti-Spam Rate Limit Validation
	local now = os.clock()
	local lastFired = playerWebPelletCooldowns[player] or 0
	if (now - lastFired) < 0.18 then return end
	playerWebPelletCooldowns[player] = now

	WebAbilities.handleWebPelletHit(player, targetModel, isImpactArg == true, combatVFXRemote)
end

-- 5. 🔫 WEB-YANK DISARM & WEAPON THROW (Q Key)
function WebAbilities.handleDisarmThrow(player: Player, targetModel: any, combatVFXRemote: RemoteEvent)
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
		CombatDamage.damageEnemy(targetModel, 0, pullDir * 12 + Vector3.new(0, 2, 0), player)

		-- 1. Web Snatch & Overhead Whip Arc
		combatVFXRemote:FireAllClients("DisarmYankVFX", player, weaponHandle)

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
						CombatDamage.damageEnemy(targetModel, CombatConfig.Moves.DisarmAndThrow.Damage or 28, throwDir * (CombatConfig.Moves.DisarmAndThrow.KnockbackForce or 18), player)
					end

					combatVFXRemote:FireAllClients("WeaponImpactVFX", throwTargetPos, throwDir)
				end)
			end)
		end)
	end
end

-- ⚡ Web-Strike Remote (60-Stud Zip Dropkick)
function WebAbilities.handleWebStrike(player: Player, targetModel: any, isAmbushArg: any, combatVFXRemote: RemoteEvent)
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
		combatVFXRemote:FireAllClients("VenomBlastVFX", player, enemyRoot.Position, 14)
		combatVFXRemote:FireAllClients("AmbushCritVFX", player, enemyRoot.Position)
	end
	local punchDir = strikeDir
	local knockback = punchDir * 4

	-- 💥 Guard Break Synergy: Web-Strike breaks Heavy Brute's guard stance!
	local isBrute = targetModel:GetAttribute("Archetype") == "Brute"
	if isBrute then
		targetModel:SetAttribute("GuardBroken", true)
		combatVFXRemote:FireAllClients("GuardBreakVFX", targetModel)
		local breakDuration = CombatConfig.Archetypes and CombatConfig.Archetypes.Brute and CombatConfig.Archetypes.Brute.GuardBreakDuration or 3.5
		task.delay(breakDuration, function()
			if targetModel.Parent and enemyHum.Health > 0 then
				targetModel:SetAttribute("GuardBroken", false)
			end
		end)
	end

	CombatDamage.damageEnemy(targetModel, damage, knockback, player)
	combatVFXRemote:FireAllClients("WebStrikeHit", player, targetModel, damage)

	if is2099 then
		combatVFXRemote:FireAllClients("CyberStrikeVFX", player, enemyRoot.Position)
	end

	-- ⚡ Miles Morales: Electric Web-Strike 2.0s Paralyzing Stun (Strictly on Camo Ambush)
	if isMilesStrike then
		if isAmbushStrike then
			targetModel:SetAttribute("IsAttacking", false)
			targetModel:SetAttribute("AttackDodged", true)
			targetModel:SetAttribute("VenomStunned", true)
			enemyHum.WalkSpeed = 0
			combatVFXRemote:FireAllClients("VenomStunVFX", player, targetModel, 2.0)
			combatVFXRemote:FireAllClients("VenomBlastVFX", player, enemyRoot.Position, 10)

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
			CombatDamage.damageEnemy(targetModel, 8, Vector3.zero, player)
			combatVFXRemote:FireAllClients("VenomBlastVFX", player, enemyRoot.Position, 8)
		end
	end

	if isStark then
		combatVFXRemote:FireAllClients("WaldoRepulsorShockwave", player, enemyRoot.Position, 10)
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
							combatVFXRemote:FireAllClients("GuardBreakVFX", otherEnemy)
							local breakDuration = CombatConfig.Archetypes and CombatConfig.Archetypes.Brute and CombatConfig.Archetypes.Brute.GuardBreakDuration or 3.5
							task.delay(breakDuration, function()
								if otherEnemy.Parent and oHum.Health > 0 then
									otherEnemy:SetAttribute("GuardBroken", false)
								end
							end)
						end
						CombatDamage.damageEnemy(otherEnemy, splashDamage, pushOutDir * 18, player)

						-- ⚡ Miles Morales Splash Electric Stun (Strictly on Camo Ambush)
						if isMilesStrike and isAmbushStrike and otherEnemy:GetAttribute("VenomStunned") ~= true then
							otherEnemy:SetAttribute("IsAttacking", false)
							otherEnemy:SetAttribute("AttackDodged", true)
							otherEnemy:SetAttribute("VenomStunned", true)
							oHum.WalkSpeed = 0
							combatVFXRemote:FireAllClients("VenomStunVFX", player, otherEnemy, 2.0)

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
				CombatDamage.checkAndPinToWall(targetModel, strikeDir, combatVFXRemote)
			end
		end)
	end
end

-- 🌪️ 360° Web Cyclone Finisher Remote Listener (Continuous Multi-Hit AoE DPS)
function WebAbilities.handleWebCyclone(player: Player, actionType: any, targetModel: any, extraData: any, combatVFXRemote: RemoteEvent)
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
		local tickDamage = if isAcrobatic then 8 else 6

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
								combatVFXRemote:FireAllClients("GuardBreakVFX", enemy)
							end
							CombatDamage.damageEnemy(enemy, tickDamage, flingDir * 12, player)
							combatVFXRemote:FireAllClients("KineticHit", player, enemy, 1)
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
			CombatDamage.damageEnemy(targetModel, 25, throwDir * throwSpeed, player)
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

		combatVFXRemote:FireAllClients("WebStrikeHit", player, targetModel)

		-- Check Wall Pin after high-speed flight
		task.delay(0.10, function()
			if targetModel.Parent then
				CombatDamage.checkAndPinToWall(targetModel, throwDir, combatVFXRemote)
			end
		end)
	end
end

return WebAbilities
