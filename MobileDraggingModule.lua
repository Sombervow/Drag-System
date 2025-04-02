local MobileDraggingModule = {}

MobileDraggingModule.__index = MobileDraggingModule

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local Config
local Util

local BUTTON_STYLE = {
	Size = UDim2.new(0, 70, 0, 70),
	BackgroundColor3 = Color3.fromRGB(50, 50, 50),
	BackgroundTransparency = 0.5,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.FredokaOne,
	TextSize = 16,
	BorderSizePixel = 0,
}

function MobileDraggingModule.new(draggingModule)
	local self = setmetatable({}, MobileDraggingModule)

	Config = require(script.Parent.DraggingConfig)
	Util = require(script.Parent.DraggingUtil)

	self.enabled = false
	self.isDragging = false
	self.isRotating = false
	self.targetDot = nil
	self.targetObject = nil
	self.mobileButtons = {}
	self.connections = {}
	self.player = Players.LocalPlayer
	self.currentAxis = Config:Get("Input", "RotationAxis")
	self.currentDraggable = nil
	self.dragConstraints = {}

	return self
end

-- =============================================
-- 1. INITIALIZATION
-- =============================================

function MobileDraggingModule:Initialize()
	if not RunService:IsClient() or not self:IsMobilePlatform() then
		return self
	end

	Config = require(script.Parent.DraggingConfig)
	Util = require(script.Parent.DraggingUtil)

	self.Remotes = {
		StartDragging = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("StartDragging"),
		UpdateDragPosition = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("UpdateDragPosition"),
		StopDragging = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("StopDragging"),
		ThrowObject = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("ThrowObject")
	}

	self:CleanupAllHighlights()
	self:CreateTargetDot()
	self:CreateMobileControls()
	self:SetupConnections()
	self.enabled = true
	self.dragConstraints = {}
	self.lastHighlightedObject = nil
	local originalTouchTap = UserInputService.TouchTap
	local touchHandlerConnection = originalTouchTap:Connect(function(touchPos, gameProcessed)
		
		return
	end)

	self.connections.touchHandler = touchHandlerConnection

	if Config:Get("Behavior", "AutoDropEnabled") then
		self.connections.autoDropCheck = RunService.Heartbeat:Connect(function(deltaTime)
			-- Only check periodically to save performance
			self.autoDropTimer = (self.autoDropTimer or 0) + deltaTime
			if self.autoDropTimer >= Config:Get("Behavior", "AutoDropCheckRate") then
				self:CheckDistanceAndAutoDrop()
				self.autoDropTimer = 0
			end
		end)
	end

	return self
end

-- =============================================
-- 2. UI ELEMENTS
-- =============================================

