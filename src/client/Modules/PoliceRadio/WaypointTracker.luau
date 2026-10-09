--!strict
--[[
	WaypointTracker.luau
	Mathematical 3D to 2D screen clamping, elevation tracking (High-Rise / Street / Level),
	compact vs full layout switching, and off-screen directional chevron indicator.
]]

local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local WaypointTracker = {}

local lastWaypointMode: string? = nil

-- 🧭 Mathematical 3D to Screen Clamping with Smooth Bounds Intersection
function WaypointTracker.calculateScreenPoint(targetWorldPos: Vector3, margin: number, topMargin: number?): (Vector2, boolean, number, Vector2)
	local curCam = Workspace.CurrentCamera
	if not curCam then
		return Vector2.zero, false, 0, Vector2.zero
	end

	local screenPos, onScreen = curCam:WorldToViewportPoint(targetWorldPos)
	local viewportSize = curCam.ViewportSize
	local center = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
	local actualTopMargin = topMargin or margin

	if onScreen and screenPos.Z > 0 then
		local clampedY = math.clamp(screenPos.Y, actualTopMargin, math.max(actualTopMargin + 20, viewportSize.Y - margin))
		return Vector2.new(screenPos.X, clampedY), true, 0, Vector2.zero
	end

	-- Behind camera or outside viewport bounds
	local toTarget = targetWorldPos - curCam.CFrame.Position
	local forward = curCam.CFrame.LookVector
	local isBehind = forward:Dot(toTarget) < 0 or screenPos.Z < 0

	local rawDir = Vector2.new(screenPos.X - center.X, screenPos.Y - center.Y)
	if isBehind then
		rawDir = -rawDir
	end

	local dir = rawDir.Magnitude > 0.001 and rawDir.Unit or Vector2.new(0, -1)

	local safeHalfW = math.max(20, (viewportSize.X / 2) - margin)
	local safeHalfH = math.max(20, (viewportSize.Y / 2) - actualTopMargin)

	local scaleX = math.abs(dir.X) > 0.0001 and (safeHalfW / math.abs(dir.X)) or 1e6
	local scaleY = math.abs(dir.Y) > 0.0001 and (safeHalfH / math.abs(dir.Y)) or 1e6
	local scale = math.min(scaleX, scaleY)

	local clampedPos = center + (dir * scale)
	local finalY = math.clamp(clampedPos.Y, actualTopMargin, math.max(actualTopMargin + 20, viewportSize.Y - margin))
	local angleDeg = math.deg(math.atan2(dir.Y, dir.X)) + 90

	return Vector2.new(clampedPos.X, finalY), false, angleDeg, dir
end

-- 🧭 Waypoint Layout Modes (applied only on change)
function WaypointTracker.applyWaypointLayout(
	marker: Frame,
	titleLabel: TextLabel?,
	stroke: UIStroke?,
	iconLabel: TextLabel?,
	distLabel: TextLabel?,
	mode: string
)
	local isFull = mode == "Full"
	local isMini = mode == "Mini"

	if titleLabel then
		titleLabel.Visible = isFull
	end
	marker.Size = if isFull then UDim2.fromOffset(150, 34) elseif isMini then UDim2.fromOffset(72, 24) else UDim2.fromOffset(124, 26)
	marker.BackgroundTransparency = if isFull then 0.18 elseif isMini then 0.35 else 0.22
	if stroke then
		stroke.Transparency = if isFull then 0.2 elseif isMini then 0.45 else 0.25
	end
	if iconLabel then
		iconLabel.Position = if isFull then UDim2.new(0, 6, 0.5, -9) else UDim2.new(0, if isMini then 4 else 6, 0.5, -8)
		iconLabel.Size = if isFull then UDim2.fromOffset(18, 18) else UDim2.fromOffset(16, 16)
		iconLabel.TextSize = if isFull then 13 elseif isMini then 11 else 12
	end
	if distLabel then
		if isFull then
			distLabel.Position = UDim2.fromOffset(28, 17)
			distLabel.Size = UDim2.new(1, -32, 0, 14)
			distLabel.TextSize = 9.5
		else
			local left = if isMini then 22 else 24
			distLabel.Position = UDim2.fromOffset(left, 0)
			distLabel.Size = UDim2.new(1, -(left + 4), 1, 0)
			distLabel.TextSize = 10
		end
	end
