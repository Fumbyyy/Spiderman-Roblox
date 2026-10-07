--!strict
--[[
	CrimeService.server.luau
	Phase 5: Server Authority for Procedural Dynamic City Crimes & Police Scanner.
	
	Features:
	- Procedural Crime Generator with 4 Dynamic Archetypes (Bank Heist, Rooftop Deal, Alley Mugging, Getaway Chase)
	- Automatic map anchor scanner (custom parts supported: Crime_Bank, Crime_Rooftop, Crime_Alley, Crime_Getaway)
	- Co-Op wave & reward scaling for multi-hero battles (<= 120 studs)
	- Server-authoritative economy & leaderstats (Level, XP, Hero Cash, Crimes Stopped)
	- Interactive props (Sabotageable Getaway Van engine, Throwable Military Tech Crates)
	- Atmospheric police radio dispatch broadcast
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrimeConfig = require(Shared:WaitForChild("CrimeConfig"))
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local EnemyOverheadUI = require(Shared:WaitForChild("EnemyOverheadUI"))

-- 📦 Create Remotes Folder for Crime Networking
local CrimeRemotesFolder = ReplicatedStorage:FindFirstChild("CrimeRemotes")
if not CrimeRemotesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "CrimeRemotes"
	folder.Parent = ReplicatedStorage
	CrimeRemotesFolder = folder
end

local function getOrCreateRemote(name: string): RemoteEvent
	local remote = CrimeRemotesFolder:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteEvent") then
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = name
		newRemote.Parent = CrimeRemotesFolder
		return newRemote
	end
	return remote
end

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local rf = CrimeRemotesFolder:FindFirstChild(name)
	if not rf or not rf:IsA("RemoteFunction") then
		local newRf = Instance.new("RemoteFunction")
		newRf.Name = name
		newRf.Parent = CrimeRemotesFolder
		return newRf
	end
	return rf
end

local CrimeNotificationRemote = getOrCreateRemote("CrimeNotification")
local CrimeInteractRemote = getOrCreateRemote("CrimeInteract")
local GetActiveCrimesRF = getOrCreateRemoteFunction("GetActiveCrimes")

-- Combat Remotes for VFX
local CombatRemotesFolder = ReplicatedStorage:FindFirstChild("CombatRemotes")
local CombatVFXRemote = CombatRemotesFolder and CombatRemotesFolder:FindFirstChild("CombatVFX") :: RemoteEvent?

-- Active Crimes Workspace Folder
local ActiveCrimesFolder = Workspace:FindFirstChild("ActiveCrimes")
if not ActiveCrimesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "ActiveCrimes"
	folder.Parent = Workspace
	ActiveCrimesFolder = folder
end

local EnemiesFolder = Workspace:FindFirstChild("Enemies")
if not EnemiesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	EnemiesFolder = folder
end

--------------------------------------------------------------------------------
-- 🏆 PLAYER ECONOMY & LEADERSTATS SYSTEM
--------------------------------------------------------------------------------

local function setupPlayerLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local levelVal = Instance.new("IntValue")
	levelVal.Name = "Level"
	levelVal.Value = CrimeConfig.Economy.DefaultLevel or 1
	levelVal.Parent = leaderstats

	local xpVal = Instance.new("IntValue")
	xpVal.Name = "XP"
	xpVal.Value = 0
	xpVal.Parent = leaderstats

	local cashVal = Instance.new("IntValue")
	cashVal.Name = "Hero Cash"
	cashVal.Value = CrimeConfig.Economy.DefaultCash or 100
	cashVal.Parent = leaderstats

	local crimesVal = Instance.new("IntValue")
	crimesVal.Name = "Crimes Stopped"
	crimesVal.Value = 0
	crimesVal.Parent = leaderstats
end

-- 🩸 Dynamic Health Scaling (+10 HP per Level + Suit Defense Perks)
local function updatePlayerHealth(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local leaderstats = player:FindFirstChild("leaderstats")
	local levelVal = leaderstats and leaderstats:FindFirstChild("Level") :: IntValue?
	if hum and levelVal then
		local suitBonus = 0
		local suitPerkType = player:GetAttribute("SuitPerkType")
		local suitPerkValue = player:GetAttribute("SuitPerkValue")
		if suitPerkType == "Defense" and typeof(suitPerkValue) == "number" then
			suitBonus = suitPerkValue
		end
		local targetMax = 100 + (levelVal.Value - 1) * 10 + suitBonus
		local diff = targetMax - hum.MaxHealth
		hum.MaxHealth = targetMax
		if diff > 0 then
			hum.Health = math.clamp(hum.Health + diff, 0, targetMax)
		end
	end
end

-- ⚡ Instant Debug Chat Command (/levelup)
local function setupPlayerChatCommands(player: Player)
	player.Chatted:Connect(function(message: string)
		local cleaned = string.lower(string.match(message, "^%s*(.-)%s*$") or "")
		if cleaned == "/levelup" then
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end

			local levelVal = leaderstats:FindFirstChild("Level") :: IntValue?
			local xpVal = leaderstats:FindFirstChild("XP") :: IntValue?
			if not levelVal or not xpVal then return end

			local currentLvl = levelVal.Value
			if currentLvl < 6 then
				local baseXP = math.max(1, CrimeConfig.Economy.BaseXPForLevel or 150)
				local scale = math.max(1.0, CrimeConfig.Economy.LevelScaleFactor or 1.20)
				local requiredXP = math.max(1, math.floor(baseXP * (currentLvl ^ scale)))
				local addXP = math.max(150, requiredXP - xpVal.Value)
				xpVal.Value += addXP

				while xpVal.Value >= requiredXP and levelVal.Value < 6 do
					xpVal.Value -= requiredXP
					levelVal.Value += 1
					CrimeNotificationRemote:FireClient(player, "LevelUp", levelVal.Value)

					updatePlayerHealth(player)

					currentLvl = levelVal.Value
					if currentLvl >= 6 then
						xpVal.Value = 0
						break
					end
					requiredXP = math.max(1, math.floor(baseXP * (currentLvl ^ scale)))
				end
			end
		elseif cleaned == "/cash" or cleaned == "/addcash" then
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end
			local cashVal = leaderstats:FindFirstChild("Hero Cash") :: IntValue?
			if cashVal then
				cashVal.Value += 5000
			end
		end
	end)
end

for _, player in Players:GetPlayers() do
	setupPlayerLeaderstats(player)
	setupPlayerChatCommands(player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			updatePlayerHealth(player)
		end)
	end)
	if player.Character then
		task.defer(function()
			updatePlayerHealth(player)
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	setupPlayerLeaderstats(player)
	setupPlayerChatCommands(player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			updatePlayerHealth(player)
		end)
	end)
	if player.Character then
		task.defer(function()
			updatePlayerHealth(player)
		end)
	end

	if currentActiveCrime ~= nil then
		task.delay(1.5, function()
			if currentActiveCrime ~= nil and player:IsDescendantOf(Players) then
				CrimeNotificationRemote:FireClient(player, "CrimeSpawned", {
					Id = currentActiveCrime.Id,
					Title = currentActiveCrime.Archetype.Title,
					PoliceCode = currentActiveCrime.Archetype.PoliceCode,
					DispatchMessage = currentActiveCrime.Archetype.DispatchMessage,
					Icon = currentActiveCrime.Archetype.Icon,
					Epicenter = currentActiveCrime.Epicenter,
					ThemeColor = currentActiveCrime.Archetype.ThemeColor,
					Timeout = CrimeConfig.Scheduler.CrimeTimeout,
				})
			end
		end)
	end
end)

-- 💰 Award XP & Hero Cash with Level 6 Hard Cap & Scaled Progression
local function awardPlayerRewards(player: Player, xpAmount: number, cashAmount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local levelVal = leaderstats:FindFirstChild("Level") :: IntValue?
	local xpVal = leaderstats:FindFirstChild("XP") :: IntValue?
	local cashVal = leaderstats:FindFirstChild("Hero Cash") :: IntValue?
	local crimesVal = leaderstats:FindFirstChild("Crimes Stopped") :: IntValue?

	if xpVal and cashVal and levelVal then
		local currentLvl = levelVal.Value
		if currentLvl < 6 then
			xpVal.Value += xpAmount
		else
			xpVal.Value = 0
		end
		cashVal.Value += cashAmount
		if crimesVal then crimesVal.Value += 1 end

		if currentLvl < 6 then
			local baseXP = math.max(1, CrimeConfig.Economy.BaseXPForLevel or 150)
			local scale = math.max(1.0, CrimeConfig.Economy.LevelScaleFactor or 1.20)
			local requiredXP = math.max(1, math.floor(baseXP * (currentLvl ^ scale)))

			while xpVal.Value >= requiredXP and levelVal.Value < 6 do
				xpVal.Value -= requiredXP
				levelVal.Value += 1
				CrimeNotificationRemote:FireClient(player, "LevelUp", levelVal.Value)

				updatePlayerHealth(player)

				currentLvl = levelVal.Value
				if currentLvl >= 6 then
					xpVal.Value = 0
					break
				end
				requiredXP = math.max(1, math.floor(baseXP * (currentLvl ^ scale)))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 🦹 ENEMY & PROP GENERATOR HELPERS
--------------------------------------------------------------------------------

-- Clean Overhead Health Bar for Crime Enemies (shared implementation)
local function attachCrimeHealthBar(enemyModel: Model, enemyName: string, archetype: string, _maxHp: number)
	EnemyOverheadUI.attach(enemyModel, enemyName, archetype)
end

-- Spawn Physical Enemy Model with Full Archetype Attributes
local function spawnCrimeEnemy(spawnCFrame: CFrame, archetype: "Gunner" | "Brute" | "Brawler", enemyName: string, healthBonusMult: number?): Model
	local character = Instance.new("Model")
	character.Name = enemyName

	local archConfig = CombatConfig.Archetypes and CombatConfig.Archetypes[archetype]
	local baseHp = archConfig and archConfig.MaxHealth or 80
	local maxHealth = math.floor(baseHp * (healthBonusMult or 1.0))
	local walkSpeed = archConfig and archConfig.WalkSpeed or 14

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = walkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = character

	local isBrute = (archetype == "Brute")
	local isGunner = (archetype == "Gunner")

	local torsoSize = isBrute and Vector3.new(2.8, 2.6, 1.6) or Vector3.new(2, 2, 1)
	local torsoColor = isBrute and Color3.fromRGB(48, 56, 68) or (isGunner and Color3.fromRGB(38, 48, 62) or Color3.fromRGB(110, 42, 42))

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = torsoSize
	torso.CFrame = spawnCFrame * CFrame.new(0, isBrute and 3.8 or 3.0, 0)
	torso.Color = torsoColor
	torso.Material = isBrute and Enum.Material.DiamondPlate or Enum.Material.SmoothPlastic
	torso.CanCollide = true
	torso.Parent = character

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = torsoSize
	rootPart.CFrame = torso.CFrame
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Parent = character
	character.PrimaryPart = rootPart

	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "RootJoint"
	rootJoint.Part0 = rootPart
	rootJoint.Part1 = torso
	rootJoint.Parent = rootPart

	-- Head
	local headSize = isBrute and Vector3.new(1.4, 1.4, 1.4) or Vector3.new(1.2, 1.2, 1.2)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = headSize
	head.CFrame = torso.CFrame * CFrame.new(0, isBrute and 2.0 or 1.6, 0)
	head.Color = isBrute and Color3.fromRGB(215, 175, 135) or Color3.fromRGB(225, 185, 145)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = true
	head.Parent = character

	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.Part0 = torso
	neck.Part1 = head
	neck.C0 = CFrame.new(0, isBrute and 1.3 or 1.0, 0)
	neck.C1 = CFrame.new(0, -0.6, 0)
	neck.Parent = torso

	-- Limbs
	local limbSize = isBrute and Vector3.new(1.3, 2.4, 1.3) or Vector3.new(1.0, 2.0, 1.0)
	local function createLimb(name: string, offset: Vector3, color: Color3): BasePart
		local limb = Instance.new("Part")
		limb.Name = name
		limb.Size = limbSize
		limb.CFrame = torso.CFrame * CFrame.new(offset)
		limb.Color = color
		limb.Material = isBrute and Enum.Material.DiamondPlate or Enum.Material.SmoothPlastic
		limb.CanCollide = true
		limb.Parent = character

		local joint = Instance.new("Motor6D")
		joint.Name = name .. "Joint"
		joint.Part0 = torso
		joint.Part1 = limb
		joint.C0 = CFrame.new(offset)
		joint.C1 = CFrame.new(0, 0.5, 0)
		joint.Parent = torso
		return limb
	end

	local armX = isBrute and 2.0 or 1.5
	local rightArm = createLimb("Right Arm", Vector3.new(armX, 0, 0), torsoColor)
	createLimb("Left Arm", Vector3.new(-armX, 0, 0), torsoColor)
	createLimb("Right Leg", Vector3.new(isBrute and 0.7 or 0.5, -2.2, 0), Color3.fromRGB(28, 28, 32))
	createLimb("Left Leg", Vector3.new(isBrute and -0.7 or -0.5, -2.2, 0), Color3.fromRGB(28, 28, 32))

	if isBrute then
		for _, side in { -1, 1 } do
			local pauldron = Instance.new("Part")
			pauldron.Name = "Pauldron"
			pauldron.Size = Vector3.new(1.6, 0.6, 1.6)
			pauldron.Color = Color3.fromRGB(90, 100, 115)
			pauldron.Material = Enum.Material.Metal
			pauldron.CanCollide = false
			pauldron.Parent = character

			local pWeld = Instance.new("WeldConstraint")
			pWeld.Part0 = torso
			pWeld.Part1 = pauldron
			pWeld.Parent = pauldron
			pauldron.CFrame = torso.CFrame * CFrame.new(side * 1.9, 1.1, 0)
		end
	end

	if isGunner then
		local gun = Instance.new("Part")
		gun.Name = "Gun"
		gun.Size = Vector3.new(0.6, 0.8, 1.8)
		gun.Color = Color3.fromRGB(35, 38, 45)
		gun.Material = Enum.Material.Metal
		gun.CanCollide = false
		gun.Parent = character

		local gunWeld = Instance.new("Weld")
		gunWeld.Name = "GunWeld"
		gunWeld.Part0 = rightArm
		gunWeld.Part1 = gun
		gunWeld.C0 = CFrame.new(0, -0.9, -0.6)
		gunWeld.Parent = rightArm
	end

	-- Attributes
	character:SetAttribute("IsEnemy", true)
	character:SetAttribute("IsCrimeEnemy", true)
	character:SetAttribute("Archetype", archetype)
	character:SetAttribute("IsArmed", isGunner)
	character:SetAttribute("IsWebbed", false)
	character:SetAttribute("IsPinned", false)
	character:SetAttribute("WebStacks", 0)
	character:SetAttribute("IsAttacking", false)
	character:SetAttribute("AttackDodged", false)
	character:SetAttribute("GuardBroken", false)
	character:SetAttribute("IsBlocking", isBrute)

	CollectionService:AddTag(character, "Enemy")
	attachCrimeHealthBar(character, enemyName, archetype, maxHealth)
	character.Parent = EnemiesFolder

	-- AI Behavior Loop
	task.spawn(function()
		local spawnClock = os.clock()
		local swarmOffsetAngle = (math.random() * math.pi * 2)

		while character.Parent and humanoid.Health > 0 do
			task.wait(0.30)

			-- 🛡️ Void Fall & Geometry Clip Guard
			if rootPart.Position.Y < (Workspace.FallenPartsDestroyHeight + 35) then
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.CFrame = spawnCFrame * CFrame.new(0, isBrute and 3.8 or 3.0, 0)
			end

			if character:GetAttribute("IsWebbed") == true or character:GetAttribute("IsPinned") == true or character:GetAttribute("VenomStunned") == true then
				humanoid:MoveTo(rootPart.Position)
				continue
			end

			-- Find nearest player
			local nearestPlayer: Player? = nil
			local nearestDist = 80

			for _, player in Players:GetPlayers() do
				local pChar = player.Character
				if pChar and (pChar:GetAttribute("MilesCamouflaged") == true or player:GetAttribute("MilesCamouflaged") == true) then
					continue -- 👤 Spider-Verse Camouflage: Ignore cloaked players completely
				end
				local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
				local pHum = pChar and pChar:FindFirstChildOfClass("Humanoid")
				if pRoot and pHum and pHum.Health > 0 then
					local d = (pRoot.Position - rootPart.Position).Magnitude
					if d < nearestDist then
						nearestDist = d
						nearestPlayer = player
					end
				end
			end

			if not nearestPlayer or not nearestPlayer.Character then
				continue
			end

			local pChar = nearestPlayer.Character
			local pRoot = pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			local pHum = pChar:FindFirstChildOfClass("Humanoid")
			if not pRoot or not pHum or pHum.Health <= 0 then continue end

			local dist = (pRoot.Position - rootPart.Position).Magnitude

			-- 🔫 GUNNER AI
			if archetype == "Gunner" and character:GetAttribute("IsArmed") == true and character:FindFirstChild("Gun") then
				local minStandoff = 20
				local maxStandoff = 48

				if dist < minStandoff then
					local awayDir = (rootPart.Position - pRoot.Position).Unit
					humanoid:MoveTo(rootPart.Position + (awayDir * 12))
				elseif dist > maxStandoff then
					humanoid:MoveTo(pRoot.Position)
				else
					humanoid:MoveTo(rootPart.Position)
					rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(pRoot.Position.X, rootPart.Position.Y, pRoot.Position.Z))

					character:SetAttribute("IsAttacking", true)
					character:SetAttribute("AttackDodged", false)

					local gunPart = character:FindFirstChild("Gun") :: BasePart?
					local telegraphDuration = 0.90
					local telegraphStart = os.clock()

					local laserPart = Instance.new("Part")
					laserPart.Name = "GunnerAimLaser"
					laserPart.Material = Enum.Material.Neon
					laserPart.Color = Color3.fromRGB(255, 40, 40)
					laserPart.Transparency = 0.15
					laserPart.CanCollide = false
					laserPart.Anchored = true
					laserPart.Parent = Workspace

					local isTelegraphValid = true
					while (os.clock() - telegraphStart) < telegraphDuration do
						task.wait(0.03)
						local stillArmed = character:GetAttribute("IsArmed") == true and character:FindFirstChild("Gun") ~= nil
						local isWebbed = character:GetAttribute("IsWebbed") == true or (character:GetAttribute("WebStacks") or 0) >= 2
						local isDodged = character:GetAttribute("AttackDodged") == true

						if not character.Parent or humanoid.Health <= 0 or not pChar.Parent or pHum.Health <= 0 or not stillArmed or isWebbed or isDodged or character:GetAttribute("IsAttacking") ~= true then
							isTelegraphValid = false
							break
						end

						if gunPart and pRoot and laserPart and laserPart.Parent then
							local muzzlePos = gunPart.Position + (gunPart.CFrame.LookVector * 1.0)
							local targetChestPos = pRoot.Position + Vector3.new(0, 0.4, 0)
							local beamVec = targetChestPos - muzzlePos
							local beamDist = beamVec.Magnitude

							laserPart.Size = Vector3.new(0.06, 0.06, math.max(0.5, beamDist))
							laserPart.CFrame = CFrame.lookAt((muzzlePos + targetChestPos) / 2, targetChestPos)
							rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(pRoot.Position.X, rootPart.Position.Y, pRoot.Position.Z))
						end
					end

					if laserPart then laserPart:Destroy() end

					if isTelegraphValid and character.Parent and humanoid.Health > 0 and character:GetAttribute("IsAttacking") == true and character:GetAttribute("IsArmed") == true then
						local gunPartActive = character:FindFirstChild("Gun") :: BasePart?
						if gunPartActive and pRoot then
							local muzzlePos = gunPartActive.Position + (gunPartActive.CFrame.LookVector * 1.0)
							local targetChestPos = pRoot.Position + Vector3.new(0, 0.4, 0)
							local fireDir = (targetChestPos - muzzlePos).Unit
							local fireDist = (targetChestPos - muzzlePos).Magnitude

							if CombatVFXRemote then
								CombatVFXRemote:FireAllClients("GunnerMuzzleVFX", muzzlePos, fireDir, fireDist)
							end

							local playerInvulnerable = pChar:GetAttribute("IsInvulnerable") == true or pChar:GetAttribute("MilesCamouflaged") == true or nearestPlayer:GetAttribute("MilesCamouflaged") == true
							if not playerInvulnerable and fireDist <= (maxStandoff + 10) then
								pHum:TakeDamage(12)
							end
						end
					end

					character:SetAttribute("IsAttacking", false)
					character:SetAttribute("AttackDodged", false)
					task.wait(3.0)
				end

			-- 🛡️ BRUTE AI
			elseif archetype == "Brute" then
				local isWebbed = character:GetAttribute("IsWebbed") == true or (character:GetAttribute("WebStacks") or 0) >= 2
				local isGuardBroken = character:GetAttribute("GuardBroken") == true
				character:SetAttribute("IsBlocking", not isWebbed and not isGuardBroken)

				local meleeRange = 7.0
				if dist > meleeRange then
					humanoid:MoveTo(pRoot.Position)
				else
					humanoid:MoveTo(rootPart.Position)
					rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(pRoot.Position.X, rootPart.Position.Y, pRoot.Position.Z))

					character:SetAttribute("IsAttacking", true)
					character:SetAttribute("AttackDodged", false)

					local telegraphTime = 1.10
					local tStart = os.clock()
					while (os.clock() - tStart) < telegraphTime do
						task.wait(0.04)
						if not character.Parent or humanoid.Health <= 0 then break end
						if character:GetAttribute("AttackDodged") == true or character:GetAttribute("IsAttacking") ~= true or character:GetAttribute("IsWebbed") == true or character:GetAttribute("IsPinned") == true or character:GetAttribute("GuardBroken") == true then
							break
						end
					end

					if character.Parent and humanoid.Health > 0 and (character:GetAttribute("IsWebbed") ~= true) and (character:GetAttribute("AttackDodged") ~= true) and (character:GetAttribute("IsAttacking") == true) and (character:GetAttribute("GuardBroken") ~= true) then
						local playerInvulnerable = pChar:GetAttribute("IsInvulnerable") == true
						local curDist = (pRoot.Position - rootPart.Position).Magnitude
						if not playerInvulnerable and curDist <= (meleeRange + 3.0) then
							pHum:TakeDamage(20)
							if CombatVFXRemote then
								CombatVFXRemote:FireAllClients("ShockwaveVFX", rootPart.Position, 8)
							end
						end
					end

					character:SetAttribute("IsAttacking", false)
					character:SetAttribute("AttackDodged", false)
					task.wait(3.5)
				end

			-- 🥊 BRAWLER AI
			else
				local meleeRange = 6.0
				local surroundRad = 7.5
				local orbitAngle = swarmOffsetAngle + ((os.clock() - spawnClock) * 0.4)
				local flankOffset = Vector3.new(math.cos(orbitAngle) * surroundRad, 0, math.sin(orbitAngle) * surroundRad)
				local targetMovePos = (dist > (meleeRange + 3.0)) and (pRoot.Position + flankOffset) or pRoot.Position

				if dist > meleeRange then
					humanoid:MoveTo(targetMovePos)
				else
					humanoid:MoveTo(rootPart.Position)
					rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(pRoot.Position.X, rootPart.Position.Y, pRoot.Position.Z))

					character:SetAttribute("IsAttacking", true)
					character:SetAttribute("AttackDodged", false)

					local telegraphTime = 0.85
					local tStart = os.clock()
					while (os.clock() - tStart) < telegraphTime do
						task.wait(0.04)
						if not character.Parent or humanoid.Health <= 0 then break end
						if character:GetAttribute("AttackDodged") == true or character:GetAttribute("IsAttacking") ~= true or character:GetAttribute("IsWebbed") == true or character:GetAttribute("IsPinned") == true then
							break
						end
					end

					if character.Parent and humanoid.Health > 0 and (character:GetAttribute("IsWebbed") ~= true) and (character:GetAttribute("AttackDodged") ~= true) and (character:GetAttribute("IsAttacking") == true) then
						local playerInvulnerable = pChar:GetAttribute("IsInvulnerable") == true
						local curDist = (pRoot.Position - rootPart.Position).Magnitude
						if not playerInvulnerable and curDist <= (meleeRange + 2.5) then
							pHum:TakeDamage(8)
						end
					end

					character:SetAttribute("IsAttacking", false)
					character:SetAttribute("AttackDodged", false)
					task.wait(2.8)
				end
			end
		end
	end)

	return character