function MobileDraggingModule:CreateMobileControls()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MobileDraggingControls"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local actionContainer = Instance.new("Frame")
	actionContainer.Name = "ActionButtonsContainer"
	actionContainer.Size = UDim2.new(0, 240, 0, 240)
	actionContainer.Position = UDim2.new(1, -240, 1, -240)
	actionContainer.BackgroundTransparency = 1
	actionContainer.Parent = screenGui

	local pickupButton = self:CreateButton("Pickup", UDim2.new(0, 80, 1, -80), function()
		self:OnPickupPressed()
	end)
	pickupButton.Parent = screenGui
	pickupButton.AnchorPoint = Vector2.new(0.5, 0.5)
	pickupButton.Position = UDim2.new(.83, 0, .9, -80)
	self.mobileButtons.pickup = pickupButton

	local rotationEnabled = Config:Get("Input", "RotationEnabled", true)

	if rotationEnabled then
		local rotateButton = Instance.new("TextButton")
		rotateButton.Name = "RotateButton"
		rotateButton.Size = UDim2.new(0, 70, 0, 70)
		rotateButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		rotateButton.BackgroundTransparency = 0.5
		rotateButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		rotateButton.Font = Enum.Font.FredokaOne
		rotateButton.TextSize = 16
		rotateButton.Text = "Rotate"
		rotateButton.BorderSizePixel = 0
		rotateButton.AnchorPoint = Vector2.new(0.5, 0.5)
		rotateButton.Position = UDim2.new(.437, 0, .8, -80)

		local uiCorner = Instance.new("UICorner")
		uiCorner.CornerRadius = UDim.new(1, 0)
		uiCorner.Parent = rotateButton

		local uiStroke = Instance.new("UIStroke")
		uiStroke.Color = Color3.fromRGB(255, 255, 255)
		uiStroke.Thickness = 1.5
		uiStroke.Transparency = 0.7
		uiStroke.Parent = rotateButton

		rotateButton.MouseButton1Click:Connect(function()
			if self.isDragging and self.currentDraggable then
				if not Config:Get("Input", "RotationEnabled", true) then
					self:ShowNotification("Rotation is disabled in settings")
					return
				end

				local rotationDegrees = Config:Get("Input", "MobileRotationIncrement", 15)
				local rotationAmount = math.rad(rotationDegrees)
				self:ApplyMobileRotation(self.currentAxis, rotationAmount)
			end
		end)

		rotateButton.TouchTap:Connect(function()
			if self.isDragging and self.currentDraggable then
				if not Config:Get("Input", "RotationEnabled", true) then
					self:ShowNotification("Rotation is disabled in settings")
					return
				end

				local rotationDegrees = Config:Get("Input", "MobileRotationIncrement", 15)
				local rotationAmount = math.rad(rotationDegrees)
				self:ApplyMobileRotation(self.currentAxis, rotationAmount)
			end
		end)

		rotateButton.Parent = actionContainer
		self.mobileButtons.rotate = rotateButton

		local axisButton = self:CreateButton("Axis", UDim2.new(0, 0, 0, 0), function()
			self:OnAxisPressed()
		end)
		axisButton.AnchorPoint = Vector2.new(0.5, 0.5)
		axisButton.Position = UDim2.new(0.35, 0, 0.78, 0)
		axisButton.Parent = actionContainer
		self.mobileButtons.axis = axisButton
	end

	local dropButton = self:CreateButton("Drop", UDim2.new(0, 0, 0, 0), function()
		self:OnDropPressed()
	end)
	dropButton.AnchorPoint = Vector2.new(0.5, 0.5)

	if rotationEnabled then
		dropButton.Position = UDim2.new(.75, 0, .7, -80)
	else
		dropButton.Position = UDim2.new(0.5, 0, 0.7, -80)
	end

	dropButton.Parent = actionContainer
	self.mobileButtons.drop = dropButton

	actionContainer.Visible = false
	pickupButton.Visible = true

	screenGui.Parent = self.player:WaitForChild("PlayerGui")

	self.mobileButtons.container = actionContainer
	self.mobileButtons.gui = screenGui
end

function MobileDraggingModule:CreateTargetDot()


	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MobileDraggingGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling


	local viewportSize = workspace.CurrentCamera.ViewportSize
	local centerOffsetY = -20 

	local targetDot = Instance.new("Frame")
	targetDot.Name = "TargetDot"
	targetDot.Size = UDim2.new(0, 10, 0, 10)
	targetDot.AnchorPoint = Vector2.new(0.5, 0.5)
	targetDot.Position = UDim2.new(0.5, 0, 0.5, centerOffsetY)
	targetDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	targetDot.BorderSizePixel = 0

	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Color3.fromRGB(0, 0, 0)
	dotStroke.Thickness = 1
	dotStroke.Transparency = 0.5
	dotStroke.Parent = targetDot

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(1, 0)
	uiCorner.Parent = targetDot
	targetDot.Parent = screenGui

	self.viewportSize = viewportSize
	self.centerOffsetY = centerOffsetY

	screenGui.Parent = self.player:WaitForChild("PlayerGui")

	self.targetDot = {
		gui = screenGui,
		dot = targetDot
	}

	self.raycastOffsetY = centerOffsetY
end

function MobileDraggingModule:UpdateRaycastOrigin(offsetY)
	self.raycastOffsetY = offsetY
end

