--!strict
--[[
	GrappleConfig.luau
	Central configuration module for Spider-Man Web-Swinging mechanics.
	Shared between Client (physics & inputs) and Server (anti-cheat verification).
]]

local GrappleConfig = {
	-- 🎮 Controls & Keybinds (Right Click exclusively for Web-Swinging!)
	Keybinds = {
		Swing = Enum.UserInputType.MouseButton2,     -- Right Click: Dedicated Web-Swinging & Slingshot
		JumpKey = Enum.KeyCode.Space,                -- Spacebar: Web Jump & Wall Jump launch
	},

	-- 🔍 Smart Building Anchor Detection (Forward-facing street building ledges)
	Targeting = {
		RequireBuilding = true,                       -- Requires buildings/structures nearby to swing in mid-air
		MaxDistance = 135,                            -- Maximum reach to nearby street buildings (studs)
		MinDistance = 25,                             -- Minimum anchor distance (prevents attaching right at waist/hip)
		MinForwardDistance = 15,                      -- Must be ahead of player (never behind!)
		ScanAngles = {-45, 45, -25, 25, -60, 60, -10, 10}, -- Wide cone raycast angles to left & right buildings
		ScanHeights = {20, 40, 65, 90},               -- Building facade scan heights
	},

	-- ⏱️ Cooldown Settings
	Cooldown = {
		SwingCooldown = 0.22,                         -- Brief cooldown between swings to prevent spam glitching
	},

	-- 🚀 Ground Double-Web Slingshot (Dual Web Sky Rocket Launch)
	Slingshot = {
		Enabled = true,
		UpwardVelocity = 145,   -- High vertical sky rocket boost
		ForwardVelocity = 85,   -- Forward trajectory speed
		Duration = 0.50,        -- Slingshot pull duration before soaring
		SkyHeight = 150,        -- Height of dual sky anchors
		SpreadWidth = 40,       -- Left/Right spread of the dual anchors
	},


	-- 🕸️ True Spherical Pendulum Physics (Energy Conservation & Centripetal Arc)
	Physics = {
		GravityForce = 150,            -- Gravitational acceleration pulling down into the swing arc (studs/s^2)
		ForwardPumpForce = 75,         -- Fast forward acceleration force when holding W / looking forward
		UpwardClimbLift = 65,          -- Upward climb buoyancy lifting player high above street level
		CameraSteerResponsiveness = 8.5, -- Look-to-Steer: How quickly holding W curves your swing towards camera look
		InitialSwingSpeed = 115,       -- Fast, thrilling initial swing entry speed
		AirSteerForce = 50,            -- A/D lateral banking steering force
		MinSpeed = 60,                 -- Minimum speed to keep pendulum flowing smoothly
		MaxSpeed = 185,                -- High-speed, thrilling top pendulum velocity
		TensionStiffness = 28,         -- Radial tension keeping the web line 100% taut
		MinRopeLength = 20,            -- Minimum rope length (studs)
		WallClearanceDistance = 7,     -- Buffer distance from building walls to prevent dragging
	},

	-- 🚀 Dynamic Peak Height Auto-Release (Auto-releases cleanly at 70-degree apex!)
	AutoRelease = {
		Enabled = true,          -- Auto-release enabled
		ApexAngleThreshold = 72, -- 🎯 Auto-releases cleanly at 70-72 degrees at peak height!
		MinSwingDuration = 0.55, -- Ensures you complete the bottom swoop before apex release
		MaxSwingDuration = 4.00, -- Generous safety timeout
	},

	-- 💨 Fast Release Fling (High-momentum Spider-Man launch!)
	Launch = {
		PeakHeightUpwardBoost = 75,     -- Upward catapult boost at peak height (soars cleanly over buildings)
		PeakHeightForwardSpeed = 85,    -- Fast forward gliding speed when releasing at peak height
		BottomForwardBoost = 65,        -- Fast forward boost when releasing at bottom
		BottomUpwardLift = 30,          -- Healthy trajectory lift so you never drop straight down
		VelocityPreservation = 0.98,    -- High momentum preservation
		JumpBoostMultiplier = 1.50,     -- Extra height boost when pressing Spacebar
		MinimumFlingSpeed = 80,         -- Fast forward exit speed so you always glide with high speed
		MaxVelocity = 160,              -- High-speed velocity cap
	},

	-- 🍃 Mid-Air Aerodynamic Gliding (Fast, thrilling flight between swings)
	Gliding = {
		MaxSpeed = 145,                 -- Fast glide speed cap (exhilarating flight)
		DecayRate = 14,                 -- Aerodynamic speed reduction rate (studs/s^2)
		GravityMultiplier = 0.45,       -- Gentle downward gravity curve while gliding
		SteerResponsiveness = 5.5,      -- Mid-air camera steer responsiveness
	},

	-- 🎥 Camera & Dynamic FOV Settings (Web Rush action cam)
	Camera = {
		AutoShiftLock = true,                           -- Auto-lock cursor and rotate camera with mouse
		HideCursor = true,                              -- Hide default mouse pointer
		OverShoulderOffset = Vector3.new(1.75, 1.2, 0), -- Over-the-shoulder hero camera offset
		DynamicFOV = {
			Enabled = true,
			BaseFOV = 70,                               -- Resting FOV
			MaxFOV = 82,                                -- Balanced high-speed swinging FOV
			LerpSpeed = 5,                              -- Smoothness of FOV transitions
		},
	},

	-- 🕷️ Wall-Run & Wall-Crawl System (Automatic wall-running on contact)
	WallMovement = {
		Enabled = true,
		WallRunSpeed = 52,              -- Upward sprint speed along building walls
		WallLateralSpeed = 35,          -- Sideways sprint speed along building walls
		WallJumpForce = 75,             -- Outward & upward catapult force when jumping off walls
		WallStickDistance = 3.5,        -- Maximum distance to attach/stick to walls
		WallDetectionRadius = 4.5,      -- Wall detection radius around character
	},

	-- ✨ Visuals & Audio
	Visuals = {
		RopeColor = Color3.fromRGB(245, 248, 255), -- White spider-web silk
		RopeThickness = 0.12,
		WebShootSoundId = "", -- 🎵 Paste your custom Roblox Sound Asset ID here (e.g. "rbxassetid://123456789")
	},
}

return GrappleConfig



