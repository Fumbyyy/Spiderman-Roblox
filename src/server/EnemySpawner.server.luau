--!strict
--[[
	EnemySpawner.server.luau
	Phase 4.2 Tactical Enemy AI Archetypes & Avatar Rig System:
	1. ?? Armed Gunner / Rooftop Sniper (Ranged Threat: 25-45 studs standoff, 0.9s red laser telegraph, 12 DMG)
	2. ??? Armored Heavy Brute (Defensive Tank: 160 HP, bulky physique, blocks frontal punches, 1.1s smash)
	3. ?? Street Brawler Mob (Swarm Threat: 80 HP, dynamic angular surround slots, 0.85s punch combo)

	Avatar System:
	- Clones custom-dressed enemy rigs from ReplicatedStorage.EnemyTemplates (Gunner, Brute, Brawler, Thug)
	- Zero-HTTP robust procedural fallback (Humanoid rig with Clothing, Wearables, Weapons & Pauldrons)
	- Authoritative gameplay attributes, overhead tactical health bars, auto-respawn, and AI state machines
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local EnemyOverheadUI = require(Shared:WaitForChild("EnemyOverheadUI"))
local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local CombatVFXRemote = RemotesFolder:WaitForChild("CombatVFX") :: RemoteEvent

-- ?? Enemies Folder in Workspace
local EnemiesFolder = Workspace:FindFirstChild("Enemies")
if not EnemiesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	EnemiesFolder = folder
end

export type EnemyArchetype = "Gunner" | "Brute" | "Brawler"

--------------------------------------------------------------------------------
-- ?? TACTICAL OVERHEAD HEALTH BAR
--------------------------------------------------------------------------------

local function attachHealthBar(enemyModel: Model, enemyName: string, archetype: EnemyArchetype, _maxHp: number)
	EnemyOverheadUI.attach(enemyModel, enemyName, archetype)
end

--------------------------------------------------------------------------------
-- ?? WEAPON BUILDERS
--------------------------------------------------------------------------------

local function createGunWeapon(): BasePart
	local gun = Instance.new("Part")
	gun.Name = "Gun"
	gun.Size = Vector3.new(0.5, 0.8, 1.8)
	gun.Color = Color3.fromRGB(35, 38, 45)
	gun.Material = Enum.Material.Metal
	gun.CanCollide = false
	gun.CastShadow = true
	return gun
end

local function createMeleeWeapon(archetype: EnemyArchetype): BasePart?
	if archetype == "Brawler" then
		local bat = Instance.new("Part")
		bat.Name = "MeleeWeapon"
		bat.Size = Vector3.new(0.4, 0.4, 3.4)
		bat.Color = Color3.fromRGB(165, 120, 80)
		bat.Material = Enum.Material.Wood
		bat.CanCollide = false
		return bat
	end
	return nil
end

--------------------------------------------------------------------------------
-- ?? SPAWN CRIMINAL (Templates & Procedural Fallback)
--------------------------------------------------------------------------------

local startEnemyAI: (character: Model, humanoid: Humanoid, rootPart: BasePart, archetype: EnemyArchetype, spawnPos: Vector3) -> ()

local function spawnCriminal(position: Vector3, archetype: EnemyArchetype, enemyName: string): Model
	local isBrute = (archetype == "Brute")
	local isGunner = (archetype == "Gunner")

	local archConfig = CombatConfig.Archetypes and CombatConfig.Archetypes[archetype]
	local maxHealth = archConfig and archConfig.MaxHealth or (isBrute and 160 or (isGunner and 70 or 80))
	local walkSpeed = archConfig and archConfig.WalkSpeed or (isBrute and 12 or (isGunner and 14 or 16))

	-- 1. Query ReplicatedStorage.EnemyTemplates for pre-authored models
	local enemyTemplates = ReplicatedStorage:FindFirstChild("EnemyTemplates")
	local customTemplate: Model? = nil

	if enemyTemplates then
		customTemplate = (enemyTemplates:FindFirstChild(archetype)
			or enemyTemplates:FindFirstChild(enemyName)
			or (isBrute and enemyTemplates:FindFirstChild("Enforcer"))
			or (isGunner and enemyTemplates:FindFirstChild("Marksman"))
			or enemyTemplates:FindFirstChild("Brawler")
			or enemyTemplates:FindFirstChild("Thug")
			or enemyTemplates:FindFirstChild("Enemy")
			or enemyTemplates:FindFirstChild("Default")) :: Model?
	end

	local character: Model
	local humanoid: Humanoid
	local rootPart: BasePart

	if customTemplate and customTemplate:IsA("Model") then
		character = customTemplate:Clone()
		character.Name = enemyName

		local hrp = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
		if not hrp then
			hrp = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
		end
		if not hrp or not hrp:IsA("BasePart") then
			hrp = Instance.new("Part")
			hrp.Name = "HumanoidRootPart"
			hrp.Size = Vector3.new(2, 2, 1)
			hrp.Transparency = 1
			hrp.CanCollide = false
			hrp.Parent = character
		end
		character.PrimaryPart = hrp
		rootPart = hrp
		character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))

		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum then
			hum = Instance.new("Humanoid")
			hum.Parent = character
		end
		humanoid = hum
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
		humanoid.WalkSpeed = walkSpeed
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		-- Dynamic Archetype Proportions for R15 template rigs
		pcall(function()
			local description = humanoid:GetAppliedDescription()
			if description then
				if isBrute then
					description.HeightScale = 1.15
					description.WidthScale = 1.25
					description.DepthScale = 1.20
					description.BodyTypeScale = 0.90
				elseif isGunner then
					description.HeightScale = 0.95
					description.WidthScale = 0.90
					description.DepthScale = 0.90
				end
				humanoid:ApplyDescription(description)
			end
		end)

		-- Ensure weapon for Gunner if not already present
		if isGunner and not character:FindFirstChild("Gun") then
			local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") :: BasePart?
			if rightHand then
				local gun = createGunWeapon()
				gun.Position = rightHand.Position + Vector3.new(0, -0.8, -0.5)
				gun.Parent = character

				local gunWeld = Instance.new("WeldConstraint")
				gunWeld.Part0 = rightHand
				gunWeld.Part1 = gun
				gunWeld.Parent = gun
			end
		end
	else
		-- 2. Zero-HTTP Procedural Humanoid Rig Fallback
		character = Instance.new("Model")
		character.Name = enemyName

		humanoid = Instance.new("Humanoid")
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
		humanoid.WalkSpeed = walkSpeed
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.Parent = character

		local torsoSize = isBrute and Vector3.new(2.8, 2.6, 1.6) or Vector3.new(2, 2, 1)
		local torsoColor = if isBrute then Color3.fromRGB(48, 56, 68) elseif isGunner then Color3.fromRGB(38, 48, 62) else Color3.fromRGB(110, 42, 42)

		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Size = torsoSize
		torso.Position = position + Vector3.new(0, isBrute and 3.8 or 3.0, 0)
		torso.Color = torsoColor
		torso.Material = isBrute and Enum.Material.DiamondPlate or Enum.Material.SmoothPlastic
		torso.CanCollide = true
		torso.Parent = character

		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = torsoSize
		rootPart.Position = torso.Position
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.Parent = character
		character.PrimaryPart = rootPart

		local rootJoint = Instance.new("Motor6D")
		rootJoint.Name = "RootJoint"
		rootJoint.Part0 = rootPart
		rootJoint.Part1 = torso
		rootJoint.Parent = rootPart

		local headSize = isBrute and Vector3.new(1.4, 1.4, 1.4) or Vector3.new(1.2, 1.2, 1.2)
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = headSize
		head.Position = torso.Position + Vector3.new(0, isBrute and 2.0 or 1.6, 0)
		head.Color = isBrute and Color3.fromRGB(215, 175, 135) or Color3.fromRGB(225, 185, 145)
		head.Material = Enum.Material.SmoothPlastic
		head.CanCollide = true
		head.Parent = character

		local face = Instance.new("Decal")
		face.Name = "face"
		face.Face = Enum.NormalId.Front
		face.Texture = "rbxassetid://144075659"
		face.Parent = head

		local neck = Instance.new("Motor6D")
		neck.Name = "Neck"
		neck.Part0 = torso
		neck.Part1 = head
		neck.C0 = CFrame.new(0, isBrute and 1.3 or 1.0, 0)
		neck.C1 = CFrame.new(0, -0.6, 0)
		neck.Parent = torso

		-- Thug Beanie / Mask Wearable
		local beanie = Instance.new("Part")
		beanie.Name = "ThugBeanie"
		beanie.Size = isBrute and Vector3.new(1.45, 0.4, 1.45) or Vector3.new(1.25, 0.35, 1.25)
		beanie.Color = isBrute and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(35, 38, 45)
		beanie.Material = Enum.Material.Fabric
		beanie.CanCollide = false
		beanie.Parent = character
		local bWeld = Instance.new("WeldConstraint")
		bWeld.Part0 = head
		bWeld.Part1 = beanie
		bWeld.Parent = beanie
		beanie.CFrame = head.CFrame * CFrame.new(0, isBrute and 0.65 or 0.55, 0)

		-- Procedural Street Clothing
		local shirt = Instance.new("Shirt")
		shirt.Name = "ThugShirt"
		shirt.ShirtTemplate = "http://www.roblox.com/asset/?id=39863358"
		shirt.Parent = character

		local pants = Instance.new("Pants")
		pants.Name = "ThugPants"
		pants.PantsTemplate = "http://www.roblox.com/asset/?id=39863374"
		pants.Parent = character

		-- Limbs
		local limbSize = isBrute and Vector3.new(1.3, 2.4, 1.3) or Vector3.new(1.0, 2.0, 1.0)
		local function createLimb(name: string, offset: Vector3, color: Color3): BasePart
			local limb = Instance.new("Part")
			limb.Name = name
			limb.Size = limbSize
			limb.Position = torso.Position + offset
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
		local armY = isBrute and 0.1 or 0
		local rightArm = createLimb("Right Arm", Vector3.new(armX, armY, 0), torsoColor)
		createLimb("Left Arm", Vector3.new(-armX, armY, 0), torsoColor)

		local legX = isBrute and 0.7 or 0.5
		local legY = isBrute and -2.4 or -2.0
		createLimb("Right Leg", Vector3.new(legX, legY, 0), Color3.fromRGB(28, 28, 32))
		createLimb("Left Leg", Vector3.new(-legX, legY, 0), Color3.fromRGB(28, 28, 32))

		-- Brute Heavy Pauldrons
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

		-- Gunner Handgun
		if isGunner then
			local gun = createGunWeapon()
			gun.Position = rightArm.Position + Vector3.new(0, -0.9, -0.6)
			gun.Parent = character

			local gunWeld = Instance.new("WeldConstraint")
			gunWeld.Part0 = rightArm
			gunWeld.Part1 = gun
			gunWeld.Parent = gun
		end
	end

	-- 3. Authoritative Attributes & Setup (Applied to both template and fallback rigs)
	character:SetAttribute("IsEnemy", true)
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
	attachHealthBar(character, enemyName, archetype, maxHealth)
	character.Parent = EnemiesFolder

	-- Auto-Respawn
	humanoid.Died:Connect(function()
		task.delay(CombatConfig.Enemies.RespawnDelay + 1.0, function()
			if character and character.Parent then
				character:Destroy()
			end
			spawnCriminal(position, archetype, enemyName)
		end)
	end)

	-- 4. Start Dynamic AI State Machine
	startEnemyAI(character, humanoid, rootPart, archetype, position)

	return character
