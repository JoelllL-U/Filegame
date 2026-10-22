local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local npcSystem = ReplicatedStorage:WaitForChild("NPCSystem")
local NPCRegistry = require(npcSystem.Config.NPCRegistry)
local MutationRegistry = require(npcSystem.Config.MutationRegistry)
local NPCVisualUtils = require(npcSystem.Shared.NPCVisualUtils)
local EasyVisualsController = require(npcSystem.Shared.EasyVisualsController)

local trackedLabelConnections: { [GuiObject]: { RBXScriptConnection } } = {}

local function disconnectTrackedLabel(guiObject: GuiObject)
	local connections = trackedLabelConnections[guiObject]
	if not connections then
		return
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	trackedLabelConnections[guiObject] = nil
	EasyVisualsController.Destroy(guiObject)
end

local function findNearestModel(instance: Instance?): Model?
	local current = instance
	while current do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function resolveRarityId(guiObject: GuiObject): string?
	local model = findNearestModel(guiObject)
	if model then
		local rarityId = model:GetAttribute("RarityId")
		if typeof(rarityId) == "string" and rarityId ~= "" then
			return rarityId
		end
		local definitionId = model:GetAttribute("DefinitionId")
		local definition = typeof(definitionId) == "string" and NPCRegistry.GetDefinitionById(definitionId) or nil
		if definition and typeof(definition.RarityId) == "string" then
			return definition.RarityId
		end
	end

	local text = guiObject:IsA("TextLabel") and guiObject.Text or guiObject:IsA("TextButton") and guiObject.Text or nil
	if typeof(text) ~= "string" then
		return nil
	end
	for rarityId, rarity in pairs(NPCRegistry.GetRarityDefinitions()) do
		if text == rarity.DisplayName or text == rarityId then
			return rarityId
		end
	end
	return nil
end

local function resolveMutationId(guiObject: GuiObject): string?
	local model = findNearestModel(guiObject)
	if model then
		local mutationId = model:GetAttribute("MutationId")
		if typeof(mutationId) == "string" and mutationId ~= "" then
			return mutationId
		end
	end

	local text = guiObject:IsA("TextLabel") and guiObject.Text or guiObject:IsA("TextButton") and guiObject.Text or nil
	if typeof(text) ~= "string" then
		return nil
	end
	for mutationId, mutation in pairs(MutationRegistry.GetDefinitions()) do
		if text == mutation.DisplayName or text == mutationId then
			return mutationId
		end
	end
	return nil
end

local function refreshLabelEffect(guiObject: GuiObject)
	if not guiObject.Parent then
		disconnectTrackedLabel(guiObject)
		return
	end

	local effectTargetName = guiObject.Name
	if guiObject.Parent and (guiObject.Parent.Name == "Rarity" or guiObject.Parent.Name == "Mutation") then
		effectTargetName = guiObject.Parent.Name
	end

	if effectTargetName == "Rarity" then
		EasyVisualsController.Apply(guiObject, NPCVisualUtils.GetRarityEasyVisualsConfig(resolveRarityId(guiObject)))
		return
	end
	if effectTargetName == "Mutation" then
		EasyVisualsController.Apply(guiObject, NPCVisualUtils.GetMutationEasyVisualsConfig(resolveMutationId(guiObject)))
		return
	end
end

local function trackGuiObject(guiObject: GuiObject)
	if trackedLabelConnections[guiObject] then
		return
	end
	trackedLabelConnections[guiObject] = {
		guiObject:GetPropertyChangedSignal("Text"):Connect(function()
			refreshLabelEffect(guiObject)
		end),
		guiObject.AncestryChanged:Connect(function()
			refreshLabelEffect(guiObject)
		end),
		guiObject.Destroying:Connect(function()
			disconnectTrackedLabel(guiObject)
		end),
	}
	refreshLabelEffect(guiObject)
end

local function shouldTrack(descendant: Instance): boolean
	if not (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) then
		return false
	end
	if descendant.Name == "Rarity" or descendant.Name == "Mutation" then
		return true
	end
	local parent = descendant.Parent
	return parent ~= nil and (parent.Name == "Rarity" or parent.Name == "Mutation")
end

local function scanContainer(container: Instance)
	for _, descendant in ipairs(container:GetDescendants()) do
		if shouldTrack(descendant) then
			trackGuiObject(descendant)
		end
	end
end

scanContainer(Workspace)
local playerGui = player:WaitForChild("PlayerGui")
scanContainer(playerGui)
playerGui.DescendantAdded:Connect(function(descendant)
	if shouldTrack(descendant) then
		trackGuiObject(descendant)
	end
end)

Workspace.DescendantAdded:Connect(function(descendant)
	if shouldTrack(descendant) then
		trackGuiObject(descendant)
	end
end)

player:WaitForChild("PlayerScripts").DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ModuleScript") and string.find(string.lower(descendant.Name), "easyvisual", 1, true) then
		for guiObject in pairs(trackedLabelConnections) do
			refreshLabelEffect(guiObject)
		end
	end
end)