function MobileDraggingModule:CreateButton(text, position, callback)

	local button = Instance.new("TextButton")
	button.Name = text .. "Button"

	button.Size = UDim2.new(0, 70, 0, 70)
	button.Position = position
	button.BackgroundColor3 = BUTTON_STYLE.BackgroundColor3
	button.BackgroundTransparency = BUTTON_STYLE.BackgroundTransparency
	button.TextColor3 = BUTTON_STYLE.TextColor3
	button.Font = BUTTON_STYLE.Font
	button.TextSize = BUTTON_STYLE.TextSize
	button.Text = text
	button.BorderSizePixel = BUTTON_STYLE.BorderSizePixel
	button.AnchorPoint = Vector2.new(0.5, 0.5)

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(1, 0)
	uiCorner.Parent = button

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = Color3.fromRGB(255, 255, 255)
	uiStroke.Thickness = 1.5
	uiStroke.Transparency = 0.7
	uiStroke.Parent = button

	if callback then
		button.TouchTap:Connect(callback)
	end

	return button
end

function MobileDraggingModule:ShowActionButtons(visible)
	if self.mobileButtons and self.mobileButtons.container then
		self.mobileButtons.container.Visible = visible
	end

	if self.mobileButtons and self.mobileButtons.pickup then
		self.mobileButtons.pickup.Visible = not visible
	end
end

function MobileDraggingModule:CheckDistanceAndAutoDrop()
	if not self.isDragging or not self.currentDraggable then
		return
	end

	local player = self.player
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
		self:EndAllInteractions()

		self:ShowNotification("Object dropped: Too far from player")
	end



	return self

end

function MobileDraggingModule:UpdateHighlight(object)

	if self.isDragging then
		return
	end

	if self.highlightedObject and (not object or self.highlightedObject ~= object) then
		local highlight = self.highlightedObject:FindFirstChild("DraggableHighlight")

		if highlight then
			highlight:Destroy()
		end

		local label = self.highlightedObject:FindFirstChild("DraggableLabel")
		if label then
			label:Destroy()
		end

		self.highlightedObject = nil

	end

	if not object or not Util.IsDraggable(object) then
		return
	end

	if object ~= self.targetObject then
		return
	end

	if self.highlightedObject == object then
		return
	end

	if Config:Get("Visual", "EnableHighlight") then
		local highlight = Instance.new("Highlight")
		highlight.Name = "DraggableHighlight"
		highlight.FillColor = Config:Get("Visual", "HighlightColor")
		highlight.FillTransparency = Config:Get("Visual", "UseOutlineOnly") and 1 or Config:Get("Visual", "HighlightTransparency")
		highlight.OutlineColor = Config:Get("Visual", "OutlineColor") or Config:Get("Visual", "HighlightColor")
		highlight.OutlineTransparency = Config:Get("Visual", "OutlineTransparency")
		highlight.Adornee = object
		highlight.Parent = object
	end

	if Config:Get("Visual", "ShowObjectName") then
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
	end

	self.highlightedObject = object
	self.lastHighlightedObject = tick()
end


function MobileDraggingModule:IsMobilePlatform()

	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled

end



function MobileDraggingModule:UpdateTargeting(deltaTime)
	if not self.enabled or not self.targetDot then return end
	
	self.targetDot.dot.Position = UDim2.new(0.5, 0, 0.5, self.centerOffsetY or -20)
	local targetObject = self:GetObjectAtCenter()

	if targetObject and Util.IsDraggable(targetObject) then
		self.targetObject = targetObject
	else
		self.targetObject = nil
	end
	
	if not self.isDragging and not self.isRotating then
		self:UpdateHighlight(targetObject)
	elseif self.isDragging and self.currentDraggable then
		if not self.currentDraggable:FindFirstChild("DraggableHighlight") then
			self:AddHighlight(self.currentDraggable)
		end
	end
end

