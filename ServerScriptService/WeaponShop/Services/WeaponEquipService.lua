local Players = game:GetService("Players")

local WeaponEquipService = {}
WeaponEquipService.__index = WeaponEquipService

local function resolvePath(pathSegments)
	local current = game
	for _, segment in ipairs(pathSegments) do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	return current
end

local function debugWarn(config, message)
	if config.EnableDebugWarnings then
		warn(message)
	end
end

function WeaponEquipService.new(config, ownershipService)
	local self = setmetatable({}, WeaponEquipService)
	self._config = config
	self._ownershipService = ownershipService
	self._toolsFolder = resolvePath(config.ToolsFolderPath)
	if not self._toolsFolder then
		debugWarn(config, "[WeaponEquipService] Missing tools folder path. Equip will fail until fixed.")
	end
	return self
end

function WeaponEquipService:_isManagedTool(instance)
	return instance:IsA("Tool") and instance:GetAttribute(self._config.ManagedToolAttribute) == true
end

function WeaponEquipService:_isExtraLoadoutWeapon(weaponDefinition)
	return weaponDefinition.LoadoutSlot == "Extra" or weaponDefinition.CanCoexistWithEquippedWeapon == true
end

function WeaponEquipService:_isExtraManagedTool(tool: Tool): boolean
	return tool:GetAttribute("WeaponLoadoutSlot") == "Extra" or tool:GetAttribute("CanCoexistWithEquippedWeapon") == true
end

function WeaponEquipService:_cleanupManagedTools(player, predicate)
	local function cleanupIn(container)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if self:_isManagedTool(child) and (predicate == nil or predicate(child)) then
				child:Destroy()
			end
		end
	end
	cleanupIn(player:FindFirstChildOfClass("Backpack"))
	cleanupIn(player.Character)
end

function WeaponEquipService:_hasManagedTool(player, weaponId: string, includeBackpack: boolean, includeCharacter: boolean): boolean
	local function containerHas(container)
		if not container then
			return false
		end
		for _, child in ipairs(container:GetChildren()) do
			if self:_isManagedTool(child) and child:GetAttribute(self._config.ManagedToolWeaponIdAttribute) == weaponId then
				return true
			end
		end
		return false
	end

	if includeBackpack and containerHas(player:FindFirstChildOfClass("Backpack")) then
		return true
	end
	if includeCharacter and containerHas(player.Character) then
		return true
	end
	return false
end

function WeaponEquipService:_applyCombatAttributes(tool: Tool, weaponDefinition)
	tool:SetAttribute(self._config.ManagedToolAttribute, true)
	tool:SetAttribute(self._config.ManagedToolWeaponIdAttribute, weaponDefinition.Id)
	tool:SetAttribute(self._config.CombatToolAttribute or "NPCCombatTool", true)
	tool:SetAttribute("WeaponLoadoutSlot", self:_isExtraLoadoutWeapon(weaponDefinition) and "Extra" or "Primary")
	tool:SetAttribute("Damage", weaponDefinition.Damage or tool:GetAttribute("Damage") or 10)
	tool:SetAttribute("AttackRange", weaponDefinition.AttackRange or tool:GetAttribute("AttackRange") or 10)
	if typeof(weaponDefinition.AttackHitboxSize) == "Vector3" then
		tool:SetAttribute("AttackHitboxSize", weaponDefinition.AttackHitboxSize)
	end
	if typeof(weaponDefinition.PlayerHitboxSize) == "Vector3" then
		tool:SetAttribute("PlayerHitboxSize", weaponDefinition.PlayerHitboxSize)
	elseif typeof(weaponDefinition.AttackHitboxSize) == "Vector3" then
		tool:SetAttribute("PlayerHitboxSize", weaponDefinition.AttackHitboxSize)
	end
	tool:SetAttribute("CanDamagePlayers", weaponDefinition.CanDamagePlayers == true)
	tool:SetAttribute("CanCoexistWithEquippedWeapon", weaponDefinition.CanCoexistWithEquippedWeapon == true)
	tool:SetAttribute("ContestDisarmEnabled", weaponDefinition.ContestDisarmEnabled == true)
	tool:SetAttribute("KnockbackHorizontal", weaponDefinition.KnockbackHorizontal or 0)
	tool:SetAttribute("KnockbackVertical", weaponDefinition.KnockbackVertical or 0)
end

function WeaponEquipService:_ensureCoexistingWeapon(player, weaponDefinition)
	if not self:_isExtraLoadoutWeapon(weaponDefinition) or not self._ownershipService:OwnsWeapon(player, weaponDefinition.Id) then
		return
	end
	local weaponId = weaponDefinition.Id
	local function alreadyHas(container)
		if not container then
			return false
		end
		for _, child in ipairs(container:GetChildren()) do
			if self:_isManagedTool(child) and child:GetAttribute(self._config.ManagedToolWeaponIdAttribute) == weaponId then
				return true
			end
		end
		return false
	end
	if alreadyHas(player:FindFirstChildOfClass("Backpack")) or alreadyHas(player.Character) then
		return
	end
	local template = self:_getToolTemplate(weaponDefinition.ToolNameInReplicatedStorage)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not (template and backpack) then
		return
	end
	local clone = template:Clone()
	self:_applyCombatAttributes(clone, weaponDefinition)
	clone.Parent = backpack
