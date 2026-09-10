--!strict
--[[
	CombatWebs.luau
	Handles all Spider-Man tactical web-based combat moves:
	1. 🕸️ Rapid Web-Pellets & Wall-Pinning (E Key)
	2. 🔫 Web-Yank Disarm & Weapon Throw (Q / Smart E Key)
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
local PropThrowRemote = RemotesFolder:WaitForChild("PropThrowRemote") :: RemoteEvent

local ModulesFolder = script.Parent
local CombatReticle = require(ModulesFolder:WaitForChild("CombatReticle"))
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))

local CombatWebs = {}

-- State
CombatWebs.lastWebPelletTime = 0
CombatWebs.lastDisarmTime = 0
CombatWebs.lastWebStrikeTime = 0
CombatWebs.lastPropThrowTime = 0
CombatWebs.isHoldingWebPellet = false
CombatWebs.isWebStriking = false
CombatWebs.isYankingProp = false
CombatWebs.isRightHandWeb = false

--------------------------------------------------------------------------------
-- 🔍 INTERNAL TARGETING HELPERS
--------------------------------------------------------------------------------

local function isArmedEnemy(enemy: Model): boolean
	return (enemy:GetAttribute("IsArmed") == true) or (enemy:FindFirstChild("Gun") ~= nil)
end

-- Scan camera view cone for valid enemy targets (fallback when reticle target is nil)
local function findEnemyInCone(rootPart: BasePart, camera: Camera, maxDist: number, minDot: number, requireArmed: boolean?): Model?
	local enemies = CollectionService:GetTagged("Enemy")
	local camCFrame = camera.CFrame
	local bestTarget: Model? = nil
	local bestDist = maxDist

	for _, enemy in enemies do
		if enemy:IsA("Model") then
			if requireArmed and not isArmedEnemy(enemy) then
				continue
			end

			local eHum = enemy:FindFirstChildOfClass("Humanoid")
			local eRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")) :: BasePart?
			if eHum and eHum.Health > 0 and eRoot then
				local offset = eRoot.Position - rootPart.Position
				local d = offset.Magnitude
				if d <= maxDist and d < bestDist then
					local toEnemy = (eRoot.Position - camCFrame.Position).Unit
					local dot = camCFrame.LookVector:Dot(toEnemy)
					if dot > minDot then
						bestTarget = enemy
						bestDist = d
					end
				end
			end
		end
	end

	return bestTarget
end

--------------------------------------------------------------------------------
-- ✨ VISUAL WEB HELPERS
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- 1. 🕸️ RAPID WEB-PELLETS (E Key)
--------------------------------------------------------------------------------

function CombatWebs.performWebPellet(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera, isHoldingAttack: boolean, lastMeleeActionTime: number)
	local now = os.clock()
	local cooldown = CombatConfig.Moves.WebPellet.Cooldown or 0.32
	if (now - CombatWebs.lastWebPelletTime) < cooldown then return end
	if isHoldingAttack or (now - lastMeleeActionTime) < 0.22 then return end

	local target = CombatReticle.getCurrentTarget() or findEnemyInCone(rootPart, camera, 55, 0.35, false)
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
end

--------------------------------------------------------------------------------
-- 2. 🔫 WEB-YANK DISARM & WEAPON THROW (Q / Smart E Key)
--------------------------------------------------------------------------------

function CombatWebs.performWebDisarm(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera, isHoldingAttack: boolean, lastMeleeActionTime: number)
	local now = os.clock()
	local cooldown = CombatConfig.Moves.DisarmAndThrow.Cooldown or 2.5
	if (now - CombatWebs.lastDisarmTime) < cooldown then return end
	if isHoldingAttack or (now - lastMeleeActionTime) < 0.22 then return end

	local target = CombatReticle.getCurrentTarget()
	if not target or not isArmedEnemy(target) then
		target = findEnemyInCone(rootPart, camera, 55, 0.40, true)
	end

	if not target or not isArmedEnemy(target) then return end

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

	-- Dynamic Camera tension pulse
	local camTweenIn = TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = 74,
	})
	camTweenIn:Play()

	task.delay(0.24, function()
		local camTweenOut = TweenService:Create(camera, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			FieldOfView = 70,
		})
		camTweenOut:Play()
	end)
end

--------------------------------------------------------------------------------
-- 2b. 📦 CONTEXTUAL WEB-YANK & PROP THROW (Q Key)
--------------------------------------------------------------------------------

