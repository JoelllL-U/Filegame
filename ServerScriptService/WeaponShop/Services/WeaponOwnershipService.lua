local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponShopRegistry = require(ReplicatedStorage.WeaponShop.Config.WeaponShopRegistry)

local WeaponOwnershipService = {}

local config = WeaponShopRegistry.GetConfig()
local function debugWarn(message)
	if config.EnableDebugWarnings then
		warn(message)
	end
end
WeaponOwnershipService.__index = WeaponOwnershipService

type OwnershipData = {
	OwnedWeapons: { [string]: boolean },
	EquippedWeaponId: string?,
	ProcessedPurchases: { [string]: boolean },
}

local function isPrimaryLoadoutWeapon(weaponId: string): boolean
	local weapon = WeaponShopRegistry.GetWeaponById(weaponId)
	return weapon ~= nil and weapon.LoadoutSlot ~= "Extra" and weapon.CanCoexistWithEquippedWeapon ~= true
end

local function sanitizeOwnershipData(raw)
	local data: OwnershipData = {
		OwnedWeapons = {},
		EquippedWeaponId = nil,
		ProcessedPurchases = {},
	}
	if typeof(raw) ~= "table" then
		return data
	end
	if typeof(raw.OwnedWeapons) == "table" then
		for weaponId, value in pairs(raw.OwnedWeapons) do
			if value and WeaponShopRegistry.GetWeaponById(weaponId) then
				data.OwnedWeapons[weaponId] = true
			end
		end
	end
	if typeof(raw.EquippedWeaponId) == "string" and data.OwnedWeapons[raw.EquippedWeaponId] and isPrimaryLoadoutWeapon(raw.EquippedWeaponId) then
		data.EquippedWeaponId = raw.EquippedWeaponId
	end
	if typeof(raw.ProcessedPurchases) == "table" then
		for purchaseKey, processed in pairs(raw.ProcessedPurchases) do
			if processed then
				data.ProcessedPurchases[tostring(purchaseKey)] = true
			end
		end
	end
	return data
end

local function cloneOwnershipData(data: OwnershipData): OwnershipData
	local clone: OwnershipData = {
		OwnedWeapons = {},
		EquippedWeaponId = data.EquippedWeaponId,
		ProcessedPurchases = {},
	}
	for weaponId in pairs(data.OwnedWeapons) do
		clone.OwnedWeapons[weaponId] = true
	end
	for purchaseKey in pairs(data.ProcessedPurchases) do
		clone.ProcessedPurchases[purchaseKey] = true
	end
	if clone.EquippedWeaponId and not clone.OwnedWeapons[clone.EquippedWeaponId] then
		clone.EquippedWeaponId = nil
	end
	return clone
end

function WeaponOwnershipService.new(onOwnershipChanged)
	local self = setmetatable({}, WeaponOwnershipService)
	self._config = WeaponShopRegistry.GetConfig()
	self._dataStore = DataStoreService:GetDataStore(self._config.OwnershipDataStoreName)
	self._sessionByPlayer = {}
	self._onOwnershipChanged = onOwnershipChanged
	return self
end

function WeaponOwnershipService:SetOwnershipChangedCallback(callback)
	self._onOwnershipChanged = callback
end

function WeaponOwnershipService:_getKey(player)
	return self._config.OwnershipDataKeyPrefix .. tostring(player.UserId)
end

function WeaponOwnershipService:_retryDelay(attempt)
	return self._config.InitialBackoffSeconds * (2 ^ (attempt - 1))
end

function WeaponOwnershipService:_loadFromStore(player)
	local key = self:_getKey(player)
	for attempt = 1, self._config.MaxSaveRetries do
		local success, result = pcall(function()
			return self._dataStore:GetAsync(key)
		end)
		if success then
			return true, sanitizeOwnershipData(result)
		end
		debugWarn(("[WeaponOwnershipService] GetAsync failed for %s attempt %d/%d: %s"):format(player.Name, attempt, self._config.MaxSaveRetries, tostring(result)))
		if attempt < self._config.MaxSaveRetries then
			task.wait(self:_retryDelay(attempt))
		end
	end
	return false, sanitizeOwnershipData(nil)
end

function WeaponOwnershipService:_saveToStore(player, data: OwnershipData)
	local key = self:_getKey(player)
	for attempt = 1, self._config.MaxSaveRetries do
		local success, err = pcall(function()
			self._dataStore:UpdateAsync(key, function(existing)
				local old = sanitizeOwnershipData(existing)
				old.OwnedWeapons = cloneOwnershipData(data).OwnedWeapons
				old.EquippedWeaponId = data.EquippedWeaponId
				old.ProcessedPurchases = cloneOwnershipData(data).ProcessedPurchases
				return old
			end)
		end)
		if success then
			return true
		end
		debugWarn(("[WeaponOwnershipService] UpdateAsync failed for %s attempt %d/%d: %s"):format(player.Name, attempt, self._config.MaxSaveRetries, tostring(err)))
		if attempt < self._config.MaxSaveRetries then
			task.wait(self:_retryDelay(attempt))
		end
	end
	return false
