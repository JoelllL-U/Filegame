local CountdownUtils = {}

function CountdownUtils.AlignExpiryTime(nowValue: number, durationSeconds: number, stepSeconds: number?): number
	local safeNow = typeof(nowValue) == "number" and nowValue or os.clock()
	local safeDuration = math.max(0, tonumber(durationSeconds) or 0)
	local safeStep = math.max(0.01, tonumber(stepSeconds) or 0.1)
	return math.ceil((safeNow + safeDuration) / safeStep) * safeStep
end

function CountdownUtils.FormatTenthsSeconds(secondsRemaining: number, decimalPlaces: number?): string
	local places = math.max(0, math.floor(tonumber(decimalPlaces) or 1))
	local multiplier = 10 ^ places
	local safeSeconds = math.max(0, tonumber(secondsRemaining) or 0)
	local roundedUp = math.ceil(safeSeconds * multiplier) / multiplier
	return ("%0." .. tostring(places) .. "fs"):format(roundedUp)
end

return CountdownUtils
