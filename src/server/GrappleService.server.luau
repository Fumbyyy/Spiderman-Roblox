local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GrappleConfig = require(Shared:WaitForChild("GrappleConfig"))

-- Ensure Remotes Folder exists in ReplicatedStorage
local RemotesFolder = ReplicatedStorage:FindFirstChild("GrappleRemotes")
if not RemotesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "GrappleRemotes"
	folder.Parent = ReplicatedStorage
	RemotesFolder = folder
end

-- Helper: Get or create RemoteEvent
local function getOrCreateRemote(name: string): RemoteEvent
	local remote = RemotesFolder:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteEvent") then
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = name
		newRemote.Parent = RemotesFolder
		return newRemote
	end
	return remote
end

local GrappleStartRemote = getOrCreateRemote("GrappleStart")
local GrappleEndRemote = getOrCreateRemote("GrappleEnd")

-- Server-side tracking to prevent spam or client-side exploits
local activeGrapples: { [Player]: { HookPosition: Vector3, StartTime: number } } = {}

-- Player shoots a web
GrappleStartRemote.OnServerEvent:Connect(function(player: Player, hookPosition: any, isRightHand: any)
	-- Type Validation
	if typeof(hookPosition) ~= "Vector3" then
		return
	end
	local isRight: boolean = if typeof(isRightHand) == "boolean" then isRightHand else false

	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Distance validation (allow extra margin for ping/network latency)
	local distance = (hookPosition - rootPart.Position).Magnitude
	local maxAllowed = GrappleConfig.Targeting.MaxDistance + 50
	if distance > maxAllowed then
		warn(string.format("[GrappleService] Anti-Cheat: %s web distance (%.1f) exceeded max (%.1f)", player.Name, distance, maxAllowed))
		return
	end

	activeGrapples[player] = {
		HookPosition = hookPosition,
		StartTime = os.clock(),
	}

	-- Replicate web line visual to all OTHER players
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			GrappleStartRemote:FireClient(otherPlayer, player, hookPosition, isRight)
		end
	end
end)

-- Player releases web
GrappleEndRemote.OnServerEvent:Connect(function(player: Player)
	if activeGrapples[player] then
		activeGrapples[player] = nil
	end

	-- Tell other players to remove web visual for this player
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			GrappleEndRemote:FireClient(otherPlayer, player)
		end
	end
end)

-- Cleanup when player leaves the server
Players.PlayerRemoving:Connect(function(player: Player)
	if activeGrapples[player] then
		activeGrapples[player] = nil
		for _, otherPlayer in Players:GetPlayers() do
			GrappleEndRemote:FireClient(otherPlayer, player)
		end
	end
end)

