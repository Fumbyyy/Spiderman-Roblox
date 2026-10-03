--!strict
--[[
	WebVisuals.luau
	Handles all Spider-Man web silk visual beams, hand attachments, audio effects,
	and multiplayer replication.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GrappleConfig = require(Shared:WaitForChild("GrappleConfig"))

local WebVisuals = {}

-- Stores replicated beams for other players in the game
local otherPlayersVisuals: { [Player]: { [string]: any } } = {}

-- 🖐️ Get or create an attachment on the character's hand (supports R15 and R6)
function WebVisuals.getHandAttachment(character: Model, isRight: boolean): Attachment
	local handPart: BasePart? = nil
	if isRight then
		handPart = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") or character:FindFirstChild("RightLowerArm") or character:FindFirstChild("RightUpperArm")) :: BasePart?
	else
		handPart = (character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("LeftUpperArm")) :: BasePart?
	end

	local parentPart: BasePart = handPart or (character:FindFirstChild("HumanoidRootPart") :: BasePart)
	local attName = isRight and "WebSilkAttachment_R" or "WebSilkAttachment_L"
	local existing = parentPart:FindFirstChild(attName) :: Attachment?
	if existing then
		return existing
	end

	local newAtt = Instance.new("Attachment")
	newAtt.Name = attName
	newAtt.Position = Vector3.new(0, -0.2, 0)
	newAtt.Parent = parentPart
	return newAtt
end

-- ✨ Create a glowing white Spider-Man web silk beam between two attachments
function WebVisuals.createWebBeam(att0: Attachment, att1: Attachment, parent: Instance, casterChar: Model?): Beam
	local beam = Instance.new("Beam")
	beam.Name = "SpiderWebBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1

	-- Resolve the true caster character cleanly without suit bleeding
	local resolvedChar = casterChar
	if not resolvedChar then
		local p0 = att0.Parent
		if p0 and p0:IsA("BasePart") and p0.Parent and p0.Parent:IsA("Model") and p0.Parent:FindFirstChildOfClass("Humanoid") then
			resolvedChar = p0.Parent
		elseif parent and parent:IsA("BasePart") and parent.Parent and parent.Parent:IsA("Model") and parent.Parent:FindFirstChildOfClass("Humanoid") then
			resolvedChar = parent.Parent
		else
			resolvedChar = LocalPlayer and LocalPlayer.Character or nil
		end
	end

	local casterPlayer = if resolvedChar then Players:GetPlayerFromCharacter(resolvedChar) else nil
	local suitId = (resolvedChar and resolvedChar:GetAttribute("EquippedSuit"))
		or (casterPlayer and casterPlayer:GetAttribute("EquippedSuit"))

	if not suitId and LocalPlayer and (resolvedChar == LocalPlayer.Character or casterPlayer == LocalPlayer) then
		suitId = LocalPlayer:GetAttribute("EquippedSuit")
	end

	local is2099 = (suitId == "Cyber2099")
	local isSymbiote = (suitId == "SymbioteBlack")

	if is2099 then
		beam.Width0 = 0.14
		beam.Width1 = 0.14
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 45, 80))
		beam.LightEmission = 0.9
		beam.Transparency = NumberSequence.new(0.04)
	elseif isSymbiote then
		beam.Width0 = 0.16
		beam.Width1 = 0.16
		beam.Color = ColorSequence.new(Color3.fromRGB(20, 20, 25))
		beam.LightEmission = 0.05
		beam.Transparency = NumberSequence.new(0.04)
	else
		beam.Width0 = 0.16
		beam.Width1 = 0.16
		beam.Color = ColorSequence.new(GrappleConfig.Visuals.RopeColor)
		beam.LightEmission = 0.35
		beam.Transparency = NumberSequence.new(0.04)
	end

	beam.FaceCamera = true
	beam.Parent = parent
	return beam
end

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

-- 🔊 Play the classic web-shooter "thwip" sound
function WebVisuals.playWebSound(_originPart: BasePart?)
	-- Zero SFX Policy: Silent visual-only web firing
	return
end

-- 💥 Create a dynamic web impact splatter effect at hit location
function WebVisuals.createImpactSplatVFX(impactPos: Vector3, normal: Vector3?)
	local splatCount = 4
	local baseNormal = normal or Vector3.new(0, 1, 0)

	for i = 1, splatCount do
		local strand = Instance.new("Part")
		strand.Name = "WebImpactStrand"
		strand.Material = Enum.Material.Neon
		strand.Color = Color3.fromRGB(245, 248, 255)
		strand.Transparency = 0.2
		strand.CanCollide = false
		strand.Anchored = true

		local spread = Vector3.new(
			(math.random() - 0.5) * 1.8,
			(math.random() - 0.5) * 1.8,
			(math.random() - 0.5) * 1.8
		)
		local endPos = impactPos + spread
		local dist = (endPos - impactPos).Magnitude

		strand.Size = Vector3.new(0.08, 0.08, math.max(0.3, dist))
		strand.CFrame = CFrame.lookAt((impactPos + endPos) / 2, endPos)
		strand.Parent = Workspace

		local tween = TweenService:Create(strand, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.02, 0.02, dist * 1.1),
		})
		tween:Play()
		Debris:AddItem(strand, 0.38)
	end
end

-- 🚀 High-speed Web-Pellet Projectile (with trailing web silk)
function WebVisuals.launchWebPelletProjectile(startAtt: Attachment, targetWorldPos: Vector3, callback: (() -> ())?)
	local startPos = startAtt.WorldPosition
	local toTarget = targetWorldPos - startPos
	local distance = toTarget.Magnitude
	local speed = 220 -- Studs per second
	local flightTime = math.clamp(distance / speed, 0.04, 0.22)

	-- Projectile Core Pellet
	local pellet = Instance.new("Part")
	pellet.Name = "WebPelletProjectile"
	pellet.Shape = Enum.PartType.Ball
	pellet.Size = Vector3.new(0.45, 0.45, 0.45)
	pellet.Material = Enum.Material.Neon
	local isSymbiotePellet = (LocalPlayer and LocalPlayer:GetAttribute("EquippedSuit") == "SymbioteBlack")
		or (LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:GetAttribute("EquippedSuit") == "SymbioteBlack")
	if isSymbiotePellet then
		pellet.Color = Color3.fromRGB(20, 20, 25)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(45, 25, 60)
		glow.Brightness = 3.2
		glow.Range = 6
		glow.Parent = pellet
	else
		pellet.Color = Color3.fromRGB(255, 255, 255)
	end
	pellet.CanCollide = false
	pellet.Anchored = true
	pellet.CFrame = CFrame.new(startPos)
	pellet.Parent = Workspace

	-- Trailing Silk Beam behind the projectile
	local pelletAtt = Instance.new("Attachment")
	pelletAtt.Parent = pellet

	local trailBeam = WebVisuals.createWebBeam(startAtt, pelletAtt, pellet)
	trailBeam.Width0 = 0.12
	trailBeam.Width1 = 0.18
	trailBeam.Transparency = NumberSequence.new(0.1, 0.7)

	local tween = TweenService:Create(pellet, TweenInfo.new(flightTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(targetWorldPos),
	})

	tween:Play()
	tween.Completed:Connect(function()
		pellet:Destroy()
		WebVisuals.createImpactSplatVFX(targetWorldPos)
		if callback then
			callback()
		end
	end)
end

-- 🕸️ Progressive Webbing Strands on Enemy (Stack 1 & 2)
function WebVisuals.applyProgressiveWebs(targetModel: Model, stack: number)
	local root = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
	if not root then return end

	-- Clean up previous strands if at stack 1
	if stack == 1 then
		WebVisuals.clearProgressiveWebs(targetModel)
	end

	local strandCount = (stack == 1) and 3 or 6
	for i = 1, strandCount do
		local strand = Instance.new("Part")
		strand.Name = "ProgressiveWebStrand"
		strand.Material = Enum.Material.Neon
		strand.Color = Color3.fromRGB(240, 245, 255)
		strand.Transparency = 0.25
		strand.CanCollide = false
		strand.Massless = true
		strand.Parent = targetModel

		local offsetA = Vector3.new(math.random(-12, 12) * 0.1, math.random(-15, 15) * 0.1, math.random(-8, 8) * 0.1)
		local offsetB = Vector3.new(math.random(-12, 12) * 0.1, math.random(-15, 15) * 0.1, math.random(-8, 8) * 0.1)
		local posA = root.Position + offsetA
		local posB = root.Position + offsetB
		local length = (posB - posA).Magnitude

		strand.Size = Vector3.new(0.1, 0.1, math.max(0.4, length))
		strand.CFrame = CFrame.lookAt((posA + posB) / 2, posB)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = strand
		weld.Parent = strand

		Debris:AddItem(strand, 8.0)
	end
end

-- 🧹 Clear Progressive Web Strands
function WebVisuals.clearProgressiveWebs(targetModel: Model)
	for _, child in targetModel:GetChildren() do
		if child.Name == "ProgressiveWebStrand" then
			child:Destroy()
		end
	end