function MobileDraggingModule:SetupConnections()
	self.connections.renderStepped = RunService.RenderStepped:Connect(function(deltaTime)
		self:UpdateTargeting(deltaTime)

		if self.isDragging and self.currentDraggable then
			self:UpdateDragPosition()

			if self.buttonStates and self.buttonStates.rotate and self.buttonStates.rotate.isHeld then
				if not Config:Get("Input", "RotationEnabled", true) then
					return
				end

				local rotationSpeed = math.rad(Config:Get("Input", "RotationSpeed", 45))
				local rotationAmount = rotationSpeed * deltaTime

				self:ApplyMobileRotation(self.currentAxis, rotationAmount)
			end
		end

		if self.highlightedObject and self.highlightedObject ~= self.targetObject then
			local highlight = self.highlightedObject:FindFirstChild("DraggableHighlight")
			if highlight then highlight:Destroy() end

			local label = self.highlightedObject:FindFirstChild("DraggableLabel")
			if label then label:Destroy() end

			self.highlightedObject = nil
		end

		if self.lastHighlightedObject and tick() - self.lastHighlightedObject > 1 then
			for _, obj in pairs(workspace:GetDescendants()) do
				if obj.Name == "DraggableHighlight" and (not self.highlightedObject or obj.Parent ~= self.highlightedObject) then
					obj:Destroy()
				end
				if obj.Name == "DraggableLabel" and (not self.highlightedObject or obj.Parent ~= self.highlightedObject) then
					obj:Destroy()
				end
			end
			self.lastHighlightedObject = tick()
		end
	end)

	self.connections.touchBegan = UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
		if gameProcessed then return end
	end)

	self.connections.characterAdded = self.player.CharacterAdded:Connect(function()
		if self.isDragging or self.isRotating then
			self:EndAllInteractions()
		end
	end)

	self.connections.characterDied = self.player.CharacterRemoving:Connect(function()
		self:EndAllInteractions()
	end)

	self.connections.cleanupTimer = task.spawn(function()
		while true do
			wait(2)
			if not self.enabled then break end

			for _, obj in pairs(workspace:GetDescendants()) do
				if obj.Name == "DraggableHighlight" or obj.Name == "DraggableLabel" then
					if not self.highlightedObject or obj.Parent ~= self.highlightedObject then
						obj:Destroy()
					end
				end
			end
		end
	end)

	if Config:Get("Behavior", "AutoDropEnabled") then
		self.connections.autoDropCheck = RunService.Heartbeat:Connect(function(deltaTime)
			self.autoDropTimer = (self.autoDropTimer or 0) + deltaTime
			if self.autoDropTimer >= Config:Get("Behavior", "AutoDropCheckRate") then
				self:CheckDistanceAndAutoDrop()
				self.autoDropTimer = 0
			end
		end)
	end
end

function MobileDraggingModule:AddHighlight(object)
	if not object or object == workspace then
		return
	end

	if not Config:Get("Visual", "EnableHighlight") then
		return
	end

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

	self.highlightedObject = object
end

function MobileDraggingModule:CreateObjectLabel(object)
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

function MobileDraggingModule:GetObjectAtCenter()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local viewportSize = camera.ViewportSize
	local centerX = viewportSize.X / 2
	local centerY = viewportSize.Y / 2 + (self.raycastOffsetY or 0)

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



function MobileDraggingModule:OnPickupPressed()
	if self.isDragging or self.isRotating then
		self:EndAllInteractions()
		return
	end

	if self.targetObject and Util.IsDraggable(self.targetObject) then
		self.highlightedObject = self.targetObject

		if not self.targetObject:FindFirstChild("DraggableHighlight") then
			self:AddHighlight(self.targetObject)
		end

		self.isDragging = true
		self.currentDraggable = self.targetObject
		self:CreateMobileDragConstraints(self.targetObject)
		self:UpdateDragPosition()
		self.Remotes.StartDragging:FireServer(self.targetObject)
		self:ShowActionButtons(true)
		self:ShowNotification("Dragging: " .. self.targetObject.Name)
	else
		self:ShowNotification("No draggable object targeted")
	end
end

