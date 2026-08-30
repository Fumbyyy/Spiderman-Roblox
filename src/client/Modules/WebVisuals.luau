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
function WebVisuals.createWebBeam(att0: Attachment, att1: Attachment, parent: Instance): Beam
	local beam = Instance.new("Beam")
	beam.Name = "SpiderWebBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Width0 = 0.16
	beam.Width1 = 0.16
	beam.Color = ColorSequence.new(GrappleConfig.Visuals.RopeColor)
	beam.Transparency = NumberSequence.new(0.04)
	beam.FaceCamera = true
	beam.LightEmission = 0.35
	beam.Parent = parent
	return beam
end

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

-- 🔊 Play the classic web-shooter "thwip" sound
function WebVisuals.playWebSound(originPart: BasePart?)
	local soundId = GrappleConfig.Visuals.WebShootSoundId
	if not soundId or soundId == "" then return end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 1.0
	sound.RollOffMaxDistance = 150
	sound.Parent = originPart or SoundService
	
	-- Play locally for instant, crisp response
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 2.5)
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
	pellet.Color = Color3.fromRGB(255, 255, 255)
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

	local beamL = WebVisuals.createWebBeam(leftAtt, weaponAtt, weaponPart)
	local beamR = WebVisuals.createWebBeam(rightAtt, weaponAtt, weaponPart)

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

function WebVisuals.updateWindSound(rootPart: BasePart?, speed: number)
	if not rootPart then return end

	local soundId = GrappleConfig.Visuals and GrappleConfig.Visuals.WindSoundId or ""
	if not soundId or soundId == "" then
		if windLoopSound then
			windLoopSound:Stop()
			windLoopSound:Destroy()
			windLoopSound = nil
		end
		return
	end

	if not windLoopSound or not windLoopSound.Parent then
		local s = Instance.new("Sound")
		s.Name = "WindRushLoop"
		s.SoundId = soundId
		s.Looped = true
		s.Volume = 0
		s.PlaybackSpeed = 1.0
		s.Parent = rootPart
		s:Play()
		windLoopSound = s
	end

	local minSpeed = 50
	if speed > minSpeed then
		local ratio = math.clamp((speed - minSpeed) / 110, 0, 1)
		local targetVol = 0.50 * ratio
		local targetPitch = 0.85 + (ratio * 0.45)

		windLoopSound.Volume = windLoopSound.Volume + (targetVol - windLoopSound.Volume) * 0.25
		windLoopSound.PlaybackSpeed = targetPitch
		if not windLoopSound.IsPlaying then windLoopSound:Play() end
	else
		windLoopSound.Volume = math.max(0, windLoopSound.Volume - 0.1)
		if windLoopSound.Volume <= 0.01 and windLoopSound.IsPlaying then
			windLoopSound:Stop()
		end
	end
end

-- 👥 Multiplayer Replication Listener
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
		local beam = WebVisuals.createWebBeam(playerAtt, worldAtt, otherRoot)

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

return WebVisuals
