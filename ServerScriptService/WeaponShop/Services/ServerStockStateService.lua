local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponShopRegistry = require(ReplicatedStorage.WeaponShop.Config.WeaponShopRegistry)

local ServerStockStateService = {}
ServerStockStateService.__index = ServerStockStateService

function ServerStockStateService.new(globalStockRotationService)
	local self = setmetatable({}, ServerStockStateService)
	self._globalStockRotationService = globalStockRotationService
	self._currentCycleId = nil
	self._nextResetUnix = 0
	self._remainingByWeapon = {}
	self._onCycleChangedCallbacks = {}
	self:RefreshIfNeeded()
	return self
end

function ServerStockStateService:RegisterCycleChangedCallback(callback)
	table.insert(self._onCycleChangedCallbacks, callback)
end

function ServerStockStateService:_applyCycle(cycleInfo)
	self._currentCycleId = cycleInfo.CycleId
	self._nextResetUnix = cycleInfo.NextResetUnix
	self._remainingByWeapon = {}
	for weaponId, amount in pairs(cycleInfo.InitialStockByWeapon) do
		self._remainingByWeapon[weaponId] = amount
	end
	for _, callback in ipairs(self._onCycleChangedCallbacks) do
		callback(cycleInfo)
	end
end

function ServerStockStateService:RefreshIfNeeded()
	local cycleInfo = self._globalStockRotationService:GetCurrentCycleInfo()
	if self._currentCycleId == cycleInfo.CycleId then
		self._nextResetUnix = cycleInfo.NextResetUnix
		return false
	end
	self:_applyCycle(cycleInfo)
	return true
end

function ServerStockStateService:GetSnapshot()
	self:RefreshIfNeeded()
	local stockByWeapon = {}
	for _, weapon in ipairs(WeaponShopRegistry.GetOrderedWeapons()) do
		stockByWeapon[weapon.Id] = math.max(0, self._remainingByWeapon[weapon.Id] or 0)
	end
	return {
		CycleId = self._currentCycleId,
		NextResetUnix = self._nextResetUnix,
		StockByWeapon = stockByWeapon,
	}
end

function ServerStockStateService:GetRemainingStock(weaponId)
	self:RefreshIfNeeded()
	return math.max(0, self._remainingByWeapon[weaponId] or 0)
end

function ServerStockStateService:TryConsumeStock(weaponId, amount)
	self:RefreshIfNeeded()
	local consume = math.max(1, math.floor((tonumber(amount) or 1) + 0.5))
	local current = self:GetRemainingStock(weaponId)
	if current < consume then
		return false, current
	end
	self._remainingByWeapon[weaponId] = current - consume
	return true, self._remainingByWeapon[weaponId]
end

return ServerStockStateService
