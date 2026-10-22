local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponShopRegistry = require(ReplicatedStorage.WeaponShop.Config.WeaponShopRegistry)

local GlobalStockRotationService = {}
GlobalStockRotationService.__index = GlobalStockRotationService

local function getUnixNow()
	return DateTime.now().UnixTimestamp
end

local function computeCycleId(config, unixTime)
	local elapsed = math.max(0, unixTime - config.CycleEpochUnix)
	return math.floor(elapsed / config.CycleDurationSeconds)
end

local function hashString(value)
	local hash = 2166136261
	for i = 1, #value do
		hash = bit32.bxor(hash, string.byte(value, i))
		hash = (hash * 16777619) % 4294967296
	end
	return hash
end

local function nextRandom(seed)
	seed = bit32.bxor(seed, bit32.lshift(seed, 13))
	seed = bit32.bxor(seed, bit32.rshift(seed, 17))
	seed = bit32.bxor(seed, bit32.lshift(seed, 5))
	return seed % 4294967296
end

local function rollStockForWeapon(config, cycleId, weaponId, minStock, maxStock, appearanceChancePercent)
	local clampedChance = math.clamp(tonumber(appearanceChancePercent) or 100, 0, 100)
	local availabilitySeed = (cycleId * 1103515245 + config.StockRollSalt + hashString(weaponId .. "_appear")) % 4294967296
	availabilitySeed = nextRandom(availabilitySeed)
	local rollBasisPoints = availabilitySeed % 10000
	local chanceBasisPoints = clampedChance * 100
	if rollBasisPoints >= chanceBasisPoints then
		return 0
	end
	if maxStock <= minStock then
		return minStock
	end
	local seed = (cycleId * 1103515245 + config.StockRollSalt + hashString(weaponId .. "_amount")) % 4294967296
	seed = nextRandom(seed)
	local range = maxStock - minStock + 1
	return minStock + (seed % range)
end

function GlobalStockRotationService.new()
	local self = setmetatable({}, GlobalStockRotationService)
	self._config = WeaponShopRegistry.GetConfig()
	return self
end

function GlobalStockRotationService:GetCurrentCycleInfo(unixTime)
	local now = unixTime or getUnixNow()
	local cycleId = computeCycleId(self._config, now)
	local cycleStart = self._config.CycleEpochUnix + (cycleId * self._config.CycleDurationSeconds)
	local nextResetUnix = cycleStart + self._config.CycleDurationSeconds
	local initialStockByWeapon = {}
	for _, weapon in ipairs(WeaponShopRegistry.GetOrderedWeapons()) do
		initialStockByWeapon[weapon.Id] = rollStockForWeapon(self._config, cycleId, weapon.Id, weapon.StockMin, weapon.StockMax, weapon.StockAppearanceChancePercent)
	end
	return {
		CycleId = cycleId,
		CycleStartUnix = cycleStart,
		NextResetUnix = nextResetUnix,
		InitialStockByWeapon = initialStockByWeapon,
	}
end

return GlobalStockRotationService
