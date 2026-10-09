--!strict
--[[
	WebVisuals.luau
	Master coordinator for Spider-Man web silk visual beams, hand attachments,
	audio effects, and multiplayer replication.
	Delegates specialized VFX to modular VFX sub-packages:
	  - VFX/CombatHitVFX: Melee hit flares, brute deflection, muzzle flashes, counter shockwaves
	  - VFX/StarkTechVFX: Plasma thrusters & Waldo shockwaves
	  - VFX/MilesVenomVFX: Bio-electric venom blast, stun lightning, chromatic glitch decoy
	  - VFX/SymbioteVFX: Alien tendril ground slams, punch bursts, cleave arcs
	  - VFX/CyberScarletVFX: Impact web capsules & explosions, 2099 cyber slashes, Spider-Sense squiggles
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GrappleConfig = require(Shared:WaitForChild("GrappleConfig"))

local VFXFolder = script.Parent:WaitForChild("VFX")
local CombatHitVFX = require(VFXFolder:WaitForChild("CombatHitVFX"))
local StarkTechVFX = require(VFXFolder:WaitForChild("StarkTechVFX"))
local MilesVenomVFX = require(VFXFolder:WaitForChild("MilesVenomVFX"))
local SymbioteVFX = require(VFXFolder:WaitForChild("SymbioteVFX"))
local CyberScarletVFX = require(VFXFolder:WaitForChild("CyberScarletVFX"))

local WebVisuals = {}

-- Stores replicated beams for other players in the game
local otherPlayersVisuals: { [Player]: { [string]: any } } = {}

-- 🖐️ Get or create an attachment on the character's hand (supports R15 and R6)
function WebVisuals.getHandAttachment(character: Model, isRight: boolean): Attachment
	local handPart: BasePart? = nil
	if isRight then
		handPart = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") or character:FindFirstChild("RightLowerArm") or character:FindFirstChild("RightUpperArm")) :: BasePart?
	else
		handPart = (character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("LeftUpperArm")) :: BasePart?
	end

	local parentPart: BasePart = handPart or (character:FindFirstChild("HumanoidRootPart") :: BasePart)
	local attName = isRight and "WebSilkAttachment_R" or "WebSilkAttachment_L"
	local existing = parentPart:FindFirstChild(attName) :: Attachment?
	if existing then
		return existing
	end

	local newAtt = Instance.new("Attachment")
	newAtt.Name = attName
	newAtt.Position = Vector3.new(0, -0.2, 0)
	newAtt.Parent = parentPart
	return newAtt
end

-- ✨ Create a glowing white Spider-Man web silk beam between two attachments
function WebVisuals.createWebBeam(att0: Attachment, att1: Attachment, parent: Instance, casterChar: Model?): Beam
	local beam = Instance.new("Beam")
	beam.Name = "SpiderWebBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1

	local resolvedChar = casterChar
	if not resolvedChar then
		local p0 = att0.Parent
		if p0 and p0:IsA("BasePart") and p0.Parent and p0.Parent:IsA("Model") and p0.Parent:FindFirstChildOfClass("Humanoid") then
			resolvedChar = p0.Parent
		elseif parent and parent:IsA("BasePart") and parent.Parent and parent.Parent:IsA("Model") and parent.Parent:FindFirstChildOfClass("Humanoid") then
			resolvedChar = parent.Parent
		else
			resolvedChar = LocalPlayer and LocalPlayer.Character or nil
		end
	end

	local casterPlayer = if resolvedChar then Players:GetPlayerFromCharacter(resolvedChar) else nil
	local suitId = (resolvedChar and resolvedChar:GetAttribute("EquippedSuit"))
		or (casterPlayer and casterPlayer:GetAttribute("EquippedSuit"))

	if not suitId and LocalPlayer and (resolvedChar == LocalPlayer.Character or casterPlayer == LocalPlayer) then
		suitId = LocalPlayer:GetAttribute("EquippedSuit")
	end

	local is2099 = (suitId == "Cyber2099")
	local isSymbiote = (suitId == "SymbioteBlack")

	if is2099 then
		beam.Width0 = 0.14
		beam.Width1 = 0.14
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 45, 80))
		beam.LightEmission = 0.9
		beam.Transparency = NumberSequence.new(0.04)
	elseif isSymbiote then
		beam.Width0 = 0.16
		beam.Width1 = 0.16
		beam.Color = ColorSequence.new(Color3.fromRGB(20, 20, 25))
		beam.LightEmission = 0.05
		beam.Transparency = NumberSequence.new(0.04)
	else
		beam.Width0 = 0.16
		beam.Width1 = 0.16
		beam.Color = ColorSequence.new(GrappleConfig.Visuals.RopeColor)
		beam.LightEmission = 0.35
		beam.Transparency = NumberSequence.new(0.04)
	end

	beam.FaceCamera = true
	beam.Parent = parent
	return beam
