local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CompactNumberFormatter = require(ReplicatedStorage.NPCSystem.Shared.CompactNumberFormatter)

local WeaponShopFormatter = {}

function WeaponShopFormatter.FormatPrice(value)
	local n = tonumber(value) or 0
	if n < 0 then
		n = 0
	end
	return CompactNumberFormatter.FormatCurrency(tostring(math.floor(n + 0.5)))
end

function WeaponShopFormatter.FormatStock(stock)
	local amount = math.max(0, math.floor((tonumber(stock) or 0) + 0.5))
	if amount <= 0 then
		return "OUT OF STOCK"
	end
	return ("Stock: %d"):format(amount)
end

function WeaponShopFormatter.FormatAppearanceChance(chancePercent)
	local chance = math.clamp(tonumber(chancePercent) or 100, 0, 100)
	local text = string.format("%.3f", chance)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return ("%s%%"):format(text)
end

return WeaponShopFormatter