end

-- 🔫 Create dual high-tension web tethers connecting player hands to snatched weapon
function WebVisuals.createDisarmWebTether(playerChar: Model, weaponPart: BasePart, duration: number)
	local leftAtt = WebVisuals.getHandAttachment(playerChar, false)
	local rightAtt = WebVisuals.getHandAttachment(playerChar, true)

	local weaponAtt = Instance.new("Attachment")
	weaponAtt.Name = "DisarmWeaponAtt"
	weaponAtt.Parent = weaponPart

	local beamL = WebVisuals.createWebBeam(leftAtt, weaponAtt, weaponPart, playerChar)
	local beamR = WebVisuals.createWebBeam(rightAtt, weaponAtt, weaponPart, playerChar)

	task.delay(duration, function()
		if beamL then beamL:Destroy() end
		if beamR then beamR:Destroy() end
		if weaponAtt then weaponAtt:Destroy() end
	end)
end

-- 🥊 Create Melee Hit Sparks and Comic-Book Impact Shards
function WebVisuals.createMeleeHitSparks(hitPos: Vector3, isHeavy: boolean)
	local flash = Instance.new("Part")
	flash.Name = "MeleeHitFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.4, 0.4, 0.4)
	flash.Position = hitPos
	flash.Color = isHeavy and Color3.fromRGB(255, 220, 100) or Color3.fromRGB(255, 255, 255)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.1
	flash.CanCollide = false
	flash.Anchored = true
	flash.Parent = Workspace

	local targetSize = isHeavy and Vector3.new(3.2, 3.2, 3.2) or Vector3.new(1.8, 1.8, 1.8)
	local tween = TweenService:Create(flash, TweenInfo.new(isHeavy and 0.20 or 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = targetSize,
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(flash, 0.22)

	local shardCount = isHeavy and 5 or 3
	for _ = 1, shardCount do
		local shard = Instance.new("Part")
		shard.Name = "HitSparkShard"
		shard.Size = Vector3.new(0.08, 0.08, isHeavy and 0.9 or 0.5)
		shard.Material = Enum.Material.Neon
		shard.Color = Color3.fromRGB(255, 240, 160)
		shard.CanCollide = false
		shard.Anchored = true

		local dir = Vector3.new((math.random() - 0.5) * 2, (math.random() - 0.5) * 2, (math.random() - 0.5) * 2).Unit
		local startP = hitPos + (dir * 0.2)
		local endP = hitPos + (dir * (isHeavy and 2.4 or 1.4))

		shard.CFrame = CFrame.lookAt((startP + endP) / 2, endP)
		shard.Parent = Workspace

		local sTween = TweenService:Create(shard, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.02, 0.02, 0.2),
		})
		sTween:Play()
		Debris:AddItem(shard, 0.20)
	end
end

-- 🛡️ Create Metallic Clang Deflection Sparks when Heavy Brute blocks frontal punches
function WebVisuals.createBruteBlockSparks(hitPos: Vector3, blockNormal: Vector3)
	-- 1. Shield Hexagon / Disc Deflection Pulse
	local shieldPulse = Instance.new("Part")
	shieldPulse.Name = "BruteBlockShield"
	shieldPulse.Shape = Enum.PartType.Cylinder
	shieldPulse.Size = Vector3.new(0.15, 2.5, 2.5)
	shieldPulse.CFrame = CFrame.lookAt(hitPos, hitPos + blockNormal) * CFrame.Angles(0, math.rad(90), 0)
	shieldPulse.Color = Color3.fromRGB(120, 205, 255)
	shieldPulse.Material = Enum.Material.Neon
	shieldPulse.Transparency = 0.20
	shieldPulse.CanCollide = false
	shieldPulse.Anchored = true
	shieldPulse.Parent = Workspace

	local pulseTween = TweenService:Create(shieldPulse, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 4.8, 4.8),
		Transparency = 1,
	})
	pulseTween:Play()
	Debris:AddItem(shieldPulse, 0.26)

	-- 2. Metallic Ricochet Sparks
	for _ = 1, 6 do
		local spark = Instance.new("Part")
		spark.Name = "MetalClangSpark"
		spark.Size = Vector3.new(0.08, 0.08, 0.7)
		spark.Color = Color3.fromRGB(255, 220, 110)
		spark.Material = Enum.Material.Neon
		spark.CanCollide = false
		spark.Anchored = true

		local randDir = (blockNormal + Vector3.new((math.random() - 0.5) * 1.5, (math.random() - 0.5) * 1.5, (math.random() - 0.5) * 1.5)).Unit
		local startP = hitPos + (randDir * 0.2)
		local endP = hitPos + (randDir * 2.2)

		spark.CFrame = CFrame.lookAt((startP + endP) / 2, endP)
		spark.Parent = Workspace

		local sTween = TweenService:Create(spark, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.02, 0.02, 0.1),
		})
		sTween:Play()
		Debris:AddItem(spark, 0.22)
	end
end

-- 💥 Create Shattering Guard-Break Sparks when Web-Strike breaks Brute's stance
function WebVisuals.createGuardBreakBurst(hitPos: Vector3)
	local shockRing = Instance.new("Part")
	shockRing.Name = "GuardBreakRing"
	shockRing.Shape = Enum.PartType.Cylinder
	shockRing.Size = Vector3.new(0.2, 1.5, 1.5)
	shockRing.CFrame = CFrame.new(hitPos) * CFrame.Angles(0, 0, math.rad(90))
	shockRing.Color = Color3.fromRGB(255, 185, 45)
	shockRing.Material = Enum.Material.Neon
	shockRing.Transparency = 0.1
	shockRing.CanCollide = false
	shockRing.Anchored = true
	shockRing.Parent = Workspace

	local ringTween = TweenService:Create(shockRing, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 8.0, 8.0),
		Transparency = 1,
	})
	ringTween:Play()
	Debris:AddItem(shockRing, 0.35)

	-- Shattering crystalline armor fragments
	for _ = 1, 8 do
		local frag = Instance.new("Part")
		frag.Name = "ArmorShard"
		frag.Size = Vector3.new(0.25, 0.25, 0.25)
		frag.Position = hitPos + Vector3.new((math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.5)
		frag.Color = Color3.fromRGB(255, 205, 80)
		frag.Material = Enum.Material.Glass
		frag.CanCollide = false
		frag.Anchored = false
		frag.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 28, math.random(8, 22), (math.random() - 0.5) * 28)
		frag.AssemblyAngularVelocity = Vector3.new(math.random(-30, 30), math.random(-30, 30), math.random(-30, 30))
		frag.Parent = Workspace

		task.delay(0.35, function()
			if frag.Parent then
				local fTween = TweenService:Create(frag, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
					Size = Vector3.zero,
				})
				fTween:Play()
				fTween.Completed:Connect(function()
					frag:Destroy()
				end)
			end
		end)
		Debris:AddItem(frag, 0.9)
	end
end

-- 🔫 Gunner Muzzle Flash and Supersonic Tracer Beam
function WebVisuals.createGunnerMuzzleFlash(muzzlePos: Vector3, fireDir: Vector3, tracerLength: number?)
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.7, 0.7, 0.7)
	flash.Position = muzzlePos
	flash.Color = Color3.fromRGB(255, 215, 80)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.05
	flash.CanCollide = false
	flash.Anchored = true
	flash.Parent = Workspace

	local fTween = TweenService:Create(flash, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1.8, 1.8, 1.8),
		Transparency = 1,
	})
	fTween:Play()
	Debris:AddItem(flash, 0.12)

	-- Bullet Tracer Line
	local length = tracerLength or 40
	local tracer = Instance.new("Part")
	tracer.Name = "BulletTracer"
	tracer.Size = Vector3.new(0.08, 0.08, length)
	tracer.Color = Color3.fromRGB(255, 230, 140)
	tracer.Material = Enum.Material.Neon
	tracer.Transparency = 0.15
	tracer.CanCollide = false
	tracer.Anchored = true
	tracer.CFrame = CFrame.lookAt(muzzlePos + (fireDir.Unit * (length / 2)), muzzlePos + (fireDir.Unit * length))
	tracer.Parent = Workspace

	local tTween = TweenService:Create(tracer, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.02, 0.02, length * 1.1),
	})
	tTween:Play()
	Debris:AddItem(tracer, 0.15)
end

