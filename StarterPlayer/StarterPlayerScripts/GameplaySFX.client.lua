local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local npcSystem = ReplicatedStorage:WaitForChild("NPCSystem")
local config = require(npcSystem.Config.GameplaySFXConfig)
local remotesFolder = npcSystem:WaitForChild("Remotes")
local gameplaySFXRemote = remotesFolder:WaitForChild(config.RemoteEventName)

local cooldownUntilBySoundKey: { [string]: number } = {}
local warnedMissingTemplateFolder = false
local warnedMissingTemplateByKey: { [string]: boolean } = {}

local function resolvePath(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, segment in ipairs(path) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
	end
	return current
end

local function resolveTemplateSound(soundKey: string, eventConfig: { [string]: any }): Sound?
	local folderPath = config.TemplateFolderPath
	if typeof(folderPath) ~= "table" then
		return nil
	end
	local templateFolder = resolvePath(game, folderPath)
	if not templateFolder then
		if not warnedMissingTemplateFolder then
			warn("[GameplaySFX] Missing configured gameplay SFX template folder")
			warnedMissingTemplateFolder = true
		end
		return nil
	end

	local templateName = typeof(eventConfig.TemplateName) == "string" and eventConfig.TemplateName or soundKey
	local template = templateFolder:FindFirstChild(templateName)
	if not template then
		if not warnedMissingTemplateByKey[soundKey] then
			warn(("[GameplaySFX] Missing sound template %s in gameplay SFX folder"):format(templateName))
			warnedMissingTemplateByKey[soundKey] = true
		end
		return nil
	end

	if template:IsA("Sound") then
		return template:Clone()
	end

	local embedded = template:FindFirstChildWhichIsA("Sound", true)
	if embedded then
		return embedded:Clone()
	end

	if not warnedMissingTemplateByKey[soundKey] then
		warn(("[GameplaySFX] Template %s does not contain a Sound instance"):format(templateName))
		warnedMissingTemplateByKey[soundKey] = true
	end
	return nil
end

local function getEventConfig(soundKey: string): { [string]: any }?
	local events = config.Events
	if typeof(events) ~= "table" then
		return nil
	end
	local eventConfig = events[soundKey]
	if typeof(eventConfig) ~= "table" then
		return nil
	end
	return eventConfig
end

local function canPlayNow(soundKey: string, eventConfig: { [string]: any }): boolean
	local cooldown = tonumber(eventConfig.CooldownSeconds)
	if cooldown == nil then
		local defaults = config.Defaults
		cooldown = (typeof(defaults) == "table" and tonumber(defaults.CooldownSeconds)) or 0
	end
	cooldown = math.max(0, cooldown or 0)
	local now = os.clock()
	local nextAllowed = cooldownUntilBySoundKey[soundKey] or 0
	if now < nextAllowed then
		return false
	end
	cooldownUntilBySoundKey[soundKey] = now + cooldown
	return true
end

local function playSound(soundKey: string, payload: { [string]: any })
	local eventConfig = getEventConfig(soundKey)
	if not eventConfig then
		return
	end
	local sound = resolveTemplateSound(soundKey, eventConfig)
	if not sound then
		return
	end
	if not canPlayNow(soundKey, eventConfig) then
		sound:Destroy()
		return
	end

	local defaults = typeof(config.Defaults) == "table" and config.Defaults or {}
	sound.Name = "GameplaySFX_" .. soundKey
	sound.Volume = math.max(0, tonumber(eventConfig.Volume) or tonumber(defaults.Volume) or 0.75)
	sound.PlaybackSpeed = math.max(0.05, tonumber(eventConfig.PlaybackSpeed) or tonumber(defaults.PlaybackSpeed) or 1)
	sound.RollOffMinDistance = math.max(1, tonumber(eventConfig.RollOffMinDistance) or tonumber(defaults.RollOffMinDistance) or 8)
	sound.RollOffMaxDistance = math.max(sound.RollOffMinDistance, tonumber(eventConfig.RollOffMaxDistance) or tonumber(defaults.RollOffMaxDistance) or 70)
	sound.RollOffMode = Enum.RollOffMode.Linear

	local worldPosition = payload.WorldPosition
	local spatial = eventConfig.Spatial ~= false and typeof(worldPosition) == "Vector3"
	if spatial then
		local holder = Instance.new("Part")
		holder.Name = sound.Name .. "Part"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.CFrame = CFrame.new(worldPosition)
		holder.Parent = workspace
		sound.Parent = holder
		sound:Play()
		Debris:AddItem(holder, math.max(sound.TimeLength + (tonumber(config.CleanupBufferSeconds) or 0.35), 2))
		return
	end

	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, math.max(sound.TimeLength + (tonumber(config.CleanupBufferSeconds) or 0.35), 2))
end

gameplaySFXRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local soundKey = payload.SoundKey
	if typeof(soundKey) ~= "string" or soundKey == "" then
		return
	end
	playSound(soundKey, payload)
end)
