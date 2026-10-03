--!strict
--[[
	CombatUltimate.luau
	Phase 5: Continuous Multi-Hit AoE DPS 360° Web Cyclone (T Key) + Quick-Heal (H Key).
	- 🌪️ 360° Web Cyclone: Grabs enemy with dual web tethers, continuously spins them in a
	  high-speed human wrecking-ball blender dealing multi-hit DPS every 0.20s across 14.5 studs,
	  and hurls them at 135 studs/s into a skyscraper wall with an automatic web matrix snap!
	- 💚 Quick-Heal: Restores +35 HP with bio-web nano particles on a 20s cooldown.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local ModulesFolder = script.Parent
local CombatReticle = require(ModulesFolder:WaitForChild("CombatReticle"))
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))
local CombatStyleHUD = require(ModulesFolder:WaitForChild("CombatStyleHUD"))

local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local WebCycloneRemote = RemotesFolder:WaitForChild("WebCycloneRemote") :: RemoteEvent

local CombatUltimate = {
	isExecutingUltimate = false,
	isUlting = false,
	lastCycloneTime = 0,
}

-- 🌪️ Perform 360° Web Cyclone Continuous DPS Blender (T Key)
function CombatUltimate.performWebCyclone(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera)
	local now = os.clock()
	local cooldown = 15.0
	if CombatUltimate.isExecutingUltimate or (now - CombatUltimate.lastCycloneTime) < cooldown then return end

	-- 🛡️ Level Gate Check: Web Cyclone requires Level 2+ (or Studio testing)
	local LocalPlayer = Players.LocalPlayer
	local leaderstats = LocalPlayer and LocalPlayer:FindFirstChild("leaderstats")
	local playerLevel = leaderstats and leaderstats:FindFirstChild("Level") and (leaderstats.Level :: IntValue).Value or 1
	if playerLevel < 2 and not RunService:IsStudio() then return end

	-- Find primary target to spin: Active Reticle Target OR Fallback Camera Cone Sweep
	local target = CombatReticle.getCurrentTarget()
	if not target then
		local enemies = CollectionService:GetTagged("Enemy")
		local camCFrame = camera.CFrame
		local bestDist = 45
		for _, enemy in enemies do
			if enemy:IsA("Model") then
				local eHum = enemy:FindFirstChildOfClass("Humanoid")
				local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				if eHum and eHum.Health > 0 and eRoot then
					local offset = eRoot.Position - rootPart.Position
					local d = offset.Magnitude
					if d <= 45 and d < bestDist then
						local toEnemy = (eRoot.Position - camCFrame.Position).Unit
						local dot = camCFrame.LookVector:Dot(toEnemy)
						if dot > 0.35 then
							target = enemy
							bestDist = d
						end
					end
				end
			end
		end
	end

	if not target then return end

	local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
	local targetHum = target:FindFirstChildOfClass("Humanoid")
	if not targetRoot or not targetHum or targetHum.Health <= 0 then return end

	CombatUltimate.lastCycloneTime = now
	CombatUltimate.isExecutingUltimate = true
	CombatUltimate.isUlting = true
	CombatStyleHUD.setCooldown("WebCyclone", cooldown)

	local is2099 = (LocalPlayer and LocalPlayer:GetAttribute("EquippedSuit") == "Cyber2099")
		or (character and character:GetAttribute("EquippedSuit") == "Cyber2099")
	local isAcrobatic = is2099 or (LocalPlayer and LocalPlayer:GetAttribute("SuitPerkType") == "Acrobatic")
	local centerPos = rootPart.Position
	local spinDuration = 2.4
	local spinRadius = if isAcrobatic then 12.35 else 9.5
	local startTime = os.clock()
	local lastTickTime = 0

	-- Spawn Dual Web Lines
	local leftHand = WebVisuals.getHandAttachment(character, false)
	local rightHand = WebVisuals.getHandAttachment(character, true)

	local webTether1 = Instance.new("Part")
	webTether1.Name = "CycloneWeb1"
	webTether1.Material = Enum.Material.Neon
	webTether1.Color = if is2099 then Color3.fromRGB(255, 45, 80) else Color3.fromRGB(245, 248, 255)
	webTether1.Transparency = 0.15
	webTether1.CanCollide = false
	webTether1.Anchored = true
	webTether1.Size = Vector3.new(0.16, 0.16, 1)
	webTether1.Parent = Workspace

	local webTether2 = webTether1:Clone()
	webTether2.Name = "CycloneWeb2"
	webTether2.Parent = Workspace

	-- Continuous Rotating Tornado Visual Ring
	local vortex = Instance.new("Part")
	vortex.Name = "CycloneVortexRing"
	vortex.Shape = Enum.PartType.Cylinder
	vortex.Size = Vector3.new(0.3, 3, 3)
	vortex.Material = Enum.Material.Neon
	vortex.Color = if is2099 then Color3.fromRGB(255, 45, 80) else Color3.fromRGB(85, 235, 255)
	vortex.Transparency = 0.35
	vortex.CanCollide = false
	vortex.Anchored = true
	vortex.CFrame = CFrame.new(centerPos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	vortex.Parent = Workspace

	local vortexEndDiameter = if isAcrobatic then 37.7 else 30
	local vortexTween = TweenService:Create(vortex, TweenInfo.new(spinDuration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.3, vortexEndDiameter, vortexEndDiameter),
		Transparency = 0.8,
	})
	vortexTween:Play()

	-- 🤖 2099 Cyber Suit: Concentric Cyan Geometric Holographic Ring
	local cyberRing: Part? = nil
	if is2099 then
		cyberRing = Instance.new("Part")
		cyberRing.Name = "CycloneCyberRing"
		cyberRing.Shape = Enum.PartType.Cylinder
		cyberRing.Size = Vector3.new(0.2, 3.5, 3.5)
		cyberRing.Material = Enum.Material.Neon
		cyberRing.Color = Color3.fromRGB(45, 220, 255)
		cyberRing.Transparency = 0.4
		cyberRing.CanCollide = false
		cyberRing.Anchored = true
		cyberRing.CFrame = CFrame.new(centerPos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		cyberRing.Parent = Workspace

		local ringTween = TweenService:Create(cyberRing, TweenInfo.new(spinDuration, Enum.EasingStyle.Linear), {
			Size = Vector3.new(0.2, 38, 38),
			Transparency = 0.85,
		})
		ringTween:Play()
	end

	-- 🔄 Centrifugal 360° Continuous DPS Spin Loop
	local spinConnection: RBXScriptConnection?
	local function cleanupVFX()
		if spinConnection then spinConnection:Disconnect() end
		if webTether1 and webTether1.Parent then webTether1:Destroy() end
		if webTether2 and webTether2.Parent then webTether2:Destroy() end
		if vortex and vortex.Parent then vortex:Destroy() end
		if cyberRing and cyberRing.Parent then cyberRing:Destroy() end
		CombatUltimate.isExecutingUltimate = false
		CombatUltimate.isUlting = false
	end

	spinConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= spinDuration or not character.Parent or not target.Parent or humanoid.Health <= 0 then
			cleanupVFX()

			-- Final Centrifugal Launch into Wall
			local finalLook = camera.CFrame.LookVector
			WebCycloneRemote:FireServer("ThrowTarget", target, finalLook)
			WebVisuals.createMeleeHitSparks(targetRoot.Position, true)
			return
		end

		-- High speed angular rotation: 3.5 full 360° spins per second
		local angle = elapsed * (math.pi * 7)
		local currentRadius = math.min(spinRadius, 3 + (elapsed * 4.5))
		local targetOffset = Vector3.new(math.cos(angle) * currentRadius, 0.6, math.sin(angle) * currentRadius)
		local currentTargetPos = centerPos + targetOffset

		-- Orient player and target
		rootPart.CFrame = CFrame.lookAt(centerPos, currentTargetPos)
		targetRoot.CFrame = CFrame.lookAt(currentTargetPos, centerPos) * CFrame.Angles(math.rad(55), 0, 0)

		-- Update web tethers
		local lPos = leftHand.WorldPosition
		local rPos = rightHand.WorldPosition
		local tPos = targetRoot.Position

		local dist1 = (tPos - lPos).Magnitude
		webTether1.Size = Vector3.new(0.16, 0.16, math.max(0.2, dist1))
		webTether1.CFrame = CFrame.lookAt((lPos + tPos) / 2, tPos)

		local dist2 = (tPos - rPos).Magnitude
		webTether2.Size = Vector3.new(0.16, 0.16, math.max(0.2, dist2))
		webTether2.CFrame = CFrame.lookAt((rPos + tPos) / 2, tPos)

		-- 💥 CONTINUOUS AoE DPS TICK: Smashes mobs every 0.20s with rapid hit sparks
		if (elapsed - lastTickTime) >= 0.20 then
			lastTickTime = elapsed
			WebCycloneRemote:FireServer("CycloneTick", target)
			WebVisuals.createMeleeHitSparks(currentTargetPos, false)
			WebVisuals.createWeaponImpactSparks(centerPos, Vector3.new(0, 1, 0))
		end
	end)
end



return CombatUltimate
