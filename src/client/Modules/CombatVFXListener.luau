--!strict
--[[
	CombatVFXListener.luau
	Handles all multiplayer Combat VFX replications from the server:
	- WebPelletHit & Progressive webs
	- DisarmYankVFX & Web tethers
	- WeaponImpactVFX & Camera impacts
	- WallPinnedVFX & Multi-strand Web Matrix
	- CocoonVFX capsule mesh
	- ShockwaveVFX & ZZZ CounterStrikeVFX
	- WebStrikeHit sparks & impacts
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local ModulesFolder = script.Parent
local WebVisuals = require(ModulesFolder:WaitForChild("WebVisuals"))
local CombatStyleHUD = require(ModulesFolder:WaitForChild("CombatStyleHUD"))

local CombatVFXListener = {}

-- ⏱️ Dynamic Hit-Stop: 2-frame tactile micro-pause on heavy impacts
local function triggerHitStop(duration: number, camera: Camera, isHeavy: boolean)
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local savedVel = root.AssemblyLinearVelocity
	local microPause = isHeavy and 0.042 or 0.022

	-- Momentary velocity suspension gives that classic fighting-game crunch
	task.delay(microPause, function()
		if root and root.Parent then
			root.AssemblyLinearVelocity = savedVel
		end
	end)
end

function CombatVFXListener.init(CombatVFXRemote: RemoteEvent, camera: Camera, getCharacterParts: () -> (Model?, BasePart?, Humanoid?))
	CombatVFXRemote.OnClientEvent:Connect(function(actionName: string, instigator: any, targetModel: any, extra: any, hitCountArg: any)
		-- 🕸️ 1. Web Pellet Hit & Progressive Web VFX
		if actionName == "WebPelletHit" and typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
			local currentStacks = typeof(extra) == "number" and extra or (targetModel:GetAttribute("WebStacks") or 1)
			WebVisuals.applyProgressiveWebs(targetModel, currentStacks)

			local isLocal = instigator == LocalPlayer or instigator == LocalPlayer.Character
			if isLocal then
				CombatStyleHUD.registerHit(4)
				triggerHitStop(0.022, camera, false)
			elseif typeof(instigator) == "Instance" then
				local sourceChar = instigator:IsA("Player") and instigator.Character or instigator
				if sourceChar and sourceChar ~= LocalPlayer.Character then
					local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
					if enemyRoot then
						local handAtt = WebVisuals.getHandAttachment(sourceChar, true)
						WebVisuals.launchWebPelletProjectile(handAtt, enemyRoot.Position + Vector3.new(0, 0.4, 0))
					end
				end
			end
		end

		-- 🔫 2. Disarm Yank Web Lines VFX
		if actionName == "DisarmYankVFX" and typeof(instigator) == "Instance" and typeof(targetModel) == "Instance" then
			local sourceChar = instigator:IsA("Player") and instigator.Character or instigator
			local weaponPart = targetModel:IsA("BasePart") and targetModel or (targetModel:FindFirstChild("Gun") :: BasePart?)
			if sourceChar and weaponPart then
				WebVisuals.createDisarmWebTether(sourceChar, weaponPart, 0.45)
				WebVisuals.playWebSound(sourceChar:FindFirstChild("HumanoidRootPart"))
			end
		end

		-- 📦 2b. Prop Throw VFX (Multiplayer sync for other players)
		if actionName == "PropThrowVFX" and typeof(instigator) == "Instance" and typeof(targetModel) == "Instance" then
			local sourceChar = instigator:IsA("Player") and instigator.Character or instigator
			if sourceChar and sourceChar ~= LocalPlayer.Character then
				local propPart: BasePart? = nil
				if targetModel:IsA("BasePart") then
					propPart = targetModel
				elseif targetModel:IsA("Model") then
					propPart = targetModel.PrimaryPart or targetModel:FindFirstChildWhichIsA("BasePart")
				end
				if propPart then
					local leftAtt = WebVisuals.getHandAttachment(sourceChar, false)
					local rightAtt = WebVisuals.getHandAttachment(sourceChar, true)
					local propAtt = propPart:FindFirstChild("WebPropAttachment") :: Attachment?
					if not propAtt then
						propAtt = Instance.new("Attachment")
						propAtt.Name = "WebPropAttachment"
						propAtt.Position = Vector3.zero
						propAtt.Parent = propPart
					end
					local b1 = WebVisuals.createWebBeam(leftAtt, propAtt, sourceChar:FindFirstChild("HumanoidRootPart") or propPart)
					local b2 = WebVisuals.createWebBeam(rightAtt, propAtt, sourceChar:FindFirstChild("HumanoidRootPart") or propPart)
					WebVisuals.playWebSound(sourceChar:FindFirstChild("HumanoidRootPart"))
					task.delay(0.44, function()
						if b1 then b1:Destroy() end
						if b2 then b2:Destroy() end
					end)
				end
			end
		end

		-- 💥 3. Weapon Impact Sparks & Web Splat VFX
		if actionName == "WeaponImpactVFX" and typeof(instigator) == "Vector3" then
			local hitPos: Vector3 = instigator
			local hitNormal: Vector3 = (typeof(targetModel) == "Vector3") and targetModel or Vector3.new(0, 1, 0)
			WebVisuals.createWeaponImpactSparks(hitPos, hitNormal)

			local _, rootPart = getCharacterParts()
			if rootPart and (rootPart.Position - hitPos).Magnitude <= 40 then
				CombatStyleHUD.registerHit(26)
				triggerHitStop(0.045, camera, true)
			end
		end

		-- 📌 4. Wall Pinned VFX: Spawn clean multi-strand web matrix pinning enemy to wall
		if actionName == "WallPinnedVFX" and typeof(instigator) == "Instance" and typeof(targetModel) == "Vector3" then
			local enemyModel: Model = instigator
			local wallPos: Vector3 = targetModel
			local wallNormal: Vector3 = (typeof(extra) == "Vector3") and extra or Vector3.new(0, 0, 1)
			local enemyRoot = (enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:FindFirstChild("Torso")) :: BasePart?

			if enemyRoot then
				for _, child in enemyModel:GetChildren() do
					if child.Name == "WebCocoonMesh" or child.Name == "WallPinWebMatrix" then
						child:Destroy()
					end
				end

				WebVisuals.playWebSound(enemyRoot)

				local matrixFolder = Instance.new("Folder")
				matrixFolder.Name = "WallPinWebMatrix"
				matrixFolder.Parent = enemyModel
				Debris:AddItem(matrixFolder, 12)

				local bodyAnchors = {
					Vector3.new(0, 1.4, 0),
					Vector3.new(1.2, 0.5, 0),
					Vector3.new(-1.2, 0.5, 0),
					Vector3.new(0.8, -1.2, 0),
					Vector3.new(-0.8, -1.2, 0),
				}
				local wallOffsets = {
					Vector3.new(0, 2.6, 0),
					Vector3.new(2.4, 1.8, 0),
					Vector3.new(-2.4, 1.8, 0),
					Vector3.new(2.0, -1.8, 0),
					Vector3.new(-2.0, -1.8, 0),
				}

				local wallRight = Vector3.new(-wallNormal.Z, 0, wallNormal.X)
				if wallRight.Magnitude < 0.1 then
					wallRight = Vector3.new(1, 0, 0)
				else
					wallRight = wallRight.Unit
				end
				local wallUp = wallRight:Cross(wallNormal).Unit

				for i = 1, #bodyAnchors do
					local bodyOffset = bodyAnchors[i]
					local wOffset = wallOffsets[i]
					local startPos = enemyRoot.Position + (enemyRoot.CFrame.RightVector * bodyOffset.X) + (enemyRoot.CFrame.UpVector * bodyOffset.Y)
					local endPos = wallPos + (wallRight * wOffset.X) + (wallUp * wOffset.Y)
					local dist = (endPos - startPos).Magnitude

					local webStrand = Instance.new("Part")
					webStrand.Name = "WallWebStrand"
					webStrand.Material = Enum.Material.Neon
					webStrand.Color = Color3.fromRGB(245, 248, 255)
					webStrand.Transparency = 0.15
					webStrand.CanCollide = false
					webStrand.Anchored = true
					webStrand.Size = Vector3.new(0.12, 0.12, math.max(0.4, dist))
					webStrand.CFrame = CFrame.lookAt((startPos + endPos) / 2, endPos)
					webStrand.Parent = matrixFolder

					WebVisuals.createImpactSplatVFX(endPos, wallNormal)
				end
			end
		end

		-- 🕸️ 5. Cocoon VFX: 3D Translucent White Web Capsule
		if actionName == "CocoonVFX" and typeof(instigator) == "Instance" and instigator:IsA("Model") then
			local enemyModel: Model = instigator
			local enemyRoot = (enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:FindFirstChild("Torso")) :: BasePart?

			if enemyRoot then
				for _, child in enemyModel:GetChildren() do
					if child.Name == "WebCocoonMesh" then child:Destroy() end
				end

				local cocoon = Instance.new("Part")
				cocoon.Name = "WebCocoonMesh"
				cocoon.Shape = Enum.PartType.Cylinder
				cocoon.Size = Vector3.new(5.2, 2.6, 2.6)
				cocoon.CFrame = enemyRoot.CFrame * CFrame.Angles(0, 0, math.rad(90))
				cocoon.Material = Enum.Material.Neon
				cocoon.Color = Color3.fromRGB(250, 252, 255)
				cocoon.Transparency = 0.35
				cocoon.CanCollide = false
				cocoon.Massless = true
				cocoon.Parent = enemyModel

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = enemyRoot
				weld.Part1 = cocoon
				weld.Parent = cocoon

				WebVisuals.playWebSound(enemyRoot)
				Debris:AddItem(cocoon, 6.0)
			end
		end

		-- 🕸️ 5b. Ground Slam Multiplayer Web Lines Replication
		if actionName == "GroundSlamWebs" and typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
			local sourceChar = instigator:IsA("Player") and instigator.Character or instigator
			if sourceChar and sourceChar ~= LocalPlayer.Character then
				WebVisuals.createCombatWebLines(sourceChar, targetModel, true, 0.45)
			end
		end

		-- 💥 6. Ground Slam Radial Shockwave VFX & Combo Hit Registration
		if actionName == "GroundSlamShockwave" then
			local pos: Vector3 = typeof(targetModel) == "Vector3" and targetModel or (typeof(instigator) == "Vector3" and instigator or Vector3.zero)
			local shockRadius: number = typeof(extra) == "number" and extra or 24
			local totalHits: number = typeof(hitCountArg) == "number" and hitCountArg or 0

			WebVisuals.createImpactSplatVFX(pos, Vector3.new(0, 1, 0))
			WebVisuals.createWeaponImpactSparks(pos, Vector3.new(0, 1, 0))

			local shockRing = Instance.new("Part")
			shockRing.Shape = Enum.PartType.Cylinder
			shockRing.Size = Vector3.new(0.2, 2, 2)
			shockRing.CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			shockRing.Material = Enum.Material.Neon
			shockRing.Color = Color3.fromRGB(255, 255, 255)
			shockRing.Transparency = 0.2
			shockRing.CanCollide = false
			shockRing.Anchored = true
			shockRing.Parent = Workspace

			local tween = TweenService:Create(shockRing, TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.2, shockRadius * 1.5, shockRadius * 1.5),
				Transparency = 1,
			})
			tween:Play()
			Debris:AddItem(shockRing, 0.45)

			-- 🥊 Combo Registration for Local Player:
			-- Each enemy struck by the primary slam or the radial shockwave increments the combo!
			local isLocal = instigator == LocalPlayer or instigator == LocalPlayer.Character
			if isLocal and totalHits > 0 then
				for _ = 1, totalHits do
					CombatStyleHUD.registerHit(15)
				end
				triggerHitStop(0.045, camera, true)
			end
		end

		-- 💥 7. ZZZ Counter Strike Shockwave VFX
		if actionName == "CounterStrikeVFX" and typeof(instigator) == "Instance" and typeof(extra) == "Vector3" then
			local hitPos: Vector3 = extra
			WebVisuals.createCounterImpactShockwave(hitPos, 12)
			WebVisuals.createWeaponImpactSparks(hitPos, Vector3.new(0, 1, 0))

			local isLocal = instigator == LocalPlayer or instigator == LocalPlayer.Character
			if isLocal then
				CombatStyleHUD.registerHit(12)
				triggerHitStop(0.045, camera, true)
			end
		end

		-- ⚡ 8. Spider-Sense Dodge VFX
		if actionName == "SpiderSenseDodgeVFX" and typeof(instigator) == "Instance" then
			local sourceChar = instigator:IsA("Player") and instigator.Character or instigator
			if sourceChar then
				WebVisuals.createSpiderSenseSparks(sourceChar, false)
			end
		end

		-- 🚀 9. Web-Strike Dropkick Impact VFX
		if actionName == "WebStrikeHit" and typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
			local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
			if enemyRoot then
				WebVisuals.createMeleeHitSparks(enemyRoot.Position + Vector3.new(0, 0.5, 0), true)
				WebVisuals.createWeaponImpactSparks(enemyRoot.Position, Vector3.new(0, 1, 0))
			end

			local isLocal = instigator == LocalPlayer or instigator == LocalPlayer.Character
			if isLocal then
				CombatStyleHUD.registerHit(22)
				triggerHitStop(0.045, camera, true)
			end
		end

		-- 🥊 10. Kinetic Hit Replication (Multiplayer Punch Sparks)
		if actionName == "KineticHit" and typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
			local hitNum = typeof(extra) == "number" and extra or 1
			local enemyRoot = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
			if enemyRoot then
				WebVisuals.createMeleeHitSparks(enemyRoot.Position + Vector3.new(0, 0.5, 0), hitNum == 3)
			end

			local isLocal = instigator == LocalPlayer or instigator == LocalPlayer.Character
			if isLocal then
				CombatStyleHUD.registerHit(hitNum == 3 and 18 or 10)
				triggerHitStop(hitNum == 3 and 0.045 or 0.022, camera, hitNum == 3)
			end
		end

		-- 🛡️ 11. Brute Block Deflection VFX (Metallic Sparks & Clang Shield)
		if actionName == "BruteBlockVFX" and typeof(instigator) == "Instance" and instigator:IsA("Model") then
			local enemyRoot = (instigator:FindFirstChild("HumanoidRootPart") or instigator:FindFirstChild("Torso")) :: BasePart?
			local punchDir = typeof(targetModel) == "Vector3" and targetModel or (enemyRoot and enemyRoot.CFrame.LookVector or Vector3.new(0, 0, 1))
			if enemyRoot then
				local blockPos = enemyRoot.Position + (enemyRoot.CFrame.LookVector * 1.5) + Vector3.new(0, 0.4, 0)
				WebVisuals.createBruteBlockSparks(blockPos, -punchDir)
			end
		end

		-- 💥 12. Guard Break VFX (Armor Shatter Burst)
		if actionName == "GuardBreakVFX" and typeof(instigator) == "Instance" and instigator:IsA("Model") then
			local enemyRoot = (instigator:FindFirstChild("HumanoidRootPart") or instigator:FindFirstChild("Torso")) :: BasePart?
			if enemyRoot then
				WebVisuals.createGuardBreakBurst(enemyRoot.Position + Vector3.new(0, 0.5, 0))
			end
		end

		-- 🔫 13. Gunner Muzzle Flash & Tracer VFX
		if actionName == "GunnerMuzzleVFX" and typeof(instigator) == "Vector3" and typeof(targetModel) == "Vector3" then
			local muzzlePos: Vector3 = instigator
			local fireDir: Vector3 = targetModel
			local dist = typeof(extra) == "number" and extra or 40
			WebVisuals.createGunnerMuzzleFlash(muzzlePos, fireDir, dist)
		end
	end)
end

return CombatVFXListener
