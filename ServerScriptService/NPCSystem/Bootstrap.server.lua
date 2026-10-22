
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local npcSystemFolder = ReplicatedStorage:WaitForChild("NPCSystem")
if not npcSystemFolder:FindFirstChild("Remotes") then
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = npcSystemFolder
end

local servicesFolder = script.Parent:WaitForChild("Services")

local BaseService = require(servicesFolder:WaitForChild("BaseService"))
local BaseIncomeService = require(servicesFolder:WaitForChild("BaseIncomeService"))
local BaseSlotService = require(servicesFolder:WaitForChild("BaseSlotService"))
local BaseCollectionService = require(servicesFolder:WaitForChild("BaseCollectionService"))
local BaseUpgradeService = require(servicesFolder:WaitForChild("BaseUpgradeService"))
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RebirthService = require(servicesFolder:WaitForChild("RebirthService"))
local GameplaySFXService = require(servicesFolder:WaitForChild("GameplaySFXService"))

local NPCSpawnService = require(servicesFolder:WaitForChild("NPCSpawnService"))
local NPCDamageService = require(servicesFolder:WaitForChild("NPCDamageService"))

BaseService.Init()
BaseIncomeService.Init(BaseService)
BaseSlotService.Init(BaseService, BaseIncomeService)
BaseUpgradeService.Init(BaseService, BaseSlotService)
BaseCollectionService.Init(BaseService, BaseIncomeService)
DataService.Init(BaseService, BaseSlotService, BaseCollectionService, BaseUpgradeService)
if BaseIncomeService.SetDataService then
	BaseIncomeService.SetDataService(DataService)
end
RebirthService.Init(DataService)
GameplaySFXService.Init()

NPCSpawnService.Init()
NPCDamageService.Init()