function CombatWebs.performPropThrow(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera)
	local now = os.clock()
	local cooldown = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.Cooldown) or 2.0
	if (now - CombatWebs.lastPropThrowTime) < cooldown or CombatWebs.isYankingProp then return end

	local propInstance, propPart = CombatReticle.getCurrentThrowable()
	if not propInstance or not propPart or not propPart.Parent then
		-- Fallback: If no prop is targeted, check if player is facing an armed enemy to disarm
		local armedThreat = findEnemyInCone(rootPart, camera, 50, 0.40, true)
		if armedThreat then
			CombatWebs.performWebDisarm(character, rootPart, humanoid, camera, false, 0)
		end
		return
	end

	CombatWebs.lastPropThrowTime = now
	CombatWebs.isYankingProp = true
	CombatWebs.isHoldingWebPellet = false

	-- Mark as thrown immediately to prevent double-targeting
	propInstance:SetAttribute("IsThrown", true)
	propPart:SetAttribute("IsThrown", true)

	-- Find target enemy (primary reticle or nearest cone enemy)
	local targetEnemy = CombatReticle.getCurrentTarget()
	if not targetEnemy then
		targetEnemy = findEnemyInCone(rootPart, camera, 65, 0.25, false)
	end

	PropThrowRemote:FireServer(propInstance, targetEnemy)

	-- 1. Shoot Dual Web Lines to the Prop
	local leftAtt = WebVisuals.getHandAttachment(character, false)
	local rightAtt = WebVisuals.getHandAttachment(character, true)

	local propAtt = propPart:FindFirstChild("WebPropAttachment") :: Attachment?
	if not propAtt then
		propAtt = Instance.new("Attachment")
		propAtt.Name = "WebPropAttachment"
		propAtt.Position = Vector3.zero
		propAtt.Parent = propPart
	end

	local beamL = WebVisuals.createWebBeam(leftAtt, propAtt, rootPart)
	local beamR = WebVisuals.createWebBeam(rightAtt, propAtt, rootPart)
	WebVisuals.playWebSound(rootPart)

	-- Athletic pivot and crouch stance
	local toProp = (propPart.Position - rootPart.Position).Unit
	local flatToProp = Vector3.new(toProp.X, 0, toProp.Z).Unit
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatToProp)
	rootPart.AssemblyLinearVelocity = Vector3.new(0, 4.0, 0)

	-- Dynamic Camera tension punch
	local camTweenIn = TweenService:Create(camera, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = 75,
	})
	camTweenIn:Play()

	-- Take physical control of prop
	propPart.Anchored = true
	propPart.CanCollide = false

	-- Phase 1: Snatch/Lift off ground to player's right flank apex (0.16s)
	local sideApex = rootPart.Position + (rootPart.CFrame.RightVector * 3.4) + Vector3.new(0, 3.2, 0) - (rootPart.CFrame.LookVector * 1.0)
	local yankTween = TweenService:Create(propPart, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(sideApex) * CFrame.Angles(math.rad(25), math.rad(45), math.rad(20)),
	})
	yankTween:Play()

	-- Hard safety timeout to release state if character falls or gets interrupted
	task.delay(0.90, function()
		if CombatWebs.isYankingProp then
			if beamL and beamL.Parent then beamL:Destroy() end
			if beamR and beamR.Parent then beamR:Destroy() end
			CombatWebs.isYankingProp = false
		end
	end)

	yankTween.Completed:Connect(function()
		if not propPart.Parent or not character.Parent or humanoid.Health <= 0 then
			if beamL then beamL:Destroy() end
			if beamR then beamR:Destroy() end
			CombatWebs.isYankingProp = false
			return
		end

		-- Phase 2: 360° Overhead Kinetic Arc (0.26s)
		local arcDuration = 0.26
		local arcStart = os.clock()
		local arcConn: RBXScriptConnection? = nil

		arcConn = RunService.Heartbeat:Connect(function()
			if not propPart.Parent or not character.Parent or humanoid.Health <= 0 then
				if arcConn then arcConn:Disconnect() end
				if beamL and beamL.Parent then beamL:Destroy() end
				if beamR and beamR.Parent then beamR:Destroy() end
				CombatWebs.isYankingProp = false
				return
			end

			local elapsed = os.clock() - arcStart
			local progress = math.clamp(elapsed / arcDuration, 0, 1)
			local phi = progress * math.pi * 2

			local curPlayerPos = rootPart.Position
			local upVec = rootPart.CFrame.UpVector
			local rightVec = rootPart.CFrame.RightVector
			local lookVec = rootPart.CFrame.LookVector

			-- Parametric 360° overhead centrifugal arc
			local arcPos = curPlayerPos + (upVec * (3.8 + math.sin(phi) * 0.8)) + (rightVec * math.cos(phi) + lookVec * math.sin(phi)) * 3.6
			propPart.CFrame = CFrame.new(arcPos) * CFrame.Angles(phi * 2.2, phi * 1.6, phi)

			if progress >= 1 then
				if arcConn then arcConn:Disconnect() end
				arcConn = nil

				-- Phase 3: Release & Kinetic Slingshot Hurl into Enemy!
				if beamL then beamL:Destroy() end
				if beamR then beamR:Destroy() end
				WebVisuals.playWebSound(rootPart)

				local destPos: Vector3
				if targetEnemy and targetEnemy.Parent then
					local eRoot = (targetEnemy:FindFirstChild("HumanoidRootPart") or targetEnemy:FindFirstChild("Torso")) :: BasePart?
					destPos = eRoot and (eRoot.Position + Vector3.new(0, 0.8, 0)) or (curPlayerPos + lookVec * 45)
				else
					destPos = curPlayerPos + lookVec * 45
				end

				local throwDir = (destPos - propPart.Position).Unit
				local throwDist = (destPos - propPart.Position).Magnitude
				local throwSpeed = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.ThrowSpeed) or 125
				local flightTime = math.clamp(throwDist / throwSpeed, 0.12, 0.32)

				-- Dynamic camera recovery
				local camTweenOut = TweenService:Create(camera, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					FieldOfView = 70,
				})
				camTweenOut:Play()

				-- Spider-Man whip recoil
				rootPart.AssemblyLinearVelocity = (lookVec * 10) + Vector3.new(0, 1.2, 0)

				-- Kinetic Hurl Tween
				local hurlTween = TweenService:Create(propPart, TweenInfo.new(flightTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(destPos) * CFrame.Angles(math.rad(math.random(-360, 360)), math.rad(math.random(-360, 360)), math.rad(math.random(-360, 360))),
				})
				hurlTween:Play()

				hurlTween.Completed:Connect(function()
					if propPart.Parent then
						propPart.Anchored = false
						propPart.CanCollide = true
						propPart.AssemblyLinearVelocity = throwDir * 22 + Vector3.new(0, 8, 0)
						propPart.AssemblyAngularVelocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))

						WebVisuals.createWeaponImpactSparks(destPos, throwDir)
						WebVisuals.createImpactSplatVFX(destPos, throwDir)
					end
					CombatWebs.isYankingProp = false
				end)
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- 3. 🕸️ CONTEXTUAL SMART WEB GADGET (E Key)
--------------------------------------------------------------------------------

