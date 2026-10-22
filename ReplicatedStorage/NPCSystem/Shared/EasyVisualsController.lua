local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local EasyVisualsController = {}

local effectStateByObject: { [GuiObject]: { Effect: any, Signature: string? } } = {}
local easyVisualsModuleCache = nil

local function isEasyVisualsModule(candidate: any): boolean
	return typeof(candidate) == "table" and typeof(candidate.new) == "function"
end

local function buildSignature(effectConfig: { [string]: any }?): string?
	if typeof(effectConfig) ~= "table" then
		return nil
	end
	local extraArgs = effectConfig.ExtraArgs
	local extraSignature = ""
	if typeof(extraArgs) == "table" then
		for _, value in ipairs(extraArgs) do
			extraSignature ..= "|" .. tostring(value)
		end
	end
	return ("%s|%s|%s%s"):format(
		tostring(effectConfig.Preset),
		tostring(effectConfig.Speed),
		tostring(effectConfig.Size),
		extraSignature
	)
end

local function findEasyVisualsModuleIn(container: Instance?): any
	if not container then
		return nil
	end
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("ModuleScript") and string.find(string.lower(descendant.Name), "easyvisual", 1, true) then
			local ok, result = pcall(require, descendant)
			if ok and isEasyVisualsModule(result) then
				return result
			end
		end
	end
	return nil
end

local function resolveEasyVisualsModule(): any
	if isEasyVisualsModule(easyVisualsModuleCache) then
		return easyVisualsModuleCache
	end

	local globalModule = rawget(_G, "EasyVisuals")
	if isEasyVisualsModule(globalModule) then
		easyVisualsModuleCache = globalModule
		return easyVisualsModuleCache
	end

	local sharedModule = rawget(shared, "EasyVisuals")
	if isEasyVisualsModule(sharedModule) then
		easyVisualsModuleCache = sharedModule
		return easyVisualsModuleCache
	end

	local player = Players.LocalPlayer
	local fromPlayerScripts = player and findEasyVisualsModuleIn(player:FindFirstChild("PlayerScripts")) or nil
	if isEasyVisualsModule(fromPlayerScripts) then
		easyVisualsModuleCache = fromPlayerScripts
		return easyVisualsModuleCache
	end

	local fromStarterPlayerScripts = findEasyVisualsModuleIn(StarterPlayer:FindFirstChild("StarterPlayerScripts"))
	if isEasyVisualsModule(fromStarterPlayerScripts) then
		easyVisualsModuleCache = fromStarterPlayerScripts
		return easyVisualsModuleCache
	end

	local fromReplicatedStorage = findEasyVisualsModuleIn(ReplicatedStorage)
	if isEasyVisualsModule(fromReplicatedStorage) then
		easyVisualsModuleCache = fromReplicatedStorage
		return easyVisualsModuleCache
	end

	return nil
end

function EasyVisualsController.Destroy(guiObject: GuiObject)
	local state = effectStateByObject[guiObject]
	if not state then
		return
	end
	if state.Effect and typeof(state.Effect.Destroy) == "function" then
		pcall(function()
			state.Effect:Destroy()
		end)
	end
	effectStateByObject[guiObject] = nil
end

function EasyVisualsController.Apply(guiObject: GuiObject, effectConfig: { [string]: any }?)
	if not guiObject or not guiObject.Parent then
		return
	end
	local signature = buildSignature(effectConfig)
	local existing = effectStateByObject[guiObject]
	if existing and existing.Signature == signature then
		return
	end
	EasyVisualsController.Destroy(guiObject)

	if typeof(effectConfig) ~= "table" then
		return
	end
	if typeof(effectConfig.Preset) ~= "string" or effectConfig.Preset == "" then
		return
	end

	local easyVisualsModule = resolveEasyVisualsModule()
	if not easyVisualsModule then
		return
	end

	local args = { guiObject, effectConfig.Preset, effectConfig.Speed, effectConfig.Size }
	if typeof(effectConfig.ExtraArgs) == "table" then
		for _, value in ipairs(effectConfig.ExtraArgs) do
			table.insert(args, value)
		end
	end
	local ok, effect = pcall(function()
		return easyVisualsModule.new(table.unpack(args))
	end)
	if not ok then
		return
	end
	effectStateByObject[guiObject] = {
		Effect = effect,
		Signature = signature,
	}
end

return EasyVisualsController
