local DraggingModule = {}
DraggingModule.__index = DraggingModule

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(script.Parent.DraggingConfig)
local Util = require(script.Parent.DraggingUtil)

local Remotes = {}

function DraggingModule:InitializeRemotes()
	if not self.remotesInitialized then
		local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		if not remotesFolder then
			warn("Remotes folder not found in ReplicatedStorage. Creating it...")

			remotesFolder = Instance.new("Folder")
			remotesFolder.Name = "Remotes"
			remotesFolder.Parent = ReplicatedStorage

			local startDragging = Instance.new("RemoteEvent")
			startDragging.Name = "StartDragging"
			startDragging.Parent = remotesFolder

			local updateDragPosition = Instance.new("RemoteEvent")
			updateDragPosition.Name = "UpdateDragPosition"
			updateDragPosition.Parent = remotesFolder

			local stopDragging = Instance.new("RemoteEvent")
			stopDragging.Name = "StopDragging"
			stopDragging.Parent = remotesFolder

			local throwObject = Instance.new("RemoteEvent")
			throwObject.Name = "ThrowObject"
			throwObject.Parent = remotesFolder
		end

		self.Remotes = {
			StartDragging = remotesFolder:FindFirstChild("StartDragging"),
			UpdateDragPosition = remotesFolder:FindFirstChild("UpdateDragPosition"),
			StopDragging = remotesFolder:FindFirstChild("StopDragging"),
			ThrowObject = remotesFolder:FindFirstChild("ThrowObject")
		}

		for name, remote in pairs(self.Remotes) do
			if not remote then
				warn("Remote event " .. name .. " not found!")
			end
		end

		self.remotesInitialized = true
	end

	return self.Remotes
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

function DraggingModule.new()
	local self = setmetatable({}, DraggingModule)

	self.isDragging = false
	self.currentDraggable = nil
	self.dragStartPosition = nil
	self.lastPosition = nil
	self.velocityTracker = {}
	self.velocitySampleTime = 0.25
	self.highlightedObject = nil
	self.draggerPlayers = {}
	self.dragConstraints = {}
	self.rotationAxis = Config:Get("Input", "RotationAxis")
	self.centerOffsetY = -20 
	self.controllerTargetingEnabled = true
	self.controllerTargetOffset = Vector2.new(0, -20) 
	self.controllerTargetUI = nil

	self.activeInputIsController = false

	self.lastInputTime = {
		keyboard = 0,
		mouse = 0,
		controller = 0
	}

	self.controllerDragging = false
	self.controllerRotating = false
	self.controllerRotationSpeed = 0.025
	self.lastRotationUpdate = 0
	self.controllerEnabled = #UserInputService:GetConnectedGamepads() > 0
	self.controllerConfig = {
		DragTrigger = Enum.KeyCode.ButtonR2,
		RotateTrigger = Enum.KeyCode.ButtonL2,
		AxisToggleButton = Enum.KeyCode.ButtonY,
		RotationIncrement = 2,
	}

	self.connections = {}
	return self
end

function DraggingModule:Initialize()
	if Util.IsClient then
		self:InitializeRemotes()
		self:InitializeClient()
		self:InitializeControllerSupport()
	end

	if Util.IsServer then
		self:InitializeRemotes()
		self:InitializeServer()
	end

	return self
end

function DraggingModule:InitializeClient()
	local player = Players.LocalPlayer

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("Remotes folder not found in ReplicatedStorage! Dragging functionality may not work.")
		return
	end

	self.Remotes = {
		StartDragging = remotesFolder:WaitForChild("StartDragging", 5),
		UpdateDragPosition = remotesFolder:WaitForChild("UpdateDragPosition", 5),
		StopDragging = remotesFolder:WaitForChild("StopDragging", 5),
		ThrowObject = remotesFolder:WaitForChild("ThrowObject", 5)
	}

	local allRemotesFound = true
	for name, remote in pairs(self.Remotes) do
		if not remote then
			warn("Remote event " .. name .. " not found!")
			allRemotesFound = false
		end
	end

	if not allRemotesFound then
		warn("Some remote events are missing! Dragging functionality may not work properly.")
	end

	self.isDragging = false
	self.currentDraggable = nil
	self.rotationAxis = Config:Get("Input", "RotationAxis")
	self.velocityTracker = {}
	self.velocitySampleTime = 0.25

	self.activeInputIsController = false
	self.lastInputTime = {
		keyboard = 0,
		mouse = 0,
		controller = 0
	}

	if #UserInputService:GetConnectedGamepads() > 0 then
		self.activeInputIsController = true
		self.lastInputTime.controller = tick()
	end

	if Config:Get("Behavior", "AutoDropEnabled") then
		self.connections.autoDropCheck = RunService.Heartbeat:Connect(function(deltaTime)
			self.autoDropTimer = (self.autoDropTimer or 0) + deltaTime
			if self.autoDropTimer >= Config:Get("Behavior", "AutoDropCheckRate") then
				self:CheckDistanceAndAutoDrop()
				self.autoDropTimer = 0
			end
		end)
	end

	self.connections.inputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or 
			input.UserInputType == Enum.UserInputType.MouseButton2 or
			input.UserInputType == Enum.UserInputType.MouseButton3 or
			input.UserInputType == Enum.UserInputType.MouseWheel then
			self.lastInputTime.mouse = tick()
			self:UpdateInputState()
		elseif input.UserInputType == Enum.UserInputType.Keyboard then
			self.lastInputTime.keyboard = tick()
			self:UpdateInputState()

			if input.KeyCode == Config:Get("Input", "RotationKey") and self.isDragging and self.currentDraggable then
				if not Config:Get("Input", "RotationEnabled", true) then
					Util.ShowNotification("Rotation is disabled in settings", 1)
					return
				end

				local rotationIncrement = math.rad(Config:Get("Input", "RotationIncrement", 10))
				Util.RotateObject(self.currentDraggable, self.rotationAxis, rotationIncrement)

				local newCFrame
				if self.currentDraggable:IsA("BasePart") then
					newCFrame = self.currentDraggable.CFrame
				elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
					newCFrame = self.currentDraggable:GetPivot()
				end

				if newCFrame then
					self.Remotes.UpdateDragPosition:FireServer(
						self.currentDraggable,
						newCFrame,
						true
					)
				end
				self:ApplyKeyboardRotation()
			end

			if input.KeyCode == Config:Get("Input", "RotationAxisToggleKey") and self.isDragging and self.currentDraggable then
				if not Config:Get("Input", "RotationEnabled", true) then
					Util.ShowNotification("Rotation is disabled in settings", 1)
					return
				end

				local axes = {"Y", "X", "Z"}
				local currentIndex = table.find(axes, self.rotationAxis) or 1
				self.rotationAxis = axes[currentIndex % 3 + 1]

				Util.ShowNotification("Rotation axis: " .. self.rotationAxis, 1)
			end

			if input.KeyCode == Config:Get("Input", "GridToggleKey") then
				local gridEnabled = not Config:Get("Behavior", "GridEnabled")
				Config:Set("Behavior", "GridEnabled", gridEnabled)

				Util.ShowNotification("Grid snapping " .. (gridEnabled and "enabled" or "disabled"), 1)
			end
		elseif input.UserInputType == Enum.UserInputType.Gamepad1 then
			self.lastInputTime.controller = tick()
			self:UpdateInputState()

			if input.KeyCode == self.controllerConfig.DragTrigger then
				if not self.controllerDragging and not self.isDragging then
					self:StartControllerDragging()
				end
			elseif input.KeyCode == self.controllerConfig.AxisToggleButton and 
				(self.isDragging or self.controllerDragging) then
				if not Config:Get("Input", "RotationEnabled", true) then
					Util.ShowNotification("Rotation is disabled in settings", 1)
					return
				end

				self:ToggleControllerRotationAxis()
			elseif input.KeyCode == self.controllerConfig.RotateTrigger and 
				(self.isDragging or self.controllerDragging) then
				if not Config:Get("Input", "RotationEnabled", true) then
					Util.ShowNotification("Rotation is disabled in settings", 1)
					return
				end

				self:ApplyControllerRotation()
			end
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 and not self.activeInputIsController then
			local object = self:GetObjectUnderMouse()
			if object and Util.IsDraggable(object) then
				self:StartDragging(object)
			end
		end
	end)

	self.connections.inputEnded = UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and self.isDragging then
			self:EndDragging()
		elseif input.UserInputType == Enum.UserInputType.Gamepad1 and 
			input.KeyCode == self.controllerConfig.DragTrigger and self.controllerDragging then
			self:EndControllerDragging()
		end
	end)

	self.connections.renderStepped = RunService.RenderStepped:Connect(function(deltaTime)
		local targetObject
		if self.activeInputIsController then
			targetObject = self:GetObjectAtScreenCenter()
		else
			targetObject = self:GetObjectUnderMouse()
		end

		if not self.isDragging and not self.controllerDragging then
			self:UpdateHighlight(targetObject)
		end

		if self.isDragging and self.currentDraggable then
			self:UpdateDragging(deltaTime)

			if self.rotationMode and Config:Get("Input", "RotationEnabled", true) then
				self:HandleRotationMode(deltaTime)
			end
		elseif self.controllerDragging and self.currentDraggable then
			self:UpdateControllerDragging(deltaTime)
		end
	end)

	self.connections.inputChanged = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self.lastInputTime.mouse = tick()
			self:UpdateInputState()
		end

		if (input.UserInputType == Enum.UserInputType.MouseMovement or 
			input.UserInputType == Enum.UserInputType.Touch) and 
			(self.isDragging or self.controllerDragging) then

			if self.currentDraggable then
				table.insert(self.velocityTracker, {
					position = Util.GetObjectCenter(self.currentDraggable),
					time = tick()
				})

				local currentTime = tick()
				while #self.velocityTracker > 0 and (currentTime - self.velocityTracker[1].time) > self.velocitySampleTime do
					table.remove(self.velocityTracker, 1)
				end
			end
		end
	end)
