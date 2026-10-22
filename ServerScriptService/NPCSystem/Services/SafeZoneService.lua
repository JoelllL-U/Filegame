local Workspace = game:GetService("Workspace")

local SafeZoneService = {}
local SAFE_ZONE_FOLDER_NAME = "SafeZones"

local function isPointInsidePart(point: Vector3, part: BasePart): boolean
	local relative = part.CFrame:PointToObjectSpace(point)
	return math.abs(relative.X) <= (part.Size.X * 0.5)
		and math.abs(relative.Y) <= (part.Size.Y * 0.5)
		and math.abs(relative.Z) <= (part.Size.Z * 0.5)
end

local function collectSafeZoneParts(): { BasePart }
	local collected = {}
	local folder = Workspace:FindFirstChild(SAFE_ZONE_FOLDER_NAME)
	if folder then
		for _, descendant in ipairs(folder:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(collected, descendant)
			end
		end
	end
	return collected
end

function SafeZoneService.IsProtectedPosition(position: Vector3): boolean
	for _, zonePart in ipairs(collectSafeZoneParts()) do
		if zonePart.Parent and isPointInsidePart(position, zonePart) then
			return true
		end
	end
	return false
end

function SafeZoneService.IsPlayerProtected(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return SafeZoneService.IsProtectedPosition(root.Position)
end

return SafeZoneService
