local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponShopConfig = require(ReplicatedStorage.WeaponShop.Config.WeaponShopConfig)
local RarityConfig = require(ReplicatedStorage.WeaponShop.Config.RarityConfig)

local WeaponShopRegistry = {}

local function debugWarn(message)
	if WeaponShopConfig.EnableDebugWarnings then
		warn(message)
	end
end

local weaponsById = {}
local orderedWeapons = {}
local weaponsByProductId = {}

for index, definition in ipairs(WeaponShopConfig.Weapons) do
	if typeof(definition) ~= "table" then
		continue
	end
	if definition.Enabled == false then
		continue
	end
	if typeof(definition.Id) ~= "string" or definition.Id == "" then
		debugWarn(("[WeaponShopRegistry] Weapon at index %d missing Id"):format(index))
		continue
	end
	if weaponsById[definition.Id] then
		debugWarn(("[WeaponShopRegistry] Duplicate weapon Id %s"):format(definition.Id))
		continue
	end
	local rarity = RarityConfig[definition.RarityId]
	if not rarity then
		debugWarn(("[WeaponShopRegistry] Weapon %s missing rarity %s"):format(definition.Id, tostring(definition.RarityId)))
		continue
	end
	local normalized = {
		Id = definition.Id,
		SortOrder = typeof(definition.SortOrder) == "number" and definition.SortOrder or index,
		DisplayName = typeof(definition.DisplayName) == "string" and definition.DisplayName or definition.Id,
		ToolNameInReplicatedStorage = definition.ToolNameInReplicatedStorage,
		Price = math.max(0, math.floor((tonumber(definition.Price) or 0) + 0.5)),
		Icon = typeof(definition.Icon) == "string" and definition.Icon or "",
		RarityId = rarity.Id,
		StockMin = math.max(0, math.floor((tonumber(definition.StockMin) or 0) + 0.5)),
		StockMax = math.max(0, math.floor((tonumber(definition.StockMax) or 0) + 0.5)),
		StockAppearanceChancePercent = math.clamp(tonumber(definition.StockAppearanceChancePercent) or 100, 0, 100),
		RobuxProductId = math.max(0, math.floor((tonumber(definition.RobuxProductId) or 0) + 0.5)),
		LoadoutSlot = definition.LoadoutSlot == "Extra" and "Extra" or "Primary",
		Damage = math.max(0, tonumber(definition.Damage) or 0),
		AttackRange = math.max(0, tonumber(definition.AttackRange) or 0),
		AttackHitboxSize = typeof(definition.AttackHitboxSize) == "Vector3" and definition.AttackHitboxSize or nil,
		PlayerHitboxSize = typeof(definition.PlayerHitboxSize) == "Vector3" and definition.PlayerHitboxSize or (typeof(definition.AttackHitboxSize) == "Vector3" and definition.AttackHitboxSize or nil),
		CanDamagePlayers = definition.CanDamagePlayers == true,
		CanCoexistWithEquippedWeapon = definition.CanCoexistWithEquippedWeapon == true or definition.LoadoutSlot == "Extra",
		ContestDisarmEnabled = definition.ContestDisarmEnabled == true,
		KnockbackHorizontal = math.max(0, tonumber(definition.KnockbackHorizontal) or 0),
		KnockbackVertical = math.max(0, tonumber(definition.KnockbackVertical) or 0),
	}
	if normalized.StockMax < normalized.StockMin then
		normalized.StockMin, normalized.StockMax = normalized.StockMax, normalized.StockMin
	end
	weaponsById[normalized.Id] = normalized
	table.insert(orderedWeapons, normalized)
	if normalized.RobuxProductId > 0 then
		weaponsByProductId[normalized.RobuxProductId] = normalized
	end
end

table.sort(orderedWeapons, function(a, b)
	if a.SortOrder ~= b.SortOrder then
		return a.SortOrder < b.SortOrder
	end
	return a.Id < b.Id
end)

function WeaponShopRegistry.GetOrderedWeapons()
	return orderedWeapons
end

function WeaponShopRegistry.GetWeaponById(weaponId)
	return weaponsById[weaponId]
end

function WeaponShopRegistry.GetWeaponByProductId(productId)
	return weaponsByProductId[productId]
end

function WeaponShopRegistry.GetRarity(rarityId)
	return RarityConfig[rarityId]
end

function WeaponShopRegistry.GetConfig()
	return WeaponShopConfig
end

return WeaponShopRegistry