end

function DraggingModule:HandleRotationMode(deltaTime)
	if not self.currentDraggable or not self.rotationMode then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local mousePos = UserInputService:GetMouseLocation()

	if not self.lastMousePos then
		self.lastMousePos = mousePos
		return
	end

	local deltaX = (mousePos.X - self.lastMousePos.X) * 0.01
	local deltaY = (mousePos.Y - self.lastMousePos.Y) * 0.01

	local rotationCFrame
	if self.rotationAxis == "Y" then
		rotationCFrame = CFrame.Angles(0, -deltaX, 0)
	elseif self.rotationAxis == "X" then
		rotationCFrame = CFrame.Angles(deltaY, 0, 0)
	elseif self.rotationAxis == "Z" then
		rotationCFrame = CFrame.Angles(0, 0, deltaY)
	end

	local newCFrame = Util.ApplyCameraRelativeRotation(self.currentDraggable, rotationCFrame, camera)

	if self.dragAttachment1 and self.currentDraggable then
		self.dragAttachment1.WorldPosition = Util.GetObjectCenter(self.currentDraggable)
		if self.currentDraggable:IsA("BasePart") then
			self.dragAttachment1.CFrame = self.currentDraggable.CFrame - self.currentDraggable.CFrame.Position
		elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
			self.dragAttachment1.CFrame = self.currentDraggable:GetPivot() - self.currentDraggable:GetPivot().Position
		end
	end

	local currentTime = tick()
	if not self.lastRotationUpdate or (currentTime - self.lastRotationUpdate) > Config:Get("Behavior", "RemoteUpdateRate", 0.1) then
		if newCFrame then
			self.Remotes.UpdateDragPosition:FireServer(
				self.currentDraggable,
				newCFrame,
				true
			)
		end
		self.lastRotationUpdate = currentTime
	end

	self.lastMousePos = mousePos

	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

