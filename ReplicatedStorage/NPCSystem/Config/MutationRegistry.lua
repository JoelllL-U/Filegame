local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MutationConfig = require(ReplicatedStorage.NPCSystem.Config.MutationConfig)
local MutationDefinitions = require(ReplicatedStorage.NPCSystem.Config.MutationDefinitions)

local MutationRegistry = {}
local mutationRandom = Random.new()

local function getValidMutationPool(): { [number]: { [string]: any } }
	local pool = {}
	for mutationId, definition in pairs(MutationDefinitions) do
		if typeof(definition) == "table"
			and typeof(definition.Id) == "string"
			and definition.Id ~= ""
			and typeof(definition.DisplayName) == "string"
			and definition.DisplayName ~= ""
			and typeof(definition.Color) == "Color3"
			and typeof(definition.Weight) == "number"
			and definition.Weight > 0
			and typeof(definition.IncomeMultiplier) == "number"
			and definition.IncomeMultiplier > 0
			and typeof(definition.HealthMultiplier) == "number"
			and definition.HealthMultiplier > 0 then
			table.insert(pool, definition)
		else
			warn(("[MutationRegistry] Invalid mutation definition %s"):format(tostring(mutationId)))
		end
	end
	return pool
end

local function getLiteralDenominator(weight: number?): number
	local numericWeight = typeof(weight) == "number" and weight or 1
	return math.max(1, math.floor(numericWeight + 0.5))
end

local function rollLiteralOdds(weight: number?): boolean
	local denominator = getLiteralDenominator(weight)
	return mutationRandom:NextInteger(1, denominator) == 1
end

function MutationRegistry.GetDefinitions(): { [string]: any }
	return MutationDefinitions
end

function MutationRegistry.GetById(mutationId: string?)
	if typeof(mutationId) ~= "string" or mutationId == "" then
		return nil
	end
	return MutationDefinitions[mutationId]
end

function MutationRegistry.RollMutation(): { [string]: any }?
	if not MutationConfig.Enabled then
		return nil
	end

	local pool = getValidMutationPool()
	if #pool == 0 then
		return nil
	end

	local orderedPool = table.clone(pool)
	table.sort(orderedPool, function(left, right)
		return left.Weight > right.Weight
	end)

	for _, definition in ipairs(orderedPool) do
		if rollLiteralOdds(definition.Weight) then
			return definition
		end
	end

	if typeof(MutationConfig.NoneWeight) == "number" and MutationConfig.NoneWeight > 0 and rollLiteralOdds(MutationConfig.NoneWeight) then
		return nil
	end

	return nil
end

function MutationRegistry.ApplyMultipliers(baseHealth: number, baseIncome: number, mutationId: string?): (number, number)
	local mutation = MutationRegistry.GetById(mutationId)
	if not mutation then
		return math.max(1, math.floor(baseHealth + 0.5)), math.max(0, math.floor(baseIncome + 0.5))
	end

	local mutatedHealth = math.max(1, math.floor((baseHealth * mutation.HealthMultiplier) + 0.5))
	local mutatedIncome = math.max(0, math.floor((baseIncome * mutation.IncomeMultiplier) + 0.5))
	return mutatedHealth, mutatedIncome
end

return MutationRegistry
