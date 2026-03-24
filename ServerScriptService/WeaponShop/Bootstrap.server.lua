local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponShopRegistry = require(ReplicatedStorage.WeaponShop.Config.WeaponShopRegistry)
local GlobalStockRotationService = require(script.Parent.Services.GlobalStockRotationService)
local ServerStockStateService = require(script.Parent.Services.ServerStockStateService)
local WeaponShopRemotes = require(script.Parent.Services.WeaponShopRemotes)
local WeaponOwnershipService = require(script.Parent.Services.WeaponOwnershipService)
local WeaponEquipService = require(script.Parent.Services.WeaponEquipService)
local WeaponPurchaseService = require(script.Parent.Services.WeaponPurchaseService)

local remotes = WeaponShopRemotes.Create()
local config = WeaponShopRegistry.GetConfig()

local function buildWeaponCatalog()
	local catalog = {}
	for _, weapon in ipairs(WeaponShopRegistry.GetOrderedWeapons()) do
		local rarity = WeaponShopRegistry.GetRarity(weapon.RarityId)
		table.insert(catalog, {
			Id = weapon.Id,
			DisplayName = weapon.DisplayName,
			Price = weapon.Price,
			Icon = weapon.Icon,
			RarityId = weapon.RarityId,
			RarityName = rarity and rarity.DisplayName or weapon.RarityId,
			RarityColor = rarity and rarity.Color or Color3.fromRGB(255, 255, 255),
			StockAppearanceChancePercent = weapon.StockAppearanceChancePercent,
			RobuxProductId = weapon.RobuxProductId,
		})
	end
	return catalog
end

local weaponCatalog = buildWeaponCatalog()
local globalStockRotationService = GlobalStockRotationService.new()
local stockStateService = ServerStockStateService.new(globalStockRotationService)

local function onOwnershipChanged(_player)
	-- set later once purchase service exists
end

local ownershipService = WeaponOwnershipService.new(onOwnershipChanged)
local equipService = WeaponEquipService.new(config, ownershipService)
local purchaseService = WeaponPurchaseService.new(stockStateService, ownershipService, equipService, remotes)

local function buildStateForPlayer(player)
	local stockSnapshot = stockStateService:GetSnapshot()
	local ownedMap = ownershipService:GetOwnedMap(player)
	local equippedWeaponId = ownershipService:GetEquippedWeaponId(player)
	local weaponStatesById = {}
	local equippedWeaponIds = {}
	for _, weapon in ipairs(WeaponShopRegistry.GetOrderedWeapons()) do
		local buttonState = equipService:BuildWeaponButtonState(player, weapon)
		weaponStatesById[weapon.Id] = buttonState
		if buttonState.Equipped then
			equippedWeaponIds[weapon.Id] = true
		end
	end
	return {
		CycleId = stockSnapshot.CycleId,
		NextResetUnix = stockSnapshot.NextResetUnix,
		StockByWeapon = stockSnapshot.StockByWeapon,
		Weapons = weaponCatalog,
		OwnedWeapons = ownedMap,
		EquippedWeaponId = equippedWeaponId,
		EquippedWeaponIds = equippedWeaponIds,
		WeaponStatesById = weaponStatesById,
	}
end

purchaseService:SetStateBuilder(buildStateForPlayer)

onOwnershipChanged = function(player)
	equipService:ReequipSelectedWeapon(player, WeaponShopRegistry)
	remotes.ShopStateUpdated:FireClient(player, buildStateForPlayer(player))
end

ownershipService:SetOwnershipChangedCallback(onOwnershipChanged)

remotes.RequestShopState.OnServerInvoke = function(player)
	return buildStateForPlayer(player)
end

remotes.PurchaseWeapon.OnServerEvent:Connect(function(player, weaponId)
	if typeof(weaponId) ~= "string" then
		return
	end
	purchaseService:HandleSoftPurchase(player, weaponId)
end)

remotes.RequestEquipWeapon.OnServerEvent:Connect(function(player, weaponId)
	if typeof(weaponId) ~= "string" then
		return
	end
	purchaseService:HandleEquipRequest(player, weaponId)
end)

remotes.RequestRobuxPurchase.OnServerEvent:Connect(function(player, weaponId)
	if typeof(weaponId) ~= "string" then
		return
	end
	purchaseService:HandleRobuxPrompt(player, weaponId)
end)

stockStateService:RegisterCycleChangedCallback(function()
	for _, player in ipairs(Players:GetPlayers()) do
		remotes.ShopStateUpdated:FireClient(player, buildStateForPlayer(player))
	end
end)

ownershipService:Init()
equipService:Init(WeaponShopRegistry)

for _, player in ipairs(Players:GetPlayers()) do
	remotes.ShopStateUpdated:FireClient(player, buildStateForPlayer(player))
end

task.spawn(function()
	while true do
		task.wait(config.StockRefreshPollSeconds)
		if stockStateService:RefreshIfNeeded() then
			for _, player in ipairs(Players:GetPlayers()) do
				remotes.ShopStateUpdated:FireClient(player, buildStateForPlayer(player))
			end
		end
	end
end)
