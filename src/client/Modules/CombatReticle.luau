--!strict
--[[
	CombatReticle.luau
	Fluid Freeflow Targeting & Throwable Prop Engine for Spider-Man Combat:
	- Dynamic soft-target evaluation for enemies (angle, distance, threat, stickiness)
	- Contextual Throwable Prop Scanner (military crates, manhole covers within 45 studs)
	- In-world custom reticle prompt: [Q] WEB-YANK & HURL (completely bypasses generic ProximityPrompt)
	- Clean & responsive with zero screen clutter
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local CombatReticle = {}

local currentTarget: Model? = nil
local currentThrowableInstance: Instance? = nil
local currentThrowablePart: BasePart? = nil

-- In-World Reticle Prompt UI State
local promptGui: BillboardGui? = nil
local promptFrame: Frame? = nil
local isPromptVisible = false

local function ensurePromptGui(): (BillboardGui, Frame)
	if promptGui and promptFrame and promptGui.Parent then
		return promptGui, promptFrame
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("ThrowablePromptGui")
	if existing and existing:IsA("BillboardGui") then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ThrowablePromptGui"
	billboard.Size = UDim2.new(0, 196, 0, 42)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	billboard.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "PromptContainer"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	container.BackgroundTransparency = 0.22
	container.BorderSizePixel = 0
	container.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Name = "BorderStroke"
	stroke.Color = Color3.fromRGB(85, 235, 255)
	stroke.Thickness = 1.6
	stroke.Transparency = 0.15
	stroke.Parent = container

	-- Left Key Badge [Q]
	local keyBadge = Instance.new("Frame")
	keyBadge.Name = "KeyBadge"
	keyBadge.Size = UDim2.new(0, 28, 0, 28)
	keyBadge.Position = UDim2.new(0, 7, 0.5, -14)
	keyBadge.BackgroundColor3 = Color3.fromRGB(255, 175, 45) -- Vibrant Spider-Orange / Gold
	keyBadge.BorderSizePixel = 0
	keyBadge.Parent = container

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = keyBadge

	local keyText = Instance.new("TextLabel")
	keyText.Size = UDim2.new(1, 0, 1, 0)
	keyText.BackgroundTransparency = 1
	keyText.Font = Enum.Font.GothamBold
	keyText.Text = "Q"
	keyText.TextColor3 = Color3.fromRGB(20, 22, 28)
	keyText.TextSize = 15
	keyText.Parent = keyBadge

	-- Action Label Text
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(1, -44, 1, 0)
	actionLabel.Position = UDim2.new(0, 42, 0, 0)
	actionLabel.BackgroundTransparency = 1
	actionLabel.Font = Enum.Font.GothamBold
	actionLabel.Text = "WEB-YANK & HURL"
	actionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionLabel.TextSize = 12
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.TextStrokeTransparency = 0.4
	actionLabel.Parent = container

	promptGui = billboard
	promptFrame = container
	return billboard, container
end

local function updatePromptVisibility(targetPart: BasePart?)
	local gui, frame = ensurePromptGui()
	if targetPart then
		gui.Adornee = targetPart
		gui.Enabled = true
		if not isPromptVisible then
			isPromptVisible = true
			frame.BackgroundTransparency = 1
			TweenService:Create(frame, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0.22,
			}):Play()
		end
	else
		if isPromptVisible then
			isPromptVisible = false
			local tween = TweenService:Create(frame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				if not isPromptVisible and gui then
					gui.Enabled = false
					gui.Adornee = nil
				end
			end)
		else
			gui.Enabled = false
			gui.Adornee = nil
		end
	end
end

-- Helper to extract root part from throwable Model or Part
local function getThrowablePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

-- 🔍 Dynamic Freeflow Update Loop (Runs in RenderStepped)
function CombatReticle.update(camera: Camera, rootPart: BasePart?): (Model?, Instance?)
	if not rootPart then
		currentTarget = nil
		currentThrowableInstance = nil
		currentThrowablePart = nil
		updatePromptVisibility(nil)
		return nil, nil
	end

	local camCFrame = camera.CFrame
	local camPos = camCFrame.Position
	local camLook = camCFrame.LookVector
	local playerPos = rootPart.Position

	----------------------------------------------------------------------------
	-- 1. 🥊 ENEMY SOFT-TARGET EVALUATION
	----------------------------------------------------------------------------
	local maxEnemyDist = CombatConfig.Targeting.MaxLockDistance or 65
	local maxEnemyAngle = math.rad(CombatConfig.Targeting.LockConeAngle or 45)
	local cosMaxEnemyAngle = math.cos(maxEnemyAngle)

	local bestEnemy: Model? = nil
	local bestEnemyScore = -999999

	local enemies = CollectionService:GetTagged("Enemy")
	for _, enemy in enemies do
		if enemy:IsA("Model") then
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			local enemyRoot = (enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso") or enemy:FindFirstChild("Head")) :: BasePart?

			if humanoid and humanoid.Health > 0 and enemyRoot then
				local enemyPos = enemyRoot.Position
				local toEnemy = enemyPos - camPos
				local distance = (enemyPos - playerPos).Magnitude

				if distance <= maxEnemyDist then
					local dot = math.clamp(camLook:Dot(toEnemy.Unit), -1, 1)
					local angle = math.acos(dot)

					if angle <= maxEnemyAngle then
						local _, onScreen = camera:WorldToViewportPoint(enemyPos + Vector3.new(0, 0.5, 0))
						if onScreen then
							-- 🎯 Aim Accuracy (Crosshair Alignment)
							local aimAccuracy = math.clamp((dot - cosMaxEnemyAngle) / (1 - cosMaxEnemyAngle), 0, 1)
							local aimScore = (aimAccuracy ^ 2.2) * 500

							-- ⚡ Active Threat & Armed Priority
							local isArmed = (enemy:GetAttribute("IsArmed") == true) or (enemy:FindFirstChild("Gun") ~= nil)
							local isAttacking = enemy:GetAttribute("IsAttacking") == true
							local threatScore = 0
							if isAttacking then threatScore += 30 end
							if isArmed then threatScore += 90 end

							-- Suppress off-axis threat scoring (under feet or off-screen)
							if dot < 0.65 then
								threatScore = 0
							end

							-- 📏 Proximity Base
							local proximityScore = (1.0 - (distance / maxEnemyDist)) * 80

							-- 🔒 Target Stickiness
							local stickiness = (enemy == currentTarget) and 45 or 0

							local totalScore = aimScore + threatScore + proximityScore + stickiness
							if totalScore > bestEnemyScore then
								bestEnemyScore = totalScore
								bestEnemy = enemy
							end
						end
					end
				end
			end
		end
	end

	currentTarget = bestEnemy

	----------------------------------------------------------------------------
	-- 2. 📦 CONTEXTUAL THROWABLE PROP SCANNER ([Q] WEB-YANK & HURL)
	----------------------------------------------------------------------------
	local maxPropDist = (CombatConfig.Moves and CombatConfig.Moves.PropThrow and CombatConfig.Moves.PropThrow.MaxDistance) or 45
	local maxPropAngle = math.rad(45)
	local cosMaxPropAngle = math.cos(maxPropAngle)

	local candidateProps: { [Instance]: boolean } = {}

	-- Check tagged objects
	for _, prop in CollectionService:GetTagged("ThrowableObject") do
		candidateProps[prop] = true
	end
	for _, prop in CollectionService:GetTagged("ThrowableProp") do
		candidateProps[prop] = true
	end
	for _, prop in CollectionService:GetTagged("Throwable") do
		candidateProps[prop] = true
	end

	-- Also check interactive crates in Workspace
	for propInstance in candidateProps do
		-- Suppress generic Roblox ProximityPrompts so Spider-Man in-world reticle takes full authority
		local prompt = propInstance:FindFirstChildOfClass("ProximityPrompt")
		if prompt and prompt.Enabled then
			prompt.Enabled = false
		end
	end

	local bestThrowable: Instance? = nil
	local bestThrowablePartFound: BasePart? = nil
	local bestPropScore = -999999

	for propInstance in candidateProps do
		if propInstance and propInstance.Parent then
			-- Ensure prop is not already thrown or destroyed
			if propInstance:GetAttribute("IsThrown") ~= true then
				local propPart = getThrowablePart(propInstance)
				if propPart and propPart:GetAttribute("IsThrown") ~= true then
					local propPos = propPart.Position
					local toProp = propPos - camPos
					local distance = (propPos - playerPos).Magnitude

					if distance <= maxPropDist then
						local dot = math.clamp(camLook:Dot(toProp.Unit), -1, 1)
						local angle = math.acos(dot)

						if angle <= maxPropAngle then
							local _, onScreen = camera:WorldToViewportPoint(propPos)
							if onScreen then
								local aimAccuracy = math.clamp((dot - cosMaxPropAngle) / (1 - cosMaxPropAngle), 0, 1)
								local aimScore = (aimAccuracy ^ 2.0) * 300
								local proximityScore = (1.0 - (distance / maxPropDist)) * 100
								local stickiness = (propInstance == currentThrowableInstance) and 50 or 0

								local totalScore = aimScore + proximityScore + stickiness
								if totalScore > bestPropScore then
									bestPropScore = totalScore
									bestThrowable = propInstance
									bestThrowablePartFound = propPart
								end
							end
						end
					end
				end
			end
		end
	end

	currentThrowableInstance = bestThrowable
	currentThrowablePart = bestThrowablePartFound

	-- Update in-world [Q] WEB-YANK & HURL prompt billboard
	updatePromptVisibility(currentThrowablePart)

	return currentTarget, currentThrowableInstance
end

function CombatReticle.getCurrentTarget(): Model?
	return currentTarget
end

function CombatReticle.getCurrentThrowable(): (Instance?, BasePart?)
	return currentThrowableInstance, currentThrowablePart
end

return CombatReticle
