--!strict
--[[
	PlayerProgression.luau
	Authoritative player economy, level caps, XP curves, Hero Cash, and chat commands.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrimeConfig = require(Shared:WaitForChild("CrimeConfig"))

local PlayerProgression = {}

function PlayerProgression.setupPlayerLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local levelVal = Instance.new("IntValue")
	levelVal.Name = "Level"
	levelVal.Value = CrimeConfig.Economy.DefaultLevel or 1
	levelVal.Parent = leaderstats

	local xpVal = Instance.new("IntValue")
	xpVal.Name = "XP"
	xpVal.Value = 0
	xpVal.Parent = leaderstats

	local cashVal = Instance.new("IntValue")
	cashVal.Name = "Hero Cash"
	cashVal.Value = CrimeConfig.Economy.DefaultCash or 100
	cashVal.Parent = leaderstats

	local crimesVal = Instance.new("IntValue")
	crimesVal.Name = "Crimes Stopped"
	crimesVal.Value = 0
	crimesVal.Parent = leaderstats
end

-- 🩸 Dynamic Health Scaling (+10 HP per Level + Suit Defense Perks)
function PlayerProgression.updatePlayerHealth(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local leaderstats = player:FindFirstChild("leaderstats")
	local levelVal = leaderstats and leaderstats:FindFirstChild("Level") :: IntValue?
	if hum and levelVal then
		local suitBonus = 0
		local suitPerkType = player:GetAttribute("SuitPerkType")
		local suitPerkValue = player:GetAttribute("SuitPerkValue")
		if suitPerkType == "Defense" and typeof(suitPerkValue) == "number" then
			suitBonus = suitPerkValue
		end
		local targetMax = 100 + (levelVal.Value - 1) * 10 + suitBonus
		local diff = targetMax - hum.MaxHealth
		hum.MaxHealth = targetMax
		if diff > 0 then
			hum.Health = math.clamp(hum.Health + diff, 0, targetMax)
		end
	end
end

-- ⚡ Instant Debug Chat Command (/levelup and /cash)
function PlayerProgression.setupPlayerChatCommands(player: Player, crimeNotificationRemote: RemoteEvent)
	player.Chatted:Connect(function(message: string)
		local cleaned = string.lower(string.match(message, "^%s*(.-)%s*$") or "")
		if cleaned == "/levelup" then
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end

			local levelVal = leaderstats:FindFirstChild("Level") :: IntValue?
			local xpVal = leaderstats:FindFirstChild("XP") :: IntValue?
			if not levelVal or not xpVal then return end

			local currentLvl = levelVal.Value
			if currentLvl < 6 then
				local baseXP = math.max(1, CrimeConfig.Economy.BaseXPForLevel or 150)
				local scale = math.max(1.0, CrimeConfig.Economy.LevelScaleFactor or 1.20)
				local requiredXP = math.max(1, math.floor(baseXP * (currentLvl ^ scale)))
				local addXP = math.max(150, requiredXP - xpVal.Value)
				xpVal.Value += addXP

				while xpVal.Value >= requiredXP and levelVal.Value < 6 do
					xpVal.Value -= requiredXP
					levelVal.Value += 1
					crimeNotificationRemote:FireClient(player, "LevelUp", levelVal.Value)

					PlayerProgression.updatePlayerHealth(player)

					currentLvl = levelVal.Value
					if currentLvl >= 6 then
						xpVal.Value = 0
						break
					end
					requiredXP = math.max(1, math.floor(baseXP * (currentLvl ^ scale)))
				end
			end
		elseif cleaned == "/cash" or cleaned == "/addcash" then
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end
			local cashVal = leaderstats:FindFirstChild("Hero Cash") :: IntValue?
			if cashVal then
				cashVal.Value += 5000
			end
		end
	end)
end

-- 💰 Award XP & Hero Cash with Level 6 Hard Cap & Scaled Progression
function PlayerProgression.awardPlayerRewards(player: Player, xpAmount: number, cashAmount: number, crimeNotificationRemote: RemoteEvent)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local levelVal = leaderstats:FindFirstChild("Level") :: IntValue?
	local xpVal = leaderstats:FindFirstChild("XP") :: IntValue?
	local cashVal = leaderstats:FindFirstChild("Hero Cash") :: IntValue?
	local crimesVal = leaderstats:FindFirstChild("Crimes Stopped") :: IntValue?

	if xpVal and cashVal and levelVal then
		local currentLvl = levelVal.Value
		if currentLvl < 6 then
			xpVal.Value += xpAmount
		else
			xpVal.Value = 0
		end
		cashVal.Value += cashAmount
		if crimesVal then crimesVal.Value += 1 end

		if currentLvl < 6 then
			local baseXP = math.max(1, CrimeConfig.Economy.BaseXPForLevel or 150)
			local scale = math.max(1.0, CrimeConfig.Economy.LevelScaleFactor or 1.20)
			local requiredXP = math.max(1, math.floor(baseXP * (currentLvl ^ scale)))

			while xpVal.Value >= requiredXP and levelVal.Value < 6 do
				xpVal.Value -= requiredXP
				levelVal.Value += 1
				crimeNotificationRemote:FireClient(player, "LevelUp", levelVal.Value)

				PlayerProgression.updatePlayerHealth(player)

				currentLvl = levelVal.Value
				if currentLvl >= 6 then
					xpVal.Value = 0
					break
				end
				requiredXP = math.max(1, math.floor(baseXP * (currentLvl ^ scale)))
			end
		end
	end
end

return PlayerProgression