end

--------------------------------------------------------------------------------
-- ?? DYNAMIC ENEMY AI STATE MACHINE
--------------------------------------------------------------------------------

startEnemyAI = function(character: Model, humanoid: Humanoid, rootPart: BasePart, archetype: EnemyArchetype, spawnPos: Vector3)
	local archConfig = CombatConfig.Archetypes and CombatConfig.Archetypes[archetype]

	task.spawn(function()
		local spawnClock = os.clock()
		local swarmOffsetAngle = (math.random() * math.pi * 2)

		while character.Parent and humanoid.Health > 0 do
			task.wait(0.30)

			-- Check if immobilized by webs or venom stun
			if character:GetAttribute("IsWebbed") == true or character:GetAttribute("IsPinned") == true or character:GetAttribute("VenomStunned") == true then
				humanoid:MoveTo(rootPart.Position)
				continue
			end

			-- Find nearest player
			local nearestPlayer: Player? = nil
			local nearestDist = 65

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
				if (rootPart.Position - spawnPos).Magnitude > 8 then
					humanoid:MoveTo(spawnPos)
				end
				continue
			end

			local pChar = nearestPlayer.Character
			local pRoot = pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			local pHum = pChar:FindFirstChildOfClass("Humanoid")
			if not pRoot or not pHum or pHum.Health <= 0 then continue end

			local dist = (pRoot.Position - rootPart.Position).Magnitude

			--------------------------------------------------------------------
			-- ?? 1. ARMED GUNNER AI (25-45 studs standoff & red laser telegraph)
			--------------------------------------------------------------------
			if archetype == "Gunner" and character:GetAttribute("IsArmed") == true and character:FindFirstChild("Gun") then
				local minStandoff = archConfig and archConfig.PreferredMinDistance or 22
				local maxStandoff = archConfig and archConfig.PreferredMaxDistance or 45

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
					local telegraphDuration = archConfig and archConfig.TelegraphTime or 0.90
					local telegraphStart = os.clock()

					local laserPart = Instance.new("Part")
					laserPart.Name = "GunnerAimLaser"
					laserPart.Material = Enum.Material.Neon
					laserPart.Color = archConfig and archConfig.LaserColor or Color3.fromRGB(255, 35, 35)
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

							CombatVFXRemote:FireAllClients("GunnerMuzzleVFX", muzzlePos, fireDir, fireDist)

							local playerInvulnerable = pChar:GetAttribute("IsInvulnerable") == true or pChar:GetAttribute("MilesCamouflaged") == true or nearestPlayer:GetAttribute("MilesCamouflaged") == true
							if not playerInvulnerable and fireDist <= (maxStandoff + 10) then
								pHum:TakeDamage(archConfig and archConfig.Damage or 12)
							end
						end
					end

					character:SetAttribute("IsAttacking", false)
					character:SetAttribute("AttackDodged", false)
					task.wait(archConfig and archConfig.AttackCooldown or 3.2)
				end

			--------------------------------------------------------------------
			-- ??? 2. HEAVY ARMORED BRUTE AI (Bulky tank, frontal block & smash)
			--------------------------------------------------------------------
			elseif archetype == "Brute" then
				local isWebbed = character:GetAttribute("IsWebbed") == true or (character:GetAttribute("WebStacks") or 0) >= 2
				local isGuardBroken = character:GetAttribute("GuardBroken") == true
				local canBlock = not isWebbed and not isGuardBroken

				character:SetAttribute("IsBlocking", canBlock)

				local meleeRange = archConfig and archConfig.MeleeRange or 7.0
				if dist > meleeRange then
					humanoid:MoveTo(pRoot.Position)
				else
					humanoid:MoveTo(rootPart.Position)
					rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(pRoot.Position.X, rootPart.Position.Y, pRoot.Position.Z))

					character:SetAttribute("IsAttacking", true)
					character:SetAttribute("AttackDodged", false)

					local telegraphTime = archConfig and archConfig.TelegraphTime or 1.10
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
							pHum:TakeDamage(archConfig and archConfig.Damage or 20)
							CombatVFXRemote:FireAllClients("ShockwaveVFX", rootPart.Position, 8)
						end
					end

					character:SetAttribute("IsAttacking", false)
					character:SetAttribute("AttackDodged", false)
					task.wait(archConfig and archConfig.AttackCooldown or 3.6)
				end

			--------------------------------------------------------------------
			-- ?? 3. STREET BRAWLER MOB AI (Swarm flanking & rapid punches)
			--------------------------------------------------------------------
			else
				local meleeRange = archConfig and archConfig.MeleeRange or 6.0
				local surroundRad = archConfig and archConfig.SurroundRadius or 7.5

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

					local telegraphTime = archConfig and archConfig.TelegraphTime or 0.85
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
							pHum:TakeDamage(archConfig and archConfig.Damage or 8)
						end
					end

					character:SetAttribute("IsAttacking", false)
					character:SetAttribute("AttackDodged", false)
					task.wait(archConfig and archConfig.AttackCooldown or 2.8)
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- ?? PRACTICE DOJO DUMMIES
--------------------------------------------------------------------------------

