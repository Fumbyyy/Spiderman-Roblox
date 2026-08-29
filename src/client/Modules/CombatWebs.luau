--!strict
--[[
	CombatWebs.luau
	Handles all Spider-Man tactical web-based combat moves:
	1. 🕸️ Rapid Web-Pellets & Wall-Pinning (E Key)
	2. 🔫 Web-Yank Disarm & Weapon Throw (Q Key)
	3. 🚀 Web-Strike Zip Kick (R Key)
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local RemotesFolder = ReplicatedStorage:WaitForChild("CombatRemotes")

local WebPelletRemote = RemotesFolder:WaitForChild("WebPellet") :: RemoteEvent
local DisarmThrowRemote = RemotesFolder:WaitForChild("DisarmAndThrow") :: RemoteEvent
local WebStrikeRemote = RemotesFolder:WaitForChild("WebStrike") :: RemoteEvent

local ModulesFolder = script.Parent
local CombatReticle = require(ModulesFolder:WaitForChild("CombatReticle"))
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))

local CombatWebs = {}

-- State
CombatWebs.lastWebPelletTime = 0
CombatWebs.lastDisarmTime = 0
CombatWebs.lastWebStrikeTime = 0
CombatWebs.isHoldingWebPellet = false
CombatWebs.isWebStriking = false
CombatWebs.isRightHandWeb = false

-- ✨ Create temporary visual combat web beams between character and target
function CombatWebs.createCombatWebLines(sourceModel: Model, targetModel: Model, dualWebs: boolean, duration: number)
	local sourceRoot = sourceModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso") or targetModel:FindFirstChild("Head")) :: BasePart?
	if not sourceRoot or not targetRoot then return end

	local targetAtt = targetRoot:FindFirstChild("CombatTargetAtt") :: Attachment?
	if not targetAtt then
		targetAtt = Instance.new("Attachment")
		targetAtt.Name = "CombatTargetAtt"
		targetAtt.Parent = targetRoot
	end

	local leftAtt = WebVisuals.getHandAttachment(sourceModel, false)
	local rightAtt = WebVisuals.getHandAttachment(sourceModel, true)

	local beamRight = WebVisuals.createWebBeam(rightAtt, targetAtt, sourceRoot)
	local beamLeft: Beam? = nil

	if dualWebs then
		beamLeft = WebVisuals.createWebBeam(leftAtt, targetAtt, sourceRoot)
	end

	WebVisuals.playWebSound(sourceRoot)

	task.delay(duration, function()
		if beamRight then beamRight:Destroy() end
		if beamLeft then beamLeft:Destroy() end
	end)
end

-- 1. 🕸️ RAPID WEB-PELLETS (E Key)
function CombatWebs.performWebPellet(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera, isHoldingAttack: boolean, lastMeleeActionTime: number)
	local now = os.clock()
	local cooldown = CombatConfig.Moves.WebPellet.Cooldown or 0.32
	if (now - CombatWebs.lastWebPelletTime) < cooldown then return end

	-- Action Exclusivity: Cannot shoot webs while punching
	if isHoldingAttack or (now - lastMeleeActionTime) < 0.22 then return end

	-- Target must be locked in reticle
	local target = CombatReticle.getCurrentTarget()
	if not target then return end

	local maxDist = CombatConfig.Moves.WebPellet.MaxDistance or 50
	local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
	if not targetRoot or (targetRoot.Position - rootPart.Position).Magnitude > maxDist then return end

	CombatWebs.lastWebPelletTime = now
	CombatWebs.isRightHandWeb = not CombatWebs.isRightHandWeb

	local handAtt = WebVisuals.getHandAttachment(character, CombatWebs.isRightHandWeb)
	local targetWorldPos = targetRoot.Position + Vector3.new(0, 0.4, 0)

	WebPelletRemote:FireServer(target)
	WebVisuals.launchWebPelletProjectile(handAtt, targetWorldPos)
	WebVisuals.playWebSound(rootPart)

	-- Tactile micro camera recoil
	camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(0.18), (CombatWebs.isRightHandWeb and math.rad(-0.12) or math.rad(0.12)), 0)
end

