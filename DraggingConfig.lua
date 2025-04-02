local DraggingConfig = {}
DraggingConfig.__index = DraggingConfig

-- =============================================
-- 1. GENERAL SETTINGS
-- =============================================
DraggingConfig.General = {
	DraggableTag = "Draggable",     -- Tag for draggable objects
	DraggableClasses = {            -- Classes that can be dragged by default
		"Part",
		"MeshPart",
		"Model",
		"BasePart"
	},
	ExcludedClasses = {            -- Classes that can NEVER be dragged
		"Player",                  -- Exclude players
		"Humanoid",                -- Exclude humanoids
		"HumanoidRootPart"         -- Exclude HumanoidRootPart
	}

}

-- =============================================
-- 2. PHYSICS SETTINGS 
-- =============================================
DraggingConfig.Physics = {
	-- Dragging Physics
	DragResponsiveness = 25,        -- Higher = more responsive dragging (1-25)
	MaxForce = 100000,              -- Force applied by AlignPosition

	-- Weight System
	WeightFactor = 0.5,             -- How much weight affects drag speed (0-1)
	MinDragSpeed = 0.3,             -- Minimum drag speed for heavy objects
	UseMassForWeight = true,        -- Use the part's mass for weight calculations

	-- Throwing Physics
	ThrowEnabled = true,            -- Whether objects can be thrown
	ThrowMultiplier = 1.5,          -- Base multiplier for throw velocity
	ThrowVelocitySamples = 8,       -- Number of position samples to calculate throw velocity
	ThrowVelocityMaxSpeed = 80,     -- Maximum throwing speed (studs/sec)
	ThrowMinimumSpeed = 3,          -- Minimum speed to be considered a throw
	AddUpwardForce = true,          -- Add slight upward bias to throws
	UpwardForceAmount = 0.15,       -- Amount of upward force (0-1)

	-- Rotation Stability
	MaxTorque = 1000000,            -- Maximum torque for rotation stability
	RotationResponsiveness = 20,    -- How responsive rotation stability is (1-25)
	StabilizeRotation = false,       -- Whether to prevent objects from spinning during drag

	-- Interpolation
	PositionInterpolationSpeed = 5,     -- Speed of position interpolation (lower = smoother)
	RotationInterpolationSpeed = 3,     -- Speed of rotation interpolation (lower = smoother)
	TransitionDamping = 0.95,           -- Velocity damping during camera transitions
	DisableCollisionsDuringDrag = true,  -- Whether to disable collisions when dragging objects
}

-- =============================================
-- 3. VISUAL SETTINGS
-- =============================================
DraggingConfig.Visual = {
	-- Highlighting
	EnableHighlight = true,         -- Master toggle for all highlighting
	HighlightColor = Color3.fromRGB(0, 170, 255),  -- Main highlight color
	OutlineColor = Color3.fromRGB(255, 255, 255),  -- Outline color
	HighlightTransparency = 1,      -- 0 = solid, 1 = invisible
	OutlineTransparency = 0,        -- 0 = solid, 1 = invisible
	UseOutlineOnly = true,          -- When true, only shows outline with no fill

	-- Labels
	ShowObjectName = true,          -- Whether to show labels above objects
	NameTextColor = Color3.fromRGB(255, 255, 255),   -- Label text color
	NameBackgroundColor = Color3.fromRGB(0, 0, 0),   -- Label background color
	NameBackgroundTransparency = 0.5, -- Label background transparency
	NameTextSize = 35,              -- Label text size
	NameFont = Enum.Font.FredokaOne,-- Font used for object name labels
	NameStrokeColor = Color3.fromRGB(0, 0, 0),     -- Text stroke/outline color
	NameStrokeTransparency = 0.0,   -- Text stroke transparency (0 = visible, 1 = invisible)
	NameUseRoundedCorners = true,   -- Use rounded corners for label background
	NamePadding = UDim.new(0, 5),   -- Padding around text

	-- Notifications
	NotificationsEnabled = false,    -- Master toggle for all notifications
	NotificationDuration = 2,       -- Default duration for notifications in seconds
}

-- =============================================
-- 4. INPUT SETTINGS
-- =============================================
DraggingConfig.Input = {
	-- Rotation Controls
	RotationEnabled = false,
	RotationKey = Enum.KeyCode.R,       -- Key to press for rotation
	RotationAxisToggleKey = Enum.KeyCode.T, -- Key to toggle rotation axis

	-- Fixed Rotation Settings
	RotationIncrement = 10,             -- Fixed angle to rotate (degrees) on each R press
	MobileRotationIncrement = 15,       -- Fixed angle to rotate on mobile rotation button press
	RotationAxis = "Y",                 -- Default rotation axis (Y/X/Z)

	-- Grid Controls
	GridToggleKey = Enum.KeyCode.G,     -- Key to toggle grid
}

