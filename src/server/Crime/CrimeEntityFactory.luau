--!strict
--[[
	CrimeEntityFactory.luau
	Procedural construction of crime enemies, AI telegraph combat loops,
	getaway chase vans, civilian hostages, and throwable military crates.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local EnemyOverheadUI = require(Shared:WaitForChild("EnemyOverheadUI"))

local CrimeEntityFactory = {}

-- Clean Overhead Health Bar for Crime Enemies
function CrimeEntityFactory.attachCrimeHealthBar(enemyModel: Model, enemyName: string, archetype: string, _maxHp: number)
	EnemyOverheadUI.attach(enemyModel, enemyName, archetype)
end

-- Spawn Physical Enemy Model with Full Archetype Attributes and AI loop
function CrimeEntityFactory.spawnCrimeEnemy(
	spawnCFrame: CFrame,
	archetype: "Gunner" | "Brute" | "Brawler",
	enemyName: string,
	healthBonusMult: number?,
	enemiesFolder: Folder,
	combatVFXRemote: RemoteEvent?
): Model
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
	CrimeEntityFactory.attachCrimeHealthBar(character, enemyName, archetype, maxHealth)
	character.Parent = enemiesFolder

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

							if combatVFXRemote then
								combatVFXRemote:FireAllClients("GunnerMuzzleVFX", muzzlePos, fireDir, fireDist)
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
							if combatVFXRemote then
								combatVFXRemote:FireAllClients("ShockwaveVFX", rootPart.Position, 8)
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

-- 1. Military Tech Crate (Throwable by Spider-Man with E)
function CrimeEntityFactory.createMilitaryTechCrate(position: Vector3, parentFolder: Folder): Model
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
function CrimeEntityFactory.createCivilianNPC(position: Vector3, parentFolder: Folder): Model
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
function CrimeEntityFactory.createGetawayVan(startPos: Vector3, moveDir: Vector3, parentFolder: Folder): Model
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

return CrimeEntityFactory