-- 2. 🔫 WEB-YANK DISARM & WEAPON THROW (Q / Smart E Key)
function CombatWebs.performWebDisarm(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera, isHoldingAttack: boolean, lastMeleeActionTime: number)
	local now = os.clock()
	local cooldown = CombatConfig.Moves.DisarmAndThrow.Cooldown or 2.5
	if (now - CombatWebs.lastDisarmTime) < cooldown then return end

	if isHoldingAttack or (now - lastMeleeActionTime) < 0.22 then return end

	-- 1. Find Target: Active Reticle Target OR Fallback Camera Cone Sweep for Armed Gunners (Up to 55 studs)
	local target = CombatReticle.getCurrentTarget()
	local isTargetArmed = target and ((target:GetAttribute("IsArmed") == true) or (target:FindFirstChild("Gun") ~= nil))

	if not isTargetArmed then
		local enemies = CollectionService:GetTagged("Enemy")
		local camCFrame = camera.CFrame
		local bestDist = 55
		for _, enemy in enemies do
			if enemy:IsA("Model") and ((enemy:GetAttribute("IsArmed") == true) or (enemy:FindFirstChild("Gun") ~= nil)) then
				local eHum = enemy:FindFirstChildOfClass("Humanoid")
				local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				if eHum and eHum.Health > 0 and eRoot then
					local offset = eRoot.Position - rootPart.Position
					local d = offset.Magnitude
					if d <= 55 and d < bestDist then
						local toEnemy = (eRoot.Position - camCFrame.Position).Unit
						local dot = camCFrame.LookVector:Dot(toEnemy)
						if dot > 0.40 then
							target = enemy
							bestDist = d
						end
					end
				end
			end
		end
	end

	if not target then return end

	local isArmed = (target:GetAttribute("IsArmed") == true) or (target:FindFirstChild("Gun") ~= nil)
	if not isArmed then return end

	local maxDist = CombatConfig.Moves.DisarmAndThrow.MaxDistance or 50
	local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
	if not targetRoot or (targetRoot.Position - rootPart.Position).Magnitude > (maxDist + 5) then return end

	CombatWebs.lastDisarmTime = now
	CombatWebs.isHoldingWebPellet = false

	-- Athletic Web-Snatch Torso Hop
	local toEnemy = (targetRoot.Position - rootPart.Position).Unit
	local flatToEnemy = Vector3.new(toEnemy.X, 0, toEnemy.Z).Unit
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatToEnemy)
	rootPart.AssemblyLinearVelocity = (-flatToEnemy * 6) + Vector3.new(0, 5.5, 0)

	DisarmThrowRemote:FireServer(target)
	WebVisuals.playWebSound(rootPart)

	-- Camera tension pulse
	local camTweenIn = TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = 74,
	})
	camTweenIn:Play()

	task.delay(0.24, function()
		local camTweenOut = TweenService:Create(camera, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			FieldOfView = 70,
		})
		camTweenOut:Play()
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(0.40), 0, 0)
	end)
end

-- 🕸️ 3. CONTEXTUAL SMART WEB GADGET (E Key)
-- Automatically executes Web-Disarm if target is holding a gun or an armed sniper is aiming in view, or fires Rapid Web-Pellets!
function CombatWebs.performSmartWebGadget(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera, isHoldingAttack: boolean, lastMeleeActionTime: number)
	local target = CombatReticle.getCurrentTarget()

	-- Check if there is an active armed sniper aiming in view that should take priority for Disarm
	local armedThreat: Model? = nil
	local enemies = CollectionService:GetTagged("Enemy")
	local camCFrame = camera.CFrame

	for _, enemy in enemies do
		if enemy:IsA("Model") and ((enemy:GetAttribute("IsArmed") == true) or (enemy:FindFirstChild("Gun") ~= nil)) then
			local eHum = enemy:FindFirstChildOfClass("Humanoid")
			local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
			if eHum and eHum.Health > 0 and eRoot then
				local d = (eRoot.Position - rootPart.Position).Magnitude
				if d <= 55 then
					local toEnemy = (eRoot.Position - camCFrame.Position).Unit
					local dot = camCFrame.LookVector:Dot(toEnemy)
					if dot > 0.55 or (enemy:GetAttribute("IsAttacking") == true and dot > 0.35) then
						armedThreat = enemy
						break
					end
				end
			end
		end
	end

	if armedThreat then
		CombatWebs.performWebDisarm(character, rootPart, humanoid, camera, isHoldingAttack, lastMeleeActionTime)
		return
	end

	if target then
		local isArmed = (target:GetAttribute("IsArmed") == true) or (target:FindFirstChild("Gun") ~= nil)
		if isArmed then
			CombatWebs.performWebDisarm(character, rootPart, humanoid, camera, isHoldingAttack, lastMeleeActionTime)
		else
			CombatWebs.performWebPellet(character, rootPart, humanoid, camera, isHoldingAttack, lastMeleeActionTime)
		end
	else
		-- Fallback to WebPellet search
		CombatWebs.performWebPellet(character, rootPart, humanoid, camera, isHoldingAttack, lastMeleeActionTime)
	end
end

