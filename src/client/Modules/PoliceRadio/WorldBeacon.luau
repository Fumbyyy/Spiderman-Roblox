--!strict
--[[
	WorldBeacon.luau
	3D Holographic World Beacon (Sky pillar and ground scanner ring)
	over active crime epicenters in Midtown Manhattan.
]]

local Workspace = game:GetService("Workspace")

local WorldBeacon = {}

local activeBeaconModel: Model? = nil

function WorldBeacon.cleanup()
	if activeBeaconModel then
		activeBeaconModel:Destroy()
		activeBeaconModel = nil
	end
end

function WorldBeacon.create(epicenter: Vector3, themeColor: Color3, isUIVisible: boolean): Model?
	WorldBeacon.cleanup()
	if not isUIVisible then return nil end

	local model = Instance.new("Model")
	model.Name = "CrimeHoloBeacon"

	-- 1. Sky Pillar: Glowing neon vertical cylinder rising into the clouds
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(300, 2.6, 2.6) -- Cylinder X is height in Roblox
	pillar.CFrame = CFrame.new(epicenter + Vector3.new(0, 150, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Color = themeColor
	pillar.Material = Enum.Material.Neon
	pillar.Transparency = 0.55
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanTouch = false
	pillar.CanQuery = false
	pillar.Parent = model

	-- 2. Base Holo Disc / Ground Scanner Ring
	local ring = Instance.new("Part")
	ring.Name = "HoloRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 26, 26)
	ring.CFrame = CFrame.new(epicenter + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = themeColor
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.60
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Parent = model

	-- 3. Core Pulse Light
	local pointLight = Instance.new("PointLight")
	pointLight.Name = "BeaconLight"
	pointLight.Color = themeColor
	pointLight.Brightness = 2.5
	pointLight.Range = 35
	pointLight.Parent = ring

	model.Parent = Workspace
	activeBeaconModel = model
	return model
end

function WorldBeacon.updateDistanceFade(playerPos: Vector3, epicenter: Vector3)
	if not activeBeaconModel then return end
	local dist = (playerPos - epicenter).Magnitude
	local pillar = activeBeaconModel:FindFirstChild("Pillar") :: BasePart?
	local ring = activeBeaconModel:FindFirstChild("HoloRing") :: BasePart?

	if dist < 45 then
		if pillar and pillar.Transparency < 0.98 then
			pillar.Transparency = math.clamp(pillar.Transparency + 0.08, 0, 1)
		end
		if ring and ring.Transparency < 0.98 then
			ring.Transparency = math.clamp(ring.Transparency + 0.08, 0, 1)
		end
	else
		if pillar and pillar.Transparency > 0.55 then
			pillar.Transparency = math.clamp(pillar.Transparency - 0.08, 0.55, 1)
		end
		if ring and ring.Transparency > 0.60 then
			ring.Transparency = math.clamp(ring.Transparency - 0.08, 0.60, 1)
		end
	end
end

return WorldBeacon
