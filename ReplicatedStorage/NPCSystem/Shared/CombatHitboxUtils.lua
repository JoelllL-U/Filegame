local CombatHitboxUtils = {}

local function sanitizeDirection(direction: Vector3?, fallback: Vector3): Vector3
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
		return fallback.Unit
	end
	return direction.Unit
end

function CombatHitboxUtils.BuildFrontBox(origin: Vector3, direction: Vector3?, distance: number, size: Vector3, fallbackDirection: Vector3?): (CFrame, Vector3)
	local fallback = fallbackDirection or Vector3.zAxis
	local look = sanitizeDirection(direction, fallback)
	local clampedDistance = math.max(0.5, distance)
	local center = origin + (look * math.max(0, clampedDistance * 0.5))
	return CFrame.lookAt(center, center + look), size
end

function CombatHitboxUtils.GetPartsInFrontBox(origin: Vector3, direction: Vector3?, distance: number, size: Vector3, overlapParams: OverlapParams): ({ BasePart }, CFrame, Vector3)
	local cframe, resolvedSize = CombatHitboxUtils.BuildFrontBox(origin, direction, distance, size, direction or Vector3.zAxis)
	return workspace:GetPartBoundsInBox(cframe, resolvedSize, overlapParams), cframe, resolvedSize
end

return CombatHitboxUtils