-- 💥 Create sparks, metal debris fragments, and web splatter when a thrown weapon strikes an enemy
function WebVisuals.createWeaponImpactSparks(hitPos: Vector3, hitNormal: Vector3)
	-- 1. Expanding neon flash
	local sparkPart = Instance.new("Part")
	sparkPart.Name = "WeaponImpactSparks"
	sparkPart.Shape = Enum.PartType.Ball
	sparkPart.Size = Vector3.new(0.6, 0.6, 0.6)
	sparkPart.Position = hitPos
	sparkPart.Color = Color3.fromRGB(255, 205, 75)
	sparkPart.Material = Enum.Material.Neon
	sparkPart.Transparency = 0.15
	sparkPart.CanCollide = false
	sparkPart.Anchored = true
	sparkPart.Parent = Workspace

	local tween = TweenService:Create(sparkPart, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(4.2, 4.2, 4.2),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(sparkPart, 0.25)

	-- 2. Physical Metal Debris Fragments bursting outward
	for _ = 1, 5 do
		local frag = Instance.new("Part")
		frag.Name = "MetalDebris"
		frag.Size = Vector3.new(0.35, 0.35, 0.35)
		frag.Position = hitPos + Vector3.new(math.random(-5, 5) * 0.1, math.random(-5, 5) * 0.1, math.random(-5, 5) * 0.1)
		frag.Color = Color3.fromRGB(55, 60, 70)
		frag.Material = Enum.Material.Metal
		frag.CanCollide = false
		frag.Anchored = false
		frag.AssemblyLinearVelocity = (hitNormal * 12) + Vector3.new(math.random(-14, 14), math.random(6, 18), math.random(-14, 14))
		frag.AssemblyAngularVelocity = Vector3.new(math.random(-25, 25), math.random(-25, 25), math.random(-25, 25))
		frag.Parent = Workspace

		task.delay(0.45, function()
			if frag.Parent then
				local fadeTween = TweenService:Create(frag, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
					Size = Vector3.zero,
				})
				fadeTween:Play()
				fadeTween.Completed:Connect(function()
					frag:Destroy()
				end)
			end
		end)
		Debris:AddItem(frag, 1.2)
	end

	WebVisuals.createImpactSplatVFX(hitPos, hitNormal)
end

-- ⚡ Create Spider-Sense jagged lightning warning sparks above character head
function WebVisuals.createSpiderSenseSparks(playerChar: Model, isDanger: boolean)
	local head = playerChar:FindFirstChild("Head") or playerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head then return end

	local existing = head:FindFirstChild("SpiderSenseSparks")
	if existing then existing:Destroy() end

	local sparkFolder = Instance.new("Folder")
	sparkFolder.Name = "SpiderSenseSparks"
	sparkFolder.Parent = head
	Debris:AddItem(sparkFolder, 0.40)

	local color = isDanger and Color3.fromRGB(255, 45, 45) or Color3.fromRGB(245, 248, 255)
	local angles = { -35, 0, 35 }

	for _, angle in angles do
		local spark = Instance.new("Part")
		spark.Name = "SenseArc"
		spark.Material = Enum.Material.Neon
		spark.Color = color
		spark.Transparency = 0.05
		spark.CanCollide = false
		spark.Massless = true
		spark.Anchored = false
		spark.Size = Vector3.new(0.08, isDanger and 1.3 or 0.9, 0.08)
		spark.CFrame = head.CFrame * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(angle)) * CFrame.new(0, 0.5, 0)
		spark.Parent = sparkFolder

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = spark
		weld.Parent = spark

		local tween = TweenService:Create(spark, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.02, 0.2, 0.02),
		})
		tween:Play()
	end
end

-- 💥 ZZZ-Style Counter Impact Radial Shockwave
function WebVisuals.createCounterImpactShockwave(hitPos: Vector3, radius: number)
	local shockRing = Instance.new("Part")
	shockRing.Name = "CounterShockRing"
	shockRing.Shape = Enum.PartType.Cylinder
	shockRing.Size = Vector3.new(0.3, 2, 2)
	shockRing.CFrame = CFrame.new(hitPos) * CFrame.Angles(0, 0, math.rad(90))
	shockRing.Color = Color3.fromRGB(255, 240, 120)
	shockRing.Material = Enum.Material.Neon
	shockRing.Transparency = 0.15
	shockRing.CanCollide = false
	shockRing.Anchored = true
	shockRing.Parent = Workspace

	local targetSize = radius and (radius * 2) or 24
	local tween = TweenService:Create(shockRing, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, targetSize, targetSize),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(shockRing, 0.35)
end

-- 🍃 Looping Wind Rush Sound
local windLoopSound: Sound? = nil

function WebVisuals.updateWindSound(_rootPart: BasePart?, _speed: number)
	-- Zero SFX Policy: Silent visual-only swinging
	if windLoopSound then
		windLoopSound:Stop()
		windLoopSound:Destroy()
		windLoopSound = nil
	end
	return
end

-- Multiplayer Replication Listener
function WebVisuals.initMultiplayerReplication(remotesFolder: Folder)
	local GrappleStartRemote = remotesFolder:WaitForChild("GrappleStart") :: RemoteEvent
	local GrappleEndRemote = remotesFolder:WaitForChild("GrappleEnd") :: RemoteEvent

	GrappleStartRemote.OnClientEvent:Connect(function(otherPlayer: Player, anchorPos: Vector3, isRight: boolean)
		if otherPlayer == LocalPlayer or not otherPlayer.Character then return end

		local otherChar = otherPlayer.Character
		local otherRoot = otherChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not otherRoot then return end

		local key = isRight and "Right" or "Left"
		if not otherPlayersVisuals[otherPlayer] then
			otherPlayersVisuals[otherPlayer] = {}
		end

		if otherPlayersVisuals[otherPlayer][key] then
			otherPlayersVisuals[otherPlayer][key].Beam:Destroy()
			otherPlayersVisuals[otherPlayer][key].Att0:Destroy()
			otherPlayersVisuals[otherPlayer][key].Att1:Destroy()
			otherPlayersVisuals[otherPlayer][key] = nil
		end

		local worldAtt = Instance.new("Attachment")
		worldAtt.WorldPosition = anchorPos
		worldAtt.Parent = Workspace.Terrain

		local playerAtt = WebVisuals.getHandAttachment(otherChar, isRight)
		local beam = WebVisuals.createWebBeam(playerAtt, worldAtt, otherRoot, otherChar)

		WebVisuals.playWebSound(otherRoot)

		otherPlayersVisuals[otherPlayer][key] = {
			Beam = beam,
			Att0 = playerAtt,
			Att1 = worldAtt,
		}
	end)

	GrappleEndRemote.OnClientEvent:Connect(function(otherPlayer: Player)
		if otherPlayersVisuals[otherPlayer] then
			for _, data in otherPlayersVisuals[otherPlayer] do
				if data.Beam then data.Beam:Destroy() end
				if data.Att0 then data.Att0:Destroy() end
				if data.Att1 then data.Att1:Destroy() end
			end
			otherPlayersVisuals[otherPlayer] = nil
		end
	end)
end


-- ⚡ Stark Tech Apex Repulsor Jet Thrusters (True Plasma Jet Particles) & Waldo Repulsor Shockwave
type StarkThrusterState = {
	character: Model,
	upperTorso: BasePart,
	attL: Attachment,
	attR: Attachment,
	emitterL: ParticleEmitter,
	emitterR: ParticleEmitter,
	active: boolean,
}

local currentStarkThruster: StarkThrusterState? = nil

local function getOrCreateThrusterEmitter(att: Attachment): ParticleEmitter
	local existing = att:FindFirstChild("StarkPlasmaJet") :: ParticleEmitter?
	if existing then return existing end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "StarkPlasmaJet"
	emitter.Color = ColorSequence.new(Color3.fromRGB(50, 220, 255))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.Speed = NumberRange.new(18, 30)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.65, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.08, 0.16)
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = att
	return emitter
end

function WebVisuals.cleanupStarkThrusters(immediate: boolean?)
	if not currentStarkThruster then return end
	local state = currentStarkThruster

	state.emitterL.Rate = 0
	state.emitterL.Enabled = false
	state.emitterR.Rate = 0
	state.emitterR.Enabled = false
	state.active = false

	if immediate then
		currentStarkThruster = nil
		if state.attL and state.attL.Parent then state.attL:Destroy() end
		if state.attR and state.attR.Parent then state.attR:Destroy() end
	end
end

function WebVisuals.activateStarkThrusters(character: Model, upperTorso: BasePart, speed: number)
	if not currentStarkThruster or currentStarkThruster.character ~= character or currentStarkThruster.upperTorso ~= upperTorso then
		if currentStarkThruster then
			WebVisuals.cleanupStarkThrusters(true)
		end

		-- Clean up any lingering physical 3D cylinders if present
		local oldL = character:FindFirstChild("StarkThruster_L")
		if oldL then oldL:Destroy() end
		local oldR = character:FindFirstChild("StarkThruster_R")
		if oldR then oldR:Destroy() end

		-- Attach two small Attachments to the back of UpperTorso offset at (-0.6, 0.4, 0.75) and (0.6, 0.4, 0.75)
		local attL = upperTorso:FindFirstChild("ThrusterAtt_L") :: Attachment?
		if not attL then
			attL = Instance.new("Attachment")
			attL.Name = "ThrusterAtt_L"
			attL.CFrame = CFrame.new(-0.6, 0.4, 0.75)
			attL.Parent = upperTorso
		end

		local attR = upperTorso:FindFirstChild("ThrusterAtt_R") :: Attachment?
		if not attR then
			attR = Instance.new("Attachment")
			attR.Name = "ThrusterAtt_R"
			attR.CFrame = CFrame.new(0.6, 0.4, 0.75)
			attR.Parent = upperTorso
		end

		local emL = getOrCreateThrusterEmitter(attL)
		local emR = getOrCreateThrusterEmitter(attR)

		currentStarkThruster = {
			character = character,
			upperTorso = upperTorso,
			attL = attL,
			attR = attR,
			emitterL = emL,
			emitterR = emR,
			active = true,
		}
	end

	local state = currentStarkThruster
	if state then
		state.active = true
		state.emitterL.Rate = 45
		state.emitterL.Enabled = true
		state.emitterR.Rate = 45
		state.emitterR.Enabled = true

		local dynMin = math.clamp(18 + (speed - 80) * 0.12, 18, 35)
		local dynMax = math.clamp(30 + (speed - 80) * 0.18, 30, 52)
		state.emitterL.Speed = NumberRange.new(dynMin, dynMax)
		state.emitterR.Speed = NumberRange.new(dynMin, dynMax)
	end
