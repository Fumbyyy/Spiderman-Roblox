--!strict
--[[
	SymbioteVFX.luau
	Visual effects for Symbiote Black Suit: alien tendril ground slam, brutal fist tendril burst,
	and dark matter cleave hit effects.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SymbioteVFX = {}

-- 🌑 1. Symbiote Alien Tendril Ground Slam VFX (Expanding floor ring, erupting tendril spikes & matter burst)
function SymbioteVFX.createTendrilGroundSlamVFX(originPos: Vector3, maxRadius: number?)
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

		-- Fade out sharp tips over 0.2s
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

-- 🌑 2. Symbiote Brutal Fist Tendril Burst (Combo Step 3)
function SymbioteVFX.createTendrilPunchBurst(fist: BasePart)
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

-- 🌑 3. Replicated Symbiote Cleave Hit Burst
function SymbioteVFX.createSymbioteCleaveVFX(position: Vector3)
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

return SymbioteVFX
