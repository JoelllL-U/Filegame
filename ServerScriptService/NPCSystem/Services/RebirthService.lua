local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthConfig = require(ReplicatedStorage.NPCSystem.Config.RebirthConfig)
local CompactNumberFormatter = require(ReplicatedStorage.NPCSystem.Shared.CompactNumberFormatter)
local BigNumber = require(ReplicatedStorage.NPCSystem.Shared.BigNumber)

local RebirthService = {}
RebirthService.__index = RebirthService

local DataService = nil
local getStateFunction: RemoteFunction? = nil
local requestRebirthFunction: RemoteFunction? = nil
local stateChangedEvent: RemoteEvent? = nil

local function sanitizeTier(tier: { [string]: any }): { [string]: any }
	return {
		RequiredMoney = BigNumber.Sanitize(tier.RequiredMoney),
		Multiplier = math.max(0, tonumber(tier.Multiplier) or 1),
		RewardMoney = BigNumber.Sanitize(tier.RewardMoney),
	}
end

local function getTier(index: number): { [string]: any }?
	local tiers = RebirthConfig.Tiers or {}
	local entry = tiers[index]
	if typeof(entry) ~= "table" then
		return nil
	end
	return sanitizeTier(entry)
end

local function getCurrentState(player: Player): { [string]: any }
	local money = DataService and DataService.GetMoneyString and DataService.GetMoneyString(player) or "0"
	local rebirth = DataService and DataService.GetRebirthState and DataService.GetRebirthState(player) or { Index = 0, Multiplier = 1 }
	local completedIndex = math.max(0, math.floor(tonumber(rebirth.Index) or 0))
	local currentMultiplier = math.max(0, tonumber(rebirth.Multiplier) or 1)
	local nextTier = getTier(completedIndex + 1)

	if not nextTier then
		return {
			CurrentMoney = money,
			Progress = 1,
			CurrentRebirthIndex = completedIndex,
			CurrentMultiplier = currentMultiplier,
			NextTierIndex = nil,
			NextRequiredMoney = "0",
			NextRewardMoney = "0",
			NextMultiplier = currentMultiplier,
			IsMax = true,
			Display = {
				MoneyText = "$MAX",
				RewardText = "$0",
				MultiplierText = ("x%s"):format(tostring(currentMultiplier)),
			},
		}
	end

	local progress = 0
	if BigNumber.Compare(nextTier.RequiredMoney, "0") <= 0 then
		progress = 1
	else
		local currentDigits = BigNumber.Sanitize(money)
		local requiredDigits = BigNumber.Sanitize(nextTier.RequiredMoney)
		if BigNumber.Compare(currentDigits, requiredDigits) >= 0 then
			progress = 1
		else
			local currentNumber = tonumber(currentDigits)
			local requiredNumber = tonumber(requiredDigits)
			if currentNumber and requiredNumber and requiredNumber > 0 then
				progress = math.clamp(currentNumber / requiredNumber, 0, 1)
			end
		end
	end

	return {
		CurrentMoney = money,
		Progress = math.clamp(progress, RebirthConfig.ProgressBar.BackgroundMinScale or 0, RebirthConfig.ProgressBar.BackgroundMaxScale or 1),
		CurrentRebirthIndex = completedIndex,
		CurrentMultiplier = currentMultiplier,
		NextTierIndex = completedIndex + 1,
		NextRequiredMoney = nextTier.RequiredMoney,
		NextRewardMoney = nextTier.RewardMoney,
		NextMultiplier = nextTier.Multiplier,
		IsMax = false,
		Display = {
			MoneyText = ("%s/%s"):format(
				CompactNumberFormatter.FormatCurrency(money, "$"),
				CompactNumberFormatter.FormatCurrency(nextTier.RequiredMoney, "$")
			),
			RewardText = CompactNumberFormatter.FormatCurrency(nextTier.RewardMoney, "$"),
			MultiplierText = ("x%s"):format(tostring(nextTier.Multiplier)),
		},
	}
end

local function fireState(player: Player)
	if not stateChangedEvent then
		return
	end
	stateChangedEvent:FireClient(player, getCurrentState(player))
end

local function performRebirth(player: Player): { [string]: any }
	if not (DataService and DataService.IsLoaded and DataService.IsLoaded(player)) then
		return { Success = false, Reason = "NotLoaded", State = getCurrentState(player) }
	end

	local state = getCurrentState(player)
	if state.IsMax then
		return { Success = false, Reason = "MaxReached", State = state }
	end

	if BigNumber.Compare(state.CurrentMoney, state.NextRequiredMoney) < 0 then
		return { Success = false, Reason = "NotEnoughMoney", State = state }
	end

	if DataService.SetRebirthState then
		DataService.SetRebirthState(player, state.NextTierIndex, state.NextMultiplier)
	end
	if DataService.SetMoney then
		DataService.SetMoney(player, state.NextRewardMoney)
	end

	local latest = getCurrentState(player)
	fireState(player)
	return { Success = true, Reason = "OK", State = latest }
end

function RebirthService.Init(dataService)
	DataService = dataService

	local remotesFolder = ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Remotes")
	local existingGet = remotesFolder:FindFirstChild(RebirthConfig.Remotes.GetStateFunctionName)
	local existingRequest = remotesFolder:FindFirstChild(RebirthConfig.Remotes.RequestRebirthFunctionName)
	local existingChanged = remotesFolder:FindFirstChild(RebirthConfig.Remotes.StateChangedEventName)

	if existingGet and existingGet:IsA("RemoteFunction") then
		getStateFunction = existingGet
	elseif existingGet then
		existingGet:Destroy()
	end
	if not getStateFunction then
		getStateFunction = Instance.new("RemoteFunction")
		getStateFunction.Name = RebirthConfig.Remotes.GetStateFunctionName
		getStateFunction.Parent = remotesFolder
	end

	if existingRequest and existingRequest:IsA("RemoteFunction") then
		requestRebirthFunction = existingRequest
	elseif existingRequest then
		existingRequest:Destroy()
	end
	if not requestRebirthFunction then
		requestRebirthFunction = Instance.new("RemoteFunction")
		requestRebirthFunction.Name = RebirthConfig.Remotes.RequestRebirthFunctionName
		requestRebirthFunction.Parent = remotesFolder
	end

	if existingChanged and existingChanged:IsA("RemoteEvent") then
		stateChangedEvent = existingChanged
	elseif existingChanged then
		existingChanged:Destroy()
	end
	if not stateChangedEvent then
		stateChangedEvent = Instance.new("RemoteEvent")
		stateChangedEvent.Name = RebirthConfig.Remotes.StateChangedEventName
		stateChangedEvent.Parent = remotesFolder
	end

	getStateFunction.OnServerInvoke = function(player)
		return getCurrentState(player)
	end
	requestRebirthFunction.OnServerInvoke = function(player)
		return performRebirth(player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			fireState(player)
		end)
	end)
end

return RebirthService