end

-- ? Stark Tech Waldo Repulsor Shockwave Pulse (Expanding Cyan Ring from 2 to 14 studs in 0.25s)
function WebVisuals.createWaldoRepulsorShockwave(originPos: Vector3, maxRadius: number?)
	local targetRadius = maxRadius or 14
	local themeCyan = Color3.fromRGB(60, 220, 255)

	-- 1. Outer Shockwave Ring
	local ring = Instance.new("Part")
	ring.Name = "StarkRepulsorRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.35, 2, 2)
	ring.CFrame = CFrame.new(originPos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = themeCyan
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.15
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Anchored = true
	ring.Parent = Workspace

	local ringTween = TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, targetRadius * 2, targetRadius * 2),
		Transparency = 1,
	})
	ringTween:Play()
	ringTween.Completed:Connect(function()
		ring:Destroy()
	end)
	Debris:AddItem(ring, 0.35)

	-- 2. Concussive Center Core Sphere
	local core = Instance.new("Part")
	core.Name = "StarkRepulsorCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(1.8, 1.8, 1.8)
	core.CFrame = CFrame.new(originPos)
	core.Color = Color3.fromRGB(210, 245, 255)
	core.Material = Enum.Material.Neon
	core.Transparency = 0.1
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.Anchored = true
	core.Parent = Workspace

	local coreTween = TweenService:Create(core, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(targetRadius * 1.2, targetRadius * 1.2, targetRadius * 1.2),
		Transparency = 1,
	})
	coreTween:Play()
	coreTween.Completed:Connect(function()
		core:Destroy()
	end)
	Debris:AddItem(core, 0.30)

	-- 3. Dynamic Repulsor Light Flash
	local lightPart = Instance.new("Part")
	lightPart.Size = Vector3.new(0.1, 0.1, 0.1)
	lightPart.CFrame = CFrame.new(originPos)
	lightPart.Transparency = 1
	lightPart.CanCollide = false
	lightPart.CanTouch = false
	lightPart.CanQuery = false
	lightPart.Anchored = true
	lightPart.Parent = Workspace

	local pl = Instance.new("PointLight")
	pl.Color = themeCyan
	pl.Range = 22
	pl.Brightness = 6
	pl.Parent = lightPart

	local lightTween = TweenService:Create(pl, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Range = 32,
		Brightness = 0,
	})
	lightTween:Play()
	lightTween.Completed:Connect(function()
		lightPart:Destroy()
	end)
	Debris:AddItem(lightPart, 0.35)
end

--------------------------------------------------------------------------------
-- ⚡ MILES MORALES (SPIDER-VERSE): BIO-ELECTRIC VENOM & CAMOUFLAGE VFX
--------------------------------------------------------------------------------

-- 1. Branching electric sparks on punches
function WebVisuals.createVenomFistSparks(fistPart: BasePart)
	local att = Instance.new("Attachment")
	att.Parent = fistPart

	local em = Instance.new("ParticleEmitter")
	em.Name = "VenomPunchSparks"
	em.Color = ColorSequence.new(Color3.fromRGB(255, 230, 60))
	em.LightEmission = 1
	em.LightInfluence = 0
	em.Speed = NumberRange.new(6, 15)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.40),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Lifetime = NumberRange.new(0.08, 0.16)
	em.Rate = 0
	em.Parent = att

	em:Emit(8)
	Debris:AddItem(att, 0.22)
end

-- 2. 12-stud Bio-Electric Venom Blast Shockwave (Combo 3 Finisher)
function WebVisuals.createVenomBlastShockwave(originPos: Vector3, maxRadius: number?)
	local targetRadius = maxRadius or 12
	local yellowElectric = Color3.fromRGB(255, 230, 60)

	-- Expanding Yellow Shockwave Ring
	local ring = Instance.new("Part")
	ring.Name = "VenomShockwaveRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.35, 2, 2)
	ring.CFrame = CFrame.new(originPos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = yellowElectric
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.12
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Anchored = true
	ring.Parent = Workspace

	local ringTween = TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, targetRadius * 2, targetRadius * 2),
		Transparency = 1,
	})
	ringTween:Play()
	ringTween.Completed:Connect(function()
		ring:Destroy()
	end)
	Debris:AddItem(ring, 0.32)

	-- Center Core Sphere
	local core = Instance.new("Part")
	core.Name = "VenomCoreBurst"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(2, 2, 2)
	core.CFrame = CFrame.new(originPos)
	core.Color = Color3.fromRGB(255, 250, 180)
	core.Material = Enum.Material.Neon
	core.Transparency = 0.1
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.Anchored = true
	core.Parent = Workspace

	local coreTween = TweenService:Create(core, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(targetRadius * 1.1, targetRadius * 1.1, targetRadius * 1.1),
		Transparency = 1,
	})
	coreTween:Play()
	coreTween.Completed:Connect(function()
		core:Destroy()
	end)
	Debris:AddItem(core, 0.28)

	-- 16 Bright Yellow Electric Sparks Outward
	local sparkPart = Instance.new("Part")
	sparkPart.Size = Vector3.new(0.1, 0.1, 0.1)
	sparkPart.CFrame = CFrame.new(originPos)
	sparkPart.Transparency = 1
	sparkPart.CanCollide = false
	sparkPart.CanTouch = false
	sparkPart.CanQuery = false
	sparkPart.Anchored = true
	sparkPart.Parent = Workspace

	local att = Instance.new("Attachment")
	att.Parent = sparkPart

	local em = Instance.new("ParticleEmitter")
	em.Name = "VenomRadialSparks"
	em.Color = ColorSequence.new(yellowElectric)
	em.LightEmission = 1
	em.LightInfluence = 0
	em.Speed = NumberRange.new(22, 38)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.60),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Lifetime = NumberRange.new(0.12, 0.24)
	em.Rate = 0
	em.Parent = att

	em:Emit(16)

	-- Dynamic Light Flash
	local pl = Instance.new("PointLight")
	pl.Color = yellowElectric
	pl.Range = 26
	pl.Brightness = 7
	pl.Parent = sparkPart

	TweenService:Create(pl, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Range = 36,
		Brightness = 0,
	}):Play()

	Debris:AddItem(sparkPart, 0.35)
end

