local DraggingUtil = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local Config = nil

DraggingUtil.IsClient = RunService:IsClient()
DraggingUtil.IsServer = RunService:IsServer()
DraggingUtil.ConfigLoaded = false

local mathClamp = math.clamp
local mathMax = math.max
local mathRound = math.round
local Vector3new = Vector3.new
local CFramenew = CFrame.new
local CFrameAngles = CFrame.Angles
local stringFind = string.find
local tableInsert = table.insert

local Config = require(script.Parent.DraggingConfig)

function DraggingUtil.Initialize()
	if not DraggingUtil.ConfigLoaded then
		Config = require(script.Parent.DraggingConfig)
		DraggingUtil.ConfigLoaded = true
	end
end

function DraggingUtil.GetActivationDistance()
	return DraggingUtil.GetConfig("General", "ActivationDistance", 25)
end

function DraggingUtil.SetupCollisionGroups()
	if not Config or not Config.Physics or not Config.Physics.UseCollisionGroups then
		return false
	end

	local PhysicsService = game:GetService("PhysicsService")

	local draggableGroupName = DraggingUtil.GetConfig("Physics", "DraggableCollisionGroupName", "DraggableObjects")
	local playerGroupName = DraggingUtil.GetConfig("Physics", "PlayerCollisionGroupName", "Players")

	local success, errorMsg = pcall(function()
		if not table.find(PhysicsService:GetRegisteredCollisionGroups(), draggableGroupName) then
			PhysicsService:RegisterCollisionGroup(draggableGroupName)
		end

		if not table.find(PhysicsService:GetRegisteredCollisionGroups(), playerGroupName) then
			PhysicsService:RegisterCollisionGroup(playerGroupName)
		end

		PhysicsService:CollisionGroupSetCollidable(draggableGroupName, playerGroupName, false)
	end)

	if not success then
		warn("Failed to setup collision groups: " .. errorMsg)
		return false
	end

	return true
end