end

function WaypointTracker.resetMode()
	lastWaypointMode = nil
end

function WaypointTracker.update(
	marker: Frame,
	markerStroke: UIStroke?,
	titleLabel: TextLabel?,
	iconLabel: TextLabel?,
	distLabel: TextLabel?,
	pointerArrow: ImageLabel?,
	epicenter: Vector3,
	playerPos: Vector3,
	isCommCardVisible: boolean,
	isVisorOpen: boolean
)
	local distStuds = (playerPos - epicenter).Magnitude

	-- Proximity Combat Fade: When within 35 studs or visor is open, hide 2D waypoint
	if distStuds <= 35 or isVisorOpen then
		marker.Visible = false
		lastWaypointMode = nil
		if pointerArrow then
			pointerArrow.Visible = false
		end
		return
	end

	local distMeters = math.floor(distStuds / 3)

	-- Elevation Tracking
	local deltaY = epicenter.Y - playerPos.Y
	local elevationSymbol = "◆"
	local elevationDesc = "Level"

	if deltaY > 18 then
		elevationSymbol = "▲"
		elevationDesc = "High-Rise"
	elseif deltaY < -18 then
		elevationSymbol = "▼"
		elevationDesc = "Street"
	end

	local mode = if isCommCardVisible then "Compact" elseif distMeters > 90 then "Mini" else "Full"
	if mode ~= lastWaypointMode then
		lastWaypointMode = mode
		WaypointTracker.applyWaypointLayout(marker, titleLabel, markerStroke, iconLabel, distLabel, mode)
	end

	if distLabel then
		local distText = if mode == "Mini"
			then string.format("%s %dm", elevationSymbol, distMeters)
			else string.format("%s %dm  ·  %s", elevationSymbol, distMeters, elevationDesc)
		if distLabel.Text ~= distText then
			distLabel.Text = distText
		end
		distLabel.TextColor3 = if deltaY > 18 then Color3.fromRGB(255, 195, 60)
			elseif deltaY < -18 then Color3.fromRGB(255, 95, 95)
			else Color3.fromRGB(85, 220, 255)
	end

	-- Target World Anchor (Head height over crime scene)
	local targetWorldPos = epicenter + Vector3.new(0, 6.5, 0)
	local topMargin = if isCommCardVisible then 135 else 90
	local screenPos2D, onScreen, angleDeg, dirVector = WaypointTracker.calculateScreenPoint(targetWorldPos, 90, topMargin)

	local curCam = Workspace.CurrentCamera
	local viewport = curCam and curCam.ViewportSize or Vector2.new(1920, 1080)
	local healthHudBottom = GuiService:GetGuiInset().Y + 112
	local pillX, pillY = screenPos2D.X, screenPos2D.Y
	if pillX > viewport.X - 330 and pillY < healthHudBottom then
		pillY = healthHudBottom
	end
	local halfW = marker.AbsoluteSize.X / 2 + 8
	pillX = math.clamp(pillX, halfW, math.max(halfW, viewport.X - halfW))
	screenPos2D = Vector2.new(pillX, pillY)

	marker.Position = UDim2.fromOffset(screenPos2D.X, screenPos2D.Y)
	marker.Visible = true

	if pointerArrow then
		if onScreen then
			pointerArrow.Visible = false
		else
			pointerArrow.Visible = true
			pointerArrow.Position = UDim2.new(0, screenPos2D.X + (dirVector.X * 32), 0, screenPos2D.Y + (dirVector.Y * 24))
			pointerArrow.Rotation = angleDeg
		end
	end
end

return WaypointTracker