-- 4. 🚀 WEB-STRIKE ZIP KICK (R Key)
function CombatWebs.performWebStrike(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera)
	local now = os.clock()
	local cooldown = CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.Cooldown or 2.0
	if CombatWebs.isWebStriking or (now - CombatWebs.lastWebStrikeTime) < cooldown then return end

	-- 1. Find Target: Active Reticle Target OR Fallback Camera Cone Sweep (Up to 65 studs!)
	local target = CombatReticle.getCurrentTarget()
	if not target then
		local enemies = CollectionService:GetTagged("Enemy")
		local camCFrame = camera.CFrame
		local bestDist = 65
		for _, enemy in enemies do
			if enemy:IsA("Model") then
				local eHum = enemy:FindFirstChildOfClass("Humanoid")
				local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
				if eHum and eHum.Health > 0 and eRoot then
					local offset = eRoot.Position - rootPart.Position
					local d = offset.Magnitude
					if d <= 65 and d < bestDist then
						local dot = camCFrame.LookVector:Dot(offset.Unit)
						if dot > 0.60 then
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

	local maxDist = CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.MaxDistance or 65
	local dist = (targetRoot.Position - rootPart.Position).Magnitude
	if dist > maxDist or dist < 2.5 then return end

	CombatWebs.isWebStriking = true
	CombatWebs.lastWebStrikeTime = now
	CombatWebs.isHoldingWebPellet = false

	-- Clean up old movement constraints
	for _, oldLv in rootPart:GetChildren() do
		if oldLv.Name == "WebStrikeLinearVelocity" or oldLv.Name == "DodgeLinearVelocity" then
			oldLv:Destroy()
		end
	end

	-- Shoot twin webs
	CombatWebs.createCombatWebLines(character, target, true, 0.60)
	WebVisuals.playWebSound(rootPart)

	-- Propulsion LinearVelocity
	local att = rootPart:FindFirstChild("WebStrikeAttachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "WebStrikeAttachment"
		att.Parent = rootPart
	end

	local lv = Instance.new("LinearVelocity")
	lv.Name = "WebStrikeLinearVelocity"
	lv.Attachment0 = att
	lv.MaxForce = 350000
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.Parent = rootPart

	local zipSpeed = CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.ZipSpeed or 120
	local originalAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false

	-- FOV speed pull
	local fovTweenIn = TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = 76,
	})
	fovTweenIn:Play()

	local zipStartTime = os.clock()
	local maxZipDuration = 0.65

	-- Hard safety reset timer
	task.delay(0.70, function()
		if lv and lv.Parent then lv:Destroy() end
		if humanoid and humanoid.Parent then humanoid.AutoRotate = originalAutoRotate end
		CombatWebs.isWebStriking = false
	end)

	local zipConn: RBXScriptConnection? = nil
	zipConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - zipStartTime
		if not character.Parent or humanoid.Health <= 0 or not target.Parent or targetHum.Health <= 0 or elapsed >= maxZipDuration then
			if zipConn then zipConn:Disconnect() end
			if lv and lv.Parent then lv:Destroy() end
			if humanoid and humanoid.Parent then humanoid.AutoRotate = originalAutoRotate end
			CombatWebs.isWebStriking = false
			return
		end

		local currentDist = (targetRoot.Position - rootPart.Position).Magnitude
		local zipDir = (targetRoot.Position - rootPart.Position).Unit
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + Vector3.new(zipDir.X, 0, zipDir.Z))
		lv.VectorVelocity = zipDir * zipSpeed

		-- 💥 Impact Threshold: Reach target OR any intervening mob in the cluster!
		local hitCandidate: Model? = nil
		if currentDist <= 5.5 then
			hitCandidate = target
		else
			local enemies = CollectionService:GetTagged("Enemy")
			for _, enemy in enemies do
				if enemy:IsA("Model") then
					local eHum = enemy:FindFirstChildOfClass("Humanoid")
					local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
					if eHum and eHum.Health > 0 and eRoot then
						local d = (eRoot.Position - rootPart.Position).Magnitude
						if d <= 4.8 then
							hitCandidate = enemy
							break
						end
					end
				end
			end
		end

		if hitCandidate then
			if zipConn then zipConn:Disconnect() end
			if lv and lv.Parent then lv:Destroy() end
			if humanoid and humanoid.Parent then humanoid.AutoRotate = originalAutoRotate end

			local hitRoot = (hitCandidate:FindFirstChild("HumanoidRootPart") or hitCandidate:FindFirstChild("Torso")) :: BasePart? or targetRoot
			local impactDir = (hitRoot.Position - rootPart.Position).Unit
			local flatZipDir = Vector3.new(impactDir.X, 0, impactDir.Z)

			if flatZipDir.Magnitude > 0.1 then
				flatZipDir = flatZipDir.Unit
				local strikePos = hitRoot.Position - (flatZipDir * 4.2)
				rootPart.CFrame = CFrame.lookAt(Vector3.new(strikePos.X, rootPart.Position.Y, strikePos.Z), hitRoot.Position)
			end

			WebStrikeRemote:FireServer(hitCandidate)
			WebVisuals.createMeleeHitSparks(hitRoot.Position + Vector3.new(0, 0.5, 0), true)
			camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(-0.5), math.rad(math.random(-1, 1) * 0.3), 0)

			local fovTweenOut = TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = 70,
			})
			fovTweenOut:Play()

			-- Athletic kick-off rebound pop (smooth backstep bounce, perfectly positioned to combo!)
			rootPart.AssemblyLinearVelocity = (-flatZipDir * 12) + Vector3.new(0, 8, 0)
			CombatWebs.isWebStriking = false
		end
	end)
end

return CombatWebs
