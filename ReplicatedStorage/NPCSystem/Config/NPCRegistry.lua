local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCDefinitions = require(ReplicatedStorage.NPCSystem.Config.NPCDefinitions)
local RarityDefinitions = require(ReplicatedStorage.NPCSystem.Config.RarityDefinitions)

local NPCRegistry = {}

local NPC_REQUIRED_FIELDS = {
	"Id",
	"TemplateName",
	"DisplayName",
	"MaxHealth",
	"RarityId",
	"AttackRadius",
	"IncomePerSecond",
	"BaseUpgradeCost",
	"CapturableLifetimeSeconds",
}

local RARITY_REQUIRED_FIELDS = {
	"Id",
	"DisplayName",
	"Color",
	"Weight",
}

local definitionsByLookupKey: { [string]: any } = {}
local fallbackRarityDefaultsById: { [string]: { DisplayName: string, Color: Color3, Weight: number } } = {
	Mythic = {
		DisplayName = "Mythic",
		Color = Color3.fromRGB(255, 64, 64),
		Weight = 1200,
	},
}
local warnedFallbackRarityIds: { [string]: boolean } = {}

local function normalizeLookupKey(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local trimmed = value:match("^%s*(.-)%s*$")
	if trimmed == "" then
		return nil
	end
	return string.lower((trimmed :: string):gsub("%s+", ""))
end

local function registerLookupKey(definition: { [string]: any }, lookupKey: any)
	if typeof(lookupKey) ~= "string" or lookupKey == "" then
		return
	end
	if not definitionsByLookupKey[lookupKey] then
		definitionsByLookupKey[lookupKey] = definition
	end
	local normalized = normalizeLookupKey(lookupKey)
	if normalized and not definitionsByLookupKey[normalized] then
		definitionsByLookupKey[normalized] = definition
	end
end

local function validateRarityDefinition(rarityId: string, rarity: { [string]: any }): boolean
	for _, fieldName in ipairs(RARITY_REQUIRED_FIELDS) do
		if rarity[fieldName] == nil then
			warn(("[NPCRegistry] Rarity %s missing field %s"):format(rarityId, fieldName))
			return false
		end
	end

	if typeof(rarity.Id) ~= "string" or rarity.Id == "" then
		warn(("[NPCRegistry] Rarity %s has invalid Id"):format(rarityId))
		return false
	end
	if typeof(rarity.DisplayName) ~= "string" or rarity.DisplayName == "" then
		warn(("[NPCRegistry] Rarity %s has invalid DisplayName"):format(rarityId))
		return false
	end
	if typeof(rarity.Color) ~= "Color3" then
		warn(("[NPCRegistry] Rarity %s has invalid Color"):format(rarityId))
		return false
	end
	if typeof(rarity.Weight) ~= "number" or rarity.Weight <= 0 then
		warn(("[NPCRegistry] Rarity %s has invalid Weight"):format(rarityId))
		return false
	end

	return true
end

local function getFallbackRarityDefinition(rarityId: string): { [string]: any }?
	if typeof(rarityId) ~= "string" or rarityId == "" then
		return nil
	end
	local configuredFallback = fallbackRarityDefaultsById[rarityId]
	if configuredFallback then
		if not warnedFallbackRarityIds[rarityId] then
			warnedFallbackRarityIds[rarityId] = true
			warn(("[NPCRegistry] Using fallback rarity definition for %s"):format(rarityId))
		end
		return {
			Id = rarityId,
			DisplayName = configuredFallback.DisplayName,
			Color = configuredFallback.Color,
			Weight = configuredFallback.Weight,
		}
	end
	return nil
end

local function validateNPCDefinition(definitionId: string, definition: { [string]: any }): boolean
	for _, fieldName in ipairs(NPC_REQUIRED_FIELDS) do
		if definition[fieldName] == nil then
			warn(("[NPCRegistry] Definition %s missing field %s"):format(definitionId, fieldName))
			return false
		end
	end

	if typeof(definition.Id) ~= "string" or definition.Id == "" then
		warn(("[NPCRegistry] Definition %s has invalid Id"):format(definitionId))
		return false
	end
	if typeof(definition.TemplateName) ~= "string" or definition.TemplateName == "" then
		warn(("[NPCRegistry] Definition %s has invalid TemplateName"):format(definitionId))
		return false
	end
	if typeof(definition.DisplayName) ~= "string" or definition.DisplayName == "" then
		warn(("[NPCRegistry] Definition %s has invalid DisplayName"):format(definitionId))
		return false
	end
	if typeof(definition.MaxHealth) ~= "number" or definition.MaxHealth <= 0 then
		warn(("[NPCRegistry] Definition %s has invalid MaxHealth"):format(definitionId))
		return false
	end
	if typeof(definition.RarityId) ~= "string" or definition.RarityId == "" then
		warn(("[NPCRegistry] Definition %s has invalid RarityId"):format(definitionId))
		return false
	end
	if typeof(definition.AttackRadius) ~= "number" or definition.AttackRadius <= 0 then
		warn(("[NPCRegistry] Definition %s has invalid AttackRadius"):format(definitionId))
		return false
	end
	if typeof(definition.IncomePerSecond) ~= "number" or definition.IncomePerSecond < 0 then
		warn(("[NPCRegistry] Definition %s has invalid IncomePerSecond"):format(definitionId))
		return false
	end
	if typeof(definition.BaseUpgradeCost) ~= "number" or definition.BaseUpgradeCost <= 0 then
		warn(("[NPCRegistry] Definition %s has invalid BaseUpgradeCost"):format(definitionId))
		return false
	end
	if typeof(definition.CapturableLifetimeSeconds) ~= "number" or definition.CapturableLifetimeSeconds <= 0 then
		warn(("[NPCRegistry] Definition %s has invalid CapturableLifetimeSeconds"):format(definitionId))
		return false
	end

	local idleAnimationId = definition.IdleAnimationId
	if idleAnimationId ~= nil and typeof(idleAnimationId) ~= "string" then
		warn(("[NPCRegistry] Definition %s has invalid IdleAnimationId"):format(definitionId))
		return false
	end

	local aliveLifetimeSeconds = definition.AliveLifetimeSeconds
	if aliveLifetimeSeconds ~= nil and (typeof(aliveLifetimeSeconds) ~= "number" or aliveLifetimeSeconds <= 0) then
		warn(("[NPCRegistry] Definition %s has invalid AliveLifetimeSeconds"):format(definitionId))
		return false
	end

	return true
end

function NPCRegistry.GetDefinitions(): { [string]: any }
	return NPCDefinitions
end

function NPCRegistry.GetRarityDefinitions(): { [string]: any }
	return RarityDefinitions
end

function NPCRegistry.GetDefinitionById(definitionId: string)
	local exact = NPCDefinitions[definitionId] or definitionsByLookupKey[definitionId]
	if exact then
		return exact
	end
	local normalized = normalizeLookupKey(definitionId)
	if normalized then
		return definitionsByLookupKey[normalized]
	end
	return nil
end

function NPCRegistry.ResolveTemplateModel(templateFolder: Folder, definition: { [string]: any }): Model?
	local exactCandidates = {
		definition.TemplateName,
		definition.Id,
		definition.DisplayName,
	}
	for _, candidate in ipairs(exactCandidates) do
		if typeof(candidate) == "string" and candidate ~= "" then
			local exact = templateFolder:FindFirstChild(candidate)
			if exact and exact:IsA("Model") then
				return exact
			end
		end
	end

	local normalizedTemplates: { [string]: Model } = {}
	for _, child in ipairs(templateFolder:GetChildren()) do
		if child:IsA("Model") then
			local normalized = normalizeLookupKey(child.Name)
			if normalized and not normalizedTemplates[normalized] then
				normalizedTemplates[normalized] = child
			end
		end
	end

	for _, candidate in ipairs(exactCandidates) do
		local normalized = normalizeLookupKey(candidate)
		if normalized and normalizedTemplates[normalized] then
			return normalizedTemplates[normalized]
		end
	end

	return nil
end

function NPCRegistry.BuildRaritySpawnPool(templateFolder: Folder): { any }
	local templatesByName: { [string]: Model } = {}
	for _, child in ipairs(templateFolder:GetChildren()) do
		if child:IsA("Model") then
			templatesByName[child.Name] = child
		else
			warn(("[NPCRegistry] Ignoring non-Model template %s"):format(child.Name))
		end
	end

	local validRarities: { [string]: any } = {}
	for rarityId, rarity in pairs(RarityDefinitions) do
		if validateRarityDefinition(rarityId, rarity) then
			validRarities[rarity.Id] = rarity
		end
	end

	local groupedByRarity: { [string]: { any } } = {}
	for definitionId, definition in pairs(NPCDefinitions) do
		if not validateNPCDefinition(definitionId, definition) then
			continue
		end

		local rarity = validRarities[definition.RarityId]
		if not rarity then
			rarity = getFallbackRarityDefinition(definition.RarityId)
			if rarity then
				validRarities[rarity.Id] = rarity
			else
				warn(("[NPCRegistry] Definition %s references missing rarity %s"):format(definitionId, tostring(definition.RarityId)))
				continue
			end
		end

		local template = NPCRegistry.ResolveTemplateModel(templateFolder, definition)
		if not template then
			warn(("[NPCRegistry] Missing template model %s for definition %s"):format(definition.TemplateName, definitionId))
			continue
		end

		groupedByRarity[rarity.Id] = groupedByRarity[rarity.Id] or {}
		table.insert(groupedByRarity[rarity.Id], {
			Definition = definition,
			Template = template,
			Rarity = rarity,
		})
	end

	for templateName, _ in pairs(templatesByName) do
		local foundMatch = NPCRegistry.GetDefinitionById(templateName) ~= nil
		if not foundMatch then
			warn(("[NPCRegistry] Template %s has no matching NPC definition"):format(templateName))
		end
	end

	local rarityPool = {}
	for rarityId, rarity in pairs(validRarities) do
		local npcEntries = groupedByRarity[rarityId]
		if npcEntries and #npcEntries > 0 then
			table.insert(rarityPool, {
				Rarity = rarity,
				NPCEntries = npcEntries,
			})
		else
			warn(("[NPCRegistry] Rarity %s has no NPC definitions assigned"):format(rarityId))
		end
	end

	return rarityPool
end

for definitionKey, definition in pairs(NPCDefinitions) do
	if typeof(definition) == "table" then
		registerLookupKey(definition, definitionKey)
		registerLookupKey(definition, definition.Id)
		registerLookupKey(definition, definition.TemplateName)
		registerLookupKey(definition, definition.DisplayName)
	end
end

return NPCRegistry