end

function WeaponOwnershipService:_markDirtyAndSchedule(player)
	local session = self._sessionByPlayer[player]
	if not session then
		return
	end
	session.Dirty = true
	if session.SaveScheduled then
		return
	end
	session.SaveScheduled = true
	task.delay(self._config.SaveDebounceSeconds, function()
		local latest = self._sessionByPlayer[player]
		if not latest then
			return
		end
		latest.SaveScheduled = false
		if not latest.Dirty or not latest.CanPersist then
			return
		end
		if self:_saveToStore(player, latest.Data) then
			latest.Dirty = false
		end
	end)
end

function WeaponOwnershipService:Init()
	for _, player in ipairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:SaveNow(player)
		self._sessionByPlayer[player] = nil
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:_processReceipt(receiptInfo)
	end

	game:BindToClose(function()
		local deadline = os.clock() + self._config.ShutdownSaveTimeoutSeconds
		for _, player in ipairs(Players:GetPlayers()) do
			self:SaveNow(player)
		end
		while os.clock() < deadline do
			local pending = false
			for _, session in pairs(self._sessionByPlayer) do
				if session.SaveScheduled then
					pending = true
					break
				end
			end
			if not pending then
				break
			end
			task.wait(0.1)
		end
	end)
end

function WeaponOwnershipService:OnPlayerAdded(player)
	local loaded, data = self:_loadFromStore(player)
	self._sessionByPlayer[player] = {
		Data = data,
		Dirty = false,
		SaveScheduled = false,
		CanPersist = loaded,
	}
	if self._onOwnershipChanged then
		self._onOwnershipChanged(player)
	end
end

function WeaponOwnershipService:SaveNow(player)
	local session = self._sessionByPlayer[player]
	if not session or not session.CanPersist then
		return false
	end
	if self:_saveToStore(player, session.Data) then
		session.Dirty = false
		return true
	end
	return false
end

function WeaponOwnershipService:GetOwnedMap(player)
	local session = self._sessionByPlayer[player]
	if not session then
		return {}
	end
	return cloneOwnershipData(session.Data).OwnedWeapons
end

function WeaponOwnershipService:OwnsWeapon(player, weaponId)
	local session = self._sessionByPlayer[player]
	return session ~= nil and session.Data.OwnedWeapons[weaponId] == true
end

function WeaponOwnershipService:GrantOwnership(player, weaponId)
	local weapon = WeaponShopRegistry.GetWeaponById(weaponId)
	if not weapon then
		return false, "INVALID_WEAPON"
	end
	local session = self._sessionByPlayer[player]
	if not session then
		return false, "DATA_NOT_READY"
	end
	if session.Data.OwnedWeapons[weaponId] then
		return false, "ALREADY_OWNED"
	end
	session.Data.OwnedWeapons[weaponId] = true
	if not session.Data.EquippedWeaponId and isPrimaryLoadoutWeapon(weaponId) then
		session.Data.EquippedWeaponId = weaponId
	end
	self:_markDirtyAndSchedule(player)
	if self._onOwnershipChanged then
		self._onOwnershipChanged(player)
	end
	return true, "OWNERSHIP_GRANTED"
end

function WeaponOwnershipService:GetEquippedWeaponId(player)
	local session = self._sessionByPlayer[player]
	if not session then
		return nil
	end
	return session.Data.EquippedWeaponId
end

function WeaponOwnershipService:SetEquippedWeaponId(player, weaponId)
	local session = self._sessionByPlayer[player]
	if not session then
		return false
	end
	if weaponId ~= nil and not session.Data.OwnedWeapons[weaponId] then
		return false
	end
	if weaponId ~= nil and not isPrimaryLoadoutWeapon(weaponId) then
		return false
	end
	if session.Data.EquippedWeaponId == weaponId then
		return true
	end
	session.Data.EquippedWeaponId = weaponId
	self:_markDirtyAndSchedule(player)
	if self._onOwnershipChanged then
		self._onOwnershipChanged(player)
	end
	return true
end

function WeaponOwnershipService:_processReceipt(receiptInfo)
	local weapon = WeaponShopRegistry.GetWeaponByProductId(receiptInfo.ProductId)
	if not weapon then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local session = self._sessionByPlayer[player]
	if not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseKey = tostring(receiptInfo.PurchaseId)
	if session.Data.ProcessedPurchases[purchaseKey] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	session.Data.ProcessedPurchases[purchaseKey] = true
	if not session.Data.OwnedWeapons[weapon.Id] then
		session.Data.OwnedWeapons[weapon.Id] = true
		if isPrimaryLoadoutWeapon(weapon.Id) then
			session.Data.EquippedWeaponId = weapon.Id
		end
		if self._onOwnershipChanged then
			self._onOwnershipChanged(player)
		end
	end
	self:_markDirtyAndSchedule(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return WeaponOwnershipService