end

function WeaponEquipService:_getToolTemplate(toolName)
	if not self._toolsFolder or typeof(toolName) ~= "string" then
		return nil
	end
	local tool = self._toolsFolder:FindFirstChild(toolName)
	if tool and tool:IsA("Tool") then
		return tool
	end
	return nil
end

function WeaponEquipService:EquipWeapon(player, weaponDefinition)
	if not self._ownershipService:OwnsWeapon(player, weaponDefinition.Id) then
		return false, "NOT_OWNED"
	end
	local template = self:_getToolTemplate(weaponDefinition.ToolNameInReplicatedStorage)
	if not template then
		debugWarn(self._config, ("[WeaponEquipService] Missing tool template %s for weapon %s"):format(tostring(weaponDefinition.ToolNameInReplicatedStorage), weaponDefinition.Id))
		return false, "MISSING_TOOL"
	end

	if self:_isExtraLoadoutWeapon(weaponDefinition) then
		self:_cleanupManagedTools(player, function(tool)
			return tool:GetAttribute(self._config.ManagedToolWeaponIdAttribute) == weaponDefinition.Id
				or self:_isExtraManagedTool(tool)
		end)
	else
		self:_cleanupManagedTools(player, function(tool)
			return not self:_isExtraManagedTool(tool)
		end)
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, "MISSING_BACKPACK"
	end
	local clone = template:Clone()
	self:_applyCombatAttributes(clone, weaponDefinition)
	clone.Parent = backpack

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and not self:_isExtraLoadoutWeapon(weaponDefinition) then
		humanoid:EquipTool(clone)
	end

	if not self:_isExtraLoadoutWeapon(weaponDefinition) then
		self._ownershipService:SetEquippedWeaponId(player, weaponDefinition.Id)
	end
	return true, "EQUIPPED"
end

function WeaponEquipService:ReequipSelectedWeapon(player, registry)
	local equippedWeaponId = self._ownershipService:GetEquippedWeaponId(player)
	if not equippedWeaponId then
		self:_cleanupManagedTools(player, function(tool)
			return not self:_isExtraManagedTool(tool)
		end)
	else
		local weaponDefinition = registry.GetWeaponById(equippedWeaponId)
		if weaponDefinition and not self:_isExtraLoadoutWeapon(weaponDefinition) then
			self:EquipWeapon(player, weaponDefinition)
		end
	end
	for weaponId in pairs(self._ownershipService:GetOwnedMap(player)) do
		local ownedWeapon = registry.GetWeaponById(weaponId)
		if ownedWeapon and self:_isExtraLoadoutWeapon(ownedWeapon) then
			self:_ensureCoexistingWeapon(player, ownedWeapon)
		end
	end
end

function WeaponEquipService:IsWeaponActive(player, weaponId: string): boolean
	return self:_hasManagedTool(player, weaponId, false, true)
end

function WeaponEquipService:IsWeaponEquipped(player, weaponDefinition): boolean
	if not self._ownershipService:OwnsWeapon(player, weaponDefinition.Id) then
		return false
	end
	if self:_isExtraLoadoutWeapon(weaponDefinition) then
		return true
	end
	if self._ownershipService:GetEquippedWeaponId(player) == weaponDefinition.Id then
		return true
	end
	return self:_hasManagedTool(player, weaponDefinition.Id, true, true)
end

function WeaponEquipService:BuildWeaponButtonState(player, weaponDefinition): { [string]: any }
	local owned = self._ownershipService:OwnsWeapon(player, weaponDefinition.Id)
	if not owned then
		return {
			Owned = false,
			Equipped = false,
			Active = false,
			ButtonText = "Buy",
			ButtonEnabled = true,
		}
	end

	local active = self:IsWeaponActive(player, weaponDefinition.Id)
	local equipped = self:IsWeaponEquipped(player, weaponDefinition)
	return {
		Owned = true,
		Equipped = equipped,
		Active = active,
		ButtonText = equipped and "Equipped" or "Equip",
		ButtonEnabled = not equipped,
	}
end

function WeaponEquipService:Init(registry)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				self:ReequipSelectedWeapon(player, registry)
			end)
		end)
		if player.Character then
			task.defer(function()
				self:ReequipSelectedWeapon(player, registry)
			end)
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			task.defer(function()
				self:ReequipSelectedWeapon(player, registry)
			end)
		end)
		if player.Character then
			task.defer(function()
				self:ReequipSelectedWeapon(player, registry)
			end)
		end
	end
end

return WeaponEquipService
