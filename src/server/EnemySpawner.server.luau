--!strict
--[[
	EnemySpawner.server.luau
	Phase 4.2 Tactical Enemy AI Archetypes:
	1. 🔫 Armed Gunner / Rooftop Sniper (Ranged Threat: 25-45 studs standoff, 0.9s red laser telegraph, 12 DMG)
	2. 🛡️ Armored Heavy Brute (Defensive Tank: 160 HP, bulky physique, blocks frontal punches, 1.1s smash)
	3. 🦹 Street Brawler Mob (Swarm Threat: 80 HP, dynamic angular surround slots, 0.85s punch combo)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local CombatVFXRemote = RemotesFolder:WaitForChild("CombatVFX") :: RemoteEvent

-- 📦 Enemies Folder in Workspace
local EnemiesFolder = Workspace:FindFirstChild("Enemies")
if not EnemiesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	EnemiesFolder = folder
end

export type EnemyArchetype = "Gunner" | "Brute" | "Brawler"

-- 🎨 Create clean Overhead Billboard Health Bar for Criminals
local function attachHealthBar(enemyModel: Model, enemyName: string, archetype: EnemyArchetype, maxHp: number)
	local head = enemyModel:FindFirstChild("Head") :: BasePart?
	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthGui"
	billboard.Size = UDim2.new(3.4, 0, 0.9, 0)
	billboard.StudsOffset = Vector3.new(0, archetype == "Brute" and 3.2 or 2.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 45
	billboard.Parent = head

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = billboard

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextStrokeTransparency = 0.15

	if archetype == "Gunner" then
		nameLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
		nameLabel.Text = string.format("🔫 %s [%d HP]", enemyName, maxHp)
	elseif archetype == "Brute" then
		nameLabel.TextColor3 = Color3.fromRGB(115, 210, 255)
		nameLabel.Text = string.format("🛡️ %s [%d HP]", enemyName, maxHp)
	else
		nameLabel.TextColor3 = Color3.fromRGB(255, 190, 70)
		nameLabel.Text = string.format("🥊 %s [%d HP]", enemyName, maxHp)
	end
	nameLabel.Parent = frame

	local barBackground = Instance.new("Frame")
	barBackground.Size = UDim2.new(1, 0, 0.35, 0)
	barBackground.Position = UDim2.new(0, 0, 0.55, 0)
	barBackground.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = frame

	local corner1 = Instance.new("UICorner")
	corner1.CornerRadius = UDim.new(0, 4)
	corner1.Parent = barBackground

	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = archetype == "Brute" and Color3.fromRGB(65, 175, 245) or Color3.fromRGB(235, 55, 55)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = barBackground

	local corner2 = Instance.new("UICorner")
	corner2.CornerRadius = UDim.new(0, 4)
	corner2.Parent = healthFill

	-- Listen for health & attribute changes
	humanoid.HealthChanged:Connect(function(newHealth)
		local healthPercent = math.clamp(newHealth / humanoid.MaxHealth, 0, 1)
		healthFill.Size = UDim2.new(healthPercent, 0, 1, 0)
		if newHealth <= 0 then
			billboard:Destroy()
		end
	end)

	enemyModel:GetAttributeChangedSignal("GuardBroken"):Connect(function()
		local isBroken = enemyModel:GetAttribute("GuardBroken") == true
		if archetype == "Brute" and humanoid.Health > 0 then
			if isBroken then
				nameLabel.Text = string.format("⚡ %s [GUARD BROKEN!]", enemyName)
				nameLabel.TextColor3 = Color3.fromRGB(255, 140, 40)
				healthFill.BackgroundColor3 = Color3.fromRGB(255, 160, 40)
			else
				nameLabel.Text = string.format("🛡️ %s [%d HP]", enemyName, maxHp)
				nameLabel.TextColor3 = Color3.fromRGB(115, 210, 255)
				healthFill.BackgroundColor3 = Color3.fromRGB(65, 175, 245)
			end
		end
	end)
end

-- 🔫 Build a physical Gun Model for Armed Gunners
local function createGunWeapon(): BasePart
	local gun = Instance.new("Part")
	gun.Name = "Gun"
	gun.Size = Vector3.new(0.6, 0.8, 1.8)
	gun.Color = Color3.fromRGB(35, 38, 45)
	gun.Material = Enum.Material.Metal
	gun.CanCollide = false
	gun.CastShadow = true
	return gun
end

-- 🦹 Spawn an NPC Criminal based on Tactical Archetype
local function spawnCriminal(position: Vector3, archetype: EnemyArchetype, enemyName: string)
	local character = Instance.new("Model")
	character.Name = enemyName

	local archConfig = CombatConfig.Archetypes and CombatConfig.Archetypes[archetype]
	local maxHealth = archConfig and archConfig.MaxHealth or CombatConfig.Enemies.MaxHealth
	local walkSpeed = archConfig and archConfig.WalkSpeed or 14

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = walkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = character

	local isBrute = (archetype == "Brute")
	local isGunner = (archetype == "Gunner")

	-- Torso Sizing & Coloring
	local torsoSize = isBrute and Vector3.new(2.8, 2.6, 1.6) or Vector3.new(2, 2, 1)
	local torsoColor: Color3
	if isBrute then
		torsoColor = Color3.fromRGB(48, 56, 68) -- Heavy steel armor plate
	elseif isGunner then
		torsoColor = Color3.fromRGB(38, 48, 62) -- Dark tactical navy/slate
	else
		torsoColor = Color3.fromRGB(110, 42, 42) -- Street brawler leather
	end

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = torsoSize
	torso.Position = position + Vector3.new(0, isBrute and 3.8 or 3.0, 0)
	torso.Color = torsoColor
	torso.Material = isBrute and Enum.Material.DiamondPlate or Enum.Material.SmoothPlastic
	torso.CanCollide = true
	torso.Parent = character

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = torsoSize
	rootPart.Position = torso.Position
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Parent = character

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
	head.Position = torso.Position + Vector3.new(0, isBrute and 2.0 or 1.6, 0)
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

	-- Heavy Brute: Metallic Pauldrons on Shoulders
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

	-- Gunner: Attach Gun Weapon
	if isGunner then
		local gun = createGunWeapon()
		gun.Position = rightArm.Position + Vector3.new(0, -0.9, -0.6)
		gun.Parent = character

		local gunWeld = Instance.new("Weld")
		gunWeld.Name = "GunWeld"
		gunWeld.Part0 = rightArm
		gunWeld.Part1 = gun
		gunWeld.C0 = CFrame.new(0, -0.9, -0.6)
		gunWeld.Parent = rightArm
	end

	-- 🏷️ Enemy Tags & Attributes
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
			spawnCriminal(position, archetype, enemyName)
		end)
	end)

	-- 🤖 Dynamic Archetype AI State Machine
	task.spawn(function()
		local spawnClock = os.clock()
		local swarmOffsetAngle = (math.random() * math.pi * 2)

		while character.Parent and humanoid.Health > 0 do
			task.wait(0.30)

			-- Check if immobilized by webs
			if character:GetAttribute("IsWebbed") == true or character:GetAttribute("IsPinned") == true then
				humanoid:MoveTo(rootPart.Position)
				continue
			end

			-- Find nearest player
			local nearestPlayer: Player? = nil
			local nearestDist = 65

			for _, player in Players:GetPlayers() do
				local pChar = player.Character
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
				-- Patrol back to spawn point
				if (rootPart.Position - position).Magnitude > 8 then
					humanoid:MoveTo(position)
				end
				continue
			end

			local pChar = nearestPlayer.Character
			local pRoot = pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			local pHum = pChar:FindFirstChildOfClass("Humanoid")
			if not pRoot or not pHum or pHum.Health <= 0 then continue end

			local dist = (pRoot.Position - rootPart.Position).Magnitude

			--------------------------------------------------------------------
			-- 🔫 1. ARMED GUNNER AI (25-45 studs standoff & red laser telegraph)
			--------------------------------------------------------------------
			if archetype == "Gunner" and character:GetAttribute("IsArmed") == true and character:FindFirstChild("Gun") then
				local minStandoff = archConfig and archConfig.PreferredMinDistance or 22
				local maxStandoff = archConfig and archConfig.PreferredMaxDistance or 45

				if dist < minStandoff then
					-- 🏃 Backpedal / keep distance from player
					local awayDir = (rootPart.Position - pRoot.Position).Unit
					humanoid:MoveTo(rootPart.Position + (awayDir * 12))
				elseif dist > maxStandoff then
					-- Advance into sniper range
					humanoid:MoveTo(pRoot.Position)
				else
					-- In optimal shooting range -> Aim Red Laser Telegraph
					humanoid:MoveTo(rootPart.Position)
					rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(pRoot.Position.X, rootPart.Position.Y, pRoot.Position.Z))

					character:SetAttribute("IsAttacking", true)
					character:SetAttribute("AttackDodged", false)

					local gunPart = character:FindFirstChild("Gun") :: BasePart?
					local telegraphDuration = archConfig and archConfig.TelegraphTime or 0.90
					local telegraphStart = os.clock()

					-- Create Laser Part
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

						-- Update Laser Sight Position
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

					-- Fire Gunshot
					if isTelegraphValid and character.Parent and humanoid.Health > 0 and character:GetAttribute("IsAttacking") == true and character:GetAttribute("IsArmed") == true then
						local gunPartActive = character:FindFirstChild("Gun") :: BasePart?
						if gunPartActive and pRoot then
							local muzzlePos = gunPartActive.Position + (gunPartActive.CFrame.LookVector * 1.0)
							local targetChestPos = pRoot.Position + Vector3.new(0, 0.4, 0)
							local fireDir = (targetChestPos - muzzlePos).Unit
							local fireDist = (targetChestPos - muzzlePos).Magnitude

							CombatVFXRemote:FireAllClients("GunnerMuzzleVFX", muzzlePos, fireDir, fireDist)

							local playerInvulnerable = pChar:GetAttribute("IsInvulnerable") == true
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
			-- 🛡️ 2. HEAVY ARMORED BRUTE AI (Bulky tank, frontal block & heavy smash)
			--------------------------------------------------------------------
			elseif archetype == "Brute" then
				local isWebbed = character:GetAttribute("IsWebbed") == true or (character:GetAttribute("WebStacks") or 0) >= 2
				local isGuardBroken = character:GetAttribute("GuardBroken") == true
				local canBlock = not isWebbed and not isGuardBroken

				character:SetAttribute("IsBlocking", canBlock)

				local meleeRange = archConfig and archConfig.MeleeRange or 7.0
				if dist > meleeRange then
					-- Heavy steady advance
					humanoid:MoveTo(pRoot.Position)
				else
					-- In Melee Range -> Wind up Heavy Overhead Smash
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
			-- 🦹 3. STREET BRAWLER MOB AI (Swarm flanking & rapid punches)
			--------------------------------------------------------------------
			else
				local meleeRange = archConfig and archConfig.MeleeRange or 6.0
				local surroundRad = archConfig and archConfig.SurroundRadius or 7.5

				-- Dynamic Flanking Position around player
				local orbitAngle = swarmOffsetAngle + ((os.clock() - spawnClock) * 0.4)
				local flankOffset = Vector3.new(math.cos(orbitAngle) * surroundRad, 0, math.sin(orbitAngle) * surroundRad)
				local targetMovePos = (dist > (meleeRange + 3.0)) and (pRoot.Position + flankOffset) or pRoot.Position

				if dist > meleeRange then
					humanoid:MoveTo(targetMovePos)
				else
					-- Stop and throw punch combo
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

	return character
end

-- 🥋 Phase 4.4: Spawn Training Dummies (Custom Part Placement Supported!)
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

	-- Torso
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

	-- Head
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

	-- Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = maxHp
	humanoid.Health = maxHp
	humanoid.WalkSpeed = 0
	humanoid.Parent = dummy

	dummy.PrimaryPart = hrp
	CollectionService:AddTag(dummy, "Enemy")

	-- Overhead Health & Info Tag
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
	nameLabel.Text = string.format("🥋 %s", name)
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
				nameLabel.Text = string.format("🛡️ INFINITE DUMMY [Total DMG: %d]", totalDamageTaken)
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

	-- Aggressive Dummy: Continuous telegraph loop to practice Spider-Sense dodges
	if dummyType == "Aggressive" then
		task.spawn(function()
			while dummy.Parent and humanoid.Health > 0 do
				task.wait(2.4)
				if not dummy.Parent or humanoid.Health <= 0 then break end
				if dummy:GetAttribute("IsWebbed") ~= true and dummy:GetAttribute("IsPinned") ~= true then
					dummy:SetAttribute("IsAttacking", true)
					dummy:SetAttribute("AttackDodged", false)

					-- Telegraph 0.85s (Triggers Spider-Sense warning cue on player)
					local tStart = os.clock()
					while (os.clock() - tStart) < 0.85 do
						task.wait(0.04)
						if not dummy.Parent or humanoid.Health <= 0 then break end
						if dummy:GetAttribute("AttackDodged") == true or dummy:GetAttribute("IsWebbed") == true then break end
					end

					-- Reset strike
					dummy:SetAttribute("IsAttacking", false)
					dummy:SetAttribute("AttackDodged", false)
				end
			end
		end)
	end

	return dummy
end

-- 🌆 Initialize Default City Spawn Locations & Training Dojo Dummies
local function initEnemyWaves()
	-- Clean up any preexisting dummy models
	if EnemiesFolder then
		for _, child in EnemiesFolder:GetChildren() do
			if child:GetAttribute("IsDummy") == true then
				child:Destroy()
			end
		end
	end

	-- 🔍 Check if the creator has placed custom Dummy spawn parts in Workspace!
	local placedStatic = false
	local placedAttacking = false
	local placedInfinite = false

	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			local lowerName = string.lower(descendant.Name)
			if lowerName == "dummy_static" or lowerName == "dummystatic" or lowerName == "trainingdummy_static" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnTrainingDummyAtCFrame(descendant.CFrame, "Static")
				placedStatic = true
			elseif lowerName == "dummy_attacking" or lowerName == "dummyattacking" or lowerName == "dummy_aggressive" or lowerName == "trainingdummy_attacking" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnTrainingDummyAtCFrame(descendant.CFrame, "Aggressive")
				placedAttacking = true
			elseif lowerName == "dummy_infinite" or lowerName == "dummyinfinite" or lowerName == "trainingdummy_infinite" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				spawnTrainingDummyAtCFrame(descendant.CFrame, "Infinite")
				placedInfinite = true
			end
		end
	end

	-- Fallback: If no custom parts placed yet in map, spawn default spread
	if not placedStatic then
		spawnTrainingDummyAtCFrame(CFrame.new(-12, 3, -12), "Static")
	end
	if not placedAttacking then
		spawnTrainingDummyAtCFrame(CFrame.new(0, 3, -12), "Aggressive")
	end
	if not placedInfinite then
		spawnTrainingDummyAtCFrame(CFrame.new(12, 3, -12), "Infinite")
	end

	-- 🦹 Active Tactical Criminal Waves
	local spawnPoints = {
		-- 🔫 Armed Gunners & Snipers (Ranged Threat)
		{ Pos = Vector3.new(35, 3, -40), Archetype = "Gunner" :: EnemyArchetype, Name = "Mob Gunner" },
		{ Pos = Vector3.new(-40, 3, -30), Archetype = "Gunner" :: EnemyArchetype, Name = "Rooftop Sniper" },

		-- 🛡️ Armored Heavy Brutes (Defensive / Tank Threat)
		{ Pos = Vector3.new(20, 3, -20), Archetype = "Brute" :: EnemyArchetype, Name = "Armored Enforcer" },
		{ Pos = Vector3.new(-25, 3, 25), Archetype = "Brute" :: EnemyArchetype, Name = "Heavy Titan" },

		-- 🦹 Street Brawler Mobs (Swarm Threat)
		{ Pos = Vector3.new(45, 3, -45), Archetype = "Brawler" :: EnemyArchetype, Name = "Street Thug" },
		{ Pos = Vector3.new(50, 3, 30),  Archetype = "Brawler" :: EnemyArchetype, Name = "Alley Brawler" },
		{ Pos = Vector3.new(-30, 3, 40),  Archetype = "Brawler" :: EnemyArchetype, Name = "Mob Ruffian" },
	}

	for _, pt in spawnPoints do
		spawnCriminal(pt.Pos, pt.Archetype, pt.Name)
	end
end

initEnemyWaves()
print("🥋 Training Dummies & Tactical Enemy Archetypes active! (Custom Part Spawners Supported)")
