local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local StartDragging = Instance.new("RemoteEvent")
StartDragging.Name = "StartDragging"
StartDragging.Parent = Remotes

local UpdateDragPosition = Instance.new("RemoteEvent")
UpdateDragPosition.Name = "UpdateDragPosition"
UpdateDragPosition.Parent = Remotes

local StopDragging = Instance.new("RemoteEvent")
StopDragging.Name = "StopDragging"
StopDragging.Parent = Remotes

local ThrowObject = Instance.new("RemoteEvent")
ThrowObject.Name = "ThrowObject"
ThrowObject.Parent = Remotes

local DraggingConfig = require(ReplicatedStorage.DraggingSystem.DraggingConfig)
local DraggingUtil = require(ReplicatedStorage.DraggingSystem.DraggingUtil)
local DraggingSystem = require(ReplicatedStorage.DraggingSystem.DraggingModule)

local draggingSystem = DraggingSystem.new():Initialize()

local CollectionService = game:GetService("CollectionService")
for _, part in pairs(workspace:GetDescendants()) do
	if part.Name:match("Draggable") then
		CollectionService:AddTag(part, DraggingConfig.General.DraggableTag or "Draggable")
	end
end

local DraggingUtil = require(ReplicatedStorage.DraggingSystem.DraggingUtil)
local DraggingConfig = require(ReplicatedStorage.DraggingSystem.DraggingConfig)

if game:GetService("RunService"):IsServer() then
	local CollectionService = game:GetService("CollectionService")
	local draggableTag = DraggingConfig.General.DraggableTag

	for _, part in pairs(workspace:GetDescendants()) do
		if part.Name:match("Draggable") then
			CollectionService:AddTag(part, draggableTag)
		end
	end
end