function CombatWebs.performSmartWebGadget(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera, isHoldingAttack: boolean, lastMeleeActionTime: number)
	local target = CombatReticle.getCurrentTarget()

	-- Priority 1: Check for active armed snipers in view
	local armedThreat = findEnemyInCone(rootPart, camera, 55, 0.45, true)
	if armedThreat then
		CombatWebs.performWebDisarm(character, rootPart, humanoid, camera, isHoldingAttack, lastMeleeActionTime)
		return
	end

	-- Priority 2: Reticle target
	if target then
		if isArmedEnemy(target) then
			CombatWebs.performWebDisarm(character, rootPart, humanoid, camera, isHoldingAttack, lastMeleeActionTime)
		else
			CombatWebs.performWebPellet(character, rootPart, humanoid, camera, isHoldingAttack, lastMeleeActionTime)
		end
	else
		-- Priority 3: Fallback cone search for unarmed mobs
		CombatWebs.performWebPellet(character, rootPart, humanoid, camera, isHoldingAttack, lastMeleeActionTime)
	end
end

--------------------------------------------------------------------------------
-- 4. 🚀 WEB-STRIKE ZIP KICK (R Key)
--------------------------------------------------------------------------------

function CombatWebs.performWebStrike(character: Model, rootPart: BasePart, humanoid: Humanoid, camera: Camera)
	local now = os.clock()
	local cooldown = CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.Cooldown or 2.0
	if CombatWebs.isWebStriking or (now - CombatWebs.lastWebStrikeTime) < cooldown then return end

	local target = CombatReticle.getCurrentTarget() or findEnemyInCone(rootPart, camera, 65, 0.55, false)
	if not target then return end

	local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")) :: BasePart?
	local targetHum = target:FindFirstChildOfClass("Humanoid")
	if not targetRoot or not targetHum or targetHum.Health <= 0 then return end

	local maxDist = CombatConfig.Moves.WebStrike and CombatConfig.Moves.WebStrike.MaxDistance or 65
	local dist = (targetRoot.Position - rootPart.Position).Magnitude
	if dist > maxDist or dist < 1.5 then return end

	CombatWebs.isWebStriking = true
	CombatWebs.lastWebStrikeTime = now
	CombatWebs.isHoldingWebPellet = false

	-- Clean up previous movement constraints
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

		-- Impact Threshold: Target contact or cluster collision
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
						if (eRoot.Position - rootPart.Position).Magnitude <= 4.8 then
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
