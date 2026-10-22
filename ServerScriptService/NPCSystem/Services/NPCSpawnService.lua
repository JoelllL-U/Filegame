local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local config = require(ReplicatedStorage.NPCSystem.Config.NPCSpawnConfig)
local NPCRegistry = require(ReplicatedStorage.NPCSystem.Config.NPCRegistry)
local MutationRegistry = require(ReplicatedStorage.NPCSystem.Config.MutationRegistry)
local NPCVisualUtils = require(ReplicatedStorage.NPCSystem.Shared.NPCVisualUtils)
local NPCStateService = require(script.Parent.NPCStateService)
local BaseSlotService = require(script.Parent.BaseSlotService)

local NPCSpawnService = {}
NPCSpawnService.__index = NPCSpawnService

local spawnStates: { [BasePart]: any } = {}
local spawnPointIds: { [BasePart]: string } = {}
local npcContainer: Folder? = nil
local spawnRandom = Random.new()

local function debugWarn(message: string)
	if config.EnableDebugWarnings then
		warn("[NPCSpawnService] " .. message)
	end
end

local function getSpawnPointId(spawnPoint: BasePart): string
	local existing = spawnPointIds[spawnPoint]
	if existing then
		return existing
	end

	local generated = HttpService:GenerateGUID(false)
	spawnPointIds[spawnPoint] = generated
	spawnPoint:SetAttribute("SpawnPointId", generated)
	return generated
end

local function resolveTemplateFolder(): Folder?
	local current = game
	for _, segment in ipairs(config.TemplateFolderPath) do
		current = current:FindFirstChild(segment)
		if not current then
			warn("[NPCSpawnService] Missing template folder path segment:", segment)
			return nil
		end
	end

	if not current:IsA("Folder") then
		warn("[NPCSpawnService] Template folder path does not resolve to a Folder")
		return nil
	end

	return current
end

local function getOrCreateNPCContainer(): Folder
	if npcContainer and npcContainer.Parent then
		return npcContainer
	end

	local existing = Workspace:FindFirstChild(config.NPCContainerName)
	if existing and existing:IsA("Folder") then
		npcContainer = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = config.NPCContainerName
	folder.Parent = Workspace
	npcContainer = folder
	debugWarn(("Created NPC container folder Workspace/%s"):format(config.NPCContainerName))
	return folder
end

local function gatherRaritySpawnPool(): { any }
	local templateFolder = resolveTemplateFolder()
	if not templateFolder then
		return {}
	end

	local rarityPool = NPCRegistry.BuildRaritySpawnPool(templateFolder)
	debugWarn(("Built rarity pool with %d valid rarity tiers"):format(#rarityPool))
	return rarityPool
end

local function pickRarity(rarityPool: { any })
	if #rarityPool == 0 then
		return nil
	end

	local orderedPool = table.clone(rarityPool)
	table.sort(orderedPool, function(left, right)
		return left.Rarity.Weight > right.Rarity.Weight
	end)

	local fallbackEntry = nil
	local fallbackWeight = math.huge
	for _, entry in ipairs(orderedPool) do
		local denominator = math.max(1, math.floor((entry.Rarity.Weight or 1) + 0.5))
		if denominator < fallbackWeight then
			fallbackWeight = denominator
			fallbackEntry = entry
		end
		if spawnRandom:NextInteger(1, denominator) == 1 then
			return entry
		end
	end

	return fallbackEntry or orderedPool[#orderedPool]
end

local function pickNPCFromRarity(rarityEntry)
	if not rarityEntry or not rarityEntry.NPCEntries or #rarityEntry.NPCEntries == 0 then
		return nil
	end
	local randomIndex = spawnRandom:NextInteger(1, #rarityEntry.NPCEntries)
	return rarityEntry.NPCEntries[randomIndex]
end

local function isDescendantOfModel(instance: Instance?, model: Model): boolean
	return instance ~= nil and instance:IsDescendantOf(model)
end

local function sanitizeCloneConstraints(model: Model)
	-- NPC model internals are treated as untouchable assembled data.
	-- Do not scan or destroy welds/joints/attachments inside the model.
	return
end

local function preAnchorModel(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function placeModelAtSpawn(model: Model, spawnPoint: BasePart)
	if not model.PrimaryPart then
		local base = model:FindFirstChildWhichIsA("BasePart", true)
		if base then
			model.PrimaryPart = base
		end
	end

	local modelPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not modelPart then
		warn(("[NPCSpawnService] Spawned model %s has no BasePart"):format(model.Name))
		return
	end

	local currentPivot = model:GetPivot()
	local boxCf, boxSize = model:GetBoundingBox()
	local pivotToBox = currentPivot:ToObjectSpace(boxCf)
	local spawnTopCenter = spawnPoint.Position + Vector3.new(0, spawnPoint.Size.Y * 0.5, 0)
	local desiredCenter = spawnTopCenter + Vector3.new(0, boxSize.Y * 0.5, 0)

	local desiredBoxCf = CFrame.fromMatrix(
		desiredCenter,
		boxCf.XVector,
		boxCf.YVector,
		boxCf.ZVector
	)
	local desiredPivot = desiredBoxCf * pivotToBox:Inverse()
	model:PivotTo(desiredPivot)
end


local function isSpawnPointBlockedByDefeatedCapturable(spawnPoint: BasePart): boolean
	local spawnPointId = spawnPoint:GetAttribute("SpawnPointId")
	if typeof(spawnPointId) ~= "string" or spawnPointId == "" then
		return false
	end
	if BaseSlotService and BaseSlotService.IsSpawnPointBlocked then
		return BaseSlotService.IsSpawnPointBlocked(spawnPointId)
	end
	return false
end

local function scheduleSpawnRetry(spawnPoint: BasePart, delaySeconds: number, reason: string)
	local state = spawnStates[spawnPoint]
	if not state then
		return
	end
	if state.RetryScheduled then
		return
	end

	local safeDelay = math.max(0.1, delaySeconds)
	state.RetryScheduled = true
	local token = state.CycleToken
	debugWarn(("Retrying spawn at %s in %.1fs (%s)"):format(spawnPoint:GetFullName(), safeDelay, reason))

	task.delay(safeDelay, function()
		local current = spawnStates[spawnPoint]
		if not current or current.CycleToken ~= token then
			return
		end
		current.RetryScheduled = false
		NPCSpawnService.TrySpawnAt(spawnPoint)
	end)
end

local function scheduleRespawn(spawnPoint: BasePart)
	local state = spawnStates[spawnPoint]
	if not state then
		return
	end

	state.ActiveNPC = nil
	state.CooldownUntil = os.clock() + config.SpawnCooldownSeconds
	state.CycleToken += 1
	state.RetryScheduled = false
	local token = state.CycleToken
	debugWarn(("NPC defeated at %s. Respawn in %ds"):format(spawnPoint:GetFullName(), config.SpawnCooldownSeconds))

	task.delay(config.SpawnCooldownSeconds, function()
		local current = spawnStates[spawnPoint]
		if not current or current.CycleToken ~= token then
			return
		end
		NPCSpawnService.TrySpawnAt(spawnPoint)
	end)
end

function NPCSpawnService.TrySpawnAt(spawnPoint: BasePart)
	local state = spawnStates[spawnPoint]
	if not state then
		warn(("[NPCSpawnService] TrySpawnAt called for unregistered spawn point %s"):format(spawnPoint:GetFullName()))
		return false
	end
	if state.IsSpawning then
		return false
	end
	if state.ActiveNPC and state.ActiveNPC.Parent then
		return false
	end
	if os.clock() < state.CooldownUntil then
		return false
	end
	if isSpawnPointBlockedByDefeatedCapturable(spawnPoint) then
		scheduleSpawnRetry(spawnPoint, config.BlockedSpawnRetrySeconds or 2, "spawn point blocked by defeated capturable")
		return false
	end

	state.IsSpawning = true
	local rarityPool = gatherRaritySpawnPool()
	if #rarityPool == 0 then
		warn(("[NPCSpawnService] No valid rarity/NPC pool entries for %s"):format(spawnPoint:GetFullName()))
		state.IsSpawning = false
		scheduleSpawnRetry(spawnPoint, config.FailedSpawnRetrySeconds or 5, "rarity pool empty")
		return false
	end

	local rarityEntry = pickRarity(rarityPool)
	local npcEntry = pickNPCFromRarity(rarityEntry)
	if not rarityEntry or not npcEntry then
		warn(("[NPCSpawnService] Failed rarity->NPC roll at %s"):format(spawnPoint:GetFullName()))
		state.IsSpawning = false
		scheduleSpawnRetry(spawnPoint, config.FailedSpawnRetrySeconds or 5, "rarity or NPC roll failed")
		return false
	end

	debugWarn(("Rolled rarity %s then NPC %s at %s"):format(rarityEntry.Rarity.Id, npcEntry.Definition.Id, spawnPoint:GetFullName()))

	local rolledMutation = MutationRegistry.RollMutation()
	local mutationId = rolledMutation and rolledMutation.Id or nil
	local mutatedMaxHealth, mutatedIncome = MutationRegistry.ApplyMultipliers(
		npcEntry.Definition.MaxHealth,
		npcEntry.Definition.IncomePerSecond,
		mutationId
	)

	local npc = npcEntry.Template:Clone()
	npc.Name = npcEntry.Definition.DisplayName
	sanitizeCloneConstraints(npc)
	preAnchorModel(npc)
	NPCVisualUtils.ApplyMutationColorOverride(npc, mutationId)
	npc:SetAttribute("DefinitionId", npcEntry.Definition.Id)
	npc:SetAttribute("SpawnPoint", spawnPoint:GetFullName())
	npc:SetAttribute("SpawnPointId", getSpawnPointId(spawnPoint))
	npc:SetAttribute("AttackRadius", npcEntry.Definition.AttackRadius)
	npc:SetAttribute("MutationId", mutationId)
	npc:SetAttribute("IncomePerSecond", mutatedIncome)
	npc:SetAttribute("AliveLifetimeSeconds", npcEntry.Definition.AliveLifetimeSeconds)
	npc.Parent = getOrCreateNPCContainer()
	placeModelAtSpawn(npc, spawnPoint)

	NPCStateService.InitializeNPC(
		npc,
		spawnPoint,
		npcEntry.Definition.DisplayName,
		mutatedMaxHealth,
		npcEntry.Rarity.Id,
		npcEntry.Rarity.DisplayName,
		npcEntry.Rarity.Color,
		mutatedIncome,
		mutationId
	)

	state.ActiveNPC = npc
	npc.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			local latest = spawnStates[spawnPoint]
			if latest and latest.ActiveNPC == npc and os.clock() >= latest.CooldownUntil then
				scheduleRespawn(spawnPoint)
			end
		end
	end)

	state.IsSpawning = false
	state.RetryScheduled = false
	local finalBoxCf = select(1, npc:GetBoundingBox())
	debugWarn(("Spawned %s (%s) at %s [Id=%s Pos=%s FinalCenter=%s]"):format(npcEntry.Definition.DisplayName, npcEntry.Definition.Id, spawnPoint:GetFullName(), getSpawnPointId(spawnPoint), tostring(spawnPoint.Position), tostring(finalBoxCf.Position)))
	return true
end

local function registerSpawnPoint(part: BasePart, spawnImmediately: boolean?)
	if spawnStates[part] then
		return
	end
	spawnStates[part] = {
		Part = part,
		ActiveNPC = nil,
		IsSpawning = false,
		RetryScheduled = false,
		CooldownUntil = 0,
		CycleToken = 0,
	}
	debugWarn(("Registered spawn point: %s [Id=%s Pos=%s]"):format(part:GetFullName(), getSpawnPointId(part), tostring(part.Position)))
	if spawnImmediately ~= false then
		NPCSpawnService.TrySpawnAt(part)
	end
end

local function unregisterSpawnPoint(part: BasePart)
	local state = spawnStates[part]
	if not state then
		return
	end
	state.CycleToken += 1
	if state.ActiveNPC and state.ActiveNPC.Parent then
		NPCStateService.HandleDeath(state.ActiveNPC)
	end
	spawnStates[part] = nil
	spawnPointIds[part] = nil
end

local function getSpawnPointsFromTag(): { BasePart }
	local result = {}
	for _, tagged in ipairs(CollectionService:GetTagged(config.SpawnPointTag)) do
		if tagged:IsA("BasePart") then
			table.insert(result, tagged)
		end
	end
	return result
end

local function getSpawnPointsFromFolderOrName(): { BasePart }
	local result = {}
	local seen: { [BasePart]: boolean } = {}
	local folder = Workspace:FindFirstChild(config.SpawnPointFolderName)
	if folder and folder:IsA("Folder") then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				seen[child] = true
				table.insert(result, child)
			end
		end
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and child.Name == config.SpawnPointNameFallback and not seen[child] then
			table.insert(result, child)
		end
	end
	return result
end

local function shuffleSpawnPoints(spawnPoints: { BasePart })
	for index = #spawnPoints, 2, -1 do
		local swapIndex = spawnRandom:NextInteger(1, index)
		spawnPoints[index], spawnPoints[swapIndex] = spawnPoints[swapIndex], spawnPoints[index]
	end
end

local function beginInitialFill(spawnPoints: { BasePart })
	local initialFillConfig = config.InitialFill
	if not initialFillConfig or initialFillConfig.Enabled == false or #spawnPoints == 0 then
		for _, spawnPoint in ipairs(spawnPoints) do
			NPCSpawnService.TrySpawnAt(spawnPoint)
		end
		return
	end

	local shuffled = table.clone(spawnPoints)
	shuffleSpawnPoints(shuffled)

	local totalDuration = math.max(0, tonumber(initialFillConfig.TotalDurationSeconds) or 60)
	local firstDelay = math.max(0, tonumber(initialFillConfig.FirstSpawnDelaySeconds) or 0)
	local stepDelay = 0
	if #shuffled > 1 then
		stepDelay = totalDuration / (#shuffled - 1)
	end

	for index, spawnPoint in ipairs(shuffled) do
		local delaySeconds = firstDelay + ((index - 1) * stepDelay)
		task.delay(delaySeconds, function()
			local state = spawnStates[spawnPoint]
			if not state then
				return
			end
			NPCSpawnService.TrySpawnAt(spawnPoint)
		end)
	end
end

function NPCSpawnService.Init()
	debugWarn("Init started")
	NPCStateService.RegisterDeathCallback(function(npcModel, spawnPoint, lastHitter)
		local handleNpcDeath = BaseSlotService and BaseSlotService.HandleNPCDeath
		if typeof(handleNpcDeath) == "function" then
			local success, err = pcall(handleNpcDeath, npcModel, lastHitter)
			if not success then
				warn(("[NPCSpawnService] BaseSlotService.HandleNPCDeath failed for %s: %s"):format(npcModel:GetFullName(), tostring(err)))
			end
		end
		scheduleRespawn(spawnPoint)
	end)

	local initialSpawnPoints = {}
	local taggedSpawnPoints = getSpawnPointsFromTag()
	for _, spawnPart in ipairs(taggedSpawnPoints) do
		registerSpawnPoint(spawnPart, false)
		table.insert(initialSpawnPoints, spawnPart)
	end

	if #taggedSpawnPoints == 0 and config.EnableNameBasedSpawnPointFallback then
		local fallbackSpawnPoints = getSpawnPointsFromFolderOrName()
		if #fallbackSpawnPoints > 0 then
			warn(("[NPCSpawnService] Found 0 tagged spawn points. Using %d fallback spawn parts from Workspace/%s or name '%s'. Consider adding CollectionService tag '%s' for explicit setup."):format(#fallbackSpawnPoints, config.SpawnPointFolderName, config.SpawnPointNameFallback, config.SpawnPointTag))
			for _, spawnPart in ipairs(fallbackSpawnPoints) do
				registerSpawnPoint(spawnPart, false)
				table.insert(initialSpawnPoints, spawnPart)
			end
		else
			warn(("[NPCSpawnService] No spawn points found. Add CollectionService tag '%s' OR place BaseParts in Workspace/%s OR name parts '%s'."):format(config.SpawnPointTag, config.SpawnPointFolderName, config.SpawnPointNameFallback))
		end
	elseif #taggedSpawnPoints == 0 then
		warn(("[NPCSpawnService] No spawn points found with tag '%s'. Name-based fallback is disabled."):format(config.SpawnPointTag))
	end

	CollectionService:GetInstanceAddedSignal(config.SpawnPointTag):Connect(function(instance)
		if instance:IsA("BasePart") then
			registerSpawnPoint(instance, true)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(config.SpawnPointTag):Connect(function(instance)
		if instance:IsA("BasePart") then
			unregisterSpawnPoint(instance)
		end
	end)

	local totalRegistered = 0
	for _ in pairs(spawnStates) do
		totalRegistered += 1
	end
	beginInitialFill(initialSpawnPoints)
	debugWarn(("Init complete. Registered spawn points: %d"):format(totalRegistered))
end

return NPCSpawnService