local function HandleKeyboardRotationInput(self, input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode ~= Config:Get("Input", "RotationKey") or not self.isDragging or not self.currentDraggable then 
		return
	end

	if not Config:Get("Input", "RotationEnabled", true) then
		return
	end

	local rotationIncrement = math.rad(Config:Get("Input", "RotationIncrement", 10))
	Util.RotateObject(self.currentDraggable, self.rotationAxis, rotationIncrement)

	local newCFrame
	if self.currentDraggable:IsA("BasePart") then
		newCFrame = self.currentDraggable.CFrame
	elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
		newCFrame = self.currentDraggable:GetPivot()
	end

	if newCFrame then
		self.Remotes.UpdateDragPosition:FireServer(
			self.currentDraggable,
			newCFrame,
			true
		)
	end

	self:UpdateRotationConstraints()
end

function DraggingModule:UpdateRotationConstraints()
	if not self.dragAttachment1 or not self.currentDraggable then return end

	self.dragAttachment1.WorldPosition = Util.GetObjectCenter(self.currentDraggable)

	if self.currentDraggable:IsA("BasePart") then
		self.dragAttachment1.CFrame = self.currentDraggable.CFrame - self.currentDraggable.CFrame.Position
	elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
		self.dragAttachment1.CFrame = self.currentDraggable:GetPivot() - self.currentDraggable:GetPivot().Position
	end
end

function DraggingModule:UpdateInputState()
	local currentTime = tick()
	local mouseTime = self.lastInputTime.mouse
	local keyboardTime = self.lastInputTime.keyboard
	local controllerTime = self.lastInputTime.controller

	local mostRecentNonController = math.max(mouseTime, keyboardTime)
	local wasController = self.activeInputIsController

	self.activeInputIsController = controllerTime > mostRecentNonController

	if self.activeInputIsController ~= wasController then
		if self.controllerTargetDot and self.controllerTargetDot.gui then
			self.controllerTargetDot.gui.Enabled = self.activeInputIsController and self.controllerEnabled
		end

		UserInputService.MouseIconEnabled = not self.activeInputIsController
	end
end

function DraggingModule:UpdateTargetIndicator()
	if not self.targetIndicator or not self.targetIndicator.dot then return end

	self.targetIndicator.dot.Position = UDim2.new(0.5, 0, 0.5, self.centerOffsetY)
end

function DraggingModule:UpdateTargeting(deltaTime)
	if self.targetIndicator and self.targetIndicator.dot then
		self.targetIndicator.dot.Visible = self.activeInputIsController
	end

	local targetObject
	if self.activeInputIsController then
		targetObject = self:GetObjectAtScreenCenter()
	else
		targetObject = self:GetObjectUnderMouse()
	end

	if not self.isDragging and not self.controllerDragging then
		self:UpdateHighlight(targetObject)
	end
end

function DraggingModule:CheckDistanceAndAutoDrop()
	if not (self.isDragging or self.controllerDragging) or not self.currentDraggable then
		return
	end

	local player = Players.LocalPlayer
	if not player or not player.Character then
		return
	end

	local character = player.Character
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local objectCenter = Util.GetObjectCenter(self.currentDraggable)
	local playerPosition = humanoidRootPart.Position
	local distance = (objectCenter - playerPosition).Magnitude

	if distance > Config:Get("Behavior", "MaxDistanceFromPlayer") then
		if self.isDragging then
			self:EndDragging(false)
		elseif self.controllerDragging then
			self:EndControllerDragging()
		end

		Util.ShowNotification("Object dropped: Too far from player", 2)
	end
end

function DraggingModule:GetObjectUnderMouse()
	local mouse = Players.LocalPlayer:GetMouse()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local playersToExclude = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(playersToExclude, player.Character)
		end
	end
	raycastParams.FilterDescendantsInstances = playersToExclude

	local maxDistance = Config:Get("Behavior", "MaxDragDistance") or 20
	local result = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * maxDistance, raycastParams)

	if not result then return nil end

	local hitPart = result.Instance

	if hitPart and Util.IsDraggable(hitPart) then
		if hitPart:IsA("BasePart") and not hitPart.Anchored then
			return hitPart
		end
	end

	local model = hitPart:FindFirstAncestorWhichIsA("Model")
	if model and model ~= workspace and Util.IsDraggable(model) then
		local hasUnanchored = false
		for _, part in pairs(model:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then
				hasUnanchored = true
				break
			end
		end

		if hasUnanchored then
			return model
		end
	end

	return nil
end

function DraggingModule:GetObjectAtScreenCenter()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local viewportSize = camera.ViewportSize
	local centerX = viewportSize.X / 2
	local centerY = viewportSize.Y / 2 + self.controllerTargetOffset.Y

	local centerRay = camera:ScreenPointToRay(centerX, centerY)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local playersToExclude = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(playersToExclude, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = playersToExclude

	local maxDistance = Config:Get("Behavior", "MaxDragDistance") or 20
	local result = workspace:Raycast(centerRay.Origin, centerRay.Direction * maxDistance, rayParams)

	if not result then return nil end

	local hitPart = result.Instance

	if hitPart and Util.IsDraggable(hitPart) then
		if hitPart:IsA("BasePart") and not hitPart.Anchored then
			return hitPart
		end
	end

	local model = hitPart:FindFirstAncestorWhichIsA("Model")
	if model and model ~= workspace and Util.IsDraggable(model) then
		local hasUnanchored = false
		for _, part in pairs(model:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then
				hasUnanchored = true
				break
			end
		end

		if hasUnanchored then
			return model
		end
	end

	return nil
end

function DraggingModule:CreateControllerTargetDot()
	if self.controllerTargetDot and self.controllerTargetDot.gui then
		self.controllerTargetDot.gui:Destroy()
	end

	local player = Players.LocalPlayer
	if not player then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ControllerTargetDot"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local dot = Instance.new("Frame")
	dot.Name = "TargetDot"
	dot.Size = UDim2.new(0, 6, 0, 6)
	dot.Position = UDim2.new(0.5, 0, 0.5, -20)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.Thickness = 1
	outline.Transparency = 0.5
	outline.Parent = dot

	dot.Parent = screenGui

	self.controllerTargetDot = {
		gui = screenGui,
		dot = dot
	}

	self.controllerTargetOffset = Vector2.new(0, -20)

	screenGui.Enabled = self.controllerEnabled
	screenGui.Parent = player:WaitForChild("PlayerGui")
end

function DraggingModule:InitializeControllerSupport()
	self.controllerEnabled = #UserInputService:GetConnectedGamepads() > 0
	self:CreateControllerTargetDot()

	self.controllerConfig = {
		DragTrigger = Enum.KeyCode.ButtonR2,
		RotateTrigger = Enum.KeyCode.ButtonL2,
		AxisToggleButton = Enum.KeyCode.ButtonY,
		RotationIncrement = 10,
	}

	if self.controllerEnabled then
		UserInputService.MouseIconEnabled = false

		pcall(function()
			if Config:Get("Visual", "NotificationsEnabled", true) ~= false then
				game:GetService("StarterGui"):SetCore("SendNotification", {
					Title = "Controller Detected",
					Text = "Controller support initialized. Use RT to drag objects.",
					Duration = 5
				})
			end
		end)
	end

	self.connections.gamepadConnected = UserInputService.GamepadConnected:Connect(function(gamepad)
		self.controllerEnabled = true
		self.lastInputTime.controller = tick()
		self:UpdateInputState()

		if self.controllerTargetDot and self.controllerTargetDot.gui then
			self.controllerTargetDot.gui.Enabled = true
		end
		UserInputService.MouseIconEnabled = false

		if Config:Get("Visual", "NotificationsEnabled", true) ~= false then
			game.StarterGui:SetCore("SendNotification", {
				Title = "Controller Support",
				Text = "Controller connected. RT to drag, LT to rotate, Y to change axis",
				Duration = 5
			})
		end
	end)

	self.connections.gamepadDisconnected = UserInputService.GamepadDisconnected:Connect(function(gamepad)
		if #UserInputService:GetConnectedGamepads() == 0 then
			self.controllerEnabled = false
			self.lastInputTime.controller = 0
			self:UpdateInputState()
			self:EndControllerDragging()

			if self.controllerTargetDot and self.controllerTargetDot.gui then
				self.controllerTargetDot.gui.Enabled = false
			end
			UserInputService.MouseIconEnabled = true
		end
	end)

	local function handleTriggerInput(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			self.lastInputTime.controller = tick()
			self:UpdateInputState()

			if input.KeyCode == self.controllerConfig.DragTrigger then
				local triggerValue = input.Position.Z

				if triggerValue > 0.8 and not self.controllerDragging and not self.isDragging then
					self:StartControllerDragging()
				elseif triggerValue < 0.2 and self.controllerDragging then
					self:EndControllerDragging()
				end
			end
		end
	end

	self.connections.triggerChanged = UserInputService.InputChanged:Connect(handleTriggerInput)

	self.connections.inputBeganGamepad = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			self.lastInputTime.controller = tick()
			self:UpdateInputState()

			if input.KeyCode == self.controllerConfig.DragTrigger then
				if self.controllerDragging then
					self:EndControllerDragging()
				else
					self:StartControllerDragging()
				end
			end

			if input.KeyCode == self.controllerConfig.RotateTrigger and 
				(self.controllerDragging or self.isDragging) and self.currentDraggable then
				self:ApplyControllerRotation()
			end

			if input.KeyCode == self.controllerConfig.AxisToggleButton and 
				(self.isDragging or self.controllerDragging) and self.currentDraggable then
				self:ToggleControllerRotationAxis()
			end
		end
	end)

	self.connections.inputChangedGamepad = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			self.lastInputTime.controller = tick()
			self:UpdateInputState()

			if input.KeyCode == self.controllerConfig.DragTrigger then
				local triggerValue = input.Position.Z

				if triggerValue > 0.7 and not self.controllerDragging and not self.isDragging then
					self:StartControllerDragging()
				elseif triggerValue < 0.3 and self.controllerDragging then
					self:EndControllerDragging()
				end
			end
		end
	end)
end

function DraggingModule:StartControllerDragging()
	if self.isDragging or self.controllerDragging then return end

	local object = self:GetObjectAtScreenCenter()

	if object and Util.IsDraggable(object) then
		self.controllerDragging = true
		self.currentDraggable = object
		self.dragStartPosition = Util.GetObjectCenter(object)
		self.lastPosition = self.dragStartPosition
		self.velocityTracker = {}
		self.lastServerUpdateTime = tick()

		self:CreateDragConstraints(object)

		self.Remotes.StartDragging:FireServer(object)

		pcall(function()
			local hapticsService = game:GetService("HapticService")
			if hapticsService then
				hapticsService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0.5)
				task.delay(0.2, function()
					hapticsService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
				end)
			end
		end)

		Util.ShowNotification("Dragging: " .. object.Name, 2)
	else
		Util.ShowNotification("No draggable object found", 2)
	end
end

function DraggingModule:ToggleControllerRotationAxis()
	local axes = {"Y", "X", "Z"}
	local currentIndex = table.find(axes, self.rotationAxis) or 1
	self.rotationAxis = axes[currentIndex % 3 + 1]

	Util.ShowNotification("Rotation axis: " .. self.rotationAxis, 1)
end

function DraggingModule:UpdateControllerDragging(deltaTime)
	if not self.controllerDragging or not self.currentDraggable then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local targetPosition = self:CalculateTargetPosition()

	if Config:Get("Behavior", "GridEnabled") then
		targetPosition = Util.SnapToGrid(targetPosition, Config:Get("Behavior", "GridSize"))
	end

	if Config:Get("Behavior", "SurfaceAlignmentEnabled") then
		targetPosition = Util.CheckSurfaceAlignment(
			self.currentDraggable, 
			targetPosition, 
			Config:Get("Behavior", "SurfaceAlignmentThreshold")
		)
	end

	if self.dragAttachment1 then
		self.dragAttachment1.WorldPosition = targetPosition

		if self.currentDraggable:IsA("BasePart") then
		elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
		end
	end

	table.insert(self.velocityTracker, {
		position = targetPosition,
		time = tick()
	})

	local currentTime = tick()
	while #self.velocityTracker > 0 and 
		(currentTime - self.velocityTracker[1].time) > self.velocitySampleTime do
		table.remove(self.velocityTracker, 1)
	end

	self.lastPosition = targetPosition

	if not self.lastServerUpdateTime or (tick() - self.lastServerUpdateTime) > 0.1 then
		self.Remotes.UpdateDragPosition:FireServer(
			self.currentDraggable,
			CFrame.new(targetPosition),
			false
		)
		self.lastServerUpdateTime = tick()
	end
end

function DraggingModule:ApplyControllerRotation()
	if not self.currentDraggable then return end

	if not Config:Get("Input", "RotationEnabled", true) then
		return
	end

	local rotationIncrement = math.rad(self.controllerConfig.RotationIncrement)

	local rotationCFrame
	if self.rotationAxis == "X" then
		rotationCFrame = CFrame.Angles(rotationIncrement, 0, 0)
	elseif self.rotationAxis == "Y" then
		rotationCFrame = CFrame.Angles(0, rotationIncrement, 0)
	elseif self.rotationAxis == "Z" then
		rotationCFrame = CFrame.Angles(0, 0, rotationIncrement)
	end

	local newCFrame = self:ApplyRotationToObject(self.currentDraggable, rotationCFrame)

	self:UpdateRotationConstraints()

	if newCFrame then
		self.Remotes.UpdateDragPosition:FireServer(
			self.currentDraggable,
			newCFrame,
			true
		)
	end
end

function DraggingModule:ApplyRotationToObject(object, rotationCFrame)
	if not object then return nil end

	local newCFrame

	if object:IsA("Model") then
		if object.PrimaryPart then
			local pivotCFrame = object:GetPivot()
			local pivotPosition = pivotCFrame.Position

			newCFrame = CFrame.new(pivotPosition) * 
				rotationCFrame * 
				CFrame.new(-pivotPosition) * 
				pivotCFrame

			object:PivotTo(newCFrame)
		else
			local modelCenter = Util.GetObjectCenter(object)

			for _, part in pairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					local partPos = part.Position
					local offset = partPos - modelCenter
					local rotatedOffset = rotationCFrame:VectorToWorldSpace(offset)
					part.Position = modelCenter + rotatedOffset

					part.CFrame = CFrame.new(part.Position) * part.CFrame.Rotation * rotationCFrame
				end
			end

			for _, part in pairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					newCFrame = part.CFrame
					break
				end
			end
		end
	else
		local position = object.Position
		local currentCFrame = object.CFrame

		newCFrame = CFrame.new(position) * 
			rotationCFrame * 
			CFrame.new(-position) * 
			currentCFrame

		object.CFrame = newCFrame
	end

	return newCFrame
end

function DraggingModule:EndControllerDragging()
	if not self.controllerDragging or not self.currentDraggable then return end

	local object = self.currentDraggable

	local throwVelocity = self:CalculateThrowVelocity()

	self:CleanupDragConstraints()

	if throwVelocity.Magnitude > Config:Get("Physics", "ThrowMinimumSpeed") then
		self.Remotes.ThrowObject:FireServer(object, throwVelocity)

		pcall(function()
			local hapticsService = game:GetService("HapticService")
			if hapticsService then
				hapticsService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0.8)
				hapticsService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0.6)
				task.delay(0.3, function()
					hapticsService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
					hapticsService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
				end)
			end
		end)
	else
		self.Remotes.StopDragging:FireServer(object)

		pcall(function()
			local hapticsService = game:GetService("HapticService")
			if hapticsService then
				hapticsService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0.3)
				task.delay(0.15, function()
					hapticsService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
				end)
			end
		end)
	end

	self.controllerDragging = false
	self.controllerRotating = false
	self.currentDraggable = nil
	self.dragStartPosition = nil
	self.lastPosition = nil
	self.velocityTracker = {}

	Util.ShowNotification("Dragging: " .. object.Name, 2)