end

--------------------------------------------------------------------------------
-- 📦 INTERACTIVE WORLD PROPS GENERATORS
--------------------------------------------------------------------------------

-- 1. Military Tech Crate (Throwable by Spider-Man with E)
local function createMilitaryTechCrate(position: Vector3, parentFolder: Folder): Model
	local crateModel = Instance.new("Model")
	crateModel.Name = "MilitaryTechCrate"

	local cratePart = Instance.new("Part")
	cratePart.Name = "CratePart"
	cratePart.Size = Vector3.new(3.2, 3.2, 3.2)
	cratePart.Position = position + Vector3.new(0, 1.6, 0)
	cratePart.Color = Color3.fromRGB(65, 80, 55) -- Military Olive Drab
	cratePart.Material = Enum.Material.CorrodedMetal
	cratePart.CanCollide = true
	cratePart.Anchored = false
	cratePart.Parent = crateModel

	-- Glowing Tech Core
	local core = Instance.new("Part")
	core.Name = "TechCore"
	core.Size = Vector3.new(1.2, 1.2, 1.2)
	core.Position = cratePart.Position
	core.Color = Color3.fromRGB(0, 240, 255)
	core.Material = Enum.Material.Neon
	core.CanCollide = false
	core.Parent = crateModel

	local coreWeld = Instance.new("WeldConstraint")
	coreWeld.Part0 = cratePart
	coreWeld.Part1 = core
	coreWeld.Parent = cratePart

	crateModel.PrimaryPart = cratePart
	crateModel:SetAttribute("IsInteractiveCrate", true)
	crateModel:SetAttribute("IsThrown", false)

	-- Tag as Throwable Object
	CollectionService:AddTag(cratePart, "ThrowableObject")
	CollectionService:AddTag(crateModel, "ThrowableObject")

	crateModel.Parent = parentFolder
	return crateModel
