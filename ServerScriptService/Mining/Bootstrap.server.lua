local ReplicatedStorage = game:GetService("ReplicatedStorage")

local miningRoot = ReplicatedStorage:WaitForChild("Mining")
local configFolder = miningRoot:WaitForChild("Config")

local MiningConfig = require(configFolder:WaitForChild("MiningConfig"))

local MineGenerationService = require(script.Parent.Services:WaitForChild("MineGenerationService"))
local MineResetService = require(script.Parent.Services:WaitForChild("MineResetService"))
local MiningValidationService = require(script.Parent.Services:WaitForChild("MiningValidationService"))

local function ensureFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local remote = parent:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = ensureFolder(miningRoot, MiningConfig.References.RemotesFolderName)
local requestMineBlockRemote = ensureRemoteEvent(remotesFolder, MiningConfig.References.RequestMineBlockRemoteName)

MineGenerationService.RegenerateMine()
MiningValidationService.Init(requestMineBlockRemote, function()
	return MineResetService.IsResetting()
end)
MineResetService.Start()
