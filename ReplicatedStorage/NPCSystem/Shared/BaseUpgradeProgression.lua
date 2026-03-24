local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseUpgradeConfig = require(ReplicatedStorage.NPCSystem.Config.BaseUpgradeConfig)

local BaseUpgradeProgression = {}

local unlockSequenceCache = nil

export type UpgradeState = {
	UpgradeCount: number,
	MaxUpgradeCount: number,
	RequiredFloors: { [string]: boolean },
	UnlockedSlotNames: { [string]: boolean },
	UnlockedSlotsByFloor: { [string]: number },
	UnlockedSlotCount: number,
}

local function buildUnlockSequence(): { { FloorName: string, SlotName: string } }
	if unlockSequenceCache then
		return unlockSequenceCache
	end
	local sequence = {}
	for _, floorEntry in ipairs(BaseUpgradeConfig.FloorProgression) do
		for slotNumber = floorEntry.StartSlot, floorEntry.EndSlot do
			table.insert(sequence, {
				FloorName = floorEntry.FloorName,
				SlotName = ("Slot%d"):format(slotNumber),
			})
		end
	end
	unlockSequenceCache = sequence
	return sequence
end

function BaseUpgradeProgression.GetMaxUpgradeCount(): number
	return #buildUnlockSequence()
end

function BaseUpgradeProgression.ClampUpgradeCount(upgradeCount: number?): number
	if typeof(upgradeCount) ~= "number" then
		return 0
	end
	return math.clamp(math.floor(upgradeCount + 0.5), 0, BaseUpgradeProgression.GetMaxUpgradeCount())
end

function BaseUpgradeProgression.GetUpgradeState(upgradeCount: number?): UpgradeState
	local clamped = BaseUpgradeProgression.ClampUpgradeCount(upgradeCount)
	local requiredFloors = {
		Floor1 = true,
	}
	local unlockedSlotNames = {}
	local unlockedSlotsByFloor = {
		Floor1 = BaseUpgradeConfig.DefaultUnlockedSlots,
	}
	for slotNumber = 1, BaseUpgradeConfig.DefaultUnlockedSlots do
		unlockedSlotNames[("Slot%d"):format(slotNumber)] = true
	end

	local sequence = buildUnlockSequence()
	for index = 1, clamped do
		local entry = sequence[index]
		if entry then
			requiredFloors[entry.FloorName] = true
			unlockedSlotNames[entry.SlotName] = true
			unlockedSlotsByFloor[entry.FloorName] = (unlockedSlotsByFloor[entry.FloorName] or 0) + 1
		end
	end

	return {
		UpgradeCount = clamped,
		MaxUpgradeCount = BaseUpgradeProgression.GetMaxUpgradeCount(),
		RequiredFloors = requiredFloors,
		UnlockedSlotNames = unlockedSlotNames,
		UnlockedSlotsByFloor = unlockedSlotsByFloor,
		UnlockedSlotCount = BaseUpgradeConfig.DefaultUnlockedSlots + clamped,
	}
end

function BaseUpgradeProgression.GetCurrentCost(upgradeCount: number?): number?
	local state = BaseUpgradeProgression.GetUpgradeState(upgradeCount)
	return BaseUpgradeConfig.UpgradeCosts[state.UpgradeCount + 1]
end

function BaseUpgradeProgression.IsMaxed(upgradeCount: number?): boolean
	local state = BaseUpgradeProgression.GetUpgradeState(upgradeCount)
	return state.UpgradeCount >= state.MaxUpgradeCount
end

function BaseUpgradeProgression.GetProgressText(upgradeCount: number?): string
	local state = BaseUpgradeProgression.GetUpgradeState(upgradeCount)
	return BaseUpgradeConfig.ProgressTextTemplate:format(state.UpgradeCount, state.MaxUpgradeCount)
end

function BaseUpgradeProgression.GetUnlockedSlotNames(upgradeCount: number?): { [string]: boolean }
	return BaseUpgradeProgression.GetUpgradeState(upgradeCount).UnlockedSlotNames
end

function BaseUpgradeProgression.GetRequiredFloors(upgradeCount: number?): { [string]: boolean }
	return BaseUpgradeProgression.GetUpgradeState(upgradeCount).RequiredFloors
end

return BaseUpgradeProgression