-- 3. Paralyzing Venom Stun VFX (Lightning Arcs on Enemy Torso)
function WebVisuals.applyVenomStunVFX(enemyModel: Model, duration: number?)
	local stunTime = duration or 2.0
	local enemyRoot = (enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:FindFirstChild("Torso")) :: BasePart?
	if not enemyRoot then return end

	local stunFolder = Instance.new("Folder")
	stunFolder.Name = "VenomStunEffects"
	stunFolder.Parent = enemyRoot

	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 230, 60)
	pl.Range = 14
	pl.Brightness = 3.5
	pl.Parent = stunFolder

	local em = Instance.new("ParticleEmitter")
	em.Name = "VenomStunSparks"
	em.Color = ColorSequence.new(Color3.fromRGB(255, 230, 60))
	em.LightEmission = 1
	em.LightInfluence = 0
	em.Speed = NumberRange.new(3, 9)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Lifetime = NumberRange.new(0.1, 0.22)
	em.Rate = 32
	em.Parent = enemyRoot

	local head = enemyModel:FindFirstChild("Head") :: BasePart?

	-- ⚡ Overhead Enemy Stun Billboard (⚡ STUNNED)
	local tagAdornee = head or enemyRoot
	local stunBillboard = Instance.new("BillboardGui")
	stunBillboard.Name = "VenomStunBillboard"
	stunBillboard.Adornee = tagAdornee
	stunBillboard.Size = UDim2.new(0, 140, 0, 32)
	stunBillboard.StudsOffset = Vector3.new(0, if head then 2.6 else 3.4, 0)
	stunBillboard.AlwaysOnTop = true
	stunBillboard.ResetOnSpawn = false
	stunBillboard.Parent = stunFolder

	local stunLabel = Instance.new("TextLabel")
	stunLabel.Name = "StunText"
	stunLabel.Size = UDim2.new(1, 0, 1, 0)
	stunLabel.BackgroundTransparency = 1
	stunLabel.Font = Enum.Font.GothamBlack
	stunLabel.Text = "⚡ STUNNED"
	stunLabel.TextColor3 = Color3.fromRGB(255, 235, 70)
	stunLabel.TextSize = 16
	stunLabel.TextStrokeTransparency = 0.15
	stunLabel.TextStrokeColor3 = Color3.fromRGB(25, 20, 5)
	stunLabel.Parent = stunBillboard

	local pulseTween = TweenService:Create(stunLabel, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextColor3 = Color3.fromRGB(255, 255, 180),
		TextSize = 17,
	})
	pulseTween:Play()

	-- Yellow lightning beam arcs across enemy's torso
	if head then
		local att0 = Instance.new("Attachment")
		att0.Parent = head
		att0.Position = Vector3.new(0, -0.3, 0)

		local att1 = Instance.new("Attachment")
		att1.Parent = enemyRoot
		att1.Position = Vector3.new(0, -0.5, 0)

		local beam = Instance.new("Beam")
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 240, 80))
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = 0.35
		beam.Width1 = 0.15
		beam.Attachment0 = att0
		beam.Attachment1 = att1
		beam.Segments = 8
		beam.CurveSize0 = 1.2
		beam.CurveSize1 = -1.2
		beam.Parent = stunFolder

		local beam2 = Instance.new("Beam")
		beam2.Color = ColorSequence.new(Color3.fromRGB(255, 215, 50))
		beam2.LightEmission = 1
		beam2.LightInfluence = 0
		beam2.Width0 = 0.25
		beam2.Width1 = 0.2
		beam2.Attachment0 = att0
		beam2.Attachment1 = att1
		beam2.Segments = 8
		beam2.CurveSize0 = -1.2
		beam2.CurveSize1 = 1.2
		beam2.Parent = stunFolder

		Debris:AddItem(att0, stunTime)
		Debris:AddItem(att1, stunTime)
	end

	task.delay(stunTime, function()
		if em and em.Parent then em.Rate = 0 em.Enabled = false end
		task.delay(0.25, function()
			if stunFolder and stunFolder.Parent then stunFolder:Destroy() end
			if em and em.Parent then em:Destroy() end
		end)
	end)
	Debris:AddItem(stunBillboard, stunTime)
	Debris:AddItem(stunFolder, stunTime + 0.3)
	Debris:AddItem(em, stunTime + 0.3)
end

-- 4. Authentic Spider-Verse Chromatic Glitch Decoy (Flickers cyan/magenta & frame-jitters)
function WebVisuals.createChromaticGlitchDecoy(character: Model, rootCFrame: CFrame)
	local wasArchivable = character.Archivable
	character.Archivable = true
	local decoy = character:Clone()
	character.Archivable = wasArchivable

	if not decoy then return end
	decoy.Name = "MilesChromaticDecoy"

	local dHum = decoy:FindFirstChildOfClass("Humanoid")
	if dHum then dHum:Destroy() end
	local dAnim = decoy:FindFirstChildOfClass("Animator")
	if dAnim then dAnim:Destroy() end

	local cyan = Color3.fromRGB(40, 220, 255)
	local magenta = Color3.fromRGB(255, 30, 80)
	local parts: { BasePart } = {}

	for _, desc in decoy:GetDescendants() do
		if desc:IsA("Humanoid") or desc:IsA("Animator")
			or desc:IsA("Accessory") or desc:IsA("Shirt") or desc:IsA("Pants") or desc:IsA("ShirtGraphic")
			or desc:IsA("Motor6D") or desc:IsA("JointInstance")
			or desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("Sound")
			or desc:IsA("UIComponent") or desc:IsA("BillboardGui") or desc:IsA("Decal") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Material = Enum.Material.Neon
			desc.Color = if math.random() > 0.5 then cyan else magenta
			desc.Transparency = 0.35
			table.insert(parts, desc)
		end
	end

	decoy:PivotTo(rootCFrame)
	decoy.Parent = Workspace
	Debris:AddItem(decoy, 0.85)

	task.spawn(function()
		local elapsed = 0
		local duration = 0.80
		local frameCount = 0
		local conn: RBXScriptConnection? = nil

		conn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			frameCount += 1
			if elapsed >= duration or not decoy.Parent then
				if conn then conn:Disconnect() end
				if decoy.Parent then decoy:Destroy() end
				return
			end

			local alpha = math.clamp(elapsed / duration, 0, 1)
			local shouldJitter = (frameCount % 3 == 0)

			for _, part in parts do
				if part.Parent then
					part.Transparency = 0.35 + (0.65 * alpha)
					if shouldJitter then
						part.Color = if math.random() > 0.5 then cyan else magenta
					end
				end
			end

			if shouldJitter then
				local jitterOffset = Vector3.new(
					(math.random() - 0.5) * 0.28,
					(math.random() - 0.5) * 0.15,
					(math.random() - 0.5) * 0.28
				)
				decoy:PivotTo(rootCFrame + jitterOffset)
			end
		end)
	end)
end

-- 5. Bio-Spark Burst on Ambush / Breaking Camouflage
function WebVisuals.createBioSparkBurst(originPos: Vector3)
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.CFrame = CFrame.new(originPos)
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Anchored = true
	p.Parent = Workspace

	local att = Instance.new("Attachment")
	att.Parent = p

	local em = Instance.new("ParticleEmitter")
	em.Name = "AmbushSparks"
	em.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 220, 255)),
	})
	em.LightEmission = 1
	em.LightInfluence = 0
	em.Speed = NumberRange.new(12, 24)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Lifetime = NumberRange.new(0.10, 0.22)
	em.Rate = 0
	em.Parent = att

	em:Emit(14)
	Debris:AddItem(p, 0.30)
end

-- 6. Ambush Critical Hit Burst
function WebVisuals.createAmbushCritBurst(originPos: Vector3)
	WebVisuals.createBioSparkBurst(originPos)
	WebVisuals.createMeleeHitSparks(originPos, true)
end

-- 7. High-Speed Skyline Traversal Bio-Sparks (>75 studs/s)
type MilesSparkState = {
	character: Model,
	attachments: { Attachment },
	emitters: { ParticleEmitter },
	active: boolean,
}

local currentMilesSparks: MilesSparkState? = nil

function WebVisuals.cleanupMilesBioSparks(immediate: boolean?)
	if not currentMilesSparks then return end
	local state = currentMilesSparks

	for _, em in state.emitters do
		em.Rate = 0
		em.Enabled = false
	end
	state.active = false

	if immediate then
		currentMilesSparks = nil
		for _, att in state.attachments do
			if att.Parent then att:Destroy() end
		end
	end
end

function WebVisuals.activateMilesBioSparks(character: Model, speed: number)
	if not currentMilesSparks or currentMilesSparks.character ~= character then
		if currentMilesSparks then
			WebVisuals.cleanupMilesBioSparks(true)
		end

		local limbNames = { "RightHand", "LeftHand", "RightFoot", "LeftFoot", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
		local atts: { Attachment } = {}
		local ems: { ParticleEmitter } = {}

		for _, name in limbNames do
			local limb = character:FindFirstChild(name) :: BasePart?
			if limb and #atts < 4 then
				local att = Instance.new("Attachment")
				att.Name = "MilesBioSparkAtt"
				att.Parent = limb

				local em = Instance.new("ParticleEmitter")
				em.Name = "MilesBioSparkEmitter"
				em.Color = ColorSequence.new(Color3.fromRGB(255, 230, 60))
				em.LightEmission = 1
				em.LightInfluence = 0
				em.Speed = NumberRange.new(8, 18)
				em.SpreadAngle = Vector2.new(180, 180)
				em.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.4),
					NumberSequenceKeypoint.new(1, 0),
				})
				em.Lifetime = NumberRange.new(0.08, 0.18)
				em.Rate = 35
				em.Enabled = true
				em.Parent = att

				table.insert(atts, att)
				table.insert(ems, em)
			end
		end

		currentMilesSparks = {
			character = character,
			attachments = atts,
			emitters = ems,
			active = true,
		}
	end

	local state = currentMilesSparks
	if state then
		state.active = true
		for _, em in state.emitters do
			em.Rate = 35
			em.Enabled = true
		end
	end
end

