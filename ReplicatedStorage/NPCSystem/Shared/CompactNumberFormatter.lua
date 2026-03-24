local CompactNumberFormatter = {}

local function sanitizeDigitString(value: any): (boolean, string, string)
	if typeof(value) == "string" then
		local trimmed = value:match("^%s*(.-)%s*$") or "0"
		local sign = ""
		if string.sub(trimmed, 1, 1) == "-" then
			sign = "-"
			trimmed = string.sub(trimmed, 2)
		end
		local digits = trimmed:gsub("[^0-9]", "")
		digits = digits:gsub("^0+", "")
		if digits == "" then
			return true, "", "0"
		end
		return true, sign, digits
	end
	return false, "", "0"
end

local SUFFIXES = {
	"", "k", "m", "b", "t",
	"qa", "qi", "sx", "sp", "oc", "no",
	"dc", "ud", "dd", "td", "qad", "qid", "sxd", "spd", "ocd", "nod",
	"vg", "uvg", "dvg", "tvg", "qavg", "qivg", "sxvg", "spvg", "ocvg", "novg",
	"tg", "utg", "dtg", "ttg", "qatg", "qitg", "sxtg", "sptg", "octg", "notg",
	"qag", "uqag", "dqag", "tqag", "qqag", "qiqag", "sxqag", "spqag", "ocqag", "noqag",
}

local function trimTrailingZeroes(numberText: string): string
	numberText = numberText:gsub("(%..-)0+$", "%1")
	numberText = numberText:gsub("%.$", "")
	return numberText
end

local function formatScientificFromDigits(sign: string, digits: string): string
	if digits == "0" then
		return "0"
	end
	local exponent = #digits - 1
	local head = string.sub(digits, 1, 1)
	local frac = string.sub(digits, 2, 3)
	if frac ~= "" then
		return sign .. trimTrailingZeroes(head .. "." .. frac) .. "e+" .. tostring(exponent)
	end
	return sign .. head .. "e+" .. tostring(exponent)
end

local function sanitizeNumber(value: any): number
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
end

function CompactNumberFormatter.GetSuffixes(): { string }
	return SUFFIXES
end

function CompactNumberFormatter.Format(value: any, decimals: number?): string
	local isDigitString, digitSign, digitString = sanitizeDigitString(value)
	if isDigitString then
		if digitString == "0" then
			return "0"
		end
		if #digitString <= 3 then
			return digitSign .. digitString
		end
		local suffixIndex = math.floor((#digitString - 1) / 3) + 1
		if suffixIndex < 1 then
			suffixIndex = 1
		elseif suffixIndex > #SUFFIXES then
			return formatScientificFromDigits(digitSign, digitString)
		end
		local groupDigits = #digitString - ((suffixIndex - 1) * 3)
		if groupDigits < 1 then
			groupDigits = 1
		end
		local head = string.sub(digitString, 1, groupDigits)
		local tail = string.sub(digitString, groupDigits + 1)
		local decimalPlaces = 0
		if typeof(decimals) == "number" then
			decimalPlaces = math.max(0, math.floor(decimals + 0.5))
		else
			if groupDigits == 1 then
				decimalPlaces = 2
			elseif groupDigits == 2 then
				decimalPlaces = 1
			else
				decimalPlaces = 0
			end
		end
		if decimalPlaces > 0 and #tail > 0 then
			local frac = string.sub(tail, 1, decimalPlaces)
			if #frac < decimalPlaces then
				frac = frac .. string.rep("0", decimalPlaces - #frac)
			end
			local body = trimTrailingZeroes(head .. "." .. frac)
			return digitSign .. body .. SUFFIXES[suffixIndex]
		end
		return digitSign .. head .. SUFFIXES[suffixIndex]
	end

	local numberValue = sanitizeNumber(value)
	local sign = ""
	if numberValue < 0 then
		sign = "-"
		numberValue = -numberValue
	end

	if numberValue < 1000 then
		return sign .. tostring(math.floor(numberValue + 0.5))
	end

	local exponent = math.floor(math.log10(numberValue))
	local suffixIndex = math.floor(exponent / 3) + 1
	if suffixIndex < 1 then
		suffixIndex = 1
	elseif suffixIndex > #SUFFIXES then
		local scientificText = trimTrailingZeroes(string.format("%.2e", numberValue):gsub("e%+0*", "e+"))
		return sign .. scientificText
	end

	local scaled = numberValue / (1000 ^ (suffixIndex - 1))
	local decimalPlaces = 0
	if typeof(decimals) == "number" then
		decimalPlaces = math.max(0, math.floor(decimals + 0.5))
	else
		if scaled < 10 then
			decimalPlaces = 2
		elseif scaled < 100 then
			decimalPlaces = 1
		else
			decimalPlaces = 0
		end
	end

	local formatString = "%0." .. tostring(decimalPlaces) .. "f"
	local scaledText = trimTrailingZeroes(string.format(formatString, scaled))
	return sign .. scaledText .. SUFFIXES[suffixIndex]
end

function CompactNumberFormatter.FormatCurrency(value: any, prefix: string?): string
	local currencyPrefix = (typeof(prefix) == "string" and prefix) or "$"
	return currencyPrefix .. CompactNumberFormatter.Format(value)
end

function CompactNumberFormatter.FormatPerSecond(value: any): string
	return CompactNumberFormatter.Format(value) .. "/s"
end

return CompactNumberFormatter
