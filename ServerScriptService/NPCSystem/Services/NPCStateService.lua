local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local spawnConfig = require(ReplicatedStorage.NPCSystem.Config.NPCSpawnConfig)
local NPCRegistry = require(ReplicatedStorage.NPCSystem.Config.NPCRegistry)
local MutationRegistry = require(ReplicatedStorage.NPCSystem.Config.MutationRegistry)
local CompactNumberFormatter = require(ReplicatedStorage.NPCSystem.Shared.CompactNumberFormatter)
local CountdownUtils = require(ReplicatedStorage.NPCSystem.Shared.CountdownUtils)
local NPCVisualUtils = require(ReplicatedStorage.NPCSystem.Shared.NPCVisualUtils)

local NPCStateService = {}
NPCStateService.__index = NPCStateService

local FLASH_LOCKOUT_SECONDS = 0.5
local FLASH_COLOR = Color3.fromRGB(255, 140, 140)

local statesByModel: { [Model]: any } = {}
local deathCallbacks: { (Model, BasePart, Player?) -> () } = {}
local collisionConnectionByModel: { [Model]: RBXScriptConnection } = {}
local collisionPartConnectionByModel: { [Model]: { [BasePart]: RBXScriptConnection } } = {}
local stateMaintenanceStarted = false

local function getDisplayAnchorPart(npcModel: Model): BasePart?
	local basePart = npcModel:FindFirstChild("Base", true)
	if basePart and basePart:IsA("BasePart") then
		return basePart
	end

	local head = npcModel:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
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

local function resolveDisplayTemplateInstance(): Instance?
	local current: Instance = game
	for _, segment in ipairs(spawnConfig.WorldNPCDisplayTemplatePath) do
		local nextNode = current:FindFirstChild(segment)
		if not nextNode then
			warn(("[NPCStateService] Missing world display template path segment %s"):format(segment))
			return nil
		end
		current = nextNode
	end
	return current
end

local function removeLegacyDisplays(npcModel: Model)
	for _, descendant in ipairs(npcModel:GetDescendants()) do
		if descendant:IsA("BillboardGui") and (descendant.Name == "NPCHealthGui" or descendant.Name == "WorldNPCDisplay") then
			descendant:Destroy()
		end
	end
end

local function attachDisplayTemplate(npcModel: Model): (Instance?, TextLabel?, TextLabel?, ImageLabel?)
	removeLegacyDisplays(npcModel)

	local template = resolveDisplayTemplateInstance()
	if not template then
		return nil, nil, nil, nil
	end

	local anchorPart = getDisplayAnchorPart(npcModel)
	if not anchorPart then
		warn(("[NPCStateService] Could not attach display template for %s; no BasePart found"):format(npcModel.Name))
		return nil, nil, nil, nil
	end

	local displayRoot = template:Clone()
	displayRoot.Name = "WorldNPCDisplay"

	if not displayRoot:IsA("BillboardGui") then
		warn(("[NPCStateService] World display template must be BillboardGui, got %s"):format(displayRoot.ClassName))
		displayRoot:Destroy()
		return nil, nil, nil, nil
	end

	displayRoot.Adornee = anchorPart
	displayRoot.Parent = anchorPart

	local displayNameLabel = displayRoot:FindFirstChild("DisplayName", true)
	if not (displayNameLabel and displayNameLabel:IsA("TextLabel")) then
		warn(("[NPCStateService] World display for %s missing TextLabel DisplayName"):format(npcModel.Name))
	end

	local generationLabel = displayRoot:FindFirstChild("Generation", true)
	if not (generationLabel and generationLabel:IsA("TextLabel")) then
		warn(("[NPCStateService] World display for %s missing TextLabel Generation"):format(npcModel.Name))
	end

	local rarityLabel = displayRoot:FindFirstChild("Rarity", true)
	if not (rarityLabel and rarityLabel:IsA("TextLabel")) then
		warn(("[NPCStateService] World display for %s missing TextLabel Rarity"):format(npcModel.Name))
	end

	local brainrotLife = displayRoot:FindFirstChild("BrainrotLife", true)
	if not (brainrotLife and brainrotLife:IsA("Frame")) then
		warn(("[NPCStateService] World display for %s missing Frame BrainrotLife"):format(npcModel.Name))
	end

	local displayLife = displayRoot:FindFirstChild("DisplayLife", true)
	if not (displayLife and displayLife:IsA("TextLabel")) then
		warn(("[NPCStateService] World display for %s missing TextLabel DisplayLife"):format(npcModel.Name))
		return displayRoot, nil, nil, nil
	end

	local timerLabel = displayRoot:FindFirstChild("Timer", true)
	if not (timerLabel and timerLabel:IsA("TextLabel")) then
		warn(("[NPCStateService] World display for %s missing TextLabel Timer"):format(npcModel.Name))
		timerLabel = nil
	end

	local progress = brainrotLife and brainrotLife:FindFirstChild("Progress")
	if progress and not progress:IsA("ImageLabel") then
		progress = nil
	end
	if not progress then
		warn(("[NPCStateService] World display for %s missing ImageLabel BrainrotLife/Progress"):format(npcModel.Name))
	end

	return displayRoot, displayLife, timerLabel, progress
end

local function formatGenerationText(value: number): string
	return CompactNumberFormatter.FormatPerSecond(value)
end

local function getMutationDisplay(mutationId: string?): (string, Color3)
	local mutation = MutationRegistry.GetById(mutationId)
	if mutation then
		return mutation.DisplayName, mutation.Color
	end
	return "Normal", Color3.fromRGB(255, 255, 255)
end

local function createHealthDisplay(
	npcModel: Model,
	displayName: string,
	rarityDisplayName: string,
	rarityColor: Color3,
	incomePerSecond: number,
	mutationId: string?
): (Instance?, TextLabel?, TextLabel?, ImageLabel?)
	local displayRoot, displayLife, timerLabel, progress = attachDisplayTemplate(npcModel)
	if not displayRoot then
		return nil, nil, nil, nil
	end

	local displayNameLabel = displayRoot:FindFirstChild("DisplayName", true)
	if displayNameLabel and displayNameLabel:IsA("TextLabel") then
		displayNameLabel.Text = displayName
	end

	local generationLabel = displayRoot:FindFirstChild("Generation", true)
	if generationLabel and generationLabel:IsA("TextLabel") then
		generationLabel.Text = formatGenerationText(incomePerSecond)
	end

	local rarityLabel = displayRoot:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = rarityDisplayName
		rarityLabel.TextColor3 = rarityColor
	end

	local mutationLabel = displayRoot:FindFirstChild("Mutation", true)
	if mutationLabel and mutationLabel:IsA("TextLabel") then
		local mutationName, mutationColor = getMutationDisplay(mutationId)
		mutationLabel.Text = mutationName
		mutationLabel.TextColor3 = mutationColor
	end

	return displayRoot, displayLife, timerLabel, progress
end


local function enforceModelNonCollidable(npcModel: Model)
	for _, descendant in ipairs(npcModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end
end

local function enforcePartNonCollidable(part: BasePart)
	part.CanCollide = false
end

local function bindPartCollisionLock(npcModel: Model, part: BasePart)
	local byPart = collisionPartConnectionByModel[npcModel]
	if not byPart then
		byPart = {}
		collisionPartConnectionByModel[npcModel] = byPart
	end
	if byPart[part] then
		return
	end
	enforcePartNonCollidable(part)
	byPart[part] = part:GetPropertyChangedSignal("CanCollide"):Connect(function()
		enforcePartNonCollidable(part)
	end)
	part.Destroying:Connect(function()
		local existing = byPart[part]
		if existing then
			existing:Disconnect()
			byPart[part] = nil
		end
	end)
end

local function disconnectCollisionLocks(npcModel: Model)
	local byPart = collisionPartConnectionByModel[npcModel]
	if byPart then
		for _, connection in pairs(byPart) do
			connection:Disconnect()
		end
		collisionPartConnectionByModel[npcModel] = nil
	end
end

local function getAliveLifetimeSecondsForModel(npcModel: Model): number
	local definitionId = npcModel:GetAttribute("DefinitionId")
	local definition = typeof(definitionId) == "string" and NPCRegistry.GetDefinitionById(definitionId) or nil
	local configured = definition and definition.AliveLifetimeSeconds or nil
	if typeof(configured) == "number" and configured > 0 then
		return configured
	end
	local fallback = spawnConfig.Lifetime and spawnConfig.Lifetime.DefaultAliveLifetimeSeconds or 60
	if typeof(fallback) == "number" and fallback > 0 then
		return fallback
	end
	return 60
end

local function updateAliveTimerGui(state, nowValue: number)
	if not state.TimerLabel then
		return
	end
	if not state.TimerLabel.Parent then
		return
	end
	local decimalPlaces = spawnConfig.Lifetime and spawnConfig.Lifetime.TimerDecimalPlaces or 1
	state.TimerLabel.Text = CountdownUtils.FormatTenthsSeconds(math.max(0, state.AliveExpiresAt - nowValue), decimalPlaces)
end

local function cleanupStateForRemoval(npcModel: Model)
	statesByModel[npcModel] = nil
	local collisionConnection = collisionConnectionByModel[npcModel]
	if collisionConnection then
		collisionConnection:Disconnect()
		collisionConnectionByModel[npcModel] = nil
	end
	disconnectCollisionLocks(npcModel)
end

local function startStateMaintenance()
	if stateMaintenanceStarted then
		return
	end
	stateMaintenanceStarted = true

	local interval = spawnConfig.Lifetime and spawnConfig.Lifetime.TimerUpdateIntervalSeconds or 0.1
	if typeof(interval) ~= "number" or interval <= 0 then
		interval = 0.1
	end

	task.spawn(function()
		while true do
			task.wait(interval)
			local nowValue = os.clock()
			local toDespawn = {}
			for npcModel, state in pairs(statesByModel) do
				if state and not state.Dead then
					updateAliveTimerGui(state, nowValue)
					if nowValue >= state.AliveExpiresAt then
						table.insert(toDespawn, npcModel)
					end
				end
			end
			for _, npcModel in ipairs(toDespawn) do
				NPCStateService.DespawnAliveNPC(npcModel)
			end
		end
	end)
end

local function updateHealthGui(state)
	if state.DisplayLifeLabel and state.DisplayLifeLabel.Parent then
		state.DisplayLifeLabel.Text = ("%d/%d"):format(math.floor(state.CurrentHealth + 0.5), math.floor(state.MaxHealth + 0.5))
	end
	if state.HealthProgress and state.HealthProgress.Parent then
		local ratio = 0
		if state.MaxHealth > 0 then
			ratio = math.clamp(state.CurrentHealth / state.MaxHealth, 0, 1)
		end
		local fullSize = state.HealthProgressFullSize
		if typeof(fullSize) == "UDim2" then
			state.HealthProgress.Size = UDim2.new(
				fullSize.X.Scale * ratio,
				math.floor(fullSize.X.Offset * ratio + 0.5),
				fullSize.Y.Scale,
				fullSize.Y.Offset
			)
		end
	end
end

local function setAllPartsAnchored(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function runHitFlash(state)
	local now = os.clock()
	if now - state.LastFlashAt < FLASH_LOCKOUT_SECONDS then
		return
	end
	state.LastFlashAt = now

	local flashParts = {}
	for _, descendant in ipairs(state.Model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(flashParts, { Part = descendant, OriginalColor = descendant.Color })
		end
	end

	local tweenIn = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenOut = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	task.spawn(function()
		for _, entry in ipairs(flashParts) do
			if entry.Part and entry.Part.Parent then
				TweenService:Create(entry.Part, tweenIn, { Color = FLASH_COLOR }):Play()
			end
		end
		task.wait(0.14)
		for _, entry in ipairs(flashParts) do
			if entry.Part and entry.Part.Parent then
				TweenService:Create(entry.Part, tweenOut, { Color = entry.OriginalColor }):Play()
			end
		end
	end)
end

function NPCStateService.RegisterDeathCallback(callback: (Model, BasePart, Player?) -> ())
	table.insert(deathCallbacks, callback)
end

function NPCStateService.InitializeNPC(
	npcModel: Model,
	spawnPoint: BasePart,
	displayName: string,
	maxHealth: number,
	rarityId: string,
	rarityDisplayName: string,
	rarityColor: Color3,
	incomePerSecond: number?,
	mutationId: string?
)
	if statesByModel[npcModel] then
		return
	end

	setAllPartsAnchored(npcModel)
	enforceModelNonCollidable(npcModel)
	NPCVisualUtils.ApplyMutationColorOverride(npcModel, mutationId)
	local generation = (typeof(incomePerSecond) == "number" and incomePerSecond) or 0
	local displayRoot, displayLifeLabel, timerLabel, healthProgress = createHealthDisplay(npcModel, displayName, rarityDisplayName, rarityColor, generation, mutationId)
	local aliveLifetimeSeconds = getAliveLifetimeSecondsForModel(npcModel)
	local timerInterval = spawnConfig.Lifetime and spawnConfig.Lifetime.TimerUpdateIntervalSeconds or 0.1

	local state = {
		Model = npcModel,
		SpawnPoint = spawnPoint,
		DisplayName = displayName,
		MaxHealth = maxHealth,
		CurrentHealth = maxHealth,
		RarityId = rarityId,
		RarityDisplayName = rarityDisplayName,
		RarityColor = rarityColor,
		GenerationPerSecond = generation,
		MutationId = mutationId,
		LastHitter = nil,
		LastHitterUserId = nil,
		LastHitterName = nil,
		Dead = false,
		DisplayRoot = displayRoot,
		DisplayLifeLabel = displayLifeLabel,
		TimerLabel = timerLabel,
		HealthProgress = healthProgress,
		HealthProgressFullSize = healthProgress and healthProgress.Size or nil,
		AliveLifetimeSeconds = aliveLifetimeSeconds,
		AliveExpiresAt = CountdownUtils.AlignExpiryTime(os.clock(), aliveLifetimeSeconds, timerInterval),
		LastFlashAt = 0,
	}
	statesByModel[npcModel] = state
	updateHealthGui(state)
	updateAliveTimerGui(state, os.clock())
	startStateMaintenance()

	if collisionConnectionByModel[npcModel] then
		collisionConnectionByModel[npcModel]:Disconnect()
		collisionConnectionByModel[npcModel] = nil
	end
	disconnectCollisionLocks(npcModel)
	for _, descendant in ipairs(npcModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			bindPartCollisionLock(npcModel, descendant)
		end
	end
	collisionConnectionByModel[npcModel] = npcModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			bindPartCollisionLock(npcModel, descendant)
		end
	end)

	npcModel:SetAttribute("DisplayName", displayName)
	npcModel:SetAttribute("MaxHealth", maxHealth)
	npcModel:SetAttribute("CurrentHealth", maxHealth)
	npcModel:SetAttribute("RarityId", rarityId)
	npcModel:SetAttribute("RarityDisplayName", rarityDisplayName)
	npcModel:SetAttribute("IncomePerSecond", generation)
	npcModel:SetAttribute("MutationId", mutationId)
	npcModel:SetAttribute("AliveLifetimeSeconds", aliveLifetimeSeconds)
	npcModel:SetAttribute("AliveExpiresAt", state.AliveExpiresAt)
end

function NPCStateService.GetState(npcModel: Model)
	return statesByModel[npcModel]
end

function NPCStateService.IsAlive(npcModel: Model): boolean
	local state = statesByModel[npcModel]
	return state ~= nil and not state.Dead and state.CurrentHealth > 0
end

function NPCStateService.ApplyDamage(npcModel: Model, amount: number, hitter: Player?): (boolean, number)
	local state = statesByModel[npcModel]
	if not state or state.Dead or state.CurrentHealth <= 0 or amount <= 0 then
		return false, state and state.CurrentHealth or 0
	end

	state.LastHitter = hitter
	if hitter then
		state.LastHitterUserId = hitter.UserId
		state.LastHitterName = hitter.Name
		npcModel:SetAttribute("LastHitterUserId", hitter.UserId)
		npcModel:SetAttribute("LastHitterName", hitter.Name)
	end

	state.CurrentHealth = math.clamp(state.CurrentHealth - amount, 0, state.MaxHealth)
	npcModel:SetAttribute("CurrentHealth", state.CurrentHealth)
	runHitFlash(state)
	updateHealthGui(state)

	if state.CurrentHealth <= 0 then
		NPCStateService.HandleDeath(npcModel)
	end

	return true, state.CurrentHealth
end

function NPCStateService.HandleDeath(npcModel: Model)
	local state = statesByModel[npcModel]
	if not state or state.Dead then
		return
	end

	state.Dead = true
	npcModel:SetAttribute("CurrentHealth", 0)
	updateHealthGui(state)
	for index, callback in ipairs(deathCallbacks) do
		local success, err = pcall(callback, npcModel, state.SpawnPoint, state.LastHitter)
		if not success then
			warn(("[NPCStateService] Death callback %d failed for %s: %s"):format(index, npcModel:GetFullName(), tostring(err)))
		end
	end

	cleanupStateForRemoval(npcModel)
	npcModel:Destroy()
end

function NPCStateService.DespawnAliveNPC(npcModel: Model)
	local state = statesByModel[npcModel]
	if not state or state.Dead then
		return
	end
	state.Dead = true
	cleanupStateForRemoval(npcModel)
	npcModel:Destroy()
end

Players.PlayerRemoving:Connect(function(leavingPlayer)
	for _, state in pairs(statesByModel) do
		if state.LastHitter == leavingPlayer then
			state.LastHitter = nil
		end
	end
end)

return NPCStateService