-- Automatic Heartbeat monitor for local Apex Repulsor Thrusters
if RunService:IsClient() then
	RunService.Heartbeat:Connect(function()
		local char = LocalPlayer and LocalPlayer.Character
		if not char then
			if currentStarkThruster then
				WebVisuals.cleanupStarkThrusters(true)
			end
			return
		end

		local isStark = (LocalPlayer:GetAttribute("EquippedSuit") == "StarkTechSuit")
			or (char:GetAttribute("EquippedSuit") == "StarkTechSuit")
		local isMiles = (LocalPlayer:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
			or (char:GetAttribute("EquippedSuit") == "MilesSpiderVerse")

		if not isStark and currentStarkThruster then
			WebVisuals.cleanupStarkThrusters(true)
		end
		if not isMiles and currentMilesSparks then
			WebVisuals.cleanupMilesBioSparks(true)
		end

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local upperTorso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
		if not root then return end

		local speed = root.AssemblyLinearVelocity.Magnitude
		local isLaunching = char:GetAttribute("SlingshotLaunching") == true

		-- Stark Tech Thrusters (Speed >= 80)
		if isStark and upperTorso then
			if speed >= 80 or isLaunching then
				WebVisuals.activateStarkThrusters(char, upperTorso, speed)
			elseif speed < 65 then
				if currentStarkThruster and currentStarkThruster.active then
					WebVisuals.cleanupStarkThrusters(false)
				end
			end
		end

		-- Miles Morales Traversal Bio-Sparks (Speed >= 75)
		if isMiles then
			if speed >= 75 or isLaunching then
				WebVisuals.activateMilesBioSparks(char, speed)
			elseif speed < 60 then
				if currentMilesSparks and currentMilesSparks.active then
					WebVisuals.cleanupMilesBioSparks(false)
				end
			end
		end
	end)
end


-- 🌑 8. Symbiote Alien Tendril Ground Slam VFX (Expanding floor ring, erupting tendril spikes & matter burst)
function WebVisuals.createTendrilGroundSlamVFX(originPos: Vector3, maxRadius: number?)
	local slamRadius = maxRadius or 18

	local folder = Instance.new("Folder")
	folder.Name = "TendrilGroundSlamVFX"
	folder.Parent = Workspace

	-- 1. Expanding dark violet / black shockwave ring on the floor
	local shockRing = Instance.new("Part")
	shockRing.Name = "TendrilShockRing"
	shockRing.Shape = Enum.PartType.Cylinder
	shockRing.Size = Vector3.new(0.2, 2, 2)
	shockRing.CFrame = CFrame.new(originPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shockRing.Material = Enum.Material.Neon
	shockRing.Color = Color3.fromRGB(35, 20, 45)
	shockRing.Transparency = 0.15
	shockRing.CanCollide = false
	shockRing.Anchored = true
	shockRing.Parent = folder

	local ringTween = TweenService:Create(shockRing, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, slamRadius * 2, slamRadius * 2),
		Transparency = 1,
	})
	ringTween:Play()

	-- 2. Central dark matter and smoke particle burst
	local centerPart = Instance.new("Part")
	centerPart.Name = "TendrilCenterBurst"
	centerPart.Size = Vector3.new(1, 1, 1)
	centerPart.CFrame = CFrame.new(originPos + Vector3.new(0, 0.5, 0))
	centerPart.Transparency = 1
	centerPart.CanCollide = false
	centerPart.Anchored = true
	centerPart.Parent = folder

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "SymbioteSmokeBurst"
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 15, 25)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(45, 25, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 10, 20)),
	})
	smoke.LightEmission = 0.1
	smoke.LightInfluence = 0
	smoke.Speed = NumberRange.new(12, 26)
	smoke.SpreadAngle = Vector2.new(180, 45)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.8),
		NumberSequenceKeypoint.new(0.6, 2.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.3, 0.55)
	smoke.Rate = 0
	smoke.Parent = centerPart
	smoke:Emit(35)

	-- 3. 8 to 12 upward-curving black tendril mesh/beam spikes bursting out of the ground
	local tendrilCount = math.random(8, 12)
	for i = 1, tendrilCount do
		local angle = (i / tendrilCount) * math.pi * 2 + (math.random() - 0.5) * 0.4
		local distFromCenter = math.random(30, math.floor(slamRadius * 8)) * 0.1
		local basePos = originPos + Vector3.new(math.cos(angle) * distFromCenter, 0.1, math.sin(angle) * distFromCenter)
		local tendrilHeight = math.random(50, 85) * 0.1
		local tipSpread = Vector3.new(math.cos(angle) * 1.5 + (math.random() - 0.5) * 1.0, tendrilHeight, math.sin(angle) * 1.5 + (math.random() - 0.5) * 1.0)
		local tipPos = basePos + tipSpread

		local baseAtt = Instance.new("Attachment")
		baseAtt.WorldPosition = basePos
		baseAtt.Parent = centerPart

		local tipAtt = Instance.new("Attachment")
		tipAtt.WorldPosition = tipPos
		tipAtt.Parent = centerPart

		local tendril = Instance.new("Beam")
		tendril.Name = "SymbioteTendrilSpike"
		tendril.Attachment0 = baseAtt
		tendril.Attachment1 = tipAtt
		tendril.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 20)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(25, 18, 32)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 15)),
		})
		tendril.LightEmission = 0.05
		tendril.LightInfluence = 0
		tendril.Width0 = 0.85
		tendril.Width1 = 0.05
		tendril.Segments = 10
		tendril.CurveSize0 = math.random(2, 4) * (if math.random() > 0.5 then 1 else -1)
		tendril.CurveSize1 = math.random(1, 3) * (if math.random() > 0.5 then 1 else -1)
		tendril.FaceCamera = true
		tendril.Transparency = NumberSequence.new(0.05)
		tendril.Parent = folder

		-- Fade out sharp tips over 0.4s
		task.delay(0.20, function()
			if tendril and tendril.Parent then
				local fadeTween = TweenService:Create(tendril, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Width0 = 0,
					Width1 = 0,
				})
				fadeTween:Play()
			end
		end)
	end

	Debris:AddItem(folder, 0.48)
end

-- 🌑 9. Symbiote Brutal Fist Tendril Burst (Combo Step 3)
function WebVisuals.createTendrilPunchBurst(fist: BasePart)
	local folder = Instance.new("Folder")
	folder.Name = "TendrilPunchBurst"
	folder.Parent = Workspace

	local fistAtt = Instance.new("Attachment")
	fistAtt.Parent = fist

	local em = Instance.new("ParticleEmitter")
	em.Name = "TendrilSparks"
	em.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 15, 25)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(55, 25, 75)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 12, 20)),
	})
	em.LightEmission = 0.1
	em.LightInfluence = 0
	em.Speed = NumberRange.new(10, 22)
	em.SpreadAngle = Vector2.new(60, 60)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.7, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Lifetime = NumberRange.new(0.12, 0.26)
	em.Rate = 0
	em.Parent = fistAtt
	em:Emit(25)

	-- 4 forward whipping dark tendrils
	local lookVec = fist.CFrame.LookVector
	for i = 1, 4 do
		local tipPos = fist.Position + (lookVec * math.random(4, 7)) + Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 3, (math.random() - 0.5) * 3)
		local tipAtt = Instance.new("Attachment")
		tipAtt.WorldPosition = tipPos
		tipAtt.Parent = folder

		local tendril = Instance.new("Beam")
		tendril.Attachment0 = fistAtt
		tendril.Attachment1 = tipAtt
		tendril.Color = ColorSequence.new(Color3.fromRGB(15, 15, 20))
		tendril.Width0 = 0.45
		tendril.Width1 = 0.05
		tendril.CurveSize0 = math.random(1, 3) * (if i % 2 == 0 then 1 else -1)
		tendril.CurveSize1 = math.random(1, 2)
		tendril.FaceCamera = true
		tendril.Parent = folder

		task.delay(0.12, function()
			if tendril and tendril.Parent then
				TweenService:Create(tendril, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Width0 = 0,
					Width1 = 0,
				}):Play()
			end
		end)
	end

	Debris:AddItem(fistAtt, 0.30)
	Debris:AddItem(folder, 0.30)
end

-- 🌑 10. Replicated Symbiote Cleave Hit Burst
function WebVisuals.createSymbioteCleaveVFX(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "SymbioteCleaveVFX"
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	part.Transparency = 1
	part.CanCollide = false
	part.Anchored = true
	part.Parent = Workspace

	local att = Instance.new("Attachment")
	att.Parent = part

	local em = Instance.new("ParticleEmitter")
	em.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 22)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 25, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 15, 25)),
	})
	em.LightEmission = 0.15
	em.LightInfluence = 0
	em.Speed = NumberRange.new(8, 20)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Lifetime = NumberRange.new(0.15, 0.3)
	em.Rate = 0
	em.Parent = att
	em:Emit(30)

	Debris:AddItem(part, 0.35)
end