end

-- 🔊 Play the classic web-shooter "thwip" sound (Zero SFX Policy)
function WebVisuals.playWebSound(_originPart: BasePart?)
	return
end

-- 💥 Create a dynamic web impact splatter effect at hit location
function WebVisuals.createImpactSplatVFX(impactPos: Vector3, normal: Vector3?)
	local splatCount = 4
	local baseNormal = normal or Vector3.new(0, 1, 0)

	for i = 1, splatCount do
		local strand = Instance.new("Part")
		strand.Name = "WebImpactStrand"
		strand.Material = Enum.Material.Neon
		strand.Color = Color3.fromRGB(245, 248, 255)
		strand.Transparency = 0.2
		strand.CanCollide = false
		strand.Anchored = true

		local spread = Vector3.new(
			(math.random() - 0.5) * 1.8,
			(math.random() - 0.5) * 1.8,
			(math.random() - 0.5) * 1.8
		)
		local endPos = impactPos + spread
		local dist = (endPos - impactPos).Magnitude

		strand.Size = Vector3.new(0.08, 0.08, math.max(0.3, dist))
		strand.CFrame = CFrame.lookAt((impactPos + endPos) / 2, endPos)
		strand.Parent = Workspace

		local tween = TweenService:Create(strand, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.02, 0.02, dist * 1.1),
		})
		tween:Play()
		Debris:AddItem(strand, 0.38)
	end
end

-- 🚀 High-speed Web-Pellet Projectile (with trailing web silk)
function WebVisuals.launchWebPelletProjectile(startAtt: Attachment, targetWorldPos: Vector3, callback: (() -> ())?)
	local startPos = startAtt.WorldPosition
	local toTarget = targetWorldPos - startPos
	local distance = toTarget.Magnitude
	local speed = 220
	local flightTime = math.clamp(distance / speed, 0.04, 0.22)

	local pellet = Instance.new("Part")
	pellet.Name = "WebPelletProjectile"
	pellet.Shape = Enum.PartType.Ball
	pellet.Size = Vector3.new(0.45, 0.45, 0.45)
	pellet.Material = Enum.Material.Neon

	local isSymbiotePellet = (LocalPlayer and LocalPlayer:GetAttribute("EquippedSuit") == "SymbioteBlack")
		or (LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:GetAttribute("EquippedSuit") == "SymbioteBlack")

	if isSymbiotePellet then
		pellet.Color = Color3.fromRGB(20, 20, 25)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(45, 25, 60)
		glow.Brightness = 3.2
		glow.Range = 6
		glow.Parent = pellet
	else
		pellet.Color = Color3.fromRGB(255, 255, 255)
	end
	pellet.CanCollide = false
	pellet.Anchored = true
	pellet.CFrame = CFrame.new(startPos)
	pellet.Parent = Workspace

	local pelletAtt = Instance.new("Attachment")
	pelletAtt.Parent = pellet

	local trailBeam = WebVisuals.createWebBeam(startAtt, pelletAtt, pellet)
	trailBeam.Width0 = 0.12
	trailBeam.Width1 = 0.18
	trailBeam.Transparency = NumberSequence.new(0.1, 0.7)

	local tween = TweenService:Create(pellet, TweenInfo.new(flightTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(targetWorldPos),
	})

	tween:Play()
	tween.Completed:Connect(function()
		pellet:Destroy()
		WebVisuals.createImpactSplatVFX(targetWorldPos)
		if callback then
			callback()
		end
	end)
end