end

-- 2. Cowering Civilian NPC Model (For Alleyway Mugging)
local function createCivilianNPC(position: Vector3, parentFolder: Folder): Model
	local civ = Instance.new("Model")
	civ.Name = "Scared Civilian"

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(1.8, 1.8, 0.9)
	torso.Position = position + Vector3.new(0, 1.8, 0)
	torso.Color = Color3.fromRGB(180, 140, 100)
	torso.CanCollide = true
	torso.Parent = civ

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = torso.Size
	rootPart.Position = torso.Position
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Parent = civ

	local rootWeld = Instance.new("WeldConstraint")
	rootWeld.Part0 = rootPart
	rootWeld.Part1 = torso
	rootWeld.Parent = rootPart

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.1, 1.1, 1.1)
	head.Position = torso.Position + Vector3.new(0, 1.3, 0)
	head.Color = Color3.fromRGB(235, 195, 155)
	head.CanCollide = false
	head.Parent = civ

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = 0
	humanoid.Parent = civ

	civ.PrimaryPart = rootPart
	civ:SetAttribute("IsCivilian", true)

	-- Overhead Help Tag
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CivilianGui"
	billboard.Size = UDim2.new(3.8, 0, 0.9, 0)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	billboard.Parent = head

	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1, 0, 1, 0)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.GothamBlack
	tag.Text = "🆘 INNOCENT CIVILIAN"
	tag.TextColor3 = Color3.fromRGB(255, 120, 160)
	tag.TextSize = 14
	tag.TextStrokeTransparency = 0.2
	tag.Parent = billboard

	civ.Parent = parentFolder
	return civ