end

function DraggingModule:ApplyFixedRotation()
	if not self.currentDraggable then return end

	local rotationIncrement = math.rad(Config:Get("Input", "RotationIncrement"))

	local rotationCFrame
	if self.rotationAxis == "X" then
		rotationCFrame = CFrame.Angles(rotationIncrement, 0, 0)
	elseif self.rotationAxis == "Y" then
		rotationCFrame = CFrame.Angles(0, rotationIncrement, 0)
	elseif self.rotationAxis == "Z" then
		rotationCFrame = CFrame.Angles(0, 0, rotationIncrement)
	end

	local newCFrame = self:ApplyRotationToObject(self.currentDraggable, rotationCFrame)

	if newCFrame then
		self.Remotes.UpdateDragPosition:FireServer(
			self.currentDraggable,
			newCFrame,
			true
		)
	end

	if self.dragAttachment1 and self.currentDraggable then
		self.dragAttachment1.WorldPosition = Util.GetObjectCenter(self.currentDraggable)

		if self.currentDraggable:IsA("BasePart") then
			self.dragAttachment1.CFrame = self.currentDraggable.CFrame - self.currentDraggable.CFrame.Position
		elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
			self.dragAttachment1.CFrame = self.currentDraggable:GetPivot() - self.currentDraggable:GetPivot().Position
		end
	end

	Util.ShowNotification("Object rotated on " .. self.rotationAxis .. "-axis", 1)