-- 🕸️ Progressive Webbing Strands on Enemy (Stack 1 & 2)
function WebVisuals.applyProgressiveWebs(targetModel: Model, stack: number)
	local root = (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso")) :: BasePart?
	if not root then return end

	if stack == 1 then
		WebVisuals.clearProgressiveWebs(targetModel)
	end

	local strandCount = (stack == 1) and 3 or 6
	for i = 1, strandCount do
		local strand = Instance.new("Part")
		strand.Name = "ProgressiveWebStrand"
		strand.Material = Enum.Material.Neon
		strand.Color = Color3.fromRGB(240, 245, 255)
		strand.Transparency = 0.25
		strand.CanCollide = false
		strand.Massless = true
		strand.Parent = targetModel

		local offsetA = Vector3.new(math.random(-12, 12) * 0.1, math.random(-15, 15) * 0.1, math.random(-8, 8) * 0.1)
		local offsetB = Vector3.new(math.random(-12, 12) * 0.1, math.random(-15, 15) * 0.1, math.random(-8, 8) * 0.1)
		local posA = root.Position + offsetA
		local posB = root.Position + offsetB
		local length = (posB - posA).Magnitude

		strand.Size = Vector3.new(0.1, 0.1, math.max(0.4, length))
		strand.CFrame = CFrame.lookAt((posA + posB) / 2, posB)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = strand
		weld.Parent = strand

		Debris:AddItem(strand, 8.0)
	end
end

-- 🧹 Clear Progressive Web Strands
function WebVisuals.clearProgressiveWebs(targetModel: Model)
	for _, child in targetModel:GetChildren() do
		if child.Name == "ProgressiveWebStrand" then
			child:Destroy()
		end
	end
end

-- 🔫 Create dual high-tension web tethers connecting player hands to snatched weapon
function WebVisuals.createDisarmWebTether(playerChar: Model, weaponPart: BasePart, duration: number)
	local leftAtt = WebVisuals.getHandAttachment(playerChar, false)
	local rightAtt = WebVisuals.getHandAttachment(playerChar, true)

	local weaponAtt = Instance.new("Attachment")
	weaponAtt.Name = "DisarmWeaponAtt"
	weaponAtt.Parent = weaponPart

	local beamL = WebVisuals.createWebBeam(leftAtt, weaponAtt, weaponPart, playerChar)
	local beamR = WebVisuals.createWebBeam(rightAtt, weaponAtt, weaponPart, playerChar)

	task.delay(duration, function()
		if beamL then beamL:Destroy() end
		if beamR then beamR:Destroy() end
		if weaponAtt then weaponAtt:Destroy() end
	end)
end

-- 🍃 Looping Wind Rush Sound (Zero SFX Policy)
function WebVisuals.updateWindSound(_rootPart: BasePart?, _speed: number)
	return
end

-- Multiplayer Replication Listener
function WebVisuals.initMultiplayerReplication(remotesFolder: Folder)
	local GrappleStartRemote = remotesFolder:WaitForChild("GrappleStart") :: RemoteEvent
	local GrappleEndRemote = remotesFolder:WaitForChild("GrappleEnd") :: RemoteEvent

	GrappleStartRemote.OnClientEvent:Connect(function(otherPlayer: Player, anchorPos: Vector3, isRight: boolean)
		if otherPlayer == LocalPlayer or not otherPlayer.Character then return end

		local otherChar = otherPlayer.Character
		local otherRoot = otherChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not otherRoot then return end

		local key = isRight and "Right" or "Left"
		if not otherPlayersVisuals[otherPlayer] then
			otherPlayersVisuals[otherPlayer] = {}
		end

		if otherPlayersVisuals[otherPlayer][key] then
			otherPlayersVisuals[otherPlayer][key].Beam:Destroy()
			otherPlayersVisuals[otherPlayer][key] = nil
		end

		local worldAtt = Instance.new("Attachment")
		worldAtt.WorldPosition = anchorPos
		worldAtt.Parent = Workspace.Terrain

		local playerAtt = WebVisuals.getHandAttachment(otherChar, isRight)
		local beam = WebVisuals.createWebBeam(playerAtt, worldAtt, otherRoot, otherChar)

		otherPlayersVisuals[otherPlayer][key] = {
			Beam = beam,
			Att0 = playerAtt,
			Att1 = worldAtt,
		}
	end)

	GrappleEndRemote.OnClientEvent:Connect(function(otherPlayer: Player)
		if otherPlayersVisuals[otherPlayer] then
			for _, data in otherPlayersVisuals[otherPlayer] do
				if data.Beam then data.Beam:Destroy() end
				if data.Att0 then data.Att0:Destroy() end
				if data.Att1 then data.Att1:Destroy() end
			end
			otherPlayersVisuals[otherPlayer] = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- 🔗 COMBAT HIT VFX (DELEGATED TO CombatHitVFX)
--------------------------------------------------------------------------------
WebVisuals.createMeleeHitSparks = CombatHitVFX.createMeleeHitSparks
WebVisuals.createBruteBlockSparks = CombatHitVFX.createBruteBlockSparks
WebVisuals.createGuardBreakBurst = CombatHitVFX.createGuardBreakBurst
WebVisuals.createGunnerMuzzleFlash = CombatHitVFX.createGunnerMuzzleFlash
function WebVisuals.createWeaponImpactSparks(hitPos: Vector3, hitNormal: Vector3)
	CombatHitVFX.createWeaponImpactSparks(hitPos, hitNormal, WebVisuals.createImpactSplatVFX)
end
WebVisuals.createSpiderSenseSparks = CombatHitVFX.createSpiderSenseSparks
WebVisuals.createCounterImpactShockwave = CombatHitVFX.createCounterImpactShockwave

--------------------------------------------------------------------------------
-- 🔗 STARK TECH VFX (DELEGATED TO StarkTechVFX)
--------------------------------------------------------------------------------
WebVisuals.cleanupStarkThrusters = StarkTechVFX.cleanupStarkThrusters
WebVisuals.activateStarkThrusters = StarkTechVFX.activateStarkThrusters
WebVisuals.createWaldoRepulsorShockwave = StarkTechVFX.createWaldoRepulsorShockwave

--------------------------------------------------------------------------------
-- 🔗 MILES MORALES VENOM & CAMO VFX (DELEGATED TO MilesVenomVFX)
--------------------------------------------------------------------------------
WebVisuals.createVenomFistSparks = MilesVenomVFX.createVenomFistSparks
WebVisuals.createVenomBlastShockwave = MilesVenomVFX.createVenomBlastShockwave
WebVisuals.applyVenomStunVFX = MilesVenomVFX.applyVenomStunVFX
WebVisuals.createChromaticGlitchDecoy = MilesVenomVFX.createChromaticGlitchDecoy
WebVisuals.createBioSparkBurst = MilesVenomVFX.createBioSparkBurst
WebVisuals.createAmbushCritBurst = MilesVenomVFX.createAmbushCritBurst
WebVisuals.cleanupMilesBioSparks = MilesVenomVFX.cleanupMilesBioSparks
WebVisuals.activateMilesBioSparks = MilesVenomVFX.activateMilesBioSparks

--------------------------------------------------------------------------------
-- 🔗 SYMBIOTE BLACK SUIT VFX (DELEGATED TO SymbioteVFX)
--------------------------------------------------------------------------------
WebVisuals.createTendrilGroundSlamVFX = SymbioteVFX.createTendrilGroundSlamVFX
WebVisuals.createTendrilPunchBurst = SymbioteVFX.createTendrilPunchBurst
WebVisuals.createSymbioteCleaveVFX = SymbioteVFX.createSymbioteCleaveVFX

--------------------------------------------------------------------------------
-- 🔗 SCARLET SPIDER, CYBER 2099 & CLASSIC PETER VFX (DELEGATED TO CyberScarletVFX)
--------------------------------------------------------------------------------
WebVisuals.launchImpactWebProjectile = CyberScarletVFX.launchImpactWebProjectile
WebVisuals.createImpactWebExplosionVFX = CyberScarletVFX.createImpactWebExplosionVFX
WebVisuals.spawnCyberGlitchPolygon = CyberScarletVFX.spawnCyberGlitchPolygon
WebVisuals.createCyberCrossSlashVFX = CyberScarletVFX.createCyberCrossSlashVFX
WebVisuals.createCyberTalonSlash = CyberScarletVFX.createCyberTalonSlash
WebVisuals.createCyberStrikeVFX = CyberScarletVFX.createCyberStrikeVFX
WebVisuals.createSpiderSenseSquiggles = CyberScarletVFX.createSpiderSenseSquiggles
WebVisuals.createDoubleWebSlamVFX = CyberScarletVFX.createDoubleWebSlamVFX

-- Automatic Heartbeat monitor for local Apex Repulsor Thrusters & Miles Traversal Bio-Sparks
if RunService:IsClient() then
	RunService.Heartbeat:Connect(function()
		local char = LocalPlayer and LocalPlayer.Character
		if not char then
			StarkTechVFX.cleanupStarkThrusters(true)
			MilesVenomVFX.cleanupMilesBioSparks(true)
			return
		end

		local isStark = (LocalPlayer:GetAttribute("EquippedSuit") == "StarkTechSuit")
			or (char:GetAttribute("EquippedSuit") == "StarkTechSuit")
		local isMiles = (LocalPlayer:GetAttribute("EquippedSuit") == "MilesSpiderVerse")
			or (char:GetAttribute("EquippedSuit") == "MilesSpiderVerse")

		if not isStark then
			StarkTechVFX.cleanupStarkThrusters(true)
		end
		if not isMiles then
			MilesVenomVFX.cleanupMilesBioSparks(true)
		end

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local upperTorso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
		if not root then return end

		local speed = root.AssemblyLinearVelocity.Magnitude
		local isLaunching = char:GetAttribute("SlingshotLaunching") == true

		-- Stark Tech Thrusters (Speed >= 80)
		if isStark and upperTorso then
			if speed >= 80 or isLaunching then
				StarkTechVFX.activateStarkThrusters(char, upperTorso, speed)
			elseif speed < 65 then
				StarkTechVFX.cleanupStarkThrusters(false)
			end
		end

		-- Miles Morales Traversal Bio-Sparks (Speed >= 75)
		if isMiles then
			if speed >= 75 or isLaunching then
				MilesVenomVFX.activateMilesBioSparks(char, speed)
			elseif speed < 60 then
				MilesVenomVFX.cleanupMilesBioSparks(false)
			end
		end
	end)
end

return WebVisuals