end

-- 3. Speeding Armored Getaway Van (For High-Speed Getaway Chase)
local function createGetawayVan(startPos: Vector3, moveDir: Vector3, parentFolder: Folder): Model
	local van = Instance.new("Model")
	van.Name = "ArmoredGetawayVan"

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(8, 4.5, 16)
	chassis.CFrame = CFrame.lookAt(startPos + Vector3.new(0, 2.5, 0), startPos + Vector3.new(0, 2.5, 0) + moveDir)
	chassis.Color = Color3.fromRGB(35, 42, 52)
	chassis.Material = Enum.Material.Metal
	chassis.CanCollide = true
	chassis.Anchored = true
	chassis.Parent = van

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = chassis.Size
	hrp.CFrame = chassis.CFrame
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.Anchored = true
	hrp.Parent = van

	-- Roof Web-Zip Target Platform
	local roofZipTarget = Instance.new("Part")
	roofZipTarget.Name = "RoofTarget"
	roofZipTarget.Size = Vector3.new(6, 0.6, 10)
	roofZipTarget.CFrame = chassis.CFrame * CFrame.new(0, 2.4, 0)
	roofZipTarget.Color = Color3.fromRGB(50, 60, 72)
	roofZipTarget.Material = Enum.Material.DiamondPlate
	roofZipTarget.CanCollide = true
	roofZipTarget.Anchored = true
	roofZipTarget.Parent = van

	-- Tag as Enemy so Web-Strike (R) can target and zip straight to the roof!
	CollectionService:AddTag(roofZipTarget, "Enemy")
	roofZipTarget:SetAttribute("IsVehicleRoof", true)

	-- Engine Hood at Front
	local engineHood = Instance.new("Part")
	engineHood.Name = "EngineHood"
	engineHood.Size = Vector3.new(5.5, 2.0, 3.5)
	engineHood.CFrame = chassis.CFrame * CFrame.new(0, -0.4, -7.5)
	engineHood.Color = Color3.fromRGB(215, 48, 48)
	engineHood.Material = Enum.Material.SmoothPlastic
	engineHood.CanCollide = true
	engineHood.Anchored = true
	engineHood.Parent = van

	-- Front Headlights (Neon + Lights)
	for _, side in { -2.4, 2.4 } do
		local lightPart = Instance.new("Part")
		lightPart.Name = "Headlight"
		lightPart.Size = Vector3.new(1.0, 0.8, 0.4)
		lightPart.CFrame = chassis.CFrame * CFrame.new(side, -0.2, -9.3)
		lightPart.Color = Color3.fromRGB(255, 255, 220)
		lightPart.Material = Enum.Material.Neon
		lightPart.CanCollide = false
		lightPart.Anchored = true
		lightPart.Parent = van

		local sLight = Instance.new("SpotLight")
		sLight.Range = 30
		sLight.Angle = 70
		sLight.Brightness = 2.5
		sLight.Color = Color3.fromRGB(255, 255, 230)
		sLight.Face = Enum.NormalId.Front
		sLight.Parent = lightPart
	end

	-- Hazard Beacon on Roof
	local hazardBeacon = Instance.new("Part")
	hazardBeacon.Name = "HazardBeacon"
	hazardBeacon.Size = Vector3.new(1.2, 0.6, 1.2)
	hazardBeacon.CFrame = chassis.CFrame * CFrame.new(0, 2.8, -4.5)
	hazardBeacon.Color = Color3.fromRGB(255, 170, 30)
	hazardBeacon.Material = Enum.Material.Neon
	hazardBeacon.CanCollide = false
	hazardBeacon.Anchored = true
	hazardBeacon.Parent = van

	-- Wheels
	local wheelOffsets = {
		Vector3.new(4.2, -1.2, 4.5), Vector3.new(-4.2, -1.2, 4.5),
		Vector3.new(4.2, -1.2, -4.5), Vector3.new(-4.2, -1.2, -4.5)
	}
	for _, offset in wheelOffsets do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel.Size = Vector3.new(1.2, 2.4, 2.4)
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CFrame = (chassis.CFrame * CFrame.new(offset)) * CFrame.Angles(0, 0, math.rad(90))
		wheel.Color = Color3.fromRGB(20, 20, 20)
		wheel.Material = Enum.Material.Rubber
		wheel.CanCollide = false
		wheel.Anchored = true
		wheel.Parent = van
	end

	-- Stolen Tech Cargo in back
	for i = 1, 2 do
		local techCrate = Instance.new("Part")
		techCrate.Name = "CargoCrate"
		techCrate.Size = Vector3.new(2.4, 2.2, 2.4)
		techCrate.CFrame = chassis.CFrame * CFrame.new(i == 1 and 1.4 or -1.4, 0.4, 4.0)
		techCrate.Color = Color3.fromRGB(45, 95, 140)
		techCrate.Material = Enum.Material.CorrodedMetal
		techCrate.CanCollide = true
		techCrate.Anchored = true
		techCrate.Parent = van
	end

	van.PrimaryPart = hrp
	van:SetAttribute("IsDisabled", false)

	van.Parent = parentFolder
	return van