local function spawnTrainingDummyAtCFrame(spawnCFrame: CFrame, dummyType: "Static" | "Aggressive" | "Infinite")
	local dummy = Instance.new("Model")
	local name = (dummyType == "Static" and "Training Dummy [Standard]")
		or (dummyType == "Aggressive" and "Practice Dummy [Attacker]")
		or "Infinite Dummy [Sandbox]"
	dummy.Name = name

	dummy:SetAttribute("Archetype", "Brawler")
	dummy:SetAttribute("IsDummy", true)
	dummy:SetAttribute("DummyType", dummyType)
	dummy:SetAttribute("IsAttacking", false)
	dummy:SetAttribute("AttackDodged", false)
	dummy:SetAttribute("IsWebbed", false)
	dummy:SetAttribute("IsPinned", false)
	dummy:SetAttribute("WebStacks", 0)

	local maxHp = dummyType == "Infinite" and 99999 or 100

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = spawnCFrame * CFrame.new(0, 3, 0)
	torso.Color = dummyType == "Infinite" and Color3.fromRGB(175, 85, 255)
		or dummyType == "Aggressive" and Color3.fromRGB(255, 90, 90)
		or Color3.fromRGB(220, 200, 150)
	torso.Material = Enum.Material.WoodPlanks
	torso.CanCollide = true
	torso.Parent = dummy

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.CFrame = torso.CFrame
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.Parent = dummy

	local rootWeld = Instance.new("WeldConstraint")
	rootWeld.Part0 = hrp
	rootWeld.Part1 = torso
	rootWeld.Parent = hrp

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Position = torso.Position + Vector3.new(0, 1.5, 0)
	head.Color = dummyType == "Infinite" and Color3.fromRGB(200, 120, 255)
		or dummyType == "Aggressive" and Color3.fromRGB(255, 120, 120)
		or Color3.fromRGB(235, 215, 170)
	head.Material = Enum.Material.WoodPlanks
	head.CanCollide = false
	head.Parent = dummy

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = maxHp
	humanoid.Health = maxHp
	humanoid.WalkSpeed = 0
	humanoid.Parent = dummy

	dummy.PrimaryPart = hrp
	CollectionService:AddTag(dummy, "Enemy")

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthGui"
	billboard.Size = UDim2.new(3.8, 0, 0.95, 0)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 45
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextStrokeTransparency = 0.15
	nameLabel.TextColor3 = dummyType == "Infinite" and Color3.fromRGB(215, 125, 255)
		or dummyType == "Aggressive" and Color3.fromRGB(255, 100, 100)
		or Color3.fromRGB(240, 220, 160)
	nameLabel.Text = string.format("?? %s", name)
	nameLabel.Parent = billboard

	local barBackground = Instance.new("Frame")
	barBackground.Size = UDim2.new(1, 0, 0.35, 0)
	barBackground.Position = UDim2.new(0, 0, 0.55, 0)
	barBackground.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = billboard

	local corner1 = Instance.new("UICorner")
	corner1.CornerRadius = UDim.new(0, 4)
	corner1.Parent = barBackground

	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = dummyType == "Infinite" and Color3.fromRGB(185, 95, 255)
		or dummyType == "Aggressive" and Color3.fromRGB(255, 80, 80)
		or Color3.fromRGB(75, 225, 120)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = barBackground

	local corner2 = Instance.new("UICorner")
	corner2.CornerRadius = UDim.new(0, 4)
	corner2.Parent = healthFill

	local totalDamageTaken = 0
	local isDead = false

	humanoid.HealthChanged:Connect(function(newHealth)
		if dummyType == "Infinite" then
			if newHealth < maxHp then
				local dmg = maxHp - newHealth
				totalDamageTaken += dmg
				nameLabel.Text = string.format("??? INFINITE DUMMY [Total DMG: %d]", totalDamageTaken)
				humanoid.Health = maxHp
			end
		else
			local healthPercent = math.clamp(newHealth / humanoid.MaxHealth, 0, 1)
			healthFill.Size = UDim2.new(healthPercent, 0, 1, 0)
		end
	end)

	if dummyType ~= "Infinite" then
		humanoid.Died:Connect(function()
			if isDead then return end
			isDead = true
			billboard:Destroy()
			task.delay(2.0, function()
				if dummy.Parent then
					dummy:Destroy()
				end
				spawnTrainingDummyAtCFrame(spawnCFrame, dummyType)
			end)
		end)
	end

	dummy.Parent = EnemiesFolder

	if dummyType == "Aggressive" then
		task.spawn(function()
			while dummy.Parent and humanoid.Health > 0 do
				task.wait(2.4)
				if not dummy.Parent or humanoid.Health <= 0 then break end
				if dummy:GetAttribute("IsWebbed") ~= true and dummy:GetAttribute("IsPinned") ~= true then
					dummy:SetAttribute("IsAttacking", true)
					dummy:SetAttribute("AttackDodged", false)

					local tStart = os.clock()
					while (os.clock() - tStart) < 0.85 do
						task.wait(0.04)
						if not dummy.Parent or humanoid.Health <= 0 then break end
						if dummy:GetAttribute("AttackDodged") == true or dummy:GetAttribute("IsWebbed") == true then break end
					end

					dummy:SetAttribute("IsAttacking", false)
					dummy:SetAttribute("AttackDodged", false)
				end
			end
		end)
	end

	return dummy