end

function DraggingModule:SetupCollisionGroups()
	local PhysicsService = game:GetService("PhysicsService")

	local draggableGroupName = "DraggableObjects"
	local playerGroupName = "Players"

	local success, errMsg = pcall(function()
		local registeredGroups = PhysicsService:GetRegisteredCollisionGroups()

		if not table.find(registeredGroups, draggableGroupName) then
			PhysicsService:RegisterCollisionGroup(draggableGroupName)
		end

		if not table.find(registeredGroups, playerGroupName) then
			PhysicsService:RegisterCollisionGroup(playerGroupName)
		end

		PhysicsService:CollisionGroupSetCollidable(draggableGroupName, playerGroupName, false)
	end)

	if not success then
		warn("Failed to setup collision groups: " .. errMsg)
	end

	self.collisionGroups = {
		draggable = draggableGroupName,
		player = playerGroupName
	}

	self:SetupPlayerCollisions()

	return success
end

function DraggingModule:SetupPlayerCollisions()
	local Players = game:GetService("Players")

	local function setupPlayerCharacter(character)
		if not character then return end

		for _, part in pairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = self.collisionGroups.player
			end
		end

		character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = self.collisionGroups.player
			end
		end)
	end

	for _, player in pairs(Players:GetPlayers()) do
		if player.Character then
			setupPlayerCharacter(player.Character)
		end

		player.CharacterAdded:Connect(setupPlayerCharacter)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(setupPlayerCharacter)
	end)
end

function DraggingModule:GetRemotes()
	if not self.Remotes then
		local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		if not remotesFolder then
			warn("Remotes folder not found in ReplicatedStorage!")
			return nil
		end

		self.Remotes = {
			StartDragging = remotesFolder:FindFirstChild("StartDragging"),
			UpdateDragPosition = remotesFolder:FindFirstChild("UpdateDragPosition"),
			StopDragging = remotesFolder:FindFirstChild("StopDragging"),
			ThrowObject = remotesFolder:FindFirstChild("ThrowObject")
		}
		for name, remote in pairs(self.Remotes) do
			if not remote then
				warn("Remote event " .. name .. " not found!")
			end
		end
	end

	return self.Remotes
end

