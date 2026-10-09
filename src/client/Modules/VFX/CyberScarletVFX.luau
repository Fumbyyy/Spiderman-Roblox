--!strict
--[[
	CyberScarletVFX.luau
	Visual effects for Scarlet Spider (impact web capsules & cluster explosions),
	2099 Cyber Suit (glitch polygons, laser cross-slashes, supersonic strike),
	and Classic Peter Parker (Spider-Sense squiggles & Double Web-Slam).
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local CombatHitVFX = require(script.Parent.CombatHitVFX)

local CyberScarletVFX = {}

-- 🕸️ 1. Scarlet Spider: Impact Web Capsule Projectile (High-speed spinning web-capsule)
function CyberScarletVFX.launchImpactWebProjectile(startAtt: Attachment, targetWorldPos: Vector3, callback: (() -> ())?)
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
		CyberScarletVFX.createImpactWebExplosionVFX(targetWorldPos, 10)
		if callback then callback() end
	end)
end

-- 🕸️ 2. Scarlet Spider: Impact Web Explosion (10-stud radial web-shockwave & outward strands)
function CyberScarletVFX.createImpactWebExplosionVFX(originPos: Vector3, maxRadius: number?)
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

-- 🤖 3. 2099 Cyber Suit: Holographic Glitch Polygons for Supersonic Dropkick
function CyberScarletVFX.spawnCyberGlitchPolygon(pos: Vector3)
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

-- 🤖 4. 2099 Cyber Suit: Claw Cross-Slash & Hit-Stop Crunch
function CyberScarletVFX.createCyberCrossSlashVFX(pos: Vector3)
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

-- 🤖 5. 2099 Cyber Suit: Forearm Laser Slash Arc along Blade
function CyberScarletVFX.createCyberTalonSlash(character: Model, isRight: boolean, isHit3: boolean, camera: Camera?)
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
		CyberScarletVFX.createCyberCrossSlashVFX(bladePart.Position + character:GetPivot().LookVector * 2.5)

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

-- 🤖 6. 2099 Cyber Suit: Supersonic Strike Impact VFX
function CyberScarletVFX.createCyberStrikeVFX(pos: Vector3)
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

-- 🕷️ 7. Universal Gold Comic Spider-Sense Warning Squiggles (\/\/\)
function CyberScarletVFX.createSpiderSenseSquiggles(character: Model)
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

-- 🕸️ 8. Classic Peter Parker: Double Web-Slam Kinetic Impact VFX
function CyberScarletVFX.createDoubleWebSlamVFX(posA: Vector3, posB: Vector3, centerPos: Vector3)
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

	CombatHitVFX.createWeaponImpactSparks(centerPos, Vector3.new(0, 1, 0))

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

return CyberScarletVFX