end

--------------------------------------------------------------------------------
-- 🏙️ PROCEDURAL CRIME ARENA LIFECYCLE
--------------------------------------------------------------------------------

export type ActiveCrimeInstance = {
	Id: string,
	Archetype: CrimeConfig.CrimeArchetypeConfig,
	Epicenter: Vector3,
	Folder: Folder,
	State: "Spawned" | "InProgress" | "Cleared" | "Failed",
	StartTime: number,
	Enemies: { Model },
	ParticipatingPlayers: { [Player]: boolean },
	IsCoOpScaled: boolean,
}

local currentActiveCrime: ActiveCrimeInstance? = nil
local lastCrimeEndTime = 0

-- 🔍 Locate Optimal Spawn Points (Supports custom creator parts or dynamic city scans)
local function findCrimeSpawnLocation(archetypeId: string): (Vector3, Vector3, BasePart?)
	local specificParts: { BasePart } = {}
	local generalParts: { BasePart } = {}

	local targetPrefix = (archetypeId == "BankHeist" and "bank")
		or (archetypeId == "RooftopDeal" and "rooftop")
		or (archetypeId == "AlleywayMugging" and "alley")
		or "getaway"

	-- 1. Check if Creator placed custom map markers or spawn folders in Workspace
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			local lowerName = string.lower(descendant.Name)
			local parentName = descendant.Parent and string.lower(descendant.Parent.Name) or ""

			local isSpawnFolder = parentName == "enemyspawns" or parentName == "crimespawns" or parentName == "questspawns" or parentName == "spawnpoints" or parentName == "enemy_spawns" or parentName == "crime_spawns"
			local isSpawnNamed = string.find(lowerName, "enemyspawn") ~= nil
				or string.find(lowerName, "crimespawn") ~= nil
				or string.find(lowerName, "questspawn") ~= nil
				or string.find(lowerName, "enemy_spawn") ~= nil
				or string.find(lowerName, "crime_spawn") ~= nil
				or string.find(lowerName, "enemy spawn") ~= nil
				or string.find(lowerName, "crime spawn") ~= nil
				or string.find(lowerName, "quest spawn") ~= nil
				or lowerName == "crime_bank" or lowerName == "crime_rooftop" or lowerName == "crime_alley" or lowerName == "crime_getaway"

			if isSpawnNamed or isSpawnFolder then
				descendant.Transparency = 1
				descendant.CanCollide = false

				if string.find(lowerName, targetPrefix) ~= nil then
					table.insert(specificParts, descendant)
				else
					table.insert(generalParts, descendant)
				end
			end
		end
	end

	-- Prioritize specific archetype markers if present, otherwise general spawns
	local pool = #specificParts > 0 and specificParts or generalParts
	if #pool > 0 then
		local chosenPart = pool[math.random(1, #pool)]
		local lookDir = chosenPart.CFrame.LookVector
		local spawnPos = chosenPart.Position + Vector3.new(0, (chosenPart.Size.Y * 0.5) + 0.5, 0)
		return spawnPos, lookDir, chosenPart
	end

	-- 2. Procedural Fallback based on Players & High-Altitude Raycasting
	local fallbackPositions = {
		BankHeist = Vector3.new(0, 3, -60),
		RooftopDeal = Vector3.new(45, 65, 40),
		AlleywayMugging = Vector3.new(-50, 3, -20),
		GetawayChase = Vector3.new(-80, 3, 50),
	}

	local basePos = fallbackPositions[archetypeId] or Vector3.new(0, 3, 0)
	local moveDir = Vector3.new(0, 0, -1)

	-- If players are present, center near active player cluster
	local players = Players:GetPlayers()
	if #players > 0 then
		local p = players[math.random(1, #players)]
		local pRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if pRoot then
			local angle = math.random() * math.pi * 2
			local dist = math.random(75, 140)
			local candidateX = pRoot.Position.X + (math.cos(angle) * dist)
			local candidateZ = pRoot.Position.Z + (math.sin(angle) * dist)

			-- Raycast down from high altitude (350 studs) to hit true roof/ground, NOT interior rooms!
			local rayOrigin = Vector3.new(candidateX, 350, candidateZ)
			local rayDir = Vector3.new(0, -500, 0)
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = { EnemiesFolder, ActiveCrimesFolder }

			local result = Workspace:Raycast(rayOrigin, rayDir, rayParams)
			if result and result.Normal.Y > 0.5 and result.Position.Y > (Workspace.FallenPartsDestroyHeight + 40) then
				basePos = result.Position + Vector3.new(0, 1.5, 0)
			end
		end
	end

	return basePos, moveDir, nil
end

-- 🚨 Procedurally Trigger a Dynamic City Crime
local function spawnProceduralCrime(specificArchetypeId: string?): ActiveCrimeInstance?
	if currentActiveCrime ~= nil then return nil end

	-- Pick Random Archetype if not specified
	local archetypesList = { "BankHeist", "RooftopDeal", "AlleywayMugging", "GetawayChase" }
	local chosenId = specificArchetypeId or archetypesList[math.random(1, #archetypesList)]
	local archConfig = CrimeConfig.Archetypes[chosenId]
	if not archConfig then return nil end

	local epicenter, moveDir, chosenSpawnPart = findCrimeSpawnLocation(chosenId)

	local crimeFolder = Instance.new("Folder")
	crimeFolder.Name = "ActiveCrime_" .. chosenId
	crimeFolder.Parent = ActiveCrimesFolder

	local crimeInstance: ActiveCrimeInstance = {
		Id = chosenId,
		Archetype = archConfig,
		Epicenter = epicenter,
		Folder = crimeFolder,
		State = "Spawned",
		StartTime = os.clock(),
		Enemies = {},
		ParticipatingPlayers = {},
		IsCoOpScaled = false,
	}

	currentActiveCrime = crimeInstance

	-- 1. Generate Props
	if archConfig.InteractiveCrates and archConfig.InteractiveCrates > 0 then
		for i = 1, archConfig.InteractiveCrates do
			local offset = Vector3.new(math.cos(i * 2.1) * 6, 0, math.sin(i * 2.1) * 6)
			createMilitaryTechCrate(epicenter + offset, crimeFolder)
		end
	end

	if archConfig.HasCivilian then
		createCivilianNPC(epicenter + Vector3.new(2, 0, 2), crimeFolder)
	end

	if archConfig.IsVehicleChase then
		createGetawayVan(epicenter, moveDir, crimeFolder)
	end

	-- 2. Spawn Enemies
	for _, entry in archConfig.Enemies do
		for i = 1, entry.Count do
			local spawnPos: Vector3
			if chosenSpawnPart then
				local partSize = chosenSpawnPart.Size
				local radiusX = math.clamp(partSize.X * 0.35, 1.5, 10)
				local radiusZ = math.clamp(partSize.Z * 0.35, 1.5, 10)
				local angle = (i - 1) * (math.pi * 2 / math.max(1, entry.Count))
				local localOffset = Vector3.new(math.cos(angle) * radiusX, 0.5, math.sin(angle) * radiusZ)
				spawnPos = chosenSpawnPart.Position + localOffset
			else
				local offset = Vector3.new(math.cos(i * 1.5) * 8, 0, math.sin(i * 1.5) * 8)
				local candidatePos = epicenter + offset
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { crimeFolder, EnemiesFolder }
				local hit = Workspace:Raycast(candidatePos + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), rayParams)
				spawnPos = hit and (hit.Position + Vector3.new(0, 0.5, 0)) or (candidatePos + Vector3.new(0, 1.0, 0))
			end

			local spawnCF = CFrame.new(spawnPos)
			local enemyName = entry.Archetype == "Gunner" and string.format("%s [Gunner #%d]", archConfig.Title, i)
				or entry.Archetype == "Brute" and string.format("%s [Heavy Enforcer]", archConfig.Title)
				or string.format("%s [Mob #%d]", archConfig.Title, i)

			local enemyModel = spawnCrimeEnemy(spawnCF, entry.Archetype, enemyName, 1.0)
			table.insert(crimeInstance.Enemies, enemyModel)
		end
	end

	-- 3. Broadcast Atmospheric Police Dispatch to All Players
	CrimeNotificationRemote:FireAllClients("CrimeSpawned", {
		Id = chosenId,
		Title = archConfig.Title,
		PoliceCode = archConfig.PoliceCode,
		DispatchMessage = archConfig.DispatchMessage,
		Icon = archConfig.Icon,
		Epicenter = epicenter,
		ThemeColor = archConfig.ThemeColor,
		Timeout = CrimeConfig.Scheduler.CrimeTimeout,
	})

	print(string.format("🚨 [NYPD DISPATCH] Active Crime Triggered: %s at (%d, %d, %d)", archConfig.Title, epicenter.X, epicenter.Y, epicenter.Z))
	return crimeInstance
end

-- 🎉 Clear Active Crime & Distribute Hero Rewards
local function clearActiveCrime(crimeInstance: ActiveCrimeInstance)
	if crimeInstance.State == "Cleared" or crimeInstance.State == "Failed" then return end
	crimeInstance.State = "Cleared"
	lastCrimeEndTime = os.clock()

	-- Co-Op Multiplier Calculation
	local participantCount = 0
	for _ in crimeInstance.ParticipatingPlayers do
		participantCount += 1
	end

	local rewardMultiplier = 1.0
	if participantCount > 1 then
		rewardMultiplier += ((participantCount - 1) * (CrimeConfig.CoOp.BonusRewardPerPlayer or 0.25))
	end

	local finalXP = math.floor(crimeInstance.Archetype.RewardXP * rewardMultiplier)
	local finalCash = math.floor(crimeInstance.Archetype.RewardCash * rewardMultiplier)

	-- Award to all participating Spider-Heroes
	for player in crimeInstance.ParticipatingPlayers do
		awardPlayerRewards(player, finalXP, finalCash)
	end

	-- If no participants tracked yet (e.g. killed from afar), award nearest player
	if participantCount == 0 then
		for _, player in Players:GetPlayers() do
			local pRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if pRoot and (pRoot.Position - crimeInstance.Epicenter).Magnitude <= (CrimeConfig.CoOp.ProximityRadius or 120) then
				awardPlayerRewards(player, finalXP, finalCash)
				break
			end
		end
	end

	-- Broadcast Victory Screen
	CrimeNotificationRemote:FireAllClients("CrimeCleared", {
		Id = crimeInstance.Id,
		Title = crimeInstance.Archetype.Title,
		RewardXP = finalXP,
		RewardCash = finalCash,
		ParticipantCount = math.max(1, participantCount),
	})

	print(string.format("🎉 Crime Cleared: %s (+%d XP, +$%d Hero Cash)", crimeInstance.Archetype.Title, finalXP, finalCash))

	-- Cleanup after delay (Destroys folder and any remaining enemy instances)
	task.delay(CrimeConfig.Scheduler.DespawnCleanupDelay or 5.0, function()
		for _, enemy in crimeInstance.Enemies do
			if enemy and enemy.Parent then
				enemy:Destroy()
			end
		end
		if crimeInstance.Folder then
			crimeInstance.Folder:Destroy()
		end
		if currentActiveCrime == crimeInstance then
			currentActiveCrime = nil
		end
	end)
end

-- ❌ Fail Active Crime (Timeout or Civilian defeated)
local function failActiveCrime(crimeInstance: ActiveCrimeInstance, reason: string)
	if crimeInstance.State == "Cleared" or crimeInstance.State == "Failed" then return end
	crimeInstance.State = "Failed"
	lastCrimeEndTime = os.clock()

	CrimeNotificationRemote:FireAllClients("CrimeFailed", {
		Id = crimeInstance.Id,
		Title = crimeInstance.Archetype.Title,
		Reason = reason,
	})

	print(string.format("⚠️ Crime Expired/Failed: %s (%s)", crimeInstance.Archetype.Title, reason))

	task.delay(CrimeConfig.Scheduler.DespawnCleanupDelay or 5.0, function()
		for _, enemy in crimeInstance.Enemies do
			if enemy and enemy.Parent then
				enemy:Destroy()
			end
		end
		if crimeInstance.Folder then
			crimeInstance.Folder:Destroy()
		end
		if currentActiveCrime == crimeInstance then
			currentActiveCrime = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- 🔄 MAIN CRIME SERVICE SCHEDULER HEARTBEAT
--------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function()
	local now = os.clock()

	-- 1. Crime Lifecycle Monitor
	if currentActiveCrime ~= nil then
		local crime = currentActiveCrime
		local elapsed = now - crime.StartTime

		-- Check Timeout
		if elapsed > (CrimeConfig.Scheduler.CrimeTimeout or 240) then
			failActiveCrime(crime, "Suspects Escaped")
			return
		end

		-- Track Players in Range & Update State
		local nearbyPlayers: { Player } = {}
		for _, player in Players:GetPlayers() do
			local pChar = player.Character
			local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			local pHum = pChar and pChar:FindFirstChildOfClass("Humanoid")
			if pRoot and pHum and pHum.Health > 0 then
				local dist = (pRoot.Position - crime.Epicenter).Magnitude
				if dist <= (CrimeConfig.CoOp.ProximityRadius or 120) then
					table.insert(nearbyPlayers, player)
					crime.ParticipatingPlayers[player] = true
				end
			end
		end

		if #nearbyPlayers > 0 and crime.State == "Spawned" then
			crime.State = "InProgress"
			CrimeNotificationRemote:FireAllClients("CrimeInProgress", crime.Id)
		end

		-- Co-Op Wave Scaling (Spawn reinforcements if multi-hero presence detected)
		if #nearbyPlayers >= (CrimeConfig.CoOp.MinPlayersForScale or 2) and not crime.IsCoOpScaled then
			crime.IsCoOpScaled = true
			local extraCount = (#nearbyPlayers - 1) * (CrimeConfig.CoOp.ExtraBrawlersPerPlayer or 1)
			for i = 1, extraCount do
				local offset = Vector3.new(math.cos(i * 2) * 14, 0, math.sin(i * 2) * 14)
				local enemyModel = spawnCrimeEnemy(CFrame.new(crime.Epicenter + offset), "Brawler", string.format("Backup Mob #%d", i), 1.25)
				table.insert(crime.Enemies, enemyModel)
			end
			CrimeNotificationRemote:FireAllClients("CoOpScaleActive", #nearbyPlayers)
		end

		-- Check if all enemies defeated
		local livingEnemies = 0
		for _, enemy in crime.Enemies do
			if enemy.Parent then
				local hum = enemy:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					livingEnemies += 1
				end
			end
		end

		-- Check for getaway van enemies if van was disabled
		for _, descendant in EnemiesFolder:GetChildren() do
			if descendant:IsA("Model") and descendant:GetAttribute("IsCrimeEnemy") == true then
				local hum = descendant:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and not table.find(crime.Enemies, descendant) then
					table.insert(crime.Enemies, descendant)
					livingEnemies += 1
				end
			end
		end

		-- Auto-clear crime when all enemies are defeated (auto-disables getaway vehicle if present)
		if livingEnemies == 0 and (elapsed > 1.5) and (crime.State == "InProgress" or #crime.Enemies > 0) then
			local van = crime.Folder:FindFirstChild("ArmoredGetawayVan")
			if van and van:GetAttribute("IsDisabled") ~= true then
				van:SetAttribute("IsDisabled", true)
			end
			clearActiveCrime(crime)
		end

	-- 2. Periodic Crime Dispatch Scheduler
	else
		local cooldown = CrimeConfig.Scheduler.PostClearCooldown or 8
		if (now - lastCrimeEndTime) > cooldown then
			local nextInterval = math.random(CrimeConfig.Scheduler.SpawnIntervalMin or 25, CrimeConfig.Scheduler.SpawnIntervalMax or 45)
			if (now - lastCrimeEndTime) > (cooldown + nextInterval) and #Players:GetPlayers() > 0 then
				spawnProceduralCrime()
			end
		end
	end
end)

-- 📱 FNSM Scanner & Datapad Remote Invocations
GetActiveCrimesRF.OnServerInvoke = function(_player: Player): any
	if currentActiveCrime ~= nil then
		return {
			Id = currentActiveCrime.Id,
			Title = currentActiveCrime.Archetype.Title,
			PoliceCode = currentActiveCrime.Archetype.PoliceCode,
			Icon = currentActiveCrime.Archetype.Icon,
			Epicenter = currentActiveCrime.Epicenter,
			ThemeColor = currentActiveCrime.Archetype.ThemeColor,
			RewardXP = currentActiveCrime.Archetype.RewardXP,
			RewardCash = currentActiveCrime.Archetype.RewardCash,
			State = currentActiveCrime.State,
			District = "Midtown Manhattan",
		}
	end
	return nil
end

-- 🎮 On-Demand Police Dispatch & Crime Interaction
CrimeInteractRemote.OnServerEvent:Connect(function(_player: Player, action: string, param: any)
	if action == "RequestDispatch" or action == "RequestCrime" then
		if currentActiveCrime == nil then
			local specificArchetype = typeof(param) == "string" and param or nil
			spawnProceduralCrime(specificArchetype)
		end
	end
end)

-- Spawn first crime after initial warmup
task.delay(6.0, function()
	if currentActiveCrime == nil and #Players:GetPlayers() > 0 then
		spawnProceduralCrime()
	end
end)

print("🚨 CrimeService Online! Procedural City Crime Generator & Co-Op Scaling Active.")
