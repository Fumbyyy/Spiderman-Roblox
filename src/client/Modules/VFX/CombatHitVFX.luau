--!strict
--[[
	CombatHitVFX.luau
	Modular combat impact sparks, guard breaks, muzzle flashes, and counter shockwaves.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local CombatHitVFX = {}

-- 🥊 Create Melee Hit Sparks and Comic Book Hit Flares on punch contact
function CombatHitVFX.createMeleeHitSparks(hitPos: Vector3, isHeavy: boolean)
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
function CombatHitVFX.createBruteBlockSparks(hitPos: Vector3, blockNormal: Vector3)
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
function CombatHitVFX.createGuardBreakBurst(hitPos: Vector3)
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
function CombatHitVFX.createGunnerMuzzleFlash(muzzlePos: Vector3, fireDir: Vector3, tracerLength: number?)
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
function CombatHitVFX.createWeaponImpactSparks(hitPos: Vector3, hitNormal: Vector3, splatCallback: ((Vector3, Vector3?) -> ())?)
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

	if splatCallback then
		splatCallback(hitPos, hitNormal)
	end
end

-- ⚡ Create Spider-Sense jagged lightning warning sparks above character head
function CombatHitVFX.createSpiderSenseSparks(playerChar: Model, isDanger: boolean)
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
function CombatHitVFX.createCounterImpactShockwave(hitPos: Vector3, radius: number)
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

return CombatHitVFX
