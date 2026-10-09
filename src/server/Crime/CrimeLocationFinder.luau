--!strict
--[[
	CrimeLocationFinder.luau
	Locates optimal spawn points for city crimes:
	prioritizes creator-placed map markers, falling back to dynamic high-altitude city raycasts.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CrimeLocationFinder = {}

function CrimeLocationFinder.findCrimeSpawnLocation(
	archetypeId: string,
	enemiesFolder: Folder,
	activeCrimesFolder: Folder
): (Vector3, Vector3, BasePart?)
	local specificParts: { BasePart } = {}
	local generalParts: { BasePart } = {}

	local targetPrefix = (archetypeId == "BankHeist" and "bank")
		or (archetypeId == "RooftopDeal" and "rooftop")
		or (archetypeId == "AlleywayMugging" and "alley")
		or "getaway"

	-- 1. Check if Creator placed custom map markers or spawn folders in Workspace
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			local lowerName = string.lower(descendant.Name)
			local parentName = descendant.Parent and string.lower(descendant.Parent.Name) or ""

			local isSpawnFolder = parentName == "enemyspawns" or parentName == "crimespawns" or parentName == "questspawns" or parentName == "spawnpoints" or parentName == "enemy_spawns" or parentName == "crime_spawns"
			local isSpawnNamed = string.find(lowerName, "enemyspawn") ~= nil
				or string.find(lowerName, "crimespawn") ~= nil
				or string.find(lowerName, "questspawn") ~= nil
				or string.find(lowerName, "enemy_spawn") ~= nil
				or string.find(lowerName, "crime_spawn") ~= nil
				or string.find(lowerName, "enemy spawn") ~= nil
				or string.find(lowerName, "crime spawn") ~= nil
				or string.find(lowerName, "quest spawn") ~= nil
				or lowerName == "crime_bank" or lowerName == "crime_rooftop" or lowerName == "crime_alley" or lowerName == "crime_getaway"

			if isSpawnNamed or isSpawnFolder then
				descendant.Transparency = 1
				descendant.CanCollide = false

				if string.find(lowerName, targetPrefix) ~= nil then
					table.insert(specificParts, descendant)
				else
					table.insert(generalParts, descendant)
				end
			end
		end
	end

	-- Prioritize specific archetype markers if present, otherwise general spawns
	local pool = #specificParts > 0 and specificParts or generalParts
	if #pool > 0 then
		local chosenPart = pool[math.random(1, #pool)]
		local lookDir = chosenPart.CFrame.LookVector
		local spawnPos = chosenPart.Position + Vector3.new(0, (chosenPart.Size.Y * 0.5) + 0.5, 0)
		return spawnPos, lookDir, chosenPart
	end

	-- 2. Procedural Fallback based on Players & High-Altitude Raycasting
	local fallbackPositions = {
		BankHeist = Vector3.new(0, 3, -60),
		RooftopDeal = Vector3.new(45, 65, 40),
		AlleywayMugging = Vector3.new(-50, 3, -20),
		GetawayChase = Vector3.new(-80, 3, 50),
	}

	local basePos = fallbackPositions[archetypeId] or Vector3.new(0, 3, 0)
	local moveDir = Vector3.new(0, 0, -1)

	-- If players are present, center near active player cluster
	local players = Players:GetPlayers()
	if #players > 0 then
		local p = players[math.random(1, #players)]
		local pRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if pRoot then
			local angle = math.random() * math.pi * 2
			local dist = math.random(75, 140)
			local candidateX = pRoot.Position.X + (math.cos(angle) * dist)
			local candidateZ = pRoot.Position.Z + (math.sin(angle) * dist)

			-- Raycast down from high altitude (350 studs) to hit true roof/ground, NOT interior rooms!
			local rayOrigin = Vector3.new(candidateX, 350, candidateZ)
			local rayDir = Vector3.new(0, -500, 0)
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = { enemiesFolder, activeCrimesFolder }

			local result = Workspace:Raycast(rayOrigin, rayDir, rayParams)
			if result and result.Normal.Y > 0.5 and result.Position.Y > (Workspace.FallenPartsDestroyHeight + 40) then
				basePos = result.Position + Vector3.new(0, 1.5, 0)
			end
		end
	end

	return basePos, moveDir, nil
end

return CrimeLocationFinder