end

--------------------------------------------------------------------------------
-- ?? MAP INITIALIZATION & AMBIENT SPAWN SCANNER
--------------------------------------------------------------------------------

local function initEnemyWaves()
	if EnemiesFolder then
		for _, child in EnemiesFolder:GetChildren() do
			if child:GetAttribute("IsDummy") == true then
				child:Destroy()
			end
		end
	end

	-- Scan Workspace for custom Dummy spawn parts
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			local lowerName = string.lower(descendant.Name)
			if lowerName == "dummy_static" or lowerName == "dummystatic" or lowerName == "trainingdummy_static" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnTrainingDummyAtCFrame(descendant.CFrame, "Static")
			elseif lowerName == "dummy_attacking" or lowerName == "dummyattacking" or lowerName == "dummy_aggressive" or lowerName == "trainingdummy_attacking" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnTrainingDummyAtCFrame(descendant.CFrame, "Aggressive")
			elseif lowerName == "dummy_infinite" or lowerName == "dummyinfinite" or lowerName == "trainingdummy_infinite" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnTrainingDummyAtCFrame(descendant.CFrame, "Infinite")
			elseif lowerName == "spawn_gunner" or lowerName == "enemyspawn_gunner" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnCriminal(descendant.Position, "Gunner", "Rooftop Sniper")
			elseif lowerName == "spawn_brute" or lowerName == "enemyspawn_brute" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnCriminal(descendant.Position, "Brute", "Armored Enforcer")
			elseif lowerName == "spawn_brawler" or lowerName == "enemyspawn_brawler" or lowerName == "thugspawn" or lowerName == "enemyspawn" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnCriminal(descendant.Position, "Brawler", "Street Thug")
			end
		end
	end
end

-- ?? Inter-Script API & Bindable Hook
local spawnCriminalBindable = EnemiesFolder:FindFirstChild("SpawnCriminal")
if not spawnCriminalBindable or not spawnCriminalBindable:IsA("BindableFunction") then
	local bf = Instance.new("BindableFunction")
	bf.Name = "SpawnCriminal"
	bf.Parent = EnemiesFolder
	spawnCriminalBindable = bf
end

spawnCriminalBindable.OnInvoke = function(position: Vector3, archetype: EnemyArchetype, enemyName: string): Model
	return spawnCriminal(position, archetype, enemyName)
end

_G.SpawnCriminal = spawnCriminal

initEnemyWaves()
print("?? [EnemySpawner] Tactical Criminal AI & Avatar Template Rig System Online!")
