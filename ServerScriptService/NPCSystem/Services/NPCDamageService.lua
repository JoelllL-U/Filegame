local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage.NPCSystem.Config.NPCSpawnConfig)
local CombatHitboxUtils = require(ReplicatedStorage.NPCSystem.Shared.CombatHitboxUtils)
local NPCStateService = require(script.Parent.NPCStateService)
local BaseSlotService = require(script.Parent.BaseSlotService)
local GameplaySFXService = require(script.Parent.GameplaySFXService)
local SafeZoneService = require(script.Parent.SafeZoneService)

local NPCDamageService = {}
NPCDamageService.__index = NPCDamageService

local remotesFolder = ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Remotes")
local damageRemote: RemoteEvent = remotesFolder:FindFirstChild(config.Damage.RemoteEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")

damageRemote.Name = config.Damage.RemoteEventName
damageRemote.Parent = remotesFolder

local playerUseDebounce: { [Player]: number } = {}
local playerTargetDebounce: { [Player]: { [Instance]: number } } = {}

local function getBaseSlotServiceMethod(methodName: string): ((...any) -> ...any)?
	local method = BaseSlotService and BaseSlotService[methodName]
	if typeof(method) == "function" then
		return method
	end
	return nil
end

local function isCarryingAnyBrainrot(player: Player): boolean
	local method = getBaseSlotServiceMethod("IsCarryingAnyBrainrot")
	return method ~= nil and method(player) == true
end

local function isCarryingDefeatedCapturable(player: Player): boolean
	local method = getBaseSlotServiceMethod("IsCarryingDefeatedCapturable")
	return method ~= nil and method(player) == true
end

local function releaseDefeatedCapturableForContest(player: Player, contestSource: string)
	local method = getBaseSlotServiceMethod("ReleaseDefeatedCapturableForContest")
	if method then
		method(player, contestSource)
	end
end

local function applyHumanoidDamage(humanoid: Humanoid, damage: number)
	if damage <= 0 then
		return
	end
	local takeDamage = humanoid.TakeDamage
	if typeof(takeDamage) == "function" then
		takeDamage(humanoid, damage)
		return
	end
	humanoid.Health = math.max(0, humanoid.Health - damage)
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getAttackDirection(player: Player, payload: { [string]: any }?): Vector3
	local root = getCharacterRoot(player)
	local fallback = root and root.CFrame.LookVector or Vector3.zAxis
	if typeof(payload) ~= "table" then
		return fallback
	end
	local look = payload.CameraLookVector
	if typeof(look) == "Vector3" and look.Magnitude > 0.001 then
		return look.Unit
	end
	local cameraCFrame = payload.CameraCFrame
	if typeof(cameraCFrame) == "CFrame" then
		return cameraCFrame.LookVector.Unit
	end
	return fallback
end

local function resolveNPCModelAndHitPart(target: Instance?): (Model?, BasePart?)
	local current = target
	local hitPart = (target and target:IsA("BasePart")) and target or nil
	while current do
		if current:IsA("Model") and NPCStateService.GetState(current) then
			return current, hitPart
		end
		if not hitPart and current:IsA("BasePart") then
			hitPart = current
		end
		current = current.Parent
	end
	return nil, nil
end

local function resolveNPCAnchorPart(npcModel: Model): BasePart?
	local preferred = npcModel:FindFirstChild("Base", true)
	if preferred and preferred:IsA("BasePart") then
		return preferred
	end
	local root = npcModel:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	if npcModel.PrimaryPart then
		return npcModel.PrimaryPart
	end
	return npcModel:FindFirstChildWhichIsA("BasePart", true)
end

local function resolvePlayerFromInstance(target: Instance?): (Player?, Model?, BasePart?)
	local current = target
	local hitPart = (target and target:IsA("BasePart")) and target or nil
	while current do
		if current:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(current)
			if player then
				local root = current:FindFirstChild("HumanoidRootPart")
				return player, current, (hitPart or (root and root:IsA("BasePart") and root or nil))
			end
		end
		if not hitPart and current:IsA("BasePart") then
			hitPart = current
		end
		current = current.Parent
	end
	return nil, nil, nil
end

local function validateEquippedTool(player: Player, tool: Instance?): Tool?
	if not tool or not tool:IsA("Tool") then
		return nil
	end
	local character = player.Character
	if not character or tool.Parent ~= character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	return tool
end

local function getToolDamage(tool: Tool): number
	local damage = tool:GetAttribute("Damage")
	if typeof(damage) == "number" and damage > 0 then
		return damage
	end
	return config.Damage.DefaultToolDamage
end

local function getToolRange(tool: Tool): number
	local toolRange = tool:GetAttribute("AttackRange")
	if typeof(toolRange) == "number" and toolRange > 0 then
		return toolRange
	end
	return config.Damage.MaxHitDistance
end

local function getPlayerHitboxSize(tool: Tool, range: number): Vector3
	local hitboxSize = tool:GetAttribute("PlayerHitboxSize")
	if typeof(hitboxSize) ~= "Vector3" then
		hitboxSize = tool:GetAttribute("AttackHitboxSize")
	end
	if typeof(hitboxSize) == "Vector3" and hitboxSize.X > 0 and hitboxSize.Y > 0 and hitboxSize.Z > 0 then
		return hitboxSize
	end
	local fallback = config.Damage.DefaultPlayerHitboxSize or config.Damage.DefaultHitboxSize
	if typeof(fallback) == "Vector3" and fallback.X > 0 and fallback.Y > 0 and fallback.Z > 0 then
		return fallback
	end
	return Vector3.new(6, 6, math.max(6, range))
end

local function canUseNow(player: Player): boolean
	local now = os.clock()
	local last = playerUseDebounce[player]
	if last and now - last < config.Damage.ToolUseCooldownSeconds then
		return false
	end
	playerUseDebounce[player] = now
	return true
end

local function canHitTargetNow(player: Player, targetKey: Instance): boolean
	local now = os.clock()
	local perTarget = playerTargetDebounce[player]
	if not perTarget then
		perTarget = {}
		playerTargetDebounce[player] = perTarget
	end
	local last = perTarget[targetKey]
	if last and now - last < config.Damage.PerTargetHitCooldownSeconds then
		return false
	end
	perTarget[targetKey] = now
	return true
end

local function getPlanarDistance(a: Vector3, b: Vector3): number
	local delta = a - b
	return Vector2.new(delta.X, delta.Z).Magnitude
end

local function isNpcInRange(player: Player, npcModel: Model, hitPart: BasePart?, allowedRange: number): boolean
	local root = getCharacterRoot(player)
	if not root then
		return false
	end
	local targetPart = hitPart or npcModel.PrimaryPart or npcModel:FindFirstChildWhichIsA("BasePart", true)
	if not targetPart then
		return false
	end
	local npcAttackRadius = npcModel:GetAttribute("AttackRadius")
	local validRange = allowedRange
	if typeof(npcAttackRadius) == "number" and npcAttackRadius > 0 then
		validRange = math.min(validRange, npcAttackRadius)
	end
	return getPlanarDistance(root.Position, targetPart.Position) <= validRange
end

local function findClosestNpcInRange(player: Player, allowedRange: number): (Model?, BasePart?)
	local root = getCharacterRoot(player)
	if not root then
		return nil, nil
	end

	local npcContainer = workspace:FindFirstChild(config.NPCContainerName)
	if not (npcContainer and npcContainer:IsA("Folder")) then
		return nil, nil
	end

	local closestModel = nil
	local closestPart = nil
	local closestDistance = math.huge

	for _, child in ipairs(npcContainer:GetChildren()) do
		if child:IsA("Model") and NPCStateService.IsAlive(child) then
			local targetPart = resolveNPCAnchorPart(child)
			if targetPart then
				local npcAttackRadius = child:GetAttribute("AttackRadius")
				local validRange = allowedRange
				if typeof(npcAttackRadius) == "number" and npcAttackRadius > 0 then
					validRange = math.min(validRange, npcAttackRadius)
				end
				local distance = getPlanarDistance(root.Position, targetPart.Position)
				if distance <= validRange and distance < closestDistance then
					closestDistance = distance
					closestModel = child
					closestPart = targetPart
				end
			end
		end
	end

	return closestModel, closestPart
end

local function isPlayerInRange(player: Player, targetPart: BasePart?, allowedRange: number): boolean
	local root = getCharacterRoot(player)
	if not (root and targetPart) then
		return false
	end
	return (root.Position - targetPart.Position).Magnitude <= allowedRange
end

local function getPlayerHitDirection(player: Player, payload: { [string]: any }?): Vector3
	local root = getCharacterRoot(player)
	local fallback = root and root.CFrame.LookVector or Vector3.zAxis
	local direction = getAttackDirection(player, payload)
	local flattened = Vector3.new(direction.X, 0, direction.Z)
	if flattened.Magnitude <= 0.001 then
		flattened = Vector3.new(fallback.X, 0, fallback.Z)
	end
	if flattened.Magnitude <= 0.001 then
		return fallback.Unit
	end
	return flattened.Unit
end

local function applyPlayerKnockback(targetRoot: BasePart, direction: Vector3, horizontal: number, vertical: number)
	local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
	if horizontalDirection.Magnitude <= 0.001 then
		horizontalDirection = targetRoot.CFrame.LookVector
		horizontalDirection = Vector3.new(horizontalDirection.X, 0, horizontalDirection.Z)
	end
	if horizontalDirection.Magnitude <= 0.001 then
		horizontalDirection = Vector3.zAxis
	end
	local planarVelocity = horizontalDirection.Unit * math.max(0, horizontal)
	local currentVelocity = targetRoot.AssemblyLinearVelocity
	local desiredVelocity = Vector3.new(planarVelocity.X, math.max(currentVelocity.Y, 0) + math.max(0, vertical), planarVelocity.Z)
	local impulse = (desiredVelocity - currentVelocity) * math.max(targetRoot.AssemblyMass, 1)
	targetRoot:ApplyImpulse(impulse)
end

local function isPvPBlockedBySafeZone(attacker: Player, targetPlayer: Player): boolean
	return SafeZoneService.IsPlayerProtected(attacker) or SafeZoneService.IsPlayerProtected(targetPlayer)
end

local function playEnemyHitSFX(player: Player, worldPosition: Vector3?, killed: boolean?)
	GameplaySFXService.PlayForPlayer(player, "EnemyHit", worldPosition)
	if killed == true then
		GameplaySFXService.PlayForPlayer(player, "EnemyKill", worldPosition)
	end
end

local function applyNpcDamageForPlayer(player: Player, equippedTool: Tool, npcModel: Model): boolean
	local didDamage, remainingHealth = NPCStateService.ApplyDamage(npcModel, getToolDamage(equippedTool), player)
	if didDamage then
		playEnemyHitSFX(player, npcModel:GetPivot().Position, remainingHealth <= 0)
	end
	return didDamage
end

local function handleLegacyDirectTarget(player: Player, equippedTool: Tool, target: Instance?)
	local npcModel, hitPart = resolveNPCModelAndHitPart(target)
	if not npcModel then
		npcModel, hitPart = findClosestNpcInRange(player, getToolRange(equippedTool))
	end
	if not npcModel or not NPCStateService.IsAlive(npcModel) then
		return
	end
	if not canHitTargetNow(player, npcModel) then
		return
	end
	if not isNpcInRange(player, npcModel, hitPart, getToolRange(equippedTool)) then
		return
	end
	applyNpcDamageForPlayer(player, equippedTool, npcModel)
end

local function handleNpcRangeAttack(player: Player, equippedTool: Tool)
	local npcModel, hitPart = findClosestNpcInRange(player, getToolRange(equippedTool))
	if not npcModel or not NPCStateService.IsAlive(npcModel) then
		return
	end
	if not canHitTargetNow(player, npcModel) then
		return
	end
	if not isNpcInRange(player, npcModel, hitPart, getToolRange(equippedTool)) then
		return
	end
	applyNpcDamageForPlayer(player, equippedTool, npcModel)
end

local function collectPlayerHits(player: Player, equippedTool: Tool, payload: { [string]: any })
	local root = getCharacterRoot(player)
	if not root then
		return {}
	end
	local direction = getPlayerHitDirection(player, payload)
	local range = getToolRange(equippedTool)
	local hitboxSize = getPlayerHitboxSize(equippedTool, range)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { player.Character }
	local parts = CombatHitboxUtils.GetPartsInFrontBox(root.Position, direction, range, hitboxSize, overlapParams)
	local playerHits = {}
	local seenPlayers = {}
	for _, part in ipairs(parts) do
		local targetPlayer, _character, targetRoot = resolvePlayerFromInstance(part)
		if targetPlayer and targetPlayer ~= player then
			local existing = seenPlayers[targetPlayer]
			if not existing then
				seenPlayers[targetPlayer] = { Root = targetRoot, HitPart = part }
			elseif not existing.HitPart and part:IsA("BasePart") then
				existing.HitPart = part
			end
		end
	end
	for targetPlayer, hitData in pairs(seenPlayers) do
		table.insert(playerHits, { Player = targetPlayer, Root = hitData.Root, HitPart = hitData.HitPart or hitData.Root })
	end
	return playerHits
end

local function onDamageRequested(player: Player, tool: Instance?, payloadOrTarget: any)
	local equippedTool = validateEquippedTool(player, tool)
	if not equippedTool then
		return
	end
	if isCarryingAnyBrainrot(player) then
		return
	end
	if not canUseNow(player) then
		return
	end

	if typeof(payloadOrTarget) ~= "table" then
		handleLegacyDirectTarget(player, equippedTool, payloadOrTarget)
		return
	end

	handleNpcRangeAttack(player, equippedTool)

	local damage = getToolDamage(equippedTool)
	local range = getToolRange(equippedTool)

	local canDamagePlayers = equippedTool:GetAttribute("CanDamagePlayers") == true
	local canContestDisarm = equippedTool:GetAttribute("ContestDisarmEnabled") == true
	local knockbackHorizontal = equippedTool:GetAttribute("KnockbackHorizontal")
	local knockbackVertical = equippedTool:GetAttribute("KnockbackVertical")
	local canKnockbackPlayers = (typeof(knockbackHorizontal) == "number" and knockbackHorizontal > 0)
		or (typeof(knockbackVertical) == "number" and knockbackVertical > 0)
	if not canDamagePlayers and not canContestDisarm and not canKnockbackPlayers then
		return
	end

	local playerHits = collectPlayerHits(player, equippedTool, payloadOrTarget)
	local direction = getPlayerHitDirection(player, payloadOrTarget)
	local playedPlayerHitSFX = false
	for _, playerHit in ipairs(playerHits) do
		local targetPlayer = playerHit.Player
		local targetRoot = playerHit.Root
		local targetPart = playerHit.HitPart or targetRoot
		if not (targetPlayer and targetRoot and targetPart and canHitTargetNow(player, targetPlayer)) then
			continue
		end
		if not isPlayerInRange(player, targetPart, range) then
			continue
		end
		if isPvPBlockedBySafeZone(player, targetPlayer) then
			continue
		end
		local humanoid = targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
		if canDamagePlayers then
			applyHumanoidDamage(humanoid, damage)
			if not playedPlayerHitSFX then
				playedPlayerHitSFX = true
				GameplaySFXService.PlayForPlayer(player, "EnemyHit", targetRoot.Position)
			end
		end
		if canKnockbackPlayers then
			applyPlayerKnockback(targetRoot, direction, knockbackHorizontal, typeof(knockbackVertical) == "number" and knockbackVertical or 0)
			if not playedPlayerHitSFX then
				playedPlayerHitSFX = true
				GameplaySFXService.PlayForPlayer(player, "EnemyHit", targetRoot.Position)
			end
		end
		if canContestDisarm and isCarryingDefeatedCapturable(targetPlayer) then
			releaseDefeatedCapturableForContest(targetPlayer, tostring(equippedTool:GetAttribute("ShopWeaponId") or equippedTool.Name))
			if not playedPlayerHitSFX then
				playedPlayerHitSFX = true
				GameplaySFXService.PlayForPlayer(player, "EnemyHit", targetRoot.Position)
			end
		end
	end
end

function NPCDamageService.Init()
	damageRemote.OnServerEvent:Connect(onDamageRequested)
	Players.PlayerRemoving:Connect(function(player)
		playerUseDebounce[player] = nil
		playerTargetDebounce[player] = nil
	end)
end

return NPCDamageService