-- 🕸️ 11. Scarlet Spider: Impact Web Capsule Projectile (High-speed spinning web-capsule)
function WebVisuals.launchImpactWebProjectile(startAtt: Attachment, targetWorldPos: Vector3, callback: (() -> ())?)
	local startPos = startAtt.WorldPosition
	local toTarget = targetWorldPos - startPos
	local distance = toTarget.Magnitude
	local speed = 240
	local flightTime = math.clamp(distance / speed, 0.05, 0.22)

	local capsule = Instance.new("Part")
	capsule.Name = "ImpactWebCapsule"
	capsule.Shape = Enum.PartType.Cylinder
	capsule.Size = Vector3.new(1.4, 0.8, 0.8)
	capsule.Material = Enum.Material.Neon
	capsule.Color = Color3.fromRGB(245, 248, 255)
	capsule.CanCollide = false
	capsule.Anchored = true
	capsule.CFrame = CFrame.lookAt(startPos, targetWorldPos) * CFrame.Angles(0, math.rad(90), 0)
	capsule.Parent = Workspace

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(-0.7, 0, 0)
	att0.Parent = capsule

	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0.7, 0, 0)
	att1.Parent = capsule

	local trail = Instance.new("Trail")
	trail.Name = "ImpactCapsuleTrail"
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 50, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 115, 235)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.22
	trail.FaceCamera = true
	trail.Parent = capsule

	local tween = TweenService:Create(capsule, TweenInfo.new(flightTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(targetWorldPos, targetWorldPos + toTarget.Unit) * CFrame.Angles(0, math.rad(90), math.rad(180)),
	})
	tween:Play()
	tween.Completed:Connect(function()
		capsule:Destroy()
		WebVisuals.createImpactWebExplosionVFX(targetWorldPos, 10)
		if callback then callback() end
	end)
end

-- 🕸️ 12. Scarlet Spider: Impact Web Explosion (10-stud radial web-shockwave & outward strands)
function WebVisuals.createImpactWebExplosionVFX(originPos: Vector3, maxRadius: number?)
	local blastRadius = maxRadius or 10

	local folder = Instance.new("Folder")
	folder.Name = "ImpactWebExplosionVFX"
	folder.Parent = Workspace

	-- Expanding 10-stud web-shockwave ring
	local shockRing = Instance.new("Part")
	shockRing.Name = "ImpactWebRing"
	shockRing.Shape = Enum.PartType.Cylinder
	shockRing.Size = Vector3.new(0.2, 2, 2)
	shockRing.CFrame = CFrame.new(originPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shockRing.Material = Enum.Material.Neon
	shockRing.Color = Color3.fromRGB(245, 248, 255)
	shockRing.Transparency = 0.1
	shockRing.CanCollide = false
	shockRing.Anchored = true
	shockRing.Parent = folder

	local ringTween = TweenService:Create(shockRing, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, blastRadius * 2, blastRadius * 2),
		Transparency = 1,
	})
	ringTween:Play()

	-- 12 outward radial web strands
	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2 + (math.random() - 0.5) * 0.3
		local dist = math.random(6, math.floor(blastRadius))
		local endPos = originPos + Vector3.new(math.cos(angle) * dist, math.random(-2, 3) * 0.4, math.sin(angle) * dist)

		local strand = Instance.new("Part")
		strand.Name = "ImpactRadialStrand"
		strand.Material = Enum.Material.Neon
		strand.Color = Color3.fromRGB(240, 245, 255)
		strand.Transparency = 0.15
		strand.CanCollide = false
		strand.Anchored = true
		strand.Size = Vector3.new(0.08, 0.08, (endPos - originPos).Magnitude)
		strand.CFrame = CFrame.lookAt((originPos + endPos) / 2, endPos)
		strand.Parent = folder

		local strandTween = TweenService:Create(strand, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.02, 0.02, (endPos - originPos).Magnitude * 1.1),
		})
		strandTween:Play()
	end

	-- Particulate sparks burst
	local sparkPart = Instance.new("Part")
	sparkPart.Size = Vector3.new(1, 1, 1)
	sparkPart.CFrame = CFrame.new(originPos)
	sparkPart.Transparency = 1
	sparkPart.CanCollide = false
	sparkPart.Anchored = true
	sparkPart.Parent = folder

	local att = Instance.new("Attachment")
	att.Parent = sparkPart

	local em = Instance.new("ParticleEmitter")
	em.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 50, 60)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 115, 235)),
	})
	em.LightEmission = 0.8
	em.LightInfluence = 0
	em.Speed = NumberRange.new(10, 24)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Lifetime = NumberRange.new(0.15, 0.28)
	em.Rate = 0
	em.Parent = att
	em:Emit(35)

	Debris:AddItem(folder, 0.35)
end

-- 🤖 2099 Cyber Suit: Holographic Glitch Polygons for Supersonic Dropkick
function WebVisuals.spawnCyberGlitchPolygon(pos: Vector3)
	local glitch = Instance.new("Part")
	glitch.Name = "CyberGlitchPolygon"
	glitch.Material = Enum.Material.Neon
	glitch.Color = Color3.fromRGB(255, 35, 75)
	glitch.Size = Vector3.new(0.6, 0.6, 0.6)
	glitch.Transparency = 0.15
	glitch.CanCollide = false
	glitch.Anchored = true
	glitch.CastShadow = false
	glitch.CFrame = CFrame.new(pos) * CFrame.Angles(
		math.rad(math.random(-180, 180)),
		math.rad(math.random(-180, 180)),
		math.rad(math.random(-180, 180))
	)
	glitch.Parent = Workspace
	Debris:AddItem(glitch, 0.22)

	local tween = TweenService:Create(glitch, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.1, 0.1, 0.1),
	})
	tween:Play()
end

-- 🤖 2099 Cyber Suit: Claw Cross-Slash & Hit-Stop Crunch
function WebVisuals.createCyberCrossSlashVFX(pos: Vector3)
	local crimsonColor = Color3.fromRGB(255, 35, 75)
	local cyanAccent = Color3.fromRGB(45, 220, 255)

	local folder = Instance.new("Folder")
	folder.Name = "CyberCrossSlashVFX"
	folder.Parent = Workspace
	Debris:AddItem(folder, 0.35)

	-- Diagonal Slash 1
	local slash1 = Instance.new("Part")
	slash1.Name = "CrossSlash_1"
	slash1.Material = Enum.Material.Neon
	slash1.Color = crimsonColor
	slash1.Size = Vector3.new(0.14, 3.6, 0.8)
	slash1.Transparency = 0.05
	slash1.CanCollide = false
	slash1.Anchored = true
	slash1.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(35), 0, math.rad(45))
	slash1.Parent = folder

	-- Diagonal Slash 2
	local slash2 = Instance.new("Part")
	slash2.Name = "CrossSlash_2"
	slash2.Material = Enum.Material.Neon
	slash2.Color = crimsonColor
	slash2.Size = Vector3.new(0.14, 3.6, 0.8)
	slash2.Transparency = 0.05
	slash2.CanCollide = false
	slash2.Anchored = true
	slash2.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(-35), 0, math.rad(-45))
	slash2.Parent = folder

	-- Central Digital Flare
	local core = Instance.new("Part")
	core.Name = "CrossSlash_Core"
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = cyanAccent
	core.Size = Vector3.new(1.6, 1.6, 1.6)
	core.Transparency = 0.1
	core.CanCollide = false
	core.Anchored = true
	core.CFrame = CFrame.new(pos)
	core.Parent = folder

	TweenService:Create(slash1, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.02, 5.2, 1.2),
	}):Play()

	TweenService:Create(slash2, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.02, 5.2, 1.2),
	}):Play()

	TweenService:Create(core, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(3.2, 3.2, 3.2),
	}):Play()
end

-- 🤖 2099 Cyber Suit: Forearm Laser Slash Arc along Blade
function WebVisuals.createCyberTalonSlash(character: Model, isRight: boolean, isHit3: boolean, camera: Camera?)
	local bladeName = isRight and "Suit_BladeR_Base" or "Suit_BladeL_Base"
	local altBladeName = isRight and "BladeR_Base" or "BladeL_Base"
	local armName = isRight and "RightLowerArm" or "LeftLowerArm"
	local handName = isRight and "RightHand" or "LeftHand"

	local bladePart = character:FindFirstChild(bladeName, true)
		or character:FindFirstChild(altBladeName, true)
		or character:FindFirstChild(armName)
		or character:FindFirstChild(handName)
		or character:FindFirstChild("HumanoidRootPart")

	if not bladePart or not bladePart:IsA("BasePart") then return end

	local crimsonColor = Color3.fromRGB(255, 35, 75)

	if not isHit3 then
		-- Curved neon crimson laser slash arc along the forearm blade fading over 0.12s
		local slashArc = Instance.new("Part")
	slashArc.Name = "CyberLaserSlashArc"
	slashArc.Material = Enum.Material.Neon
	slashArc.Color = crimsonColor
	slashArc.Size = Vector3.new(0.12, 1.8, 0.45)
	slashArc.Transparency = 0.05
	slashArc.CanCollide = false
	slashArc.Anchored = false
	slashArc.Massless = true
	slashArc.CastShadow = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bladePart
		weld.Part1 = slashArc
		weld.Parent = slashArc

		slashArc.CFrame = bladePart.CFrame * CFrame.new(isRight and 0.45 or -0.45, 0, -0.6) * CFrame.Angles(math.rad(isRight and 25 or -25), math.rad(15), 0)
		slashArc.Parent = Workspace

		local tween = TweenService:Create(slashArc, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.04, 2.2, 0.7),
		})
		tween:Play()
		Debris:AddItem(slashArc, 0.15)
	else
		-- Combo Hit 3: Brutal Heavy Digital Cross-Slash with camera hit-stop crunch
		WebVisuals.createCyberCrossSlashVFX(bladePart.Position + character:GetPivot().LookVector * 2.5)

		if camera then
			local baseFov = camera.FieldOfView
			camera.FieldOfView = math.max(40, baseFov - 5)
			local fovTween = TweenService:Create(camera, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				FieldOfView = baseFov,
			})
			fovTween:Play()
		end
	end
