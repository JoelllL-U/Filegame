local ReplicatedStorage = game:GetService("ReplicatedStorage")

local npcSystemFolder = ReplicatedStorage:WaitForChild("NPCSystem")
local remotesFolder = npcSystemFolder:WaitForChild("Remotes")
local config = require(npcSystemFolder.Config.GameplaySFXConfig)

local GameplaySFXService = {}
GameplaySFXService.__index = GameplaySFXService

local gameplaySFXRemote: RemoteEvent = remotesFolder:FindFirstChild(config.RemoteEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")

gameplaySFXRemote.Name = config.RemoteEventName
gameplaySFXRemote.Parent = remotesFolder

local function resolveEventConfig(soundKey: string): { [string]: any }?
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

function GameplaySFXService.Init()
	gameplaySFXRemote.Name = config.RemoteEventName
	gameplaySFXRemote.Parent = remotesFolder
end

function GameplaySFXService.PlayForPlayer(player: Player?, soundKey: string, worldPosition: Vector3?)
	if not player or typeof(soundKey) ~= "string" or soundKey == "" then
		return
	end
	if not resolveEventConfig(soundKey) then
		return
	end
	gameplaySFXRemote:FireClient(player, {
		SoundKey = soundKey,
		WorldPosition = worldPosition,
	})
end

return GameplaySFXService
