local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local baseConfig = require(ReplicatedStorage.NPCSystem.Config.BaseConfig)
local baseUpgradeConfig = require(ReplicatedStorage.NPCSystem.Config.BaseUpgradeConfig)
local BaseUpgradeProgression = require(ReplicatedStorage.NPCSystem.Shared.BaseUpgradeProgression)
local CompactNumberFormatter = require(ReplicatedStorage.NPCSystem.Shared.CompactNumberFormatter)

local BaseUpgradeService = {}
BaseUpgradeService.__index = BaseUpgradeService

local BaseService = nil
local BaseSlotService = nil
local DataService = nil

local upgradeCountByPlayer: { [Player]: number } = {}
local purchaseInProgressByPlayer: { [Player]: boolean } = {}
local lastPurchaseRequestAtByPlayer: { [Player]: number } = {}
local changedCallbacks: { (Player, Model, number) -> () } = {}
local remotesFolder = ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Remotes")
local upgradeRequestRemote: RemoteEvent = remotesFolder:FindFirstChild(baseUpgradeConfig.RemoteEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")
local upgradeFeedbackRemote: RemoteEvent = remotesFolder:FindFirstChild(baseUpgradeConfig.FeedbackRemoteEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")
local setSlotUnlocked: (slotPart: BasePart, unlocked: boolean) -> ()

upgradeRequestRemote.Name = baseUpgradeConfig.RemoteEventName
upgradeRequestRemote.Parent = remotesFolder
upgradeFeedbackRemote.Name = baseUpgradeConfig.FeedbackRemoteEventName
upgradeFeedbackRemote.Parent = remotesFolder

local function parseTrailingNumber(name: string, expectedPrefix: string?): number?
	local normalized = name
	if expectedPrefix and expectedPrefix ~= "" then
		local startIndex, endIndex = string.find(string.lower(name), "^" .. string.lower(expectedPrefix))
		if not startIndex or startIndex ~= 1 then
			return nil
		end
		normalized = string.sub(name, (endIndex or 0) + 1)
	end
	local numericSuffix = string.match(normalized, "(%d+)$")
	if not numericSuffix then
		return nil
	end
	return tonumber(numericSuffix)
end

local function getFloorsRoot(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(baseUpgradeConfig.FloorSourceFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function resolveBaseLayoutId(baseModel: Model): string
	local attributeName = baseUpgradeConfig.BaseLayoutIdAttributeName
	local attributeValue = baseModel:GetAttribute(attributeName)
	if typeof(attributeValue) == "string" and attributeValue ~= "" then
		return attributeValue
	end
	return baseModel.Name
end

local function resolveFloorTemplate(baseModel: Model, floorName: string): Model?
	local floorsRoot = getFloorsRoot()
	if not floorsRoot then
		warn(("[BaseUpgradeService] Missing ReplicatedStorage/%s folder"):format(baseUpgradeConfig.FloorSourceFolderName))
		return nil
	end
	local baseFolder = floorsRoot:FindFirstChild(resolveBaseLayoutId(baseModel))
	if not (baseFolder and baseFolder:IsA("Folder")) then
		warn(("[BaseUpgradeService] Missing floors folder for base layout %s"):format(resolveBaseLayoutId(baseModel)))
		return nil
	end
	local floorFolder = baseFolder:FindFirstChild(floorName)
	if floorFolder and floorFolder:IsA("Folder") then
		local exactModel = floorFolder:FindFirstChild(floorName)
		if exactModel and exactModel:IsA("Model") then
			return exactModel
		end
		for _, child in ipairs(floorFolder:GetChildren()) do
			if child:IsA("Model") then
				return child
			end
		end
	end
	return nil
end

local function getFloorContainer(baseModel: Model, floorName: string): Instance?
	local floor = baseModel:FindFirstChild(floorName)
	if floor and (floor:IsA("Model") or floor:IsA("Folder")) then
		local nestedSlots = floor:FindFirstChild(baseConfig.BaseSlotsFolderName)
		if nestedSlots and nestedSlots:IsA("Folder") then
			return nestedSlots
		end
		return floor
	end
	local slotsFolder = baseModel:FindFirstChild(baseConfig.BaseSlotsFolderName)
	if slotsFolder and slotsFolder:IsA("Folder") then
		local nestedFloor = slotsFolder:FindFirstChild(floorName)
		if nestedFloor and (nestedFloor:IsA("Model") or nestedFloor:IsA("Folder")) then
			local nestedSlots = nestedFloor:FindFirstChild(baseConfig.BaseSlotsFolderName)
			if nestedSlots and nestedSlots:IsA("Folder") then
				return nestedSlots
			end
			return nestedFloor
		end
	end
	return nil
end

local function getOrderedSlotsFromContainer(container: Instance): { BasePart }
	local slotsByNumber: { [number]: BasePart } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("BasePart") then
			local slotNumber = parseTrailingNumber(child.Name, "Slot")
			if slotNumber then
				if not slotsByNumber[slotNumber] then
					slotsByNumber[slotNumber] = child
				else
					warn(("[BaseUpgradeService] Ignoring duplicate slot number %d in %s"):format(slotNumber, container:GetFullName()))
				end
			end
		end
	end
	local slots = {}
	for _, slot in pairs(slotsByNumber) do
		table.insert(slots, slot)
	end
	table.sort(slots, function(a, b)
		local aIndex = parseTrailingNumber(a.Name, "Slot")
		local bIndex = parseTrailingNumber(b.Name, "Slot")
		if aIndex and bIndex and aIndex ~= bIndex then
			return aIndex < bIndex
		end
		if aIndex and not bIndex then
			return true
		end
		if bIndex and not aIndex then
			return false
		end
		return a.Name:lower() < b.Name:lower()
	end)
	return slots
end

local function getAllKnownFloorNames(baseModel: Model): { string }
	local names = { "Floor1" }
	for _, floorEntry in ipairs(baseUpgradeConfig.FloorProgression) do
		if not table.find(names, floorEntry.FloorName) then
			table.insert(names, floorEntry.FloorName)
		end
	end
	for _, child in ipairs(baseModel:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") then
			local floorIndex = parseTrailingNumber(child.Name, "Floor")
			if floorIndex and not table.find(names, child.Name) then
				table.insert(names, child.Name)
			end
		end
	end
	return names
end

local function ensureDynamicFloor(baseModel: Model, floorName: string)
	if floorName == "Floor1" then
		return
	end
	local existing = baseModel:FindFirstChild(floorName)
	if existing and existing:IsA("Model") then
		return
	end
	local template = resolveFloorTemplate(baseModel, floorName)
	if not template then
		warn(("[BaseUpgradeService] Missing template for %s on base %s"):format(floorName, baseModel:GetFullName()))
		return
	end
	local clone = template:Clone()
	clone.Name = floorName
	clone:SetAttribute(baseUpgradeConfig.DynamicFloorAttributeName, true)
	local cloneContainer = getFloorContainer(clone, floorName)
	if cloneContainer then
		for _, slot in ipairs(getOrderedSlotsFromContainer(cloneContainer)) do
			setSlotUnlocked(slot, false)
		end
	end
	clone.Parent = baseModel
end

local function removeUnusedDynamicFloors(baseModel: Model, requiredFloors: { [string]: boolean })
	for _, child in ipairs(baseModel:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(baseUpgradeConfig.DynamicFloorAttributeName) == true and not requiredFloors[child.Name] then
			child:Destroy()
		end
	end
end

local function canSatisfyUpgradeCount(baseModel: Model, upgradeCount: number): boolean
	local requiredFloors = BaseUpgradeProgression.GetRequiredFloors(upgradeCount)
	for floorName in pairs(requiredFloors) do
		if floorName ~= "Floor1" and not getFloorContainer(baseModel, floorName) and not resolveFloorTemplate(baseModel, floorName) then
			return false
		end
	end
	return true
end

local function cacheSlotVisualDefaults(instance: Instance)
	if instance:IsA("BasePart") then
		if instance:GetAttribute("BaseUpgradeOriginalTransparency") == nil then
			instance:SetAttribute("BaseUpgradeOriginalTransparency", instance.Transparency)
		end
		if instance:GetAttribute("BaseUpgradeOriginalCanCollide") == nil then
			instance:SetAttribute("BaseUpgradeOriginalCanCollide", instance.CanCollide)
		end
		if instance:GetAttribute("BaseUpgradeOriginalCanTouch") == nil then
			instance:SetAttribute("BaseUpgradeOriginalCanTouch", instance.CanTouch)
		end
		if instance:GetAttribute("BaseUpgradeOriginalCanQuery") == nil then
			instance:SetAttribute("BaseUpgradeOriginalCanQuery", instance.CanQuery)
		end
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		if instance:GetAttribute("BaseUpgradeOriginalEnabled") == nil then
			instance:SetAttribute("BaseUpgradeOriginalEnabled", instance.Enabled)
		end
	elseif instance:IsA("ProximityPrompt") then
		if instance:GetAttribute("BaseUpgradeOriginalEnabled") == nil then
			instance:SetAttribute("BaseUpgradeOriginalEnabled", instance.Enabled)
		end
	end
end

local function setInstanceActive(instance: Instance, unlocked: boolean)
	cacheSlotVisualDefaults(instance)
	if instance:IsA("BasePart") then
		instance.Transparency = unlocked and (instance:GetAttribute("BaseUpgradeOriginalTransparency") or 0) or baseUpgradeConfig.LockedSlotTransparency
		instance.CanCollide = unlocked and (instance:GetAttribute("BaseUpgradeOriginalCanCollide") == true) or false
		instance.CanTouch = unlocked and (instance:GetAttribute("BaseUpgradeOriginalCanTouch") == true) or false
		instance.CanQuery = unlocked and (instance:GetAttribute("BaseUpgradeOriginalCanQuery") == true) or false
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		instance.Enabled = unlocked and (instance:GetAttribute("BaseUpgradeOriginalEnabled") ~= false)
	elseif instance:IsA("ProximityPrompt") then
		instance.Enabled = unlocked and (instance:GetAttribute("BaseUpgradeOriginalEnabled") ~= false)
	end
end

setSlotUnlocked = function(slotPart: BasePart, unlocked: boolean)
	slotPart:SetAttribute(baseUpgradeConfig.LockedSlotAttributeName, unlocked)
	setInstanceActive(slotPart, unlocked)
	for _, descendant in ipairs(slotPart:GetDescendants()) do
		setInstanceActive(descendant, unlocked)
	end
end

local function resolveUpgradeNodes(baseModel: Model): (GuiButton?, TextLabel?, TextLabel?)
	local upgradeModel = baseModel:FindFirstChild(baseUpgradeConfig.BaseUpgradeModelName, true)
	if not (upgradeModel and upgradeModel:IsA("Model")) then
		return nil, nil, nil
	end
	local guiPart = upgradeModel:FindFirstChild(baseUpgradeConfig.GUIPartName, true)
	if not (guiPart and guiPart:IsA("BasePart")) then
		return nil, nil, nil
	end
	local surfaceGui = guiPart:FindFirstChild(baseUpgradeConfig.SurfaceGuiName)
	if not (surfaceGui and surfaceGui:IsA("SurfaceGui")) then
		return nil, nil, nil
	end
	local button = surfaceGui:FindFirstChild(baseUpgradeConfig.ButtonName)
	if not (button and button:IsA("GuiButton")) then
		return nil, nil, nil
	end
	local costLabel = button:FindFirstChild(baseUpgradeConfig.CostLabelName)
	local slotCountLabel = button:FindFirstChild(baseUpgradeConfig.SlotCountLabelName)
	return button, costLabel and costLabel:IsA("TextLabel") and costLabel or nil, slotCountLabel and slotCountLabel:IsA("TextLabel") and slotCountLabel or nil
end

local function updateBaseUpgradeUI(baseModel: Model, upgradeCount: number)
	local button, costLabel, slotCountLabel = resolveUpgradeNodes(baseModel)
	if not button then
		return
	end
	local currentCost = BaseUpgradeProgression.GetCurrentCost(upgradeCount)
	button:SetAttribute("BaseUpgradeCount", upgradeCount)
	button:SetAttribute("BaseUpgradeMaxed", BaseUpgradeProgression.IsMaxed(upgradeCount))
	button:SetAttribute("BaseUpgradeCurrentCost", currentCost or "")
	if costLabel then
		if currentCost then
			costLabel.Text = CompactNumberFormatter.FormatCurrency(currentCost, "$")
		else
			costLabel.Text = baseUpgradeConfig.MaxCostText
		end
	end
	if slotCountLabel then
		slotCountLabel.Text = BaseUpgradeProgression.GetProgressText(upgradeCount)
	end
end

local function notifyChanged(player: Player, baseModel: Model, upgradeCount: number)
	for _, callback in ipairs(changedCallbacks) do
		callback(player, baseModel, upgradeCount)
	end
end

local function applyUpgradeStateToBase(player: Player?, baseModel: Model, upgradeCount: number)
	local progressionState = BaseUpgradeProgression.GetUpgradeState(upgradeCount)
	local clampedCount = progressionState.UpgradeCount
	local requiredFloors = progressionState.RequiredFloors
	for floorName in pairs(requiredFloors) do
		ensureDynamicFloor(baseModel, floorName)
	end
	removeUnusedDynamicFloors(baseModel, requiredFloors)

	for _, floorName in ipairs(getAllKnownFloorNames(baseModel)) do
		local floorContainer = getFloorContainer(baseModel, floorName)
		if floorContainer then
			local unlockedCountForFloor = progressionState.UnlockedSlotsByFloor[floorName] or 0
			for slotIndex, slot in ipairs(getOrderedSlotsFromContainer(floorContainer)) do
				setSlotUnlocked(slot, slotIndex <= unlockedCountForFloor)
			end
		end
	end

	baseModel:SetAttribute(baseUpgradeConfig.CurrentUpgradeAttributeName, clampedCount)
	baseModel:SetAttribute(baseUpgradeConfig.CurrentUnlockedSlotsAttributeName, progressionState.UnlockedSlotCount)
	updateBaseUpgradeUI(baseModel, clampedCount)
	if BaseSlotService and BaseSlotService.RefreshBaseLayout then
		BaseSlotService.RefreshBaseLayout(baseModel)
	end
	if player then
		upgradeCountByPlayer[player] = clampedCount
		notifyChanged(player, baseModel, clampedCount)
	end
end

local function fireUpgradeFeedback(player: Player, payload: { [string]: any })
	upgradeFeedbackRemote:FireClient(player, payload)
end

local function canUseDevReset(player: Player): boolean
	if baseUpgradeConfig.DevResetStudioOnly == true then
		return RunService:IsStudio()
	end
	return true
end

local function normalizeCommandText(message: string): string
	return string.lower((message or ""):match("^%s*(.-)%s*$") or "")
end

local function resetPlayerUpgradeProgress(player: Player)
	if not BaseService then
		return
	end
	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel or not BaseService.IsOwner(player, baseModel) then
		return
	end
	applyUpgradeStateToBase(player, baseModel, 0)
	fireUpgradeFeedback(player, {
		Type = "Reset",
		UpgradeCount = 0,
	})
end

local function bindDevResetCommand(player: Player)
	player.Chatted:Connect(function(message)
		if normalizeCommandText(message) ~= string.lower(baseUpgradeConfig.DevResetCommand) then
			return
		end
		if not canUseDevReset(player) then
			return
		end
		resetPlayerUpgradeProgress(player)
	end)
end

local function onUpgradeRequest(player: Player)
	if not BaseService then
		return
	end
	local now = os.clock()
	local lastRequestAt = lastPurchaseRequestAtByPlayer[player]
	if purchaseInProgressByPlayer[player] == true then
		return
	end
	if typeof(lastRequestAt) == "number" and now - lastRequestAt < baseUpgradeConfig.PurchaseDebounceSeconds then
		return
	end
	purchaseInProgressByPlayer[player] = true
	lastPurchaseRequestAtByPlayer[player] = now
	local baseModel = BaseService.GetBaseForPlayer(player)
	local success, err = xpcall(function()
		if not baseModel or not BaseService.IsOwner(player, baseModel) then
			return
		end
		if not (DataService and DataService.IsLoaded and DataService.IsLoaded(player)) then
			return
		end
		local currentCount = BaseUpgradeService.GetUpgradeCountForPlayer(player)
		if BaseUpgradeProgression.IsMaxed(currentCount) then
			fireUpgradeFeedback(player, { Type = "Maxed" })
			applyUpgradeStateToBase(player, baseModel, currentCount)
			return
		end
		local currentCost = BaseUpgradeProgression.GetCurrentCost(currentCount)
		if not currentCost then
			fireUpgradeFeedback(player, { Type = "Maxed" })
			return
		end
		local newCount = BaseUpgradeProgression.ClampUpgradeCount(currentCount + 1)
		if not canSatisfyUpgradeCount(baseModel, newCount) then
			warn(("[BaseUpgradeService] Cannot satisfy upgrade progression %d for %s due to missing floor templates"):format(newCount, baseModel:GetFullName()))
			return
		end
		if not (DataService and DataService.TrySpendMoney and DataService.TrySpendMoney(player, currentCost)) then
			fireUpgradeFeedback(player, { Type = "InsufficientFunds" })
			return
		end
		applyUpgradeStateToBase(player, baseModel, newCount)
		fireUpgradeFeedback(player, {
			Type = "Upgraded",
			UpgradeCount = newCount,
		})
	end, debug.traceback)
	purchaseInProgressByPlayer[player] = nil
	if not success then
		warn(("[BaseUpgradeService] Upgrade request failed for %s: %s"):format(player.Name, err))
	end
end

function BaseUpgradeService.RegisterChangedCallback(callback: (Player, Model, number) -> ())
	table.insert(changedCallbacks, callback)
end

function BaseUpgradeService.SetDataService(dataService)
	DataService = dataService
end

function BaseUpgradeService.GetUpgradeCountForPlayer(player: Player): number
	return BaseUpgradeProgression.ClampUpgradeCount(upgradeCountByPlayer[player])
end

function BaseUpgradeService.RestoreBaseForPlayer(player: Player, upgradeCount: number?)
	if not BaseService then
		return
	end
	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel then
		return
	end
	applyUpgradeStateToBase(player, baseModel, BaseUpgradeProgression.ClampUpgradeCount(upgradeCount))
end

function BaseUpgradeService.ResetProgressForPlayer(player: Player)
	resetPlayerUpgradeProgress(player)
end

function BaseUpgradeService.ResetBase(baseModel: Model)
	applyUpgradeStateToBase(nil, baseModel, 0)
end

function BaseUpgradeService.Init(baseService, baseSlotService)
	BaseService = baseService
	BaseSlotService = baseSlotService

	for _, baseModel in ipairs(BaseService.GetAllBases()) do
		BaseUpgradeService.ResetBase(baseModel)
	end

	BaseService.RegisterReleaseCallback(function(player, baseModel)
		upgradeCountByPlayer[player] = nil
		purchaseInProgressByPlayer[player] = nil
		lastPurchaseRequestAtByPlayer[player] = nil
		BaseUpgradeService.ResetBase(baseModel)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bindDevResetCommand(player)
	end
	Players.PlayerAdded:Connect(bindDevResetCommand)

	upgradeRequestRemote.OnServerEvent:Connect(onUpgradeRequest)
end

return BaseUpgradeService
