--!strict
--[[
	EnemyOverheadUI.luau
	Shared enemy overhead tag (name • role, health bar with damage-trail ghost, status states).
	- Pixel-sized BillboardGui: constant, crisp screen size at every distance (no scale clipping)
	- Zero server tweens (tweens replicate per-frame); ghost trail uses a single delayed snap
	- All connections released when the tag is destroyed
]]

local EnemyOverheadUI = {}

type Palette = { Tag: string, Accent: Color3, Fill: Color3 }

local PALETTE: { [string]: Palette } = {
	Gunner = { Tag = "MARKSMAN", Accent = Color3.fromRGB(255, 110, 110), Fill = Color3.fromRGB(235, 70, 75) },
	Brute = { Tag = "ENFORCER", Accent = Color3.fromRGB(125, 205, 255), Fill = Color3.fromRGB(70, 170, 255) },
	Brawler = { Tag = "BRAWLER", Accent = Color3.fromRGB(200, 205, 215), Fill = Color3.fromRGB(225, 75, 80) },
}

local STUN_COLOR = Color3.fromRGB(255, 225, 70)
local GUARD_COLOR = Color3.fromRGB(255, 165, 50)
local GHOST_COLOR = Color3.fromRGB(255, 238, 225)
local GHOST_DELAY = 0.35

local function escapeRich(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function EnemyOverheadUI.attach(enemyModel: Model, enemyName: string, archetype: string)
	local head = enemyModel:FindFirstChild("Head") :: BasePart?
	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid then return end

	local existing = head:FindFirstChild("HealthGui")
	if existing then existing:Destroy() end

	local palette = PALETTE[archetype] or PALETTE.Brawler
	local displayName = escapeRich(string.upper(enemyName))

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthGui"
	billboard.Size = UDim2.fromOffset(136, 30)
	billboard.StudsOffset = Vector3.new(0, if archetype == "Brute" then 2.9 else 2.3, 0)
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60

	local label = Instance.new("TextLabel")
	label.Name = "NameLabel"
	label.Size = UDim2.new(1, 0, 0, 14)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.RichText = true
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(245, 247, 252)
	label.TextStrokeColor3 = Color3.fromRGB(8, 10, 14)
	label.TextStrokeTransparency = 0.35
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "BarTrack"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 18)
	track.Size = UDim2.new(0.82, 0, 0, 6)
	track.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	track.BackgroundTransparency = 0.3
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = billboard

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Thickness = 1
	trackStroke.Color = Color3.fromRGB(0, 0, 0)
	trackStroke.Transparency = 0.45
	trackStroke.Parent = track

	local ghost = Instance.new("Frame")
	ghost.Name = "GhostFill"
	ghost.Size = UDim2.fromScale(1, 1)
	ghost.BackgroundColor3 = GHOST_COLOR
	ghost.BackgroundTransparency = 0.15
	ghost.BorderSizePixel = 0
	ghost.ZIndex = 1
	ghost.Parent = track

	local ghostCorner = Instance.new("UICorner")
	ghostCorner.CornerRadius = UDim.new(1, 0)
	ghostCorner.Parent = ghost

	local fill = Instance.new("Frame")
	fill.Name = "HealthFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = palette.Fill
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- White-to-grey shading multiplies cleanly with any fill hue
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Rotation = 90
	fillGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 190))
	fillGrad.Parent = fill

	local function renderStatus()
		if humanoid.Health <= 0 then return end
		local tagText, tagColor, fillColor = palette.Tag, palette.Accent, palette.Fill
		if enemyModel:GetAttribute("VenomStunned") == true then
			tagText, tagColor, fillColor = "⚡ STUNNED", STUN_COLOR, STUN_COLOR
		elseif archetype == "Brute" and enemyModel:GetAttribute("GuardBroken") == true then
			tagText, tagColor, fillColor = "GUARD BROKEN", GUARD_COLOR, GUARD_COLOR
		end
		label.Text = string.format('%s  <font color="#%s" size="9">%s</font>', displayName, tagColor:ToHex(), tagText)
		fill.BackgroundColor3 = fillColor
	end

	local ghostToken = 0
	local function renderHealth(newHealth: number)
		local ratio = math.clamp(newHealth / math.max(1, humanoid.MaxHealth), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		ghostToken += 1
		local token = ghostToken
		task.delay(GHOST_DELAY, function()
			if token == ghostToken and ghost.Parent then
				ghost.Size = UDim2.fromScale(ratio, 1)
			end
		end)
		if newHealth <= 0 then
			billboard:Destroy()
		end
	end

	local connections: { RBXScriptConnection } = {
		humanoid.HealthChanged:Connect(renderHealth),
		enemyModel:GetAttributeChangedSignal("VenomStunned"):Connect(renderStatus),
		enemyModel:GetAttributeChangedSignal("GuardBroken"):Connect(renderStatus),
	}
	billboard.Destroying:Connect(function()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
	end)

	renderStatus()
	billboard.Parent = head
end

return EnemyOverheadUI