function DraggingUtil.SetCollisionGroup(object, groupName)
	if not object then return false end

	local PhysicsService = game:GetService("PhysicsService")
	if not table.find(PhysicsService:GetRegisteredCollisionGroups(), groupName) then
		local success = pcall(function()
			PhysicsService:RegisterCollisionGroup(groupName)
		end)

		if not success then
			warn("Failed to register collision group: " .. groupName)
			return false
		end
	end

	local setSuccess = true

	if object:IsA("BasePart") then
		object.CollisionGroup = groupName
	elseif object:IsA("Model") then
		for _, part in pairs(object:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = groupName
			end
		end
	else
		setSuccess = false
	end

	return setSuccess
end

function DraggingUtil.SetupPlayerCollisionGroups()
	local PhysicsService = game:GetService("PhysicsService")
	local Players = game:GetService("Players")

	local playerGroupName = DraggingUtil.GetConfig("Physics", "PlayerCollisionGroupName", "Players")

	if not table.find(PhysicsService:GetRegisteredCollisionGroups(), playerGroupName) then
		local success = pcall(function()
			PhysicsService:RegisterCollisionGroup(playerGroupName)
		end)

		if not success then
			warn("Failed to register player collision group")
			return
		end
	end

	local function setupPlayerCollisions(player)
		player.CharacterAdded:Connect(function(character)
			task.wait()

			for _, part in pairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CollisionGroup = playerGroupName
				end
			end

			character.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("BasePart") then
					descendant.CollisionGroup = playerGroupName
				end
			end)
		end)
		
		if player.Character then
			for _, part in pairs(player.Character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CollisionGroup = playerGroupName
				end
			end
		end
	end

	for _, player in pairs(Players:GetPlayers()) do
		setupPlayerCollisions(player)
	end

	Players.PlayerAdded:Connect(setupPlayerCollisions)
end

function DraggingUtil.GetConfig(category, setting, default)
	if not DraggingUtil.ConfigLoaded then
		DraggingUtil.Initialize()
	end

	if not Config then
		warn("DraggingUtil: Config could not be loaded")
		return default
	end

	if Config.Get then
		local value = Config:Get(category, setting)
		return value ~= nil and value or default
	else
		if Config[category] and Config[category][setting] ~= nil then
			return Config[category][setting]
		end
		warn("DraggingUtil: Setting not found -", category, setting)
		return default
	end
end

function DraggingUtil.GetPlayerFromInstance(instance)
	local character = instance

	while character and not character:IsA("Model") do
		character = character.Parent
	end

	if character and character:FindFirstChild("Humanoid") then
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character == character then
				return player
			end
		end
	end

	return nil
end

function DraggingUtil.IsPlayerOrCharacter(object)
	if object:IsA("Players") or 
		object:IsA("Player") or 
		object:IsA("Humanoid") or 
		(object:IsA("BasePart") and object.Name == "HumanoidRootPart") then
		return true
	end

	if DraggingUtil.GetConfig("Security", "PlayerCheckRecursive", true) then
		local ancestor = object

		while ancestor do
			if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
				return true
			end

			ancestor = ancestor.Parent

			if ancestor == workspace or ancestor == nil then
				break
			end
		end
	end

	if object.Name then
		local excludedPatterns = DraggingUtil.GetConfig("Security", "ExcludedNamePatterns", {"Player", "Character", "NPC"})
		for _, pattern in ipairs(excludedPatterns) do
			if stringFind(object.Name, pattern) then
				return true
			end
		end
	end

	return false
end

function DraggingUtil.IsDraggable(object)
	if not object or object == workspace or object:IsA("Terrain") then
		return false
	end

	if DraggingUtil.GetConfig("Security", "PreventDraggingPlayers", true) and DraggingUtil.IsPlayerOrCharacter(object) then
		return false
	end

	local excludedClasses = DraggingUtil.GetConfig("General", "ExcludedClasses", {"Player", "Humanoid", "HumanoidRootPart"})
	for _, className in ipairs(excludedClasses) do
		if object:IsA(className) then
			return false
		end
	end

	local draggableTag = DraggingUtil.GetConfig("General", "DraggableTag", "Draggable")
	if CollectionService:HasTag(object, draggableTag) then
		return true
	end

	local draggableClasses = DraggingUtil.GetConfig("General", "DraggableClasses", {"Part", "MeshPart", "Model", "BasePart"})
	for _, className in ipairs(draggableClasses) do
		if object:IsA(className) then
			return true
		end
	end

	return false
end

function DraggingUtil.CalculateWeightFactor(object)
	local weight = 1

	if DraggingUtil.GetConfig("Physics", "UseMassForWeight", true) then
		if object:IsA("BasePart") then
			weight = mathClamp(object:GetMass() / 10, 0.1, 5)
		elseif object:IsA("Model") then
			local totalMass = 0
			local parts = 0

			for _, part in pairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					totalMass = totalMass + part:GetMass()
					parts = parts + 1
				end
			end

			if parts > 0 then
				weight = mathClamp(totalMass / (10 * parts), 0.1, 5)
			end
		end
	end

	local weightFactor = DraggingUtil.GetConfig("Physics", "WeightFactor", 0.5)
	local speedFactor = 1 - (weight - 1) * weightFactor
	return mathMax(speedFactor, DraggingUtil.GetConfig("Physics", "MinDragSpeed", 0.3))
end

function DraggingUtil.SnapToGrid(position, gridSize)
	gridSize = gridSize or 1

	local x = mathRound(position.X / gridSize) * gridSize
	local y = mathRound(position.Y / gridSize) * gridSize
	local z = mathRound(position.Z / gridSize) * gridSize

	return Vector3new(x, y, z)
end

function DraggingUtil.CheckSurfaceAlignment(object, position, threshold)
	if not DraggingUtil.GetConfig("Behavior", "SurfaceAlignmentEnabled", true) then
		return position
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local toExclude = {object}
	if object:IsA("Model") then
		for _, part in pairs(object:GetDescendants()) do
			if part:IsA("BasePart") then
				tableInsert(toExclude, part)
			end
		end
	end
	rayParams.FilterDescendantsInstances = toExclude

	local objectSize = Vector3new(0, 0, 0)
	if object:IsA("BasePart") then
		objectSize = object.Size
	elseif object:IsA("Model") then
		local _, size = object:GetBoundingBox()
		objectSize = size
	end

	local directions = {
		{dir = Vector3new(0, -threshold, 0), upVector = Vector3new(0, 1, 0)},
		{dir = Vector3new(0, threshold, 0), upVector = Vector3new(0, -1, 0)},
		{dir = Vector3new(0, 0, threshold), upVector = Vector3new(0, 0, -1)},
		{dir = Vector3new(0, 0, -threshold), upVector = Vector3new(0, 0, 1)},
		{dir = Vector3new(threshold, 0, 0), upVector = Vector3new(-1, 0, 0)},
		{dir = Vector3new(-threshold, 0, 0), upVector = Vector3new(1, 0, 0)}
	}

	for _, dirData in ipairs(directions) do
		local ray = workspace:Raycast(position, dirData.dir, rayParams)
		if ray then
			local hitPosition = ray.Position
			local normal = ray.Normal

			local offset = 0
			if dirData.dir.Y < 0 then
				offset = objectSize.Y / 2
			elseif math.abs(dirData.dir.X) > 0 or math.abs(dirData.dir.Z) > 0 then
				if math.abs(dirData.dir.X) > 0 then
					offset = objectSize.X / 2
				else
					offset = objectSize.Z / 2
				end
			end

			local adjustedPosition = hitPosition + (normal * offset)

			if dirData.dir.Y < 0 then
				return Vector3new(position.X, adjustedPosition.Y, position.Z)
			end

			return adjustedPosition
		end
	end

	return position
end

function DraggingUtil.GetObjectCenter(object)
	if not object then return Vector3new(0, 0, 0) end

	if object:IsA("Model") then
		if object.PrimaryPart then
			return object:GetPivot().Position
		else
			local sum = Vector3new(0, 0, 0)
			local count = 0

			for _, part in pairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					sum = sum + part.Position
					count = count + 1
				end
			end

			if count > 0 then
				return sum / count
			else
				return Vector3new(0, 0, 0)
			end
		end
	else
		return object.Position
	end
end

function DraggingUtil.SetObjectPosition(object, position)
	if not object then return end

	if object:IsA("Model") then
		if object.PrimaryPart then
			local currentCFrame = object:GetPivot()
			local offset = position - currentCFrame.Position
			object:PivotTo(currentCFrame + offset)
		else
			local currentCenter = DraggingUtil.GetObjectCenter(object)
			local offset = position - currentCenter

			for _, part in pairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Position = part.Position + offset
				end
			end
		end
	else
		object.Position = position
	end
end

function DraggingUtil.LockMouse()
	local success, result = pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		return true
	end)

	return success and result
