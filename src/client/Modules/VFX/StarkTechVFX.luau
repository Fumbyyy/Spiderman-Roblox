--!strict
--[[
	StarkTechVFX.luau
	Visual effects for Stark Tech Suit: plasma back thrusters and Waldo repulsor shockwaves.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local StarkTechVFX = {}

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

function StarkTechVFX.cleanupStarkThrusters(immediate: boolean?)
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

function StarkTechVFX.activateStarkThrusters(character: Model, upperTorso: BasePart, speed: number)
	if not currentStarkThruster or currentStarkThruster.character ~= character or currentStarkThruster.upperTorso ~= upperTorso then
		if currentStarkThruster then
			StarkTechVFX.cleanupStarkThrusters(true)
		end

		local oldL = character:FindFirstChild("StarkThruster_L")
		if oldL then oldL:Destroy() end
		local oldR = character:FindFirstChild("StarkThruster_R")
		if oldR then oldR:Destroy() end

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

-- 🌀 Stark Tech Waldo Repulsor Shockwave Pulse (Expanding Cyan Ring from 2 to 14 studs in 0.25s)
function StarkTechVFX.createWaldoRepulsorShockwave(originPos: Vector3, maxRadius: number?)
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

return StarkTechVFX
