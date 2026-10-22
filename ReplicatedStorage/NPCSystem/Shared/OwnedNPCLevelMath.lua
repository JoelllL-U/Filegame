local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OwnedNPCLevelConfig = require(ReplicatedStorage.NPCSystem.Config.OwnedNPCLevelConfig)
local MutationRegistry = require(ReplicatedStorage.NPCSystem.Config.MutationRegistry)
local CompactNumberFormatter = require(ReplicatedStorage.NPCSystem.Shared.CompactNumberFormatter)

local OwnedNPCLevelMath = {}

local function sanitizeLevel(level: number?): number
	if typeof(level) ~= "number" then
		return OwnedNPCLevelConfig.DefaultLevel
	end
	local roundedLevel = math.floor(level + 0.5)
	return math.clamp(roundedLevel, OwnedNPCLevelConfig.DefaultLevel, OwnedNPCLevelConfig.MaxLevel)
end

local function roundPositive(value: number, minValue: number): number
	return math.max(minValue, math.floor(value + 0.5))
end

function OwnedNPCLevelMath.GetLevel(level: number?): number
	return sanitizeLevel(level)
end

function OwnedNPCLevelMath.GetMaxLevel(): number
	return OwnedNPCLevelConfig.MaxLevel
end

function OwnedNPCLevelMath.IsMaxLevel(level: number?): boolean
	return sanitizeLevel(level) >= OwnedNPCLevelConfig.MaxLevel
end

function OwnedNPCLevelMath.GetNextLevel(level: number?): number
	local currentLevel = sanitizeLevel(level)
	if currentLevel >= OwnedNPCLevelConfig.MaxLevel then
		return OwnedNPCLevelConfig.MaxLevel
	end
	return currentLevel + 1
end

function OwnedNPCLevelMath.GetLevelText(level: number?): string
	return ("Lv.%d"):format(sanitizeLevel(level))
end

function OwnedNPCLevelMath.GetLevelChangeText(level: number?): string
	local currentLevel = sanitizeLevel(level)
	if OwnedNPCLevelMath.IsMaxLevel(currentLevel) then
		return OwnedNPCLevelConfig.MaxLevelChangeTextTemplate:format(currentLevel)
	end
	return ("Level %d > Level %d"):format(currentLevel, OwnedNPCLevelMath.GetNextLevel(currentLevel))
end

function OwnedNPCLevelMath.GetIncomeWithMutation(baseHealth: number, baseIncome: number, mutationId: string?): number
	local _, mutatedIncome = MutationRegistry.ApplyMultipliers(baseHealth, baseIncome, mutationId)
	return mutatedIncome
end

function OwnedNPCLevelMath.GetEffectiveIncome(baseHealth: number, baseIncome: number, mutationId: string?, level: number?): number
	local currentLevel = sanitizeLevel(level)
	local mutatedIncome = OwnedNPCLevelMath.GetIncomeWithMutation(baseHealth, baseIncome, mutationId)
	local value = mutatedIncome * (OwnedNPCLevelConfig.LevelIncomeMultiplier ^ (currentLevel - 1))
	return roundPositive(value, 0)
end

function OwnedNPCLevelMath.GetUpgradeCost(baseUpgradeCost: number, level: number?): number
	local currentLevel = sanitizeLevel(level)
	local baseCost = math.max(OwnedNPCLevelConfig.MinimumUpgradeCost, math.floor((baseUpgradeCost or 0) + 0.5))
	local value = baseCost * (OwnedNPCLevelConfig.UpgradeCostMultiplier ^ (currentLevel - 1))
	return roundPositive(value, OwnedNPCLevelConfig.MinimumUpgradeCost)
end

function OwnedNPCLevelMath.FormatCurrency(amount: number): string
	return CompactNumberFormatter.FormatCurrency(amount, OwnedNPCLevelConfig.CurrencyPrefix)
end

return OwnedNPCLevelMath
