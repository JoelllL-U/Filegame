local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MutationRegistry = require(ReplicatedStorage.NPCSystem.Config.MutationRegistry)
local NPCVisualConfig = require(ReplicatedStorage.NPCSystem.Config.NPCVisualConfig)

local NPCVisualUtils = {}

local function getMutationVisualConfig(mutationId: string?): { [string]: any }?
	if typeof(mutationId) ~= "string" or mutationId == "" then
		return nil
	end
	return NPCVisualConfig.MutationVisuals[mutationId]
end

local function getManagedHighlightName(): string
	local highlightConfig = NPCVisualConfig.MutationHighlight
	if highlightConfig and typeof(highlightConfig.Name) == "string" and highlightConfig.Name ~= "" then
		return highlightConfig.Name
	end
	return "MutationHighlight"
end

local function destroyMutationHighlight(model: Model)
	local managedName = getManagedHighlightName()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Highlight") and (descendant.Name == managedName or descendant:GetAttribute("ManagedMutationHighlight") == true) then
			descendant:Destroy()
		end
	end
end

function NPCVisualUtils.GetMutationModelColor(mutationId: string?): Color3?
	local configured = getMutationVisualConfig(mutationId)
	if configured and typeof(configured.ModelColor) == "Color3" then
		return configured.ModelColor
	end
	local mutation = MutationRegistry.GetById(mutationId)
	if mutation and typeof(mutation.Color) == "Color3" then
		return mutation.Color
	end
	return nil
end

function NPCVisualUtils.ApplyMutationColorOverride(model: Model, mutationId: string?)
	local overrideColor = NPCVisualUtils.GetMutationModelColor(mutationId)
	destroyMutationHighlight(model)
	if not overrideColor then
		return
	end

	local highlightConfig = NPCVisualConfig.MutationHighlight or {}
	local mutationHighlight = Instance.new("Highlight")
	mutationHighlight.Name = getManagedHighlightName()
	mutationHighlight:SetAttribute("ManagedMutationHighlight", true)
	mutationHighlight.Adornee = model
	mutationHighlight.FillColor = overrideColor
	mutationHighlight.FillTransparency = typeof(highlightConfig.FillTransparency) == "number" and highlightConfig.FillTransparency or 0.45
	mutationHighlight.OutlineTransparency = typeof(highlightConfig.OutlineTransparency) == "number" and highlightConfig.OutlineTransparency or 1
	mutationHighlight.DepthMode = typeof(highlightConfig.DepthMode) == "EnumItem" and highlightConfig.DepthMode or Enum.HighlightDepthMode.Occluded
	mutationHighlight.Parent = model

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = overrideColor
		end
	end
end

function NPCVisualUtils.GetMutationEasyVisualsConfig(mutationId: string?): { [string]: any }?
	local configured = getMutationVisualConfig(mutationId)
	if configured and typeof(configured.EasyVisuals) == "table" then
		return configured.EasyVisuals
	end
	return nil
end

function NPCVisualUtils.GetRarityEasyVisualsConfig(rarityId: string?): { [string]: any }?
	if typeof(rarityId) ~= "string" or rarityId == "" then
		return nil
	end
	local configured = NPCVisualConfig.RarityVisuals[rarityId]
	if configured and typeof(configured.EasyVisuals) == "table" then
		return configured.EasyVisuals
	end
	return nil
end

return NPCVisualUtils
