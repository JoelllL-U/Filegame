local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WeaponShopRegistry = require(ReplicatedStorage.WeaponShop.Config.WeaponShopRegistry)
local DataService = require(ServerScriptService.NPCSystem.Services.DataService)

local WeaponPurchaseService = {}
local config = WeaponShopRegistry.GetConfig()

local function debugWarn(message)
	if config.EnableDebugWarnings then
		warn(message)
	end
end
WeaponPurchaseService.__index = WeaponPurchaseService

function WeaponPurchaseService.new(stockStateService, ownershipService, equipService, remotes)
	local self = setmetatable({}, WeaponPurchaseService)
	self._stockStateService = stockStateService
	self._ownershipService = ownershipService
	self._equipService = equipService
	self._remotes = remotes
	self._purchaseLockByPlayer = {}
	self._stateBuilder = nil
	return self
end

function WeaponPurchaseService:SetStateBuilder(stateBuilder)
	self._stateBuilder = stateBuilder
end

function WeaponPurchaseService:_withPlayerLock(player, callback)
	if self._purchaseLockByPlayer[player] then
		return false, "BUSY"
	end
	self._purchaseLockByPlayer[player] = true
	local ok, resultA, resultB = pcall(callback)
	self._purchaseLockByPlayer[player] = nil
	if not ok then
		debugWarn(("[WeaponPurchaseService] purchase callback failed for %s: %s"):format(player.Name, tostring(resultA)))
		return false, "INTERNAL_ERROR"
	end
	return resultA, resultB
end

function WeaponPurchaseService:_fireResult(player, success, code, weaponId)
	self._remotes.PurchaseResult:FireClient(player, {
		Success = success,
		Code = code,
		WeaponId = weaponId,
	})
end

function WeaponPurchaseService:_broadcastState()
	if not self._stateBuilder then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		self._remotes.ShopStateUpdated:FireClient(player, self._stateBuilder(player))
	end
end

function WeaponPurchaseService:HandleSoftPurchase(player, weaponId)
	local success, reason = self:_withPlayerLock(player, function()
		local weapon = WeaponShopRegistry.GetWeaponById(weaponId)
		if not weapon then
			return false, "INVALID_WEAPON"
		end
		if self._ownershipService:OwnsWeapon(player, weapon.Id) then
			return false, "ALREADY_OWNED"
		end
		local stock = self._stockStateService:GetRemainingStock(weapon.Id)
		if stock <= 0 then
			return false, "OUT_OF_STOCK"
		end
		if not DataService.TrySpendMoney(player, weapon.Price) then
			return false, "NOT_ENOUGH_MONEY"
		end
		local consumed = self._stockStateService:TryConsumeStock(weapon.Id, 1)
		if not consumed then
			DataService.AddMoney(player, weapon.Price)
			return false, "OUT_OF_STOCK"
		end
		local granted, grantReason = self._ownershipService:GrantOwnership(player, weapon.Id)
		if not granted then
			DataService.AddMoney(player, weapon.Price)
			self._stockStateService:RefreshIfNeeded()
			return false, grantReason
		end
		return true, "PURCHASED"
	end)

	self:_fireResult(player, success, reason or "UNKNOWN", weaponId)
	if success then
		self:_broadcastState()
	end
end

function WeaponPurchaseService:HandleEquipRequest(player, weaponId)
	local weapon = WeaponShopRegistry.GetWeaponById(weaponId)
	if not weapon then
		self:_fireResult(player, false, "INVALID_WEAPON", weaponId)
		return
	end
	local equipped, code = self._equipService:EquipWeapon(player, weapon)
	self:_fireResult(player, equipped, code, weapon.Id)
	if equipped then
		self:_broadcastState()
	end
end

function WeaponPurchaseService:HandleRobuxPrompt(player, weaponId)
	local weapon = WeaponShopRegistry.GetWeaponById(weaponId)
	if not weapon then
		self:_fireResult(player, false, "INVALID_WEAPON", weaponId)
		return
	end
	if self._ownershipService:OwnsWeapon(player, weapon.Id) then
		self:_fireResult(player, false, "ALREADY_OWNED", weaponId)
		return
	end
	if weapon.RobuxProductId <= 0 then
		self:_fireResult(player, false, "ROBux_PRODUCT_NOT_CONFIGURED", weaponId)
		return
	end
	MarketplaceService:PromptProductPurchase(player, weapon.RobuxProductId)
	self:_fireResult(player, true, "ROBux_PROMPTED", weaponId)
end

return WeaponPurchaseService