function MobileDraggingModule:CreatePartConstraints(part)

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "MobileDragAttachment0"
	attachment0.Position = Vector3.new(0, 0, 0)
	attachment0.Parent = part

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "MobileDragAttachment1"
	attachment1.WorldPosition = Util.GetObjectCenter(part)
	attachment1.Parent = workspace.Terrain

	attachment1.WorldOrientation = part.Orientation

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "MobileDragAlignPosition"
	alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
	alignPosition.Attachment0 = attachment0
	alignPosition.Attachment1 = attachment1
	alignPosition.RigidityEnabled = false
	alignPosition.MaxForce = Config:Get("Physics", "MaxForce")
	alignPosition.Responsiveness = Config:Get("Physics", "DragResponsiveness")
	alignPosition.Parent = part

	local weightFactor = Util.CalculateWeightFactor(part)
	alignPosition.Responsiveness = alignPosition.Responsiveness * weightFactor

	table.insert(self.dragConstraints, attachment0)
	table.insert(self.dragConstraints, attachment1)
	table.insert(self.dragConstraints, alignPosition)

	if Config:Get("Physics", "StabilizeRotation", true) then
		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "MobileDragAlignOrientation"
		alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		alignOrientation.Attachment0 = attachment0
		alignOrientation.Attachment1 = attachment1
		alignOrientation.RigidityEnabled = true
		alignOrientation.MaxTorque = Config:Get("Physics", "MaxTorque")
		alignOrientation.Responsiveness = Config:Get("Physics", "RotationResponsiveness")
		alignOrientation.Parent = part

		table.insert(self.dragConstraints, alignOrientation)
	end

	self.dragAttachment1 = attachment1
end


function MobileDraggingModule:CreateMobileDragConstraints(object)
	self:CleanupDragConstraints()

	self.dragConstraints = {}

	if object:IsA("BasePart") then
		self:CreatePartConstraints(object)
	elseif object:IsA("Model") then
		self:CreateModelConstraints(object)
	end
end

function MobileDraggingModule:CreateModelConstraints(model)
	if model.PrimaryPart then
		self:CreatePartConstraints(model.PrimaryPart)
	else
		local primaryPart = nil
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then
				primaryPart = part
				break
			end
		end

		if primaryPart then
			self:CreatePartConstraints(primaryPart)
		else
			self.isDragging = false
			self.currentDraggable = nil
			warn("Cannot drag model with no unanchored parts")
		end
	end
end

function MobileDraggingModule:CreateMobileModelDragConstraints(model)
	if model.PrimaryPart then
		self:CreateMobilePartDragConstraints(model.PrimaryPart)
	else
		local primaryPart = nil
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then
				primaryPart = part
				break
			end
		end

		if primaryPart then
			self:CreateMobilePartDragConstraints(primaryPart)
		else
			self.isDragging = false
			self.currentDraggable = nil
			warn("Cannot drag model with no unanchored parts")
		end
	end
end
function MobileDraggingModule:ApplyMobileRotation(axis, angle)
	if not self.currentDraggable then return end

	if not Config:Get("Input", "RotationEnabled", true) then
		return
	end

	local rotationCFrame
	if axis == "X" then
		rotationCFrame = CFrame.Angles(angle, 0, 0)
	elseif axis == "Y" then
		rotationCFrame = CFrame.Angles(0, angle, 0)
	elseif axis == "Z" then
		rotationCFrame = CFrame.Angles(0, 0, angle)
	else
		return
	end

	local newCFrame

	if self.currentDraggable:IsA("Model") then
		if self.currentDraggable.PrimaryPart then

			local pivotCFrame = self.currentDraggable:GetPivot()
			local pivotPosition = pivotCFrame.Position

			newCFrame = CFrame.new(pivotPosition) * 
				rotationCFrame * 
				CFrame.new(-pivotPosition) * 
				pivotCFrame

			self.currentDraggable:PivotTo(newCFrame)
		else
			local modelCenter = Util.GetObjectCenter(self.currentDraggable)

			for _, part in pairs(self.currentDraggable:GetDescendants()) do
				if part:IsA("BasePart") then
					local partPos = part.Position
					local offset = partPos - modelCenter
					local rotatedOffset = rotationCFrame:VectorToWorldSpace(offset)

					part.Position = modelCenter + rotatedOffset
					part.CFrame = part.CFrame * rotationCFrame
				end
			end

			for _, part in pairs(self.currentDraggable:GetDescendants()) do
				if part:IsA("BasePart") then
					newCFrame = part.CFrame
					break
				end
			end
		end
	else

		local position = self.currentDraggable.Position

		newCFrame = CFrame.new(position) * 
			rotationCFrame * 
			CFrame.new(-position) * 
			self.currentDraggable.CFrame

		self.currentDraggable.CFrame = newCFrame
	end

	if self.dragAttachment1 and self.currentDraggable then
		self.dragAttachment1.WorldPosition = Util.GetObjectCenter(self.currentDraggable)

		if Config:Get("Physics", "StabilizeRotation", true) then
			if self.currentDraggable:IsA("BasePart") then
				local partCFrame = self.currentDraggable.CFrame
				self.dragAttachment1.CFrame = CFrame.new(self.dragAttachment1.WorldPosition) * 
					(partCFrame - partCFrame.Position)
			elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
				local pivotCFrame = self.currentDraggable:GetPivot()
				self.dragAttachment1.CFrame = CFrame.new(self.dragAttachment1.WorldPosition) * 
					(pivotCFrame - pivotCFrame.Position)
			end
		else
			if self.currentDraggable:IsA("BasePart") then
				self.dragAttachment1.WorldOrientation = self.currentDraggable.Orientation
			elseif self.currentDraggable:IsA("Model") and self.currentDraggable.PrimaryPart then
				self.dragAttachment1.WorldOrientation = self.currentDraggable.PrimaryPart.Orientation
			end
		end
	end

	if newCFrame then
		pcall(function()
			self.Remotes.UpdateDragPosition:FireServer(
				self.currentDraggable,
				newCFrame,
				true
			)
		end)
	end
end

function MobileDraggingModule:OnRotatePressed()
	if not self.isDragging or not self.currentDraggable then
		return
	end

	if not Config:Get("Input", "RotationEnabled", true) then
		self:ShowNotification("Rotation is disabled in settings")
		return
	end

	local rotationDegrees = Config:Get("Input", "MobileRotationIncrement", 15)
	local rotationAmount = math.rad(rotationDegrees)

	self:ApplyMobileRotation(self.currentAxis, rotationAmount)

	self:ShowNotification("Rotated " .. rotationDegrees .. "° on " .. self.currentAxis .. "-axis")
end

function MobileDraggingModule:OnAxisPressed()
	if not self.isDragging or not self.currentDraggable then
		return
	end

	if not Config:Get("Input", "RotationEnabled", true) then
		self:ShowNotification("Rotation is disabled in settings")
		return
	end
	
	local axes = {"Y", "X", "Z"}
	local currentIndex = table.find(axes, self.currentAxis) or 1
	self.currentAxis = axes[currentIndex % 3 + 1]

	self:ShowNotification("Rotation axis: " .. self.currentAxis)

	if self.currentAxis == "X" then
		self.mobileButtons.axis.BackgroundColor3 = Color3.fromRGB(255, 0, 0) 
	elseif self.currentAxis == "Y" then
		self.mobileButtons.axis.BackgroundColor3 = Color3.fromRGB(0, 255, 0) 
	elseif self.currentAxis == "Z" then
		self.mobileButtons.axis.BackgroundColor3 = Color3.fromRGB(0, 0, 255) 
	end
end

function MobileDraggingModule:OnRotateHeld(deltaTime)
	if not self.isDragging or not self.currentDraggable then
		return
			end

if not Config:Get("Input", "RotationEnabled", true) then
	return
end

	local rotationSpeed = math.rad(Config:Get("Input", "RotationSpeed", 45)) 
	local rotationAmount = rotationSpeed * deltaTime
	self:ApplyMobileRotation(self.currentAxis, rotationAmount)
end

function MobileDraggingModule:CreateRotationButton()
	local rotateButton = Instance.new("TextButton")
	rotateButton.Name = "RotateButton"
	rotateButton.Size = UDim2.new(0, 70, 0, 70)
	rotateButton.Position = UDim2.new(0, 0, 0, 0)
	rotateButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	rotateButton.BackgroundTransparency = 0.5
	rotateButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	rotateButton.Font = Enum.Font.FredokaOne
	rotateButton.TextSize = 16
	rotateButton.Text = "Rotate"
	rotateButton.BorderSizePixel = 0
	rotateButton.AnchorPoint = Vector2.new(0.5, 0.5)

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(1, 0)
	uiCorner.Parent = rotateButton

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = Color3.fromRGB(255, 255, 255)
	uiStroke.Thickness = 1.5
	uiStroke.Transparency = 0.7
	uiStroke.Parent = rotateButton

	rotateButton.TouchTap:Connect(function()
		if not Config:Get("Input", "RotationEnabled", true) then
			self:ShowNotification("Rotation is disabled in settings")
			return
		end

		if self.isDragging and self.currentDraggable then
			local rotationDegrees = Config:Get("Input", "MobileRotationIncrement", 15)
			local rotationAmount = math.rad(rotationDegrees)
			self:ApplyMobileRotation(self.currentAxis, rotationAmount)

			self:ShowNotification("Rotated " .. rotationDegrees .. "° on " .. self.currentAxis .. "-axis")
		end
	end)

	return rotateButton
