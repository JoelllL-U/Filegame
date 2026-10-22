local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local npcSystem = ReplicatedStorage:WaitForChild("NPCSystem")
local baseConfig = require(npcSystem:WaitForChild("Config"):WaitForChild("BaseConfig"))

local trackedBases: { [Model]: { RBXScriptConnection } } = {}
local trackedPromptConnections: { [ProximityPrompt]: { RBXScriptConnection } } = {}
local basesFolderConnection: RBXScriptConnection? = nil
local carryRestrictionsConfig = baseConfig.CarryRestrictions or {}
local carryModeAttributeName = carryRestrictionsConfig.CarryModeAttributeName or "BrainrotCarryMode"
local ownedPlacePromptActiveAttributeName = carryRestrictionsConfig.OwnedPlacePromptActiveAttributeName or "OwnedBrainrotPlacePromptActive"

local ownerOnlyPromptNames = {
	[baseConfig.OwnedCarry.GrabPromptName] = true,
	[baseConfig.OwnedCarry.PlacePromptName] = true,
	["Delete"] = true,
}

local function resolveBaseModel(instance: Instance?): Model?
	local basesFolder = Workspace:FindFirstChild(baseConfig.BasesFolderName)
	local current = instance
	while current do
		if current:IsA("Model") and basesFolder and current.Parent == basesFolder then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getCarryMode(): string
	local mode = player:GetAttribute(carryModeAttributeName)
	if typeof(mode) == "string" then
		return mode
	end
	return "None"
end

local function isAnyCarryActive(): boolean
	return getCarryMode() ~= "None"
end

local function isOwnedPlacePromptActive(): boolean
	return player:GetAttribute(ownedPlacePromptActiveAttributeName) == true and getCarryMode() == "Owned"
end

local function shouldPromptBeVisible(prompt: ProximityPrompt): boolean
	if prompt.Name == "DefeatedCapturableGrab" then
		return not isAnyCarryActive()
	end
	if ownerOnlyPromptNames[prompt.Name] then
		local baseModel = resolveBaseModel(prompt)
		if not baseModel then
			return false
		end
		if baseModel:GetAttribute("OwnerUserId") ~= player.UserId then
			return false
		end
		if prompt.Name == baseConfig.OwnedCarry.PlacePromptName then
			return isOwnedPlacePromptActive()
		end
		if isAnyCarryActive() then
			return false
		end
		return true
	end
	return true
end

local function applyPromptVisibility(prompt: ProximityPrompt)
	if prompt.Name == "DefeatedCapturableGrab" or ownerOnlyPromptNames[prompt.Name] then
		local shouldBeVisible = shouldPromptBeVisible(prompt)
		if prompt.Enabled ~= shouldBeVisible then
			prompt.Enabled = shouldBeVisible
		end
	end
end

local function disconnectTrackedPrompt(prompt: ProximityPrompt)
	local connections = trackedPromptConnections[prompt]
	if not connections then
		return
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	trackedPromptConnections[prompt] = nil
end

local function trackPrompt(prompt: ProximityPrompt)
	if trackedPromptConnections[prompt] then
		return
	end
	trackedPromptConnections[prompt] = {
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			applyPromptVisibility(prompt)
		end),
		prompt.Destroying:Connect(function()
			disconnectTrackedPrompt(prompt)
		end),
	}
end

local function applyPromptVisibilityForAll()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			trackPrompt(descendant)
			applyPromptVisibility(descendant)
		end
	end
end

local function applyBaseVisibility(baseModel: Model)
	local isOwner = baseModel:GetAttribute("OwnerUserId") == player.UserId
	local plotPart = baseModel:FindFirstChild("PlotPart", true)
	if plotPart and plotPart:IsA("BasePart") then
		local plotGui = plotPart:FindFirstChild("PlotGUI")
		if plotGui and plotGui:IsA("BillboardGui") then
			plotGui.Enabled = isOwner
		end
	end

	for _, descendant in ipairs(baseModel:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			applyPromptVisibility(descendant)
		end
	end
end

local function disconnectTrackedBase(baseModel: Model)
	local connections = trackedBases[baseModel]
	if not connections then
		return
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	trackedBases[baseModel] = nil
end

local function trackBase(baseModel: Model)
	if trackedBases[baseModel] then
		return
	end
	applyBaseVisibility(baseModel)
	trackedBases[baseModel] = {
		baseModel:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			applyBaseVisibility(baseModel)
		end),
		baseModel.DescendantAdded:Connect(function(descendant)
			if descendant.Name == "PlotGUI" or descendant.Name == "PlotPart" then
				task.defer(function()
					applyBaseVisibility(baseModel)
				end)
				return
			end
			if descendant:IsA("ProximityPrompt") then
				trackPrompt(descendant)
				applyPromptVisibility(descendant)
			end
		end),
		baseModel.Destroying:Connect(function()
			disconnectTrackedBase(baseModel)
		end),
	}
end

local function scanBases()
	local basesFolder = Workspace:FindFirstChild(baseConfig.BasesFolderName)
	if not (basesFolder and basesFolder:IsA("Folder")) then
		return false
	end
	for _, child in ipairs(basesFolder:GetChildren()) do
		if child:IsA("Model") then
			trackBase(child)
		end
	end
	basesFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			trackBase(child)
		end
	end)
	return true
end

if not scanBases() then
	basesFolderConnection = Workspace.ChildAdded:Connect(function(child)
		if child.Name == baseConfig.BasesFolderName and child:IsA("Folder") then
			if basesFolderConnection then
				basesFolderConnection:Disconnect()
				basesFolderConnection = nil
			end
			scanBases()
			applyPromptVisibilityForAll()
		end
	end)
end

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		trackPrompt(descendant)
		applyPromptVisibility(descendant)
	end
end)

local function onCarryVisibilityStateChanged()
	applyPromptVisibilityForAll()
	for baseModel in pairs(trackedBases) do
		applyBaseVisibility(baseModel)
	end
end

player:GetAttributeChangedSignal(carryModeAttributeName):Connect(onCarryVisibilityStateChanged)
player:GetAttributeChangedSignal(ownedPlacePromptActiveAttributeName):Connect(onCarryVisibilityStateChanged)

applyPromptVisibilityForAll()