-- =============================================
-- 5. BEHAVIOR SETTINGS
-- =============================================
DraggingConfig.Behavior = {
	-- Grid Settings
	GridEnabled = false,            -- Default grid setting
	GridSize = 1,                   -- Grid cell size in studs

	-- Alignment Settings
	SurfaceAlignmentEnabled = true, -- Align objects to surfaces
	SurfaceAlignmentThreshold = 2,  -- Studs from surface to trigger alignment

	-- Collision Settings
	CollisionsEnabled = true,       -- Whether collisions are checked during drag
	CollisionPadding = 0.05,        -- Padding for collision detection

	-- Distance Settings
	MaxDistanceFromPlayer = 20,     -- Maximum distance object can be from player during drag
	MaxDragDistance = 15,           -- Maximum distance to see highlights and start dragging
	FixedHoldDistance = 12,          -- Fixed distance to hold objects from camera
	AutoDropEnabled = true,         -- Whether objects auto-drop when player is too far
	AutoDropCheckRate = 0.5,        -- How often to check for auto-drop (seconds)

	-- Network Settings
	SetNetworkOwnershipOnDrag = true, -- Transfer network ownership during drag
	ResetNetworkOwnershipOnRelease = true, -- Reset network ownership after drag

	-- Remote Settings
	ThrottleRemoteUpdates = true,    -- Limit rotation updates to server (performance)
	RemoteUpdateRate = 0.1,          -- Minimum time between rotation updates to server (seconds)
}

-- =============================================
-- 6. SECURITY SETTINGS
-- =============================================
DraggingConfig.Security = {
	-- Player Protection
	PreventDraggingPlayers = true,      -- Prevent dragging of other players
	PlayerCheckRecursive = true,        -- Check if object is part of a player character recursively

	-- Exclusion by Name
	ExcludedNamePatterns = {           -- Object names containing these strings cannot be dragged
		"Player",
		"Character",
		"NPC"
	},

	-- Permission Controls
	AdminsCanDragAnything = false,     -- Whether admins can override restrictions
	AdminsList = {},                   -- List of admin UserIds if AdminsCanDragAnything is true

	-- Ownership Controls
	OnlyOwnersCanDrag = false,         -- Whether only owners of objects can drag them
	OwnershipAttribute = "Owner",      -- Attribute name used to store owner information
}

local categories = {
	"General",
	"Physics",
	"Visual",
	"Input",
	"Behavior",
	"Security"
}


local categoryLookup = {}
for _, category in ipairs(categories) do
	categoryLookup[category] = true
end

function DraggingConfig:Get(category, setting)
	if not categoryLookup[category] then
		warn("DraggingConfig: Invalid category -", category)
		return nil
	end

	local categoryTable = self[category]
	if not categoryTable then
		warn("DraggingConfig: Category not found -", category)
		return nil
	end

	local value = categoryTable[setting]
	if value == nil then
		warn("DraggingConfig: Setting not found -", category, setting)
	end

	return value
end

function DraggingConfig:Set(category, setting, value)
	if not categoryLookup[category] then
		warn("DraggingConfig: Invalid category -", category)
		return false
	end

	local categoryTable = self[category]
	if not categoryTable then
		warn("DraggingConfig: Category not found -", category)
		return false
	end

	if categoryTable[setting] == nil then
		warn("DraggingConfig: Setting not found -", category, setting)
		return false
	end

	categoryTable[setting] = value
	return true
end

function DraggingConfig:UpdateCategory(category, settings)
	if not categoryLookup[category] then
		warn("DraggingConfig: Invalid category -", category)
		return false
	end

	local categoryTable = self[category]
	if not categoryTable then
		warn("DraggingConfig: Category not found -", category)
		return false
	end

	for setting, value in pairs(settings) do
		if categoryTable[setting] ~= nil then
			categoryTable[setting] = value
		else
			warn("DraggingConfig: Setting not found in category -", category, setting)
		end
	end

	return true
end

function DraggingConfig:GetDefaultValue(category, setting)
	if not categoryLookup[category] then
		return nil
	end

	local categoryTable = self[category]
	if not categoryTable then
		return nil
	end

	return categoryTable[setting]
end

return DraggingConfig