function DraggingModule:InitializeServer()
	local module = self

	if not module.originalProperties then
		module.originalProperties = {}
	end

	if not module.draggerPlayers then
		module.draggerPlayers = {}
	end

	if Config.Physics.DisableCollisionsDuringDrag then
		self:SetupCollisionGroups()
	end

	local Remotes = self:GetRemotes()
	if not Remotes or not Remotes.StartDragging then
		warn("Failed to initialize server: Remotes not found")
		return
	end

	Remotes.StartDragging.OnServerEvent:Connect(function(player, object)
		if not object or not object:IsA("Instance") then
			warn("Invalid object received in StartDragging event")
			return
		end

		if not module:CanPlayerDragObject(player, object) then return end

		if module:IsFullyAnchored(object) then
			return
		end

		local originalProperties = {
			Owner = player,
			Velocity = {},
			Anchored = {},
			CanCollide = {},
			CollisionGroup = {}
		}

		if object:IsA("BasePart") then
			originalProperties.Velocity[object] = object.AssemblyLinearVelocity
			originalProperties.Anchored[object] = object.Anchored
			originalProperties.CanCollide[object] = object.CanCollide
			originalProperties.CollisionGroup[object] = object.CollisionGroup

			if Config.Physics.DisableCollisionsDuringDrag then
				if module.collisionGroups then
					object.CollisionGroup = module.collisionGroups.draggable
				else
					object.CanCollide = false
				end
			end
		elseif object:IsA("Model") then
			for _, part in pairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					originalProperties.Velocity[part] = part.AssemblyLinearVelocity
					originalProperties.Anchored[part] = part.Anchored
					originalProperties.CanCollide[part] = part.CanCollide
					originalProperties.CollisionGroup[part] = part.CollisionGroup

					if Config.Physics.DisableCollisionsDuringDrag then
						if module.collisionGroups then
							part.CollisionGroup = module.collisionGroups.draggable
						else
							part.CanCollide = false
						end
					end
				end
			end
		end

		if Config.Behavior.SetNetworkOwnershipOnDrag then
			pcall(function()
				if object:IsA("BasePart") and not object.Anchored then
					object:SetNetworkOwner(player)
				elseif object:IsA("Model") then
					for _, part in pairs(object:GetDescendants()) do
						if part:IsA("BasePart") and not part.Anchored then
							part:SetNetworkOwner(player)
						end
					end
				end
			end)
		end

		module.draggerPlayers[object] = player
		module.originalProperties[object] = originalProperties
	end)

	Remotes.StopDragging.OnServerEvent:Connect(function(player, object)
		if not object or not object:IsA("Instance") then
			warn("Invalid object received in StopDragging event")
			return
		end

		if not module.draggerPlayers or not module.draggerPlayers[object] or module.draggerPlayers[object] ~= player then
			return
		end

		local props = module.originalProperties and module.originalProperties[object]
		if props then
			if object:IsA("BasePart") then
				if props.CollisionGroup[object] then
					object.CollisionGroup = props.CollisionGroup[object]
				end
				if props.CanCollide[object] ~= nil then
					object.CanCollide = props.CanCollide[object]
				end
			elseif object:IsA("Model") then
				for _, part in pairs(object:GetDescendants()) do
					if part:IsA("BasePart") then
						if props.CollisionGroup[part] then
							part.CollisionGroup = props.CollisionGroup[part]
						end
						if props.CanCollide[part] ~= nil then
							part.CanCollide = props.CanCollide[part]
						end
					end
				end
			end
		end

		if Config.Behavior.ResetNetworkOwnershipOnRelease then
			pcall(function()
				if object:IsA("BasePart") and not object.Anchored then
					object:SetNetworkOwner(nil)
				elseif object:IsA("Model") then
					for _, part in pairs(object:GetDescendants()) do
						if part:IsA("BasePart") and not part.Anchored then
							part:SetNetworkOwner(nil)
						end
					end
				end
			end)
		end

		if module.originalProperties then
			module.originalProperties[object] = nil
		end

		if module.draggerPlayers then
			module.draggerPlayers[object] = nil
		end
	end)

	Remotes.ThrowObject.OnServerEvent:Connect(function(player, object, velocity)
		if not object or not object:IsA("Instance") then
			warn("Invalid object received in ThrowObject event")
			return
		end

		if not module.draggerPlayers or not module.draggerPlayers[object] or module.draggerPlayers[object] ~= player then
			return
		end

		local props = module.originalProperties and module.originalProperties[object]
		if props then
			if object:IsA("BasePart") then
				if Config.Behavior.ResetNetworkOwnershipOnRelease then
					pcall(function() 
						object:SetNetworkOwner(nil) 
					end)
				end

				if props.CollisionGroup[object] then
					object.CollisionGroup = props.CollisionGroup[object]
				end
				if props.CanCollide[object] ~= nil then
					object.CanCollide = props.CanCollide[object]
				end

				object.Anchored = false

				module:ApplyVelocityToObject(object, velocity)
			elseif object:IsA("Model") then
				for _, part in pairs(object:GetDescendants()) do
					if part:IsA("BasePart") then
						if Config.Behavior.ResetNetworkOwnershipOnRelease then
							pcall(function() 
								part:SetNetworkOwner(nil) 
							end)
						end

						if props.CollisionGroup[part] then
							part.CollisionGroup = props.CollisionGroup[part]
						end
						if props.CanCollide[part] ~= nil then
							part.CanCollide = props.CanCollide[part]
						end

						if props.Anchored[part] ~= nil then
							part.Anchored = props.Anchored[part]
						end
					end
				end

				if object.PrimaryPart then
					module:ApplyVelocityToObject(object.PrimaryPart, velocity)
				else
					for _, part in pairs(object:GetDescendants()) do
						if part:IsA("BasePart") and not part.Anchored then
							module:ApplyVelocityToObject(part, velocity * 0.8)
						end
					end
				end
			end

			if module.originalProperties then
				module.originalProperties[object] = nil
			end

			if module.draggerPlayers then
				module.draggerPlayers[object] = nil
			end
		end
	end)
end

function DraggingModule:StartDragging(object)
	if self.isDragging or not object then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

	self.isDragging = true
	self.currentDraggable = object
	self.dragStartPosition = Util.GetObjectCenter(object)
	self.lastPosition = self.dragStartPosition
	self.velocityTracker = {}

	self:CreateDragConstraints(object)

	if not self.Remotes or not self.Remotes.StartDragging then
		warn("Cannot start dragging: Remote events not initialized")
		self:EndDragging()
		return
	end

	self.Remotes.StartDragging:FireServer(object)
end

function DraggingModule:CreateDragConstraints(object)
	self:CleanupDragConstraints()

	self.dragConstraints = {}

	if object:IsA("BasePart") then
		self:CreatePartDragConstraints(object)
	elseif object:IsA("Model") then
		self:CreateModelDragConstraints(object)
	end
end

function DraggingModule:CreatePartDragConstraints(part)
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "DragAttachment0"
	attachment0.Position = Vector3.new(0, 0, 0)
	attachment0.Parent = part

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "DragAttachment1"
	attachment1.WorldPosition = Util.GetObjectCenter(part)
	attachment1.Parent = workspace.Terrain

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "DragAlignPosition"
	alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
	alignPosition.Attachment0 = attachment0
	alignPosition.Attachment1 = attachment1
	alignPosition.RigidityEnabled = false
	alignPosition.MaxForce = Config:Get("Physics", "MaxForce")
	alignPosition.Responsiveness = Config:Get("Physics", "DragResponsiveness")
	alignPosition.Parent = part

	local weightFactor = Util.CalculateWeightFactor(part)
	alignPosition.Responsiveness = alignPosition.Responsiveness * weightFactor

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "DragAlignOrientation"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	alignOrientation.Attachment0 = attachment0
	alignOrientation.Attachment1 = attachment1
	alignOrientation.RigidityEnabled = true
	alignOrientation.MaxTorque = Config:Get("Physics", "MaxTorque", 1000000)
	alignOrientation.Responsiveness = Config:Get("Physics", "RotationResponsiveness", 20)
	alignOrientation.Parent = part

	attachment1.CFrame = part.CFrame - part.CFrame.Position

	table.insert(self.dragConstraints, attachment0)
	table.insert(self.dragConstraints, attachment1)
	table.insert(self.dragConstraints, alignPosition)
	table.insert(self.dragConstraints, alignOrientation)

	self.dragAttachment1 = attachment1
end

function DraggingModule:CreateModelDragConstraints(model)
	if model.PrimaryPart then
		self:CreatePartDragConstraints(model.PrimaryPart)
	else
		local primaryPart = nil
		for _, part in pairs(model:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then
				primaryPart = part
				break
			end
		end

		if primaryPart then
			self:CreatePartDragConstraints(primaryPart)
		else
			self.isDragging = false
			self.currentDraggable = nil
			warn("Cannot drag model with no unanchored parts")
		end
	end
end

function DraggingModule:CleanupDragConstraints()
	for _, constraint in ipairs(self.dragConstraints) do
		if constraint and constraint.Parent then
			constraint:Destroy()
		end
	end

	self.dragConstraints = {}
	self.dragAttachment1 = nil
end

function DraggingModule:UpdateDragging(deltaTime)
	if not self.currentDraggable then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local targetPosition = self:CalculateTargetPosition()

	if Config:Get("Behavior", "GridEnabled") then
		targetPosition = Util.SnapToGrid(targetPosition, Config:Get("Behavior", "GridSize"))
	end

	if Config:Get("Behavior", "SurfaceAlignmentEnabled") then
		targetPosition = Util.CheckSurfaceAlignment(
			self.currentDraggable, 
			targetPosition, 
			Config:Get("Behavior", "SurfaceAlignmentThreshold")
		)
	end

	if self.dragAttachment1 then
		self.dragAttachment1.WorldPosition = targetPosition
	end

	table.insert(self.velocityTracker, {
		position = targetPosition,
		time = tick()
	})

	local currentTime = tick()
	while #self.velocityTracker > 0 and 
		(currentTime - self.velocityTracker[1].time) > self.velocitySampleTime do
		table.remove(self.velocityTracker, 1)
	end

	self.lastPosition = targetPosition

	if not self.Remotes or not self.Remotes.UpdateDragPosition then
		return
	end

	if not self.lastServerUpdateTime or (currentTime - self.lastServerUpdateTime) > Config:Get("Behavior", "RemoteUpdateRate", 0.1) then
		self.Remotes.UpdateDragPosition:FireServer(
			self.currentDraggable,
			CFrame.new(targetPosition),
			false
		)
		self.lastServerUpdateTime = currentTime
	end
end

function DraggingModule:ApplyKeyboardRotation()
	if not self.currentDraggable then return end

	if not Config:Get("Input", "RotationEnabled", true) then
		return
	end

	local rotationIncrement = math.rad(Config:Get("Input", "RotationIncrement", 10))

	local rotationCFrame
	if self.rotationAxis == "X" then
		rotationCFrame = CFrame.Angles(rotationIncrement, 0, 0)
	elseif self.rotationAxis == "Y" then
		rotationCFrame = CFrame.Angles(0, rotationIncrement, 0)
	elseif self.rotationAxis == "Z" then
		rotationCFrame = CFrame.Angles(0, 0, rotationIncrement)
	end

	local newCFrame = self:ApplyRotationToObject(self.currentDraggable, rotationCFrame)

	if self.dragAttachment1 and self.currentDraggable then
		self.dragAttachment1.WorldPosition = Util.GetObjectCenter(self.currentDraggable)

		if self.currentDraggable:IsA("BasePart") then
			self.dragAttachment1.CFrame = self.currentDraggable.CFrame - self.currentDraggable.CFrame.Position
		elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
			self.dragAttachment1.CFrame = self.currentDraggable:GetPivot() - self.currentDraggable:GetPivot().Position
		end
	end

	if newCFrame then
		self.Remotes.UpdateDragPosition:FireServer(
			self.currentDraggable,
			newCFrame,
			true
		)
	end
end

function DraggingModule:CalculateTargetPosition()
	local camera = workspace.CurrentCamera
	if not camera then return Vector3.new(0, 0, 0) end

	local lookDirection = camera.CFrame.LookVector
	local cameraPosition = camera.CFrame.Position

	local player = Players.LocalPlayer
	local character = player.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
	local playerPosition = humanoidRootPart and humanoidRootPart.Position or cameraPosition

	local fixedDistanceFromCamera = Config:Get("Behavior", "FixedHoldDistance") or 8
	local targetPosition = cameraPosition + (lookDirection * fixedDistanceFromCamera)

	local toTarget = targetPosition - playerPosition
	local distance = toTarget.Magnitude
	local maxDistance = Config:Get("Behavior", "MaxDistanceFromPlayer")

	if distance > maxDistance then
		targetPosition = playerPosition + (toTarget.Unit * maxDistance)
	end

	return targetPosition
end

function DraggingModule:EndDragging()
	if not self.isDragging or not self.currentDraggable then return end

	local object = self.currentDraggable

	local throwVelocity = self:CalculateThrowVelocity()

	self:CleanupDragConstraints()

	if not self.Remotes then
		warn("Cannot end dragging properly: Remote events not initialized")
		self.isDragging = false
		self.currentDraggable = nil
		self.dragStartPosition = nil
		self.lastPosition = nil
		self.velocityTracker = {}
		return
	end

	if throwVelocity.Magnitude > Config:Get("Physics", "ThrowMinimumSpeed") and self.Remotes.ThrowObject then
		self.Remotes.ThrowObject:FireServer(object, throwVelocity)
	elseif self.Remotes.StopDragging then
		self.Remotes.StopDragging:FireServer(object)
	end

	self.isDragging = false
	self.currentDraggable = nil
	self.dragStartPosition = nil
	self.lastPosition = nil
	self.velocityTracker = {}
end

function DraggingModule:CalculateThrowVelocity()
	if not Config:Get("Physics", "ThrowEnabled") or #self.velocityTracker < 2 then
		return Vector3.new(0, 0, 0)
	end

	local validSamples = {}
	local currentTime = tick()

	for _, sample in ipairs(self.velocityTracker) do
		if currentTime - sample.time <= self.velocitySampleTime then
			table.insert(validSamples, sample)
		end
	end

	if #validSamples < 2 then
		return Vector3.new(0, 0, 0)
	end

	table.sort(validSamples, function(a, b)
		return a.time > b.time
	end)

	local newest = validSamples[1]
	local oldest = validSamples[#validSamples]

	local timeDiff = newest.time - oldest.time
	if timeDiff < 0.01 then
		return Vector3.new(0, 0, 0)
	end

	local movementVector = newest.position - oldest.position
	local speed = movementVector.Magnitude / timeDiff

	if speed < Config:Get("Physics", "ThrowMinimumSpeed") then
		return Vector3.new(0, 0, 0)
	end

	local throwDirection = movementVector.Unit

	if Config:Get("Physics", "AddUpwardForce") then
		local upwardAmount = Config:Get("Physics", "UpwardForceAmount")
		throwDirection = (throwDirection + Vector3.new(0, upwardAmount, 0)).Unit
	end

	local maxSpeed = Config:Get("Physics", "ThrowVelocityMaxSpeed")
	local throwMultiplier = Config:Get("Physics", "ThrowMultiplier")
	local cappedSpeed = math.min(speed * throwMultiplier, maxSpeed)

	return throwDirection * cappedSpeed
end

function DraggingModule:ApplyVelocityToObject(object, velocity)
	if not object:IsA("BasePart") then return end

	if object:FindFirstChild("RigidBody") then
		object.RigidBody:ApplyImpulse(velocity)
	elseif object.AssemblyLinearVelocity then
		object.AssemblyLinearVelocity = velocity
	else
		object.Velocity = velocity
	end
end

function DraggingModule:IsFullyAnchored(object)
	if object:IsA("BasePart") then
		return object.Anchored
	elseif object:IsA("Model") then
		local allAnchored = true
		for _, part in pairs(object:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then
				allAnchored = false
				break
			end
		end
		return allAnchored
	end
	return false
end

function DraggingModule:UpdateHighlight(object)
	if self.highlightedObject then
		if object ~= self.highlightedObject then
			self:RemoveHighlight(self.highlightedObject)
			self.highlightedObject = nil
		end
	end

	if object and object ~= self.highlightedObject then
		self:AddHighlight(object)
		self.highlightedObject = object
	end
end

function DraggingModule:AddHighlight(object)
	if not object or object == workspace then
		return
	end

	if not Config:Get("Visual", "EnableHighlight") then
		return
	end

	local existingHighlight = object
	local existingHighlight = object:FindFirstChild("DraggableHighlight")
	if existingHighlight then
		existingHighlight:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "DraggableHighlight"
	highlight.FillColor = Config:Get("Visual", "HighlightColor")
	highlight.FillTransparency = Config:Get("Visual", "UseOutlineOnly") and 1 or Config:Get("Visual", "HighlightTransparency")
	highlight.OutlineColor = Config:Get("Visual", "OutlineColor") or Config:Get("Visual", "HighlightColor")
	highlight.OutlineTransparency = Config:Get("Visual", "OutlineTransparency")
	highlight.Adornee = object
	highlight.Parent = object

	if Config:Get("Visual", "ShowObjectName") then
		self:CreateObjectLabel(object)
	end
end

function DraggingModule:RemoveHighlight(object)
	if not object then return end

	local highlight = object:FindFirstChild("DraggableHighlight")
	if highlight then
		highlight:Destroy()
	end

	local label = object:FindFirstChild("DraggableLabel")
	if label then
		label:Destroy()
	end
end

function DraggingModule:CreateObjectLabel(object)
	if not object or not Config:Get("Visual", "ShowObjectName") then return end

	local existingLabel = object:FindFirstChild("DraggableLabel")
	if existingLabel then
		existingLabel:Destroy()
	end

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "DraggableLabel"
	billboardGui.Adornee = object

	local objectSize = Vector3.new(2, 2, 2)
	if object:IsA("BasePart") then
		objectSize = object.Size
	elseif object:IsA("Model") and object.PrimaryPart then
		objectSize = object.PrimaryPart.Size
	end
	local guiWidth = math.max(objectSize.X * 50, 200)
	billboardGui.Size = UDim2.new(0, guiWidth, 0, 50)

	local yOffset = 2
	if object:IsA("BasePart") then
		yOffset = (objectSize.Y / 2) + 1
	elseif object:IsA("Model") then
		local _, size = object:GetBoundingBox()
		yOffset = (size.Y / 2) + 1
	end

	billboardGui.StudsOffset = Vector3.new(0, yOffset, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.MaxDistance = 50

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Config:Get("Visual", "NameBackgroundColor")
	frame.BackgroundTransparency = Config:Get("Visual", "NameBackgroundTransparency")

	if Config:Get("Visual", "NameUseRoundedCorners") then
		local cornerRadius = Instance.new("UICorner")
		cornerRadius.CornerRadius = UDim.new(0, 8)
		cornerRadius.Parent = frame
	end

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = Config:Get("Visual", "NamePadding")
	padding.PaddingRight = Config:Get("Visual", "NamePadding")
	padding.PaddingTop = Config:Get("Visual", "NamePadding")
	padding.PaddingBottom = Config:Get("Visual", "NamePadding")
	padding.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Config:Get("Visual", "NameTextColor")
	nameLabel.TextSize = Config:Get("Visual", "NameTextSize")
	nameLabel.Font = Config:Get("Visual", "NameFont")
	nameLabel.Text = object.Name
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.TextWrapped = true

	if Config:Get("Visual", "NameStrokeTransparency") < 1 then
		nameLabel.TextStrokeColor3 = Config:Get("Visual", "NameStrokeColor")
		nameLabel.TextStrokeTransparency = Config:Get("Visual", "NameStrokeTransparency")
	end

	nameLabel.Parent = frame
	frame.Parent = billboardGui
	billboardGui.Parent = object

	return billboardGui
end

function DraggingModule:CanPlayerDragObject(player, object)
	if Config:Get("Security", "AdminsCanDragAnything") then
		local adminsList = Config:Get("Security", "AdminsList")
		for _, adminId in ipairs(adminsList) do
			if player.UserId == adminId then
				return true
			end
		end
	end

	if Config:Get("Security", "PreventDraggingPlayers") and Util.IsPlayerOrCharacter(object) then
		return false
	end

	if Config:Get("Security", "OnlyOwnersCanDrag") then
		local ownerAttribute = Config:Get("Security", "OwnershipAttribute")
		local objectOwner = object:GetAttribute(ownerAttribute)

		if objectOwner and objectOwner ~= player.UserId then
			return false
		end
	end
	return true
end

function DraggingModule:API_StartDragging(object)
	if Util.IsClient and Util.IsDraggable(object) then
		self:StartDragging(object)
		return true
	end
	return false
end

function DraggingModule:API_StopDragging()
	if Util.IsClient and self.isDragging then
		self:EndDragging(false)
		return true
	end
	return false
end

function DraggingModule:API_MakeDraggable(object)
	local CollectionService = game:GetService("CollectionService")
	CollectionService:AddTag(object, Config:Get("General", "DraggableTag"))
	return true
end

function DraggingModule:API_MakeNonDraggable(object)
	local CollectionService = game:GetService("CollectionService")
	CollectionService:RemoveTag(object, Config:Get("General", "DraggableTag"))
	return true
end

function DraggingModule:API_UpdateConfig(category, settings)
	return Config:UpdateCategory(category, settings)
end

function DraggingModule:Destroy()

	if self.targetIndicator and self.targetIndicator.gui then
		self.targetIndicator.gui:Destroy()
		self.targetIndicator = nil
	end

	for _, connection in pairs(self.connections) do
		if typeof(connection) == "RBXScriptConnection" and connection.Connected then
			connection:Disconnect()
		end
	end

	self.connections = {}

	if self.isDragging then
		self:EndDragging(false)
	end

	if self.controllerDragging then
		self:EndControllerDragging()
	end

	if self.highlightedObject then
		self:RemoveHighlight(self.highlightedObject)
		self.highlightedObject = nil
	end

	if self.controllerTargetDot and self.controllerTargetDot.gui then
		pcall(function() self.controllerTargetDot.gui:Destroy() end)
		self.controllerTargetDot = nil
	end

	if not UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = true
	end

	self:CleanupDragConstraints()
end

return DraggingModule