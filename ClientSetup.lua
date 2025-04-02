local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local draggingSystem, mobileDraggingSystem

local function IsMobilePlatform()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end


local function InitializeDraggingSystem()
	local isMobile = IsMobilePlatform()

	if isMobile then
		local MobileDraggingModule = require(ReplicatedStorage.DraggingSystem.MobileDraggingModule)
		mobileDraggingSystem = MobileDraggingModule.new():Initialize()
	else
		local DraggingModule = require(ReplicatedStorage.DraggingSystem.DraggingModule)
		draggingSystem = DraggingModule.new():Initialize()
	end
end

local function SetupCleanup()
	Players.PlayerRemoving:Connect(function(plr)
		if plr == player then
			if draggingSystem then
				draggingSystem:Destroy()
				draggingSystem = nil
			end

			if mobileDraggingSystem then
				mobileDraggingSystem:Destroy()
				mobileDraggingSystem = nil
			end
		end
	end)
end

local function EnableControllerSupport()
	local success, result = pcall(function()
		local StarterGui = game:GetService("StarterGui")

		if UserInputService.GamepadEnabled then
			StarterGui:SetCore("GamepadDefaultButton", false)

			StarterGui:SetCore("SendNotification", {
				Title = "Controller Support",
				Text = "Controller connected! Use RT to drag objects.",
				Duration = 5
			})

			return true
		end
		return false
	end)

	return success and result
end

EnableControllerSupport()

UserInputService.GamepadConnected:Connect(function(gamepad)
	EnableControllerSupport()
end)

InitializeDraggingSystem()
SetupCleanup()