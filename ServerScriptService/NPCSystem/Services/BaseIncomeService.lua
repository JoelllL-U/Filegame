local ReplicatedStorage = game:GetService("ReplicatedStorage")

local baseConfig = require(ReplicatedStorage.NPCSystem.Config.BaseConfig)
local CompactNumberFormatter = require(ReplicatedStorage.NPCSystem.Shared.CompactNumberFormatter)

local BaseIncomeService = {}
BaseIncomeService.__index = BaseIncomeService

type LoopState = {
	Running: boolean,
	Token: number,
	BaseModel: Model,
	RawIncomePerSecond: number,
}

local activeIncomeLoops: { [BasePart]: LoopState } = {}
local pendingBySlot: { [BasePart]: number } = {}
local BaseService = nil
local DataService = nil

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

local function isSlotPart(slot: Instance): boolean
	if not slot:IsA("BasePart") then
		return false
	end
	if string.match(slot.Name, "^Slot%d+$") then
		return true
	end
	return slot:FindFirstChild(baseConfig.SlotCollectPartName) ~= nil
end

local function resolveAmountLabel(slotPart: BasePart): TextLabel?
	local collectPart = slotPart:FindFirstChild(baseConfig.SlotCollectPartName)
	if not (collectPart and collectPart:IsA("BasePart")) then
		collectPart = slotPart:FindFirstChild("CollectTouch")
	end
	if not collectPart or not collectPart:IsA("BasePart") then
		warn(("[BaseIncomeService] Slot %s missing collect part %s"):format(slotPart:GetFullName(), baseConfig.SlotCollectPartName))
		return nil
	end
	local surface = collectPart:FindFirstChild("Text")
	if not surface or not surface:IsA("SurfaceGui") then
		warn(("[BaseIncomeService] Collect part %s missing SurfaceGui Text"):format(collectPart:GetFullName()))
		return nil
	end
	local amount = surface:FindFirstChild("$amount")
	if not amount or not amount:IsA("TextLabel") then
		warn(("[BaseIncomeService] SurfaceGui %s missing TextLabel $amount"):format(surface:GetFullName()))
		return nil
	end
	return amount
end

local function formatAmount(amount: number): string
	local prefix = baseConfig.Income.SlotAmountPrefix
	if typeof(prefix) ~= "string" then
		prefix = "$"
	end
	return CompactNumberFormatter.FormatCurrency(amount, prefix)
end

function BaseIncomeService.UpdateSlotAmountUI(slotPart: BasePart)
	local amountText = resolveAmountLabel(slotPart)
	if not amountText then
		return
	end
	local pending = pendingBySlot[slotPart]
	if pending == nil then
		local empty = baseConfig.Income.SlotEmptyAmountText
		if typeof(empty) ~= "string" then
			empty = "$0"
		end
		amountText.Text = empty
		return
	end
	amountText.Text = formatAmount(pending)
end

local function addPendingForSlot(slotPart: BasePart, amount: number)
	if amount <= 0 then
		return
	end
	pendingBySlot[slotPart] = (pendingBySlot[slotPart] or 0) + amount
	BaseIncomeService.UpdateSlotAmountUI(slotPart)
end

local function getRebirthMultiplierForBase(baseModel: Model): number
	if not (BaseService and BaseService.GetOwnerForBase and DataService and DataService.GetRebirthState) then
		return 1
	end
	local owner = BaseService.GetOwnerForBase(baseModel)
	if not owner then
		return 1
	end
	local rebirthState = DataService.GetRebirthState(owner)
	local multiplier = rebirthState and tonumber(rebirthState.Multiplier) or 1
	if not multiplier or multiplier < 0 then
		return 0
	end
	return multiplier
end

function BaseIncomeService.GetPendingForSlot(slotPart: BasePart): number
	return pendingBySlot[slotPart] or 0
end

function BaseIncomeService.ClearPendingForSlot(slotPart: BasePart)
	pendingBySlot[slotPart] = 0
	BaseIncomeService.UpdateSlotAmountUI(slotPart)
end

function BaseIncomeService.StartIncome(baseModel: Model, slotPart: BasePart, incomePerSecond: number)
	BaseIncomeService.StopIncome(slotPart)

	local rate = incomePerSecond
	if typeof(rate) ~= "number" or rate < 0 then
		rate = baseConfig.Income.DefaultIncomePerSecond
	end

	local interval = baseConfig.Income.TickIntervalSeconds
	if typeof(interval) ~= "number" or interval <= 0 then
		interval = 1
	end

	local loopState: LoopState = {
		Running = true,
		Token = os.clock() * 1000,
		BaseModel = baseModel,
		RawIncomePerSecond = rate,
	}
	activeIncomeLoops[slotPart] = loopState
	pendingBySlot[slotPart] = 0
	BaseIncomeService.UpdateSlotAmountUI(slotPart)
	local token = loopState.Token

	task.spawn(function()
		while loopState.Running and activeIncomeLoops[slotPart] and activeIncomeLoops[slotPart].Token == token do
			task.wait(interval)
			if not loopState.Running then
				break
			end
			if slotPart.Parent == nil then
				break
			end
			if baseModel.Parent == nil then
				break
			end
			local effectiveRate = loopState.RawIncomePerSecond * getRebirthMultiplierForBase(loopState.BaseModel)
			addPendingForSlot(slotPart, effectiveRate * interval)
		end
	end)
end


function BaseIncomeService.UpdateIncomeRate(slotPart: BasePart, incomePerSecond: number)
	local state = activeIncomeLoops[slotPart]
	if not state then
		return false
	end
	local rate = incomePerSecond
	if typeof(rate) ~= "number" or rate < 0 then
		rate = baseConfig.Income.DefaultIncomePerSecond
	end
	state.RawIncomePerSecond = rate
	return true
end

function BaseIncomeService.StopIncome(slotPart: BasePart)
	local state = activeIncomeLoops[slotPart]
	if state then
		state.Running = false
		activeIncomeLoops[slotPart] = nil
	end
	pendingBySlot[slotPart] = nil
	BaseIncomeService.UpdateSlotAmountUI(slotPart)
end

function BaseIncomeService.StopAllForBase(baseModel: Model)
	for slotPart, state in pairs(activeIncomeLoops) do
		if state.BaseModel == baseModel or slotPart:IsDescendantOf(baseModel) then
			BaseIncomeService.StopIncome(slotPart)
		end
	end

	for slotPart, _ in pairs(pendingBySlot) do
		if slotPart:IsDescendantOf(baseModel) then
			pendingBySlot[slotPart] = nil
			BaseIncomeService.UpdateSlotAmountUI(slotPart)
		end
	end
end

local function initializeAllSlotUI(baseService)
	if not baseService then
		return
	end
	for _, baseModel in ipairs(baseService.GetAllBases()) do
		local slotsFolder = resolveSlotsFolder(baseModel)
		if slotsFolder and slotsFolder:IsA("Folder") then
			for _, candidate in ipairs(slotsFolder:GetDescendants()) do
				if isSlotPart(candidate) then
					BaseIncomeService.UpdateSlotAmountUI(candidate :: BasePart)
				end
			end
		end
	end
end

function BaseIncomeService.Init(baseService)
	BaseService = baseService
	initializeAllSlotUI(baseService)
end

function BaseIncomeService.SetDataService(dataService)
	DataService = dataService
end

return BaseIncomeService