end



function MobileDraggingModule:OnDropPressed()

	if not self.isDragging or not self.currentDraggable then
		return
	end

	self:EndAllInteractions()

	self:ShowNotification("Object dropped")

end



function MobileDraggingModule:UpdateDragPosition()
	if not self.isDragging or not self.currentDraggable then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local lookDirection = camera.CFrame.LookVector

	local cameraPosition = camera.CFrame.Position

	local player = self.player
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
end



function MobileDraggingModule:CleanupDragConstraints()

	for _, constraint in ipairs(self.dragConstraints or {}) do
		if constraint and constraint.Parent then
			constraint:Destroy()
		end
	end
	self.dragConstraints = {}
	self.dragAttachment1 = nil
end



function MobileDraggingModule:EndAllInteractions()
	if self.isDragging then
		self.isDragging = false

		if self.currentDraggable and self.Remotes and self.Remotes.StopDragging then
			pcall(function()
				self.Remotes.StopDragging:FireServer(self.currentDraggable)
			end)

			if self.currentDraggable == self.targetObject then
			else

				self.highlightedObject = nil
				self:UpdateHighlight(self.targetObject)
			end

			self.currentDraggable = nil
		end

		self:CleanupDragConstraints()

		if self.buttonStates then
			for _, state in pairs(self.buttonStates) do
				state.isHeld = false
			end
		end

		if self.mobileButtons then
			self:ShowActionButtons(false)

			if self.mobileButtons.rotate then
				self.mobileButtons.rotate.BackgroundColor3 = BUTTON_STYLE.BackgroundColor3
			end

			if self.mobileButtons.axis then
				self.mobileButtons.axis.BackgroundColor3 = BUTTON_STYLE.BackgroundColor3
			end
		end
	end
end



function MobileDraggingModule:CleanupAllHighlights()

	if self.highlightedObject then
		local highlight = self.highlightedObject:FindFirstChild("DraggableHighlight")
		if highlight then highlight:Destroy() end

		local label = self.highlightedObject:FindFirstChild("DraggableLabel")
		if label then label:Destroy() end

		self.highlightedObject = nil
	end

	for _, obj in pairs(workspace:GetDescendants()) do
		if obj.Name == "DraggableHighlight" or obj.Name == "DraggableLabel" then
			obj:Destroy()
		end
	end
end

function MobileDraggingModule:ShowNotification(message, duration)
    if not Config:Get("Visual", "NotificationsEnabled", true) then
        return
    end
    
    duration = duration or Config:Get("Visual", "NotificationDuration", 2)
    
    game.StarterGui:SetCore("SendNotification", {
        Title = "Drag System",
        Text = message,
        Duration = duration
    })
end



function MobileDraggingModule:Destroy()
	pcall(function() 
		self:EndAllInteractions() 
	end)

	if self.connections then
		for key, connection in pairs(self.connections) do
			if typeof(connection) == "RBXScriptConnection" and connection.Connected then
				connection:Disconnect()
			elseif typeof(connection) == "thread" then
				pcall(function() task.cancel(connection) end)
			end
		end
		self.connections = {}
	end

	if self.targetDot and self.targetDot.gui then
		pcall(function() self.targetDot.gui:Destroy() end)
	end
	
	self.targetDot = nil
	if self.mobileButtons then
		if self.mobileButtons.gui then
			pcall(function() self.mobileButtons.gui:Destroy() end)
		end
		
		self.mobileButtons = {}
	end

	pcall(function() self:CleanupAllHighlights() end)

	pcall(function() self:CleanupDragConstraints() end)

	self.enabled = false
	self.currentDraggable = nil
	self.targetObject = nil
	self.highlightedObject = nil
	self.dragAttachment1 = nil
	self.Remotes = nil
end

return MobileDraggingModule