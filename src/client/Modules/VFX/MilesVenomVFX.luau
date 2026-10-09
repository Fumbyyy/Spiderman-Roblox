--!strict
--[[
	MilesVenomVFX.luau
	Visual effects for Miles Morales Suit: bio-electric venom punches, blast shockwaves,
	enemy stun lightning, chromatic glitch decoys, and high-speed traversal sparks.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local CombatHitVFX = require(script.Parent.CombatHitVFX)

local MilesVenomVFX = {}

type MilesSparkState = {
	character: Model,
	attachments: { Attachment },
	emitters: { ParticleEmitter },
	active: boolean,
}

local currentMilesSparks: MilesSparkState? = nil

-- 1. Branching electric sparks on punches
function MilesVenomVFX.createVenomFistSparks(fistPart: BasePart)
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
function MilesVenomVFX.createVenomBlastShockwave(originPos: Vector3, maxRadius: number?)
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
function MilesVenomVFX.applyVenomStunVFX(enemyModel: Model, duration: number?)
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
function MilesVenomVFX.createChromaticGlitchDecoy(character: Model, rootCFrame: CFrame)
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
function MilesVenomVFX.createBioSparkBurst(originPos: Vector3)
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
function MilesVenomVFX.createAmbushCritBurst(originPos: Vector3)
	MilesVenomVFX.createBioSparkBurst(originPos)
	CombatHitVFX.createMeleeHitSparks(originPos, true)
end

-- 7. High-Speed Skyline Traversal Bio-Sparks (>75 studs/s)
function MilesVenomVFX.cleanupMilesBioSparks(immediate: boolean?)
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

function MilesVenomVFX.activateMilesBioSparks(character: Model, speed: number)
	if not currentMilesSparks or currentMilesSparks.character ~= character then
		if currentMilesSparks then
			MilesVenomVFX.cleanupMilesBioSparks(true)
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

return MilesVenomVFX
