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
local QuickHealRemote = RemotesFolder:WaitForChild("QuickHealRemote") :: RemoteEvent

local CombatUltimate = {
	isExecutingUltimate = false,
	lastCycloneTime = 0,
	lastHealTime = 0,
}

-- 🌪️ Perform 360° Web Cyclone Continuous DPS Blender (T Key)
function CombatUltimate.performWebCyclone(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera)
	local now = os.clock()
	local cooldown = 15.0
	if CombatUltimate.isExecutingUltimate or (now - CombatUltimate.lastCycloneTime) < cooldown then return end

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
	CombatStyleHUD.setCooldown("WebCyclone", cooldown)

	local centerPos = rootPart.Position
	local spinDuration = 2.4
	local spinRadius = 9.5
	local startTime = os.clock()
	local lastTickTime = 0

	-- Spawn Dual Web Lines
	local leftHand = WebVisuals.getHandAttachment(character, false)
	local rightHand = WebVisuals.getHandAttachment(character, true)

	local webTether1 = Instance.new("Part")
	webTether1.Name = "CycloneWeb1"
	webTether1.Material = Enum.Material.Neon
	webTether1.Color = Color3.fromRGB(245, 248, 255)
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
	vortex.Color = Color3.fromRGB(85, 235, 255)
	vortex.Transparency = 0.35
	vortex.CanCollide = false
	vortex.Anchored = true
	vortex.CFrame = CFrame.new(centerPos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	vortex.Parent = Workspace

	local vortexTween = TweenService:Create(vortex, TweenInfo.new(spinDuration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.3, 30, 30),
		Transparency = 0.8,
	})
	vortexTween:Play()

	-- 🔄 Centrifugal 360° Continuous DPS Spin Loop
	local spinConnection: RBXScriptConnection?
	local function cleanupVFX()
		if spinConnection then spinConnection:Disconnect() end
		if webTether1 and webTether1.Parent then webTether1:Destroy() end
		if webTether2 and webTether2.Parent then webTether2:Destroy() end
		if vortex and vortex.Parent then vortex:Destroy() end
		CombatUltimate.isExecutingUltimate = false
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

-- 💚 Perform Quick-Heal (H Key - 20s Cooldown)
function CombatUltimate.performQuickHeal(character: Model, rootPart: BasePart, humanoid: Humanoid)
	local now = os.clock()
	local cooldown = 20.0
	if (now - CombatUltimate.lastHealTime) < cooldown then return end
	if humanoid.Health >= humanoid.MaxHealth then return end

	CombatUltimate.lastHealTime = now
	CombatStyleHUD.setCooldown("QuickHeal", cooldown)
	QuickHealRemote:FireServer(35)

	-- Green Bio-Web Nano Healing Pulse VFX
	local healRing = Instance.new("Part")
	healRing.Shape = Enum.PartType.Cylinder
	healRing.Size = Vector3.new(0.3, 2, 2)
	healRing.Material = Enum.Material.Neon
	healRing.Color = Color3.fromRGB(75, 255, 150)
	healRing.Transparency = 0.2
	healRing.CanCollide = false
	healRing.Anchored = true
	healRing.CFrame = CFrame.new(rootPart.Position - Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	healRing.Parent = Workspace

	local tween = TweenService:Create(healRing, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 14, 14),
		CFrame = healRing.CFrame + Vector3.new(0, 3.5, 0),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(healRing, 0.5)

	WebVisuals.playWebSound(rootPart)
end

return CombatUltimate