end

-- 🤖 2099 Cyber Suit: Supersonic Strike Impact VFX
function WebVisuals.createCyberStrikeVFX(pos: Vector3)
	local crimsonColor = Color3.fromRGB(255, 35, 75)
	local folder = Instance.new("Folder")
	folder.Name = "CyberStrikeVFX"
	folder.Parent = Workspace
	Debris:AddItem(folder, 0.35)

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = crimsonColor
	ring.Size = Vector3.new(0.2, 2.5, 2.5)
	ring.Transparency = 0.1
	ring.CanCollide = false
	ring.Anchored = true
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder

	TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 12, 12),
		Transparency = 1,
	}):Play()

	for i = 1, 6 do
		local glitch = Instance.new("Part")
		glitch.Material = Enum.Material.Neon
		glitch.Color = if i % 2 == 0 then Color3.fromRGB(255, 45, 80) else Color3.fromRGB(45, 220, 255)
		glitch.Size = Vector3.new(0.5, 0.5, 0.5)
		glitch.Transparency = 0.1
		glitch.CanCollide = false
		glitch.Anchored = true
		local spread = Vector3.new(math.random(-5, 5), math.random(-3, 5), math.random(-5, 5))
		glitch.CFrame = CFrame.new(pos + spread) * CFrame.Angles(math.rad(math.random(0, 360)), math.rad(math.random(0, 360)), 0)
		glitch.Parent = folder

		TweenService:Create(glitch, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1),
		}):Play()
	end
end

-- 🕷️ Universal Gold Comic Spider-Sense Warning Squiggles (\/\/\)
function WebVisuals.createSpiderSenseSquiggles(character: Model)
	local head = (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not head then return end

	local folder = Instance.new("Folder")
	folder.Name = "SpiderSenseSquiggles"
	folder.Parent = Workspace
	Debris:AddItem(folder, 0.40)

	local goldColor = Color3.fromRGB(255, 220, 45)
	local headCF = head.CFrame
	local angles = { -40, -14, 14, 40 }

	for i, deg in angles do
		local rad = math.rad(deg)
		local rightOffset = math.sin(rad) * 1.5
		local upOffset = math.cos(rad) * 1.6 + 0.6
		local basePos = headCF.Position + (headCF.RightVector * rightOffset) + (headCF.UpVector * upOffset)

		-- Segment 1 (Zig)
		local seg1 = Instance.new("Part")
		seg1.Name = "SquiggleZig_" .. i
		seg1.Material = Enum.Material.Neon
		seg1.Color = goldColor
		seg1.Transparency = 0.1
		seg1.CanCollide = false
		seg1.CanTouch = false
		seg1.CanQuery = false
		seg1.Anchored = true
		seg1.Size = Vector3.new(0.12, 0.12, 0.3)
		seg1.CFrame = CFrame.lookAt(basePos, basePos + (headCF.RightVector * math.sin(rad * 1.2)) + (headCF.UpVector * math.cos(rad)))
			* CFrame.Angles(0, math.rad(if i % 2 == 0 then 22 else -22), math.rad(if i % 2 == 0 then 15 else -15))
		seg1.Parent = folder

		-- Segment 2 (Zag - outer jagged branch)
		local zagPos = basePos + (headCF.UpVector * 0.4) + (headCF.RightVector * (math.sin(rad) * 0.4))
		local seg2 = Instance.new("Part")
		seg2.Name = "SquiggleZag_" .. i
		seg2.Material = Enum.Material.Neon
		seg2.Color = goldColor
		seg2.Transparency = 0.1
		seg2.CanCollide = false
		seg2.CanTouch = false
		seg2.CanQuery = false
		seg2.Anchored = true
		seg2.Size = Vector3.new(0.12, 0.12, 0.3)
		seg2.CFrame = CFrame.lookAt(zagPos, zagPos + (headCF.RightVector * math.sin(rad * 1.4)) + (headCF.UpVector * (math.cos(rad) * 1.2)))
			* CFrame.Angles(0, math.rad(if i % 2 == 0 then -25 else 25), math.rad(if i % 2 == 0 then -18 else 18))
		seg2.Parent = folder

		-- Animate snappy 0.35s scale & fade (Size: 0.1 -> 1.4 studs, Transparency: 0.1 -> 1.0)
		local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(seg1, tweenInfo, {
			Size = Vector3.new(0.14, 0.14, 1.4),
			Transparency = 1,
			CFrame = seg1.CFrame + (headCF.UpVector * 0.5) + (headCF.RightVector * (math.sin(rad) * 0.5)),
		}):Play()

		TweenService:Create(seg2, tweenInfo, {
			Size = Vector3.new(0.14, 0.14, 1.4),
			Transparency = 1,
			CFrame = seg2.CFrame + (headCF.UpVector * 0.7) + (headCF.RightVector * (math.sin(rad) * 0.7)),
		}):Play()
	end
end

-- 🕸️ Classic Peter Parker: Double Web-Slam Kinetic Impact VFX
function WebVisuals.createDoubleWebSlamVFX(posA: Vector3, posB: Vector3, centerPos: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "DoubleWebSlamVFX"
	folder.Parent = Workspace
	Debris:AddItem(folder, 0.45)

	-- 1. Dual white web beams pulling from posA & posB toward centerPos
	local centerPart = Instance.new("Part")
	centerPart.Name = "SlamCenter"
	centerPart.Size = Vector3.new(0.2, 0.2, 0.2)
	centerPart.CFrame = CFrame.new(centerPos)
	centerPart.Transparency = 1
	centerPart.CanCollide = false
	centerPart.CanTouch = false
	centerPart.CanQuery = false
	centerPart.Anchored = true
	centerPart.Parent = folder

	local centerAtt = Instance.new("Attachment")
	centerAtt.Position = Vector3.zero
	centerAtt.Parent = centerPart

	local partA = Instance.new("Part")
	partA.Size = Vector3.new(0.2, 0.2, 0.2)
	partA.CFrame = CFrame.new(posA)
	partA.Transparency = 1
	partA.CanCollide = false
	partA.CanTouch = false
	partA.CanQuery = false
	partA.Anchored = true
	partA.Parent = folder

	local attA = Instance.new("Attachment")
	attA.Position = Vector3.zero
	attA.Parent = partA

	local partB = Instance.new("Part")
	partB.Size = Vector3.new(0.2, 0.2, 0.2)
	partB.CFrame = CFrame.new(posB)
	partB.Transparency = 1
	partB.CanCollide = false
	partB.CanTouch = false
	partB.CanQuery = false
	partB.Anchored = true
	partB.Parent = folder

	local attB = Instance.new("Attachment")
	attB.Position = Vector3.zero
	attB.Parent = partB

	local beamColor = ColorSequence.new(Color3.fromRGB(250, 252, 255))

	local beamA = Instance.new("Beam")
	beamA.Attachment0 = attA
	beamA.Attachment1 = centerAtt
	beamA.Color = beamColor
	beamA.Width0 = 0.35
	beamA.Width1 = 0.15
	beamA.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	beamA.FaceCamera = true
	beamA.Segments = 1
	beamA.Parent = folder

	local beamB = Instance.new("Beam")
	beamB.Attachment0 = attB
	beamB.Attachment1 = centerAtt
	beamB.Color = beamColor
	beamB.Width0 = 0.35
	beamB.Width1 = 0.15
	beamB.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	beamB.FaceCamera = true
	beamB.Segments = 1
	beamB.Parent = folder

	-- 2. Kinetic Shockwave Ring (radius 8 studs = diameter 16)
	local shockRing = Instance.new("Part")
	shockRing.Shape = Enum.PartType.Cylinder
	shockRing.Material = Enum.Material.Neon
	shockRing.Color = Color3.fromRGB(245, 248, 255)
	shockRing.Size = Vector3.new(0.25, 2, 2)
	shockRing.Transparency = 0.1
	shockRing.CanCollide = false
	shockRing.CanTouch = false
	shockRing.CanQuery = false
	shockRing.Anchored = true
	shockRing.CFrame = CFrame.new(centerPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shockRing.Parent = folder

	TweenService:Create(shockRing, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.25, 16, 16),
		Transparency = 1,
	}):Play()

	-- Impact Sparks at centerPos
	WebVisuals.createWeaponImpactSparks(centerPos, Vector3.new(0, 1, 0))

	-- Inward hit-stop camera crunch (-4° FOV for 0.12s)
	local camera = Workspace.CurrentCamera
	if camera then
		local baseFov = camera.FieldOfView
		camera.FieldOfView = math.max(40, baseFov - 4)
		local fovTween = TweenService:Create(camera, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = baseFov,
		})
		fovTween:Play()
	end
end

return WebVisuals
