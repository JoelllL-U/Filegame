local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local baseConfig = require(ReplicatedStorage.NPCSystem.Config.BaseConfig)

local BaseCollectionService = {}
BaseCollectionService.__index = BaseCollectionService

local BaseService = nil
local BaseIncomeService = nil
local DataService = nil

local remotesFolder = ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Remotes")
local collectionFeedbackRemote: RemoteEvent = remotesFolder:FindFirstChild(baseConfig.Remotes.CollectionFeedbackEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")

collectionFeedbackRemote.Name = baseConfig.Remotes.CollectionFeedbackEventName
collectionFeedbackRemote.Parent = remotesFolder

local touchDebounceByKey: { [string]: number } = {}
local boundCollectParts: { [BasePart]: boolean } = {}

local function getPlayerFromTouch(hitPart: BasePart): Player?
	local model = hitPart.Parent
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function addCurrency(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	if DataService and DataService.AddMoney then
		DataService.AddMoney(player, amount)
		return
	end

	warn(("[BaseCollectionService] DataService unavailable; cannot add money for %s"):format(player.Name))
end

local function canCollectNow(player: Player, collectPart: BasePart): boolean
	local now = os.clock()
	local key = tostring(player.UserId) .. "::" .. collectPart:GetFullName()
	local last = touchDebounceByKey[key]
	local cooldownSeconds = baseConfig.CollectionPerPartCooldownSeconds
	if typeof(cooldownSeconds) ~= "number" then
		cooldownSeconds = baseConfig.CollectionDebounceSeconds
	end
	if last and now - last < cooldownSeconds then
		return false
	end
	touchDebounceByKey[key] = now
	return true
end

local function isSlotPart(slot: Instance): boolean
	if not slot:IsA("BasePart") then
		return false
	end
	if string.match(slot.Name, "^Slot%d+$") then
		return true
	end
	return slot:FindFirstChild(baseConfig.SlotCollectPartName) ~= nil
end

local function resolveCollectPartForSlot(slot: BasePart): BasePart?
	local collectPart = slot:FindFirstChild(baseConfig.SlotCollectPartName)
	if collectPart and collectPart:IsA("BasePart") then
		return collectPart
	end
	local fallbackCollect = slot:FindFirstChild("CollectTouch")
	if fallbackCollect and fallbackCollect:IsA("BasePart") then
		return fallbackCollect
	end
	return nil
end

local function resolveSlotsFolder(baseModel: Model): Folder?
	local direct = baseModel:FindFirstChild(baseConfig.BaseSlotsFolderName)
	if direct and direct:IsA("Folder") then
		return direct
	end
	local nested = baseModel:FindFirstChild(baseConfig.BaseSlotsFolderName, true)
	if nested and nested:IsA("Folder") then
		return nested
	end
	return nil
end

local function fireCollectionFeedback(player: Player, collectPart: BasePart, amount: number)
	if amount <= 0 then
		return
	end
	collectionFeedbackRemote:FireClient(player, {
		CollectPart = collectPart,
		WorldPosition = collectPart.Position,
		Amount = amount,
	})
end

local function bindCollectPart(baseModel: Model, slot: BasePart, collectPart: BasePart)
	if boundCollectParts[collectPart] then
		return
	end
	boundCollectParts[collectPart] = true
	collectPart.Touched:Connect(function(hitPart)
		local player = getPlayerFromTouch(hitPart)
		if not player then
			return
		end
		if not canCollectNow(player, collectPart) then
			return
		end
		if not BaseService.IsOwner(player, baseModel) then
			return
		end

		local pending = BaseIncomeService.GetPendingForSlot(slot)
		if pending <= 0 then
			return
		end

		BaseIncomeService.ClearPendingForSlot(slot)
		addCurrency(player, pending)
		fireCollectionFeedback(player, collectPart, pending)
	end)
end

local function bindCollectPartsForBase(baseModel: Model)
	for _, candidate in ipairs(baseModel:GetDescendants()) do
		if isSlotPart(candidate) then
			local slot = candidate :: BasePart
			local collectPart = resolveCollectPartForSlot(slot)
			if collectPart then
				bindCollectPart(baseModel, slot, collectPart)
			end
		end
	end
end

function BaseCollectionService.SetDataService(dataService)
	DataService = dataService
end

function BaseCollectionService.Init(baseService, baseIncomeService)
	BaseService = baseService
	BaseIncomeService = baseIncomeService

	for _, baseModel in ipairs(BaseService.GetAllBases()) do
		local slotsFolder = resolveSlotsFolder(baseModel)
		if not (slotsFolder and slotsFolder:IsA("Folder")) then
			warn(("[BaseCollectionService] Base %s missing slots folder %s"):format(baseModel:GetFullName(), baseConfig.BaseSlotsFolderName))
		end
		bindCollectPartsForBase(baseModel)
		baseModel.DescendantAdded:Connect(function(descendant)
			if isSlotPart(descendant) then
				task.defer(function()
					local slot = descendant :: BasePart
					local collectPart = resolveCollectPartForSlot(slot)
					if collectPart then
						bindCollectPart(baseModel, slot, collectPart)
					end
				end)
				return
			end
			if descendant:IsA("BasePart") and (descendant.Name == baseConfig.SlotCollectPartName or descendant.Name == "CollectTouch") then
				local parent = descendant.Parent
				if parent and isSlotPart(parent) then
					bindCollectPart(baseModel, parent :: BasePart, descendant)
				end
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		local prefix = tostring(player.UserId) .. "::"
		for key, _ in pairs(touchDebounceByKey) do
			if string.sub(key, 1, #prefix) == prefix then
				touchDebounceByKey[key] = nil
			end
		end
	end)
end

return BaseCollectionService
