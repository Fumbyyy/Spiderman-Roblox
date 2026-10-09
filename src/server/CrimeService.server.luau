--!strict
--[[
	CrimeService.server.luau
	Master Server Authority for Procedural Dynamic City Crimes & Police Scanner.
	Delegates to modular subsystems:
	- PlayerProgression: Leaderstats, level caps, scaled XP/Cash awards, and chat commands
	- CrimeEntityFactory: Enemy models, AI combat telegraph loops, vehicles, hostages, and crates
	- CrimeLocationFinder: Custom map marker scanning and high-altitude dynamic raycasting
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrimeConfig = require(Shared:WaitForChild("CrimeConfig"))

local Crime = script.Parent:WaitForChild("Crime")
local PlayerProgression = require(Crime:WaitForChild("PlayerProgression"))
local CrimeEntityFactory = require(Crime:WaitForChild("CrimeEntityFactory"))
local CrimeLocationFinder = require(Crime:WaitForChild("CrimeLocationFinder"))

-- 📦 Create Remotes Folder for Crime Networking
local CrimeRemotesFolder = ReplicatedStorage:FindFirstChild("CrimeRemotes")
if not CrimeRemotesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "CrimeRemotes"
	folder.Parent = ReplicatedStorage
	CrimeRemotesFolder = folder
end

local function getOrCreateRemote(name: string): RemoteEvent
	local remote = CrimeRemotesFolder:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteEvent") then
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = name
		newRemote.Parent = CrimeRemotesFolder
		return newRemote
	end
	return remote
end

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local rf = CrimeRemotesFolder:FindFirstChild(name)
	if not rf or not rf:IsA("RemoteFunction") then
		local newRf = Instance.new("RemoteFunction")
		newRf.Name = name
		newRf.Parent = CrimeRemotesFolder
		return newRf
	end
	return rf
end

local CrimeNotificationRemote = getOrCreateRemote("CrimeNotification")
local CrimeInteractRemote = getOrCreateRemote("CrimeInteract")
local GetActiveCrimesRF = getOrCreateRemoteFunction("GetActiveCrimes")

-- Combat Remotes for VFX
local CombatRemotesFolder = ReplicatedStorage:FindFirstChild("CombatRemotes")
local CombatVFXRemote = CombatRemotesFolder and CombatRemotesFolder:FindFirstChild("CombatVFX") :: RemoteEvent?

-- Active Crimes Workspace Folder
local ActiveCrimesFolder = Workspace:FindFirstChild("ActiveCrimes")
if not ActiveCrimesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "ActiveCrimes"
	folder.Parent = Workspace
	ActiveCrimesFolder = folder
end

local EnemiesFolder = Workspace:FindFirstChild("Enemies")
if not EnemiesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	EnemiesFolder = folder
end

--------------------------------------------------------------------------------
-- 🏙️ ACTIVE CRIME INSTANCE DATA STRUCTURE
--------------------------------------------------------------------------------

export type ActiveCrimeInstance = {
	Id: string,
	Archetype: CrimeConfig.CrimeArchetypeConfig,
	Epicenter: Vector3,
	Folder: Folder,
	State: "Spawned" | "InProgress" | "Cleared" | "Failed",
	StartTime: number,
	Enemies: { Model },
	ParticipatingPlayers: { [Player]: boolean },
	IsCoOpScaled: boolean,
}

local currentActiveCrime: ActiveCrimeInstance? = nil
local lastCrimeEndTime = 0

--------------------------------------------------------------------------------
-- 👤 PLAYER LIFECYCLE MANAGEMENT
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	PlayerProgression.setupPlayerLeaderstats(player)
	PlayerProgression.setupPlayerChatCommands(player, CrimeNotificationRemote)

	player.CharacterAdded:Connect(function()
		task.defer(function()
			PlayerProgression.updatePlayerHealth(player)
		end)
	end)
	if player.Character then
		task.defer(function()
			PlayerProgression.updatePlayerHealth(player)
		end)
	end

	if currentActiveCrime ~= nil then
		task.delay(1.5, function()
			if currentActiveCrime ~= nil and player:IsDescendantOf(Players) then
				CrimeNotificationRemote:FireClient(player, "CrimeSpawned", {
					Id = currentActiveCrime.Id,
					Title = currentActiveCrime.Archetype.Title,
					PoliceCode = currentActiveCrime.Archetype.PoliceCode,
					DispatchMessage = currentActiveCrime.Archetype.DispatchMessage,
					Icon = currentActiveCrime.Archetype.Icon,
					Epicenter = currentActiveCrime.Epicenter,
					ThemeColor = currentActiveCrime.Archetype.ThemeColor,
					Timeout = CrimeConfig.Scheduler.CrimeTimeout,
				})
			end
		end)
	end
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

--------------------------------------------------------------------------------
-- 🚨 PROCEDURAL CRIME ARENA LIFECYCLE
--------------------------------------------------------------------------------

local function spawnProceduralCrime(specificArchetypeId: string?): ActiveCrimeInstance?
	if currentActiveCrime ~= nil then return nil end

	-- Pick Random Archetype if not specified
	local archetypesList = { "BankHeist", "RooftopDeal", "AlleywayMugging", "GetawayChase" }
	local chosenId = specificArchetypeId or archetypesList[math.random(1, #archetypesList)]
	local archConfig = CrimeConfig.Archetypes[chosenId]
	if not archConfig then return nil end

	local epicenter, moveDir, chosenSpawnPart = CrimeLocationFinder.findCrimeSpawnLocation(chosenId, EnemiesFolder, ActiveCrimesFolder)

	local crimeFolder = Instance.new("Folder")
	crimeFolder.Name = "ActiveCrime_" .. chosenId
	crimeFolder.Parent = ActiveCrimesFolder

	local crimeInstance: ActiveCrimeInstance = {
		Id = chosenId,
		Archetype = archConfig,
		Epicenter = epicenter,
		Folder = crimeFolder,
		State = "Spawned",
		StartTime = os.clock(),
		Enemies = {},
		ParticipatingPlayers = {},
		IsCoOpScaled = false,
	}

	currentActiveCrime = crimeInstance

	-- 1. Generate Props
	if archConfig.InteractiveCrates and archConfig.InteractiveCrates > 0 then
		for i = 1, archConfig.InteractiveCrates do
			local offset = Vector3.new(math.cos(i * 2.1) * 6, 0, math.sin(i * 2.1) * 6)
			CrimeEntityFactory.createMilitaryTechCrate(epicenter + offset, crimeFolder)
		end
	end

	if archConfig.HasCivilian then
		CrimeEntityFactory.createCivilianNPC(epicenter + Vector3.new(2, 0, 2), crimeFolder)
	end

	if archConfig.IsVehicleChase then
		CrimeEntityFactory.createGetawayVan(epicenter, moveDir, crimeFolder)
	end

	-- 2. Spawn Enemies
	for _, entry in archConfig.Enemies do
		for i = 1, entry.Count do
			local spawnPos: Vector3
			if chosenSpawnPart then
				local partSize = chosenSpawnPart.Size
				local radiusX = math.clamp(partSize.X * 0.35, 1.5, 10)
				local radiusZ = math.clamp(partSize.Z * 0.35, 1.5, 10)
				local angle = (i - 1) * (math.pi * 2 / math.max(1, entry.Count))
				local localOffset = Vector3.new(math.cos(angle) * radiusX, 0.5, math.sin(angle) * radiusZ)
				spawnPos = chosenSpawnPart.Position + localOffset
			else
				local offset = Vector3.new(math.cos(i * 1.5) * 8, 0, math.sin(i * 1.5) * 8)
				local candidatePos = epicenter + offset
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { crimeFolder, EnemiesFolder }
				local hit = Workspace:Raycast(candidatePos + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), rayParams)
				spawnPos = hit and (hit.Position + Vector3.new(0, 0.5, 0)) or (candidatePos + Vector3.new(0, 1.0, 0))
			end

			local spawnCF = CFrame.new(spawnPos)
			local enemyName = entry.Archetype == "Gunner" and string.format("%s [Gunner #%d]", archConfig.Title, i)
				or entry.Archetype == "Brute" and string.format("%s [Heavy Enforcer]", archConfig.Title)
				or string.format("%s [Mob #%d]", archConfig.Title, i)

			local enemyModel = CrimeEntityFactory.spawnCrimeEnemy(spawnCF, entry.Archetype, enemyName, 1.0, EnemiesFolder, CombatVFXRemote)
			table.insert(crimeInstance.Enemies, enemyModel)
		end
	end

	-- 3. Broadcast Atmospheric Police Dispatch to All Players
	CrimeNotificationRemote:FireAllClients("CrimeSpawned", {
		Id = chosenId,
		Title = archConfig.Title,
		PoliceCode = archConfig.PoliceCode,
		DispatchMessage = archConfig.DispatchMessage,
		Icon = archConfig.Icon,
		Epicenter = epicenter,
		ThemeColor = archConfig.ThemeColor,
		Timeout = CrimeConfig.Scheduler.CrimeTimeout,
	})

	return crimeInstance
end

-- 🎉 Clear Active Crime & Distribute Hero Rewards
local function clearActiveCrime(crimeInstance: ActiveCrimeInstance)
	if crimeInstance.State == "Cleared" or crimeInstance.State == "Failed" then return end
	crimeInstance.State = "Cleared"
	lastCrimeEndTime = os.clock()

	-- Co-Op Multiplier Calculation
	local participantCount = 0
	for _ in crimeInstance.ParticipatingPlayers do
		participantCount += 1
	end

	local rewardMultiplier = 1.0
	if participantCount > 1 then
		rewardMultiplier += ((participantCount - 1) * (CrimeConfig.CoOp.BonusRewardPerPlayer or 0.25))
	end

	local finalXP = math.floor(crimeInstance.Archetype.RewardXP * rewardMultiplier)
	local finalCash = math.floor(crimeInstance.Archetype.RewardCash * rewardMultiplier)

	-- Award to all participating Spider-Heroes
	for player in crimeInstance.ParticipatingPlayers do
		PlayerProgression.awardPlayerRewards(player, finalXP, finalCash, CrimeNotificationRemote)
	end

	-- If no participants tracked yet (e.g. killed from afar), award nearest player
	if participantCount == 0 then
		for _, player in Players:GetPlayers() do
			local pRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if pRoot and (pRoot.Position - crimeInstance.Epicenter).Magnitude <= (CrimeConfig.CoOp.ProximityRadius or 120) then
				PlayerProgression.awardPlayerRewards(player, finalXP, finalCash, CrimeNotificationRemote)
				break
			end
		end
	end

	-- Broadcast Victory Screen
	CrimeNotificationRemote:FireAllClients("CrimeCleared", {
		Id = crimeInstance.Id,
		Title = crimeInstance.Archetype.Title,
		RewardXP = finalXP,
		RewardCash = finalCash,
		ParticipantCount = math.max(1, participantCount),
	})

	-- Cleanup after delay (Destroys folder and any remaining enemy instances)
	task.delay(CrimeConfig.Scheduler.DespawnCleanupDelay or 5.0, function()
		for _, enemy in crimeInstance.Enemies do
			if enemy and enemy.Parent then
				enemy:Destroy()
			end
		end
		if crimeInstance.Folder then
			crimeInstance.Folder:Destroy()
		end
		if currentActiveCrime == crimeInstance then
			currentActiveCrime = nil
		end
	end)
end

-- ❌ Fail Active Crime (Timeout or Civilian defeated)
local function failActiveCrime(crimeInstance: ActiveCrimeInstance, reason: string)
	if crimeInstance.State == "Cleared" or crimeInstance.State == "Failed" then return end
	crimeInstance.State = "Failed"
	lastCrimeEndTime = os.clock()

	CrimeNotificationRemote:FireAllClients("CrimeFailed", {
		Id = crimeInstance.Id,
		Title = crimeInstance.Archetype.Title,
		Reason = reason,
	})

	task.delay(CrimeConfig.Scheduler.DespawnCleanupDelay or 5.0, function()
		for _, enemy in crimeInstance.Enemies do
			if enemy and enemy.Parent then
				enemy:Destroy()
			end
		end
		if crimeInstance.Folder then
			crimeInstance.Folder:Destroy()
		end
		if currentActiveCrime == crimeInstance then
			currentActiveCrime = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- 🔄 MAIN CRIME SERVICE SCHEDULER HEARTBEAT
--------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function()
	local now = os.clock()

	-- 1. Crime Lifecycle Monitor
	if currentActiveCrime ~= nil then
		local crime = currentActiveCrime
		local elapsed = now - crime.StartTime

		-- Check Timeout
		if elapsed > (CrimeConfig.Scheduler.CrimeTimeout or 240) then
			failActiveCrime(crime, "Suspects Escaped")
			return
		end

		-- Track Players in Range & Update State
		local nearbyPlayers: { Player } = {}
		for _, player in Players:GetPlayers() do
			local pChar = player.Character
			local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			local pHum = pChar and pChar:FindFirstChildOfClass("Humanoid")
			if pRoot and pHum and pHum.Health > 0 then
				local dist = (pRoot.Position - crime.Epicenter).Magnitude
				if dist <= (CrimeConfig.CoOp.ProximityRadius or 120) then
					table.insert(nearbyPlayers, player)
					crime.ParticipatingPlayers[player] = true
				end
			end
		end

		if #nearbyPlayers > 0 and crime.State == "Spawned" then
			crime.State = "InProgress"
			CrimeNotificationRemote:FireAllClients("CrimeInProgress", crime.Id)
		end

		-- Co-Op Wave Scaling (Spawn reinforcements if multi-hero presence detected)
		if #nearbyPlayers >= (CrimeConfig.CoOp.MinPlayersForScale or 2) and not crime.IsCoOpScaled then
			crime.IsCoOpScaled = true
			local extraCount = (#nearbyPlayers - 1) * (CrimeConfig.CoOp.ExtraBrawlersPerPlayer or 1)
			for i = 1, extraCount do
				local offset = Vector3.new(math.cos(i * 2) * 14, 0, math.sin(i * 2) * 14)
				local enemyModel = CrimeEntityFactory.spawnCrimeEnemy(CFrame.new(crime.Epicenter + offset), "Brawler", string.format("Backup Mob #%d", i), 1.25, EnemiesFolder, CombatVFXRemote)
				table.insert(crime.Enemies, enemyModel)
			end
			CrimeNotificationRemote:FireAllClients("CoOpScaleActive", #nearbyPlayers)
		end

		-- Check if all enemies defeated
		local livingEnemies = 0
		for _, enemy in crime.Enemies do
			if enemy.Parent then
				local hum = enemy:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					livingEnemies += 1
				end
			end
		end

		-- Check for getaway van enemies if van was disabled
		for _, descendant in EnemiesFolder:GetChildren() do
			if descendant:IsA("Model") and descendant:GetAttribute("IsCrimeEnemy") == true then
				local hum = descendant:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and not table.find(crime.Enemies, descendant) then
					table.insert(crime.Enemies, descendant)
					livingEnemies += 1
				end
			end
		end

		-- Auto-clear crime when all enemies are defeated (auto-disables getaway vehicle if present)
		if livingEnemies == 0 and (elapsed > 1.5) and (crime.State == "InProgress" or #crime.Enemies > 0) then
			local van = crime.Folder:FindFirstChild("ArmoredGetawayVan")
			if van and van:GetAttribute("IsDisabled") ~= true then
				van:SetAttribute("IsDisabled", true)
			end
			clearActiveCrime(crime)
		end

	-- 2. Periodic Crime Dispatch Scheduler
	else
		local cooldown = CrimeConfig.Scheduler.PostClearCooldown or 8
		if (now - lastCrimeEndTime) > cooldown then
			local nextInterval = math.random(CrimeConfig.Scheduler.SpawnIntervalMin or 25, CrimeConfig.Scheduler.SpawnIntervalMax or 45)
			if (now - lastCrimeEndTime) > (cooldown + nextInterval) and #Players:GetPlayers() > 0 then
				spawnProceduralCrime()
			end
		end
	end
end)

-- 📱 FNSM Scanner & Datapad Remote Invocations
GetActiveCrimesRF.OnServerInvoke = function(_player: Player): any
	if currentActiveCrime ~= nil then
		return {
			Id = currentActiveCrime.Id,
			Title = currentActiveCrime.Archetype.Title,
			PoliceCode = currentActiveCrime.Archetype.PoliceCode,
			Icon = currentActiveCrime.Archetype.Icon,
			Epicenter = currentActiveCrime.Epicenter,
			ThemeColor = currentActiveCrime.Archetype.ThemeColor,
			RewardXP = currentActiveCrime.Archetype.RewardXP,
			RewardCash = currentActiveCrime.Archetype.RewardCash,
			State = currentActiveCrime.State,
			District = "Midtown Manhattan",
		}
	end
	return nil
end

-- 🎮 On-Demand Police Dispatch & Crime Interaction
CrimeInteractRemote.OnServerEvent:Connect(function(_player: Player, action: string, param: any)
	if action == "RequestDispatch" or action == "RequestCrime" then
		if currentActiveCrime == nil then
			local specificArchetype = typeof(param) == "string" and param or nil
			spawnProceduralCrime(specificArchetype)
		end
	end
end)

-- Spawn first crime after initial warmup
task.delay(6.0, function()
	if currentActiveCrime == nil and #Players:GetPlayers() > 0 then
		spawnProceduralCrime()
	end
end)