end

function DraggingUtil.UnlockMouse()
	local success, result = pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		return true
	end)

	return success and result
end

function DraggingUtil.RotateObject(object, axis, angle)
	if not object then return end

	local rotationCFrame
	if axis == "X" then
		rotationCFrame = CFrameAngles(angle, 0, 0)
	elseif axis == "Y" then
		rotationCFrame = CFrameAngles(0, angle, 0)
	elseif axis == "Z" then
		rotationCFrame = CFrameAngles(0, 0, angle)
	else
		return
	end

	if object:IsA("Model") then
		local pivotCFrame = object:GetPivot()
		local pivotPosition = pivotCFrame.Position

		local newCFrame = CFramenew(pivotPosition) * rotationCFrame * CFramenew(-pivotPosition) * pivotCFrame

		object:PivotTo(newCFrame)
	else
		local position = object.Position
		local currentCFrame = object.CFrame

		local newCFrame = CFramenew(position) * rotationCFrame * CFramenew(-position) * currentCFrame

		object.CFrame = newCFrame
	end
end

function DraggingUtil.ApplyCameraRelativeRotation(object, rotationCFrame, camera)
	if not object or not camera then return end

	local camCFrame = camera.CFrame

	if object:IsA("Model") then
		if object.PrimaryPart then
			local pivotCFrame = object:GetPivot()
			local pivotPosition = pivotCFrame.Position

			local toCamSpace = camCFrame:ToObjectSpace(CFramenew(pivotPosition))
			local fromCamSpace = camCFrame * toCamSpace

			local newCFrame = fromCamSpace * rotationCFrame * fromCamSpace:Inverse() * pivotCFrame

			object:PivotTo(newCFrame)

			return newCFrame
		else
			local modelCenter = DraggingUtil.GetObjectCenter(object)

			local toCamSpace = camCFrame:ToObjectSpace(CFramenew(modelCenter))
			local fromCamSpace = camCFrame * toCamSpace

			local rotCFrame = fromCamSpace * rotationCFrame * fromCamSpace:Inverse()

			for _, part in pairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					local partRelative = part.CFrame:ToObjectSpace(CFramenew(modelCenter))
					part.CFrame = rotCFrame * CFramenew(modelCenter) * partRelative
				end
			end

			for _, part in pairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					return part.CFrame
				end
			end
		end
	else
		local position = object.Position

		local toCamSpace = camCFrame:ToObjectSpace(CFramenew(position))
		local fromCamSpace = camCFrame * toCamSpace

		local newCFrame = fromCamSpace * rotationCFrame * fromCamSpace:Inverse() * object.CFrame

		object.CFrame = newCFrame

		return newCFrame
	end

	return nil
end

DraggingUtil.Math = {
	Clamp = function(value, min, max)
		return mathMax(min, math.min(max, value))
	end,

	Distance = function(pos1, pos2)
		return (pos1 - pos2).Magnitude
	end,

	Lerp = function(a, b, t)
		return a + (b - a) * t
	end,

	SmoothDamp = function(current, target, currentVelocity, smoothTime, maxSpeed, deltaTime)
		smoothTime = mathMax(0.0001, smoothTime)
		local num = 2 / smoothTime
		local num2 = num * deltaTime
		local num3 = 1 / (1 + num2 + 0.48 * num2 * num2 + 0.235 * num2 * num2 * num2)
		local num4 = current - target
		local num5 = target
		local num6 = maxSpeed * smoothTime
		num4 = DraggingUtil.Math.Clamp(num4, -num6, num6)
		target = current - num4
		local num7 = (currentVelocity + num * num4) * deltaTime
		currentVelocity = (currentVelocity - num * num7) * num3
		local num8 = target + (num4 + num7) * num3
		if (num5 - current > 0) == (num8 > num5) then
			num8 = num5
			currentVelocity = (num8 - num5) / deltaTime
		end
		return num8, currentVelocity
	end
}


function DraggingUtil.ShowNotification(message, duration)
	if DraggingUtil.GetConfig("Visual", "NotificationsEnabled", true) == false then
		return
	end

	duration = duration or DraggingUtil.GetConfig("Visual", "NotificationDuration", 2)

	pcall(function()
		game.StarterGui:SetCore("SendNotification", {
			Title = "Drag System",
			Text = message,
			Duration = duration
		})
	end)
end

function DraggingUtil.IsNotificationsEnabled()
	return DraggingUtil.GetConfig("Visual", "NotificationsEnabled", true) ~= false
end

DraggingUtil.Initialize()
return DraggingUtil