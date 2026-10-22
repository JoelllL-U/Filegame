local BigNumber = {}

local function stripLeadingZeros(digits: string): string
	digits = digits:gsub("^0+", "")
	if digits == "" then
		return "0"
	end
	return digits
end

function BigNumber.Sanitize(value: any): string
	if typeof(value) == "string" then
		local trimmed = value:match("^%s*(.-)%s*$") or "0"
		local negative = false
		if string.sub(trimmed, 1, 1) == "-" then
			negative = true
			trimmed = string.sub(trimmed, 2)
		end
		local digits = trimmed:gsub("[^0-9]", "")
		digits = stripLeadingZeros(digits)
		if negative then
			return "0"
		end
		return digits
	end
	if typeof(value) == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end
		if value <= 0 then
			return "0"
		end
		return stripLeadingZeros(string.format("%.0f", math.floor(value + 0.0000001)))
	end
	return "0"
end

function BigNumber.Compare(a: any, b: any): number
	local left = BigNumber.Sanitize(a)
	local right = BigNumber.Sanitize(b)
	if #left > #right then
		return 1
	elseif #left < #right then
		return -1
	end
	if left == right then
		return 0
	end
	return left > right and 1 or -1
end

function BigNumber.Add(a: any, b: any): string
	local left = BigNumber.Sanitize(a)
	local right = BigNumber.Sanitize(b)
	local i = #left
	local j = #right
	local carry = 0
	local out = table.create(math.max(i, j) + 1)
	while i > 0 or j > 0 or carry > 0 do
		local da = 0
		if i > 0 then
			da = string.byte(left, i) - 48
			i -= 1
		end
		local db = 0
		if j > 0 then
			db = string.byte(right, j) - 48
			j -= 1
		end
		local sum = da + db + carry
		carry = math.floor(sum / 10)
		table.insert(out, 1, string.char(48 + (sum % 10)))
	end
	return table.concat(out)
end

function BigNumber.Subtract(a: any, b: any): string
	local left = BigNumber.Sanitize(a)
	local right = BigNumber.Sanitize(b)
	if BigNumber.Compare(left, right) < 0 then
		return "0"
	end
	local i = #left
	local j = #right
	local borrow = 0
	local out = table.create(#left)
	while i > 0 do
		local da = (string.byte(left, i) - 48) - borrow
		i -= 1
		local db = 0
		if j > 0 then
			db = string.byte(right, j) - 48
			j -= 1
		end
		if da < db then
			da += 10
			borrow = 1
		else
			borrow = 0
		end
		table.insert(out, 1, string.char(48 + (da - db)))
	end
	return stripLeadingZeros(table.concat(out))
end

function BigNumber.MultiplySmall(a: any, multiplier: any): string
	local left = BigNumber.Sanitize(a)
	local m = math.max(0, math.floor(tonumber(multiplier) or 0))
	if m == 0 or left == "0" then
		return "0"
	end
	if m == 1 then
		return left
	end
	local i = #left
	local carry = 0
	local out = table.create(#left + 16)
	while i > 0 or carry > 0 do
		local da = 0
		if i > 0 then
			da = string.byte(left, i) - 48
			i -= 1
		end
		local product = da * m + carry
		carry = math.floor(product / 10)
		table.insert(out, 1, string.char(48 + (product % 10)))
	end
	return stripLeadingZeros(table.concat(out))
end

function BigNumber.ToDisplayNumber(value: any, cap: number): number
	local digits = BigNumber.Sanitize(value)
	local numeric = tonumber(digits)
	if numeric then
		return math.clamp(numeric, 0, cap)
	end
	return cap
end

return BigNumber
