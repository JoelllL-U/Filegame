local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local baseConfig = require(ReplicatedStorage.NPCSystem.Config.BaseConfig)
local capturableFlowConfig = require(ReplicatedStorage.NPCSystem.Config.CapturableFlowConfig)
local spawnConfig = require(ReplicatedStorage.NPCSystem.Config.NPCSpawnConfig)
local NPCRegistry = require(ReplicatedStorage.NPCSystem.Config.NPCRegistry)
local MutationRegistry = require(ReplicatedStorage.NPCSystem.Config.MutationRegistry)
local OwnedNPCLevelConfig = require(ReplicatedStorage.NPCSystem.Config.OwnedNPCLevelConfig)
local OwnedNPCLevelMath = require(ReplicatedStorage.NPCSystem.Shared.OwnedNPCLevelMath)
local CompactNumberFormatter = require(ReplicatedStorage.NPCSystem.Shared.CompactNumberFormatter)
local CountdownUtils = require(ReplicatedStorage.NPCSystem.Shared.CountdownUtils)
local NPCVisualUtils = require(ReplicatedStorage.NPCSystem.Shared.NPCVisualUtils)
local NPCStateService = require(script.Parent.NPCStateService)
local GameplaySFXService = require(script.Parent.GameplaySFXService)

local upgradeNodeWarnedBySlot: { [string]: boolean } = {}

local function debugLog(message: string)
	if OwnedNPCLevelConfig.DebugLogs then
		warn("[BaseSlotService:Upgrade] " .. message)
	end
end

local function debugWarnOnce(key: string, message: string)
	if upgradeNodeWarnedBySlot[key] then
		return
	end
	upgradeNodeWarnedBySlot[key] = true
	debugLog(message)
end

local redeemDebugCooldownByKey: { [string]: number } = {}

local function debugRedeemWarn(key: string, message: string)
	if not OwnedNPCLevelConfig.DebugLogs then
		return
	end
	local now = os.clock()
	local nextAllowed = redeemDebugCooldownByKey[key] or 0
	if now < nextAllowed then
		return
	end
	redeemDebugCooldownByKey[key] = now + 1
	warn("[BaseSlotService:Redeem] " .. message)
end

local BaseSlotService = {}
BaseSlotService.__index = BaseSlotService

local BaseService = nil
local BaseIncomeService = nil
local DataService = nil

local occupancyBySlot: { [BasePart]: Model } = {}
local slotChangedCallbacks: { (Player?, Model, string, { [string]: any }?) -> () } = {}
local slotByCapturedNPC: { [Model]: BasePart } = {}
local idleTrackByCapturedNPC: { [Model]: AnimationTrack } = {}
local slotStateBySlot: { [BasePart]: { DefinitionId: string, MutationId: string?, Level: number } } = {}
local ancestryConnectionByCapturedNPC: { [Model]: RBXScriptConnection } = {}
local collisionConnectionByCapturedNPC: { [Model]: RBXScriptConnection } = {}
local collisionPartConnectionByCapturedNPC: { [Model]: { [BasePart]: RBXScriptConnection } } = {}
local placePromptBySlot: { [BasePart]: ProximityPrompt } = {}
local carryStateByPlayer: { [Player]: CarriedOwnedNPCState } = {}
local carryCharacterAddedConnectionByPlayer: { [Player]: RBXScriptConnection } = {}
local carryCharacterRemovingConnectionByPlayer: { [Player]: RBXScriptConnection } = {}
local carryHumanoidDiedConnectionByPlayer: { [Player]: RBXScriptConnection } = {}
local rebirthDisplayRefreshConnectionByPlayer: { [Player]: RBXScriptConnection } = {}
local capturableCarrySpeedStateByPlayer: { [Player]: { Humanoid: Humanoid, OriginalWalkSpeed: number } } = {}
local redeemDetectionHeartbeatConnection: RBXScriptConnection? = nil
local attachGrabPrompt: (captured: Model, baseModel: Model, slotPart: BasePart) -> ()
local attachDeletePrompt: (captured: Model, baseModel: Model, slotPart: BasePart) -> ()
local handleCarryPlaceRequest: (player: Player, baseModel: Model, targetSlot: BasePart) -> ()
local clearSlotOccupancy: (slotPart: BasePart, baseModel: Model?) -> ()
local enforceModelNonCollidable: (model: Model) -> ()
local setModelSlottedPhysics: (model: Model) -> ()
local remotesFolder = ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Remotes")
local capturePromptRemote: RemoteEvent = remotesFolder:FindFirstChild(baseConfig.Remotes.CapturePromptEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")
local captureDecisionRemote: RemoteEvent = remotesFolder:FindFirstChild(baseConfig.Remotes.CaptureDecisionEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")
local upgradeRequestRemote: RemoteEvent = remotesFolder:FindFirstChild(OwnedNPCLevelConfig.RemoteEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")
local upgradeFeedbackRemote: RemoteEvent = remotesFolder:FindFirstChild(OwnedNPCLevelConfig.UpgradeFeedbackRemoteEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")
local capturableCarryStateRemote: RemoteEvent = remotesFolder:FindFirstChild(baseConfig.Remotes.CapturableCarryStateEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")
local capturableDropRequestRemote: RemoteEvent = remotesFolder:FindFirstChild(baseConfig.Remotes.CapturableDropRequestEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")
local capturableLifecycleRemote: RemoteEvent = remotesFolder:FindFirstChild(baseConfig.Remotes.CapturableLifecycleEventName) :: RemoteEvent
	or Instance.new("RemoteEvent")

capturePromptRemote.Name = baseConfig.Remotes.CapturePromptEventName
capturePromptRemote.Parent = remotesFolder
captureDecisionRemote.Name = baseConfig.Remotes.CaptureDecisionEventName
captureDecisionRemote.Parent = remotesFolder
upgradeRequestRemote.Name = OwnedNPCLevelConfig.RemoteEventName
upgradeRequestRemote.Parent = remotesFolder
upgradeFeedbackRemote.Name = OwnedNPCLevelConfig.UpgradeFeedbackRemoteEventName
upgradeFeedbackRemote.Parent = remotesFolder
capturableCarryStateRemote.Name = baseConfig.Remotes.CapturableCarryStateEventName
capturableCarryStateRemote.Parent = remotesFolder
capturableDropRequestRemote.Name = baseConfig.Remotes.CapturableDropRequestEventName
capturableDropRequestRemote.Parent = remotesFolder
capturableLifecycleRemote.Name = baseConfig.Remotes.CapturableLifecycleEventName
capturableLifecycleRemote.Parent = remotesFolder

type PendingCapture = {
	Id: number,
	DefinitionId: string,
	MutationId: string?,
	DisplayName: string,
	CreatedAt: number,
	ExpiresAt: number,
	Resolved: boolean,
	CapturableId: number?,
}

type CarryMotionMetadata = {
	PivotToBox: CFrame,
	BoxSize: Vector3,
	SafeForwardDistance: number,
}

type CarriedOwnedNPCState = {
	Model: Model,
	DefinitionId: string,
	MutationId: string?,
	Level: number,
	SourceSlot: BasePart,
	BaseModel: Model,
	CarryMotion: CarryMotionMetadata,
	CarryWeld: WeldConstraint?,
}

type DefeatedCapturableState = {
	Id: number,
	DefinitionId: string,
	MutationId: string?,
	DisplayName: string,
	SpawnCFrame: CFrame,
	ExpiresAt: number,
	Model: Model?,
	Carrier: Player?,
	CarryMotion: CarryMotionMetadata,
	CarryWeld: WeldConstraint?,
	Redeemed: boolean,
	Expired: boolean,
	PendingPromptPlayer: Player?,
	GrabPrompt: ProximityPrompt?,
	SpawnPointId: string?,
	TransitionBusy: boolean?,
}

local pendingCaptureQueueByPlayer: { [Player]: { PendingCapture } } = {}
local activeCaptureByPlayer: { [Player]: PendingCapture? } = {}
local pendingCaptureId = 0
local handledNpcDeathsByModel = setmetatable({}, { __mode = "k" })

local defeatedCapturableById: { [number]: DefeatedCapturableState } = {}
local defeatedCapturableByModel: { [Model]: DefeatedCapturableState } = {}
local defeatedCapturableCarryByPlayer: { [Player]: DefeatedCapturableState } = {}
local defeatedCapturableId = 0
local redeemTouchDebounceByPlayer: { [Player]: number } = {}
local blockedSpawnPointCountsById: { [string]: number } = {}
local CARRY_WELD_NAME = "NPCCarryWeld"
local CARRY_INTERNAL_WELD_NAME = "NPCCarryInternalWeld"

type SlotPlacementMetadata = {
	PivotToBoxOffset: Vector3,
	PivotToHumanoidRoot: CFrame?,
	HumanoidRootToBoxOffset: Vector3?,
	BoxSize: Vector3,
	Source: string,
}

type ProtectedPartRestoreMetadata = {
	Base: CFrame?,
	EPart: CFrame?,
	XPart: CFrame?,
}

local slotPlacementMetadataByModel: { [Model]: SlotPlacementMetadata } = {}
local protectedPartRestoreMetadataByModel: { [Model]: ProtectedPartRestoreMetadata } = {}
local placementSequenceByModel: { [Model]: number } = {}

local function getCarryModeAttributeName(): string
	return (baseConfig.CarryRestrictions and baseConfig.CarryRestrictions.CarryModeAttributeName) or "BrainrotCarryMode"
end

local function getToolsLockedAttributeName(): string
	return (baseConfig.CarryRestrictions and baseConfig.CarryRestrictions.ToolsLockedAttributeName) or "BrainrotCarryToolsLocked"
end

local function getOwnedPlacePromptActiveAttributeName(): string
	return (baseConfig.CarryRestrictions and baseConfig.CarryRestrictions.OwnedPlacePromptActiveAttributeName) or "OwnedBrainrotPlacePromptActive"
end

local function getTemporaryCarryWalkSpeedMultiplier(): number
	local configured = baseConfig.CarryRestrictions and baseConfig.CarryRestrictions.TemporaryCarryWalkSpeedMultiplier or 0.9
	if typeof(configured) ~= "number" or configured <= 0 or configured > 1 then
		return 0.9
	end
	return configured
end

local function getCharacterHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function setToolsLockedForPlayer(player: Player, locked: boolean)
	player:SetAttribute(getToolsLockedAttributeName(), locked)
	if not locked then
		return
	end
	local humanoid = getCharacterHumanoid(player)
	if humanoid then
		humanoid:UnequipTools()
	end
end

local function clearTemporaryCarrySpeedPenalty(player: Player)
	local speedState = capturableCarrySpeedStateByPlayer[player]
	if not speedState then
		return
	end
	if speedState.Humanoid and speedState.Humanoid.Parent then
		speedState.Humanoid.WalkSpeed = speedState.OriginalWalkSpeed
	end
	capturableCarrySpeedStateByPlayer[player] = nil
end

local function applyTemporaryCarrySpeedPenalty(player: Player)
	local humanoid = getCharacterHumanoid(player)
	if not humanoid then
		return
	end
	local existing = capturableCarrySpeedStateByPlayer[player]
	if existing and existing.Humanoid == humanoid then
		return
	end
	clearTemporaryCarrySpeedPenalty(player)
	local originalWalkSpeed = humanoid.WalkSpeed
	capturableCarrySpeedStateByPlayer[player] = {
		Humanoid = humanoid,
		OriginalWalkSpeed = originalWalkSpeed,
	}
	humanoid.WalkSpeed = originalWalkSpeed * getTemporaryCarryWalkSpeedMultiplier()
end

local function refreshPlayerCarryRestrictions(player: Player)
	local hasOwnedCarry = carryStateByPlayer[player] ~= nil
	local hasCapturableCarry = BaseSlotService.IsCarryingDefeatedCapturable(player)
	local carryMode = "None"
	if hasOwnedCarry then
		carryMode = "Owned"
	elseif hasCapturableCarry then
		carryMode = "Capturable"
	end

	player:SetAttribute(getCarryModeAttributeName(), carryMode)
	player:SetAttribute(getOwnedPlacePromptActiveAttributeName(), hasOwnedCarry)
	setToolsLockedForPlayer(player, hasOwnedCarry or hasCapturableCarry)

	if hasCapturableCarry then
		applyTemporaryCarrySpeedPenalty(player)
	else
		clearTemporaryCarrySpeedPenalty(player)
	end
end

local function notifySlotChanged(baseModel: Model, slotPart: BasePart, slotData: { [string]: any }?)
	local owner = BaseService and BaseService.GetOwnerForBase(baseModel) or nil
	for _, callback in ipairs(slotChangedCallbacks) do
		callback(owner, baseModel, slotPart.Name, slotData)
	end
end


local function getCaptureQueue(player: Player): { PendingCapture }
	local queue = pendingCaptureQueueByPlayer[player]
	if queue then
		return queue
	end
	queue = {}
	pendingCaptureQueueByPlayer[player] = queue
	return queue
end

local function hasFreeSlotForPlayer(player: Player): boolean
	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel then
		return false
	end
	return BaseSlotService.FindFirstFreeSlot(baseModel) ~= nil
end

local function fireCapturePrompt(player: Player, pending: PendingCapture)
	capturePromptRemote:FireClient(player, {
		Type = "Prompt",
		CaptureId = pending.Id,
		NpcName = pending.DisplayName,
	})
end

local function fireNoFreeSlots(player: Player)
	capturePromptRemote:FireClient(player, {
		Type = "NoFreeSlots",
		Text = baseConfig.UI.NoFreeSlotsText,
	})
end

local function fireUpgradeFeedback(player: Player, payload: { [string]: any })
	upgradeFeedbackRemote:FireClient(player, payload)
end

local function getNextValidPending(player: Player): PendingCapture?
	local now = os.clock()
	local queue = getCaptureQueue(player)
	while #queue > 0 do
		local entry = queue[1]
		if entry.Resolved or now > entry.ExpiresAt then
			table.remove(queue, 1)
		else
			return entry
		end
	end
	return nil
end

local function pumpCapturePrompt(player: Player)
	local active = activeCaptureByPlayer[player]
	if active and not active.Resolved and os.clock() <= active.ExpiresAt then
		return
	end
	activeCaptureByPlayer[player] = nil
	local nextPending = getNextValidPending(player)
	if not nextPending then
		return
	end
	activeCaptureByPlayer[player] = nextPending
	fireCapturePrompt(player, nextPending)
end

local function enqueuePendingCapture(player: Player, definition: { [string]: any }, mutationId: string?, capturableId: number?)
	pendingCaptureId += 1
	local pending: PendingCapture = {
		Id = pendingCaptureId,
		DefinitionId = definition.Id,
		MutationId = mutationId,
		DisplayName = definition.DisplayName,
		CreatedAt = os.clock(),
		ExpiresAt = os.clock() + baseConfig.CaptureFlow.PendingTimeoutSeconds,
		Resolved = false,
		CapturableId = capturableId,
	}
	table.insert(getCaptureQueue(player), pending)
	pumpCapturePrompt(player)
end

local function resolvePendingCaptureById(player: Player, captureId: number): PendingCapture?
	local queue = getCaptureQueue(player)
	local active = activeCaptureByPlayer[player]
	if not active or active.Id ~= captureId then
		return nil
	end
	local now = os.clock()
	if active.Resolved or now > active.ExpiresAt then
		active.Resolved = true
		activeCaptureByPlayer[player] = nil
		pumpCapturePrompt(player)
		return nil
	end
	active.Resolved = true
	for i, entry in ipairs(queue) do
		if entry.Id == captureId then
			table.remove(queue, i)
			break
		end
	end
	activeCaptureByPlayer[player] = nil
	return active
end

local function cleanupPendingForPlayer(player: Player)
	pendingCaptureQueueByPlayer[player] = nil
	activeCaptureByPlayer[player] = nil
end

local function resolveTemplateFolder(): Folder?
	local current = game
	for _, segment in ipairs(spawnConfig.TemplateFolderPath) do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	if current and current:IsA("Folder") then
		return current
	end
	return nil
end

local function getSlotsFolder(baseModel: Model): Folder?
	local folder = baseModel:FindFirstChild(baseConfig.BaseSlotsFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function parseTrailingNumber(name: string, expectedPrefix: string?): number?
	local normalized = name
	if expectedPrefix and expectedPrefix ~= "" then
		local startIndex, endIndex = string.find(string.lower(name), "^" .. string.lower(expectedPrefix))
		if not startIndex or startIndex ~= 1 then
			return nil
		end
		normalized = string.sub(name, (endIndex or 0) + 1)
	end
	local numericSuffix = string.match(normalized, "(%d+)$")
	if not numericSuffix then
		return nil
	end
	local value = tonumber(numericSuffix)
	if not value then
		return nil
	end
	return value
end

local function getFloorOrderForNow(baseModel: Model): { number }
	local found = {}
	for _, child in ipairs(baseModel:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") then
			local floorIndex = parseTrailingNumber(child.Name, "Floor")
			if floorIndex and floorIndex > 0 then
				found[floorIndex] = true
			end
		end
	end
	local ordered = {}
	for floorIndex in pairs(found) do
		table.insert(ordered, floorIndex)
	end
	table.sort(ordered)
	if #ordered == 0 then
		return { 1 }
	end
	return ordered
end

local function getFloorContainer(baseModel: Model, floorIndex: number): Instance?
	local exactName = "Floor" .. tostring(floorIndex)

	-- Preferred layout: Base/Floor1 (Model/Folder) with Slots folder inside.
	local floorAtBase = baseModel:FindFirstChild(exactName)
	if floorAtBase and (floorAtBase:IsA("Model") or floorAtBase:IsA("Folder")) then
		local nestedSlots = floorAtBase:FindFirstChild(baseConfig.BaseSlotsFolderName)
		if nestedSlots and nestedSlots:IsA("Folder") then
			return nestedSlots
		end
		return floorAtBase
	end

	-- Backward-compatible layout: Base/Slots/Floor1.
	local slotsFolder = getSlotsFolder(baseModel)
	if slotsFolder then
		local floorInSlots = slotsFolder:FindFirstChild(exactName)
		if floorInSlots and (floorInSlots:IsA("Model") or floorInSlots:IsA("Folder")) then
			local nestedSlots = floorInSlots:FindFirstChild(baseConfig.BaseSlotsFolderName)
			if nestedSlots and nestedSlots:IsA("Folder") then
				return nestedSlots
			end
			return floorInSlots
		end

		for _, child in ipairs(slotsFolder:GetChildren()) do
			if child:IsA("Folder") or child:IsA("Model") then
				local parsed = parseTrailingNumber(child.Name, "Floor")
				if parsed == floorIndex then
					local nestedSlots = child:FindFirstChild(baseConfig.BaseSlotsFolderName)
					if nestedSlots and nestedSlots:IsA("Folder") then
						return nestedSlots
					end
					return child
				end
			end
		end
	end

	-- Last fallback: parse floor-like children directly under base.
	for _, child in ipairs(baseModel:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Model") then
			local parsed = parseTrailingNumber(child.Name, "Floor")
			if parsed == floorIndex then
				local nestedSlots = child:FindFirstChild(baseConfig.BaseSlotsFolderName)
				if nestedSlots and nestedSlots:IsA("Folder") then
					return nestedSlots
				end
				return child
			end
		end
	end
	return nil
end

local function getOrderedSlotsFromFloor(floorContainer: Instance): { BasePart }
	local slotsByNumber: { [number]: BasePart } = {}
	for _, child in ipairs(floorContainer:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("BaseUpgradeUnlocked") ~= false then
			local slotNumber = parseTrailingNumber(child.Name, "Slot")
			if slotNumber then
				if not slotsByNumber[slotNumber] then
					slotsByNumber[slotNumber] = child
				else
					warn(("[BaseSlotService] Ignoring duplicate slot number %d in %s"):format(slotNumber, floorContainer:GetFullName()))
				end
			end
		end
	end
	local slots = {}
	for _, slot in pairs(slotsByNumber) do
		table.insert(slots, slot)
	end
	table.sort(slots, function(a, b)
		local aIndex = parseTrailingNumber(a.Name, "Slot")
		local bIndex = parseTrailingNumber(b.Name, "Slot")
		if aIndex and bIndex and aIndex ~= bIndex then
			return aIndex < bIndex
		end
		if aIndex and not bIndex then
			return true
		end
		if bIndex and not aIndex then
			return false
		end
		return a.Name:lower() < b.Name:lower()
	end)
	return slots
end

local function getCapturedFolder(baseModel: Model): Folder
	local existing = baseModel:FindFirstChild(baseConfig.CapturedNPCFolderName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = baseConfig.CapturedNPCFolderName
	folder.Parent = baseModel
	return folder
end

local function getOrderedSlots(baseModel: Model): { BasePart }
	local slots = {}

	local activeFloors = getFloorOrderForNow(baseModel)
	local foundAnyFloor = false
	for _, floorIndex in ipairs(activeFloors) do
		local floorContainer = getFloorContainer(baseModel, floorIndex)
		if floorContainer then
			foundAnyFloor = true
			for _, slot in ipairs(getOrderedSlotsFromFloor(floorContainer)) do
				table.insert(slots, slot)
			end
		end
	end

	if not foundAnyFloor then
		local slotsFolder = getSlotsFolder(baseModel)
		if slotsFolder then
			warn(("[BaseSlotService] No active floor containers found in %s. Falling back to root slot parts."):format(slotsFolder:GetFullName()))
			local rootSlotsByNumber: { [number]: BasePart } = {}
			for _, child in ipairs(slotsFolder:GetChildren()) do
				if child:IsA("BasePart") and child:GetAttribute("BaseUpgradeUnlocked") ~= false then
					local slotNumber = parseTrailingNumber(child.Name, "Slot")
					if slotNumber then
						if not rootSlotsByNumber[slotNumber] then
							rootSlotsByNumber[slotNumber] = child
						else
							warn(("[BaseSlotService] Ignoring duplicate root slot number %d in %s"):format(slotNumber, slotsFolder:GetFullName()))
						end
					end
				end
			end
			table.clear(slots)
			for _, slot in pairs(rootSlotsByNumber) do
				table.insert(slots, slot)
			end
		else
			warn(("[BaseSlotService] Missing floor and root slots folders in %s"):format(baseModel:GetFullName()))
		end
		table.sort(slots, function(a, b)
			local aIndex = parseTrailingNumber(a.Name, "Slot")
			local bIndex = parseTrailingNumber(b.Name, "Slot")
			if aIndex and bIndex and aIndex ~= bIndex then
				return aIndex < bIndex
			end
			if aIndex and not bIndex then
				return true
			end
			if bIndex and not aIndex then
				return false
			end
			return a.Name:lower() < b.Name:lower()
		end)
	end

	return slots
end

local function findSlotByName(baseModel: Model, slotName: string): BasePart?
	for _, slot in ipairs(getOrderedSlots(baseModel)) do
		if slot.Name == slotName then
			return slot
		end
	end
	return nil
end

local function isDescendantOfModel(instance: Instance?, model: Model): boolean
	return instance ~= nil and instance:IsDescendantOf(model)
end

local function sanitizeCloneConstraints(model: Model)
	-- Brainrot model internals are treated as untouchable assembled data.
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


local function ensurePreferredPrimaryPart(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local preferred = model:FindFirstChild("HumanoidRootPart", true)
	if preferred and preferred:IsA("BasePart") then
		model.PrimaryPart = preferred
		return preferred
	end
	preferred = model:FindFirstChild("Base", true)
	if preferred and preferred:IsA("BasePart") then
		model.PrimaryPart = preferred
		return preferred
	end
	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	if firstPart and firstPart:IsA("BasePart") then
		model.PrimaryPart = firstPart
		return firstPart
	end
	return nil
end

local function shouldDebugPlacement(): boolean
	return OwnedNPCLevelConfig.DebugLogs == true
end

local function debugPlacementLog(model: Model?, message: string)
	if not shouldDebugPlacement() then
		return
	end
	local modelName = model and model:GetFullName() or "<no-model>"
	warn(("[BaseSlotService:Placement] %s :: %s"):format(modelName, message))
end

local function captureSlotPlacementMetadata(model: Model, source: string, forceRefresh: boolean?): SlotPlacementMetadata
	local existing = slotPlacementMetadataByModel[model]
	if existing and forceRefresh ~= true then
		return existing
	end
	local currentPivot = model:GetPivot()
	local boxCf, boxSize = model:GetBoundingBox()
	local humanoidRoot = model:FindFirstChild("HumanoidRootPart", true)
	local metadata: SlotPlacementMetadata = {
		PivotToBoxOffset = currentPivot:PointToObjectSpace(boxCf.Position),
		PivotToHumanoidRoot = nil,
		HumanoidRootToBoxOffset = nil,
		BoxSize = boxSize,
		Source = source,
	}
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		metadata.PivotToHumanoidRoot = currentPivot:ToObjectSpace(humanoidRoot.CFrame)
		metadata.HumanoidRootToBoxOffset = humanoidRoot.CFrame:PointToObjectSpace(boxCf.Position)
	end
	slotPlacementMetadataByModel[model] = metadata
	debugPlacementLog(model, ("Captured placement metadata source=%s boxSize=%s pivotToBoxOffset=%s pivotToHumanoidRoot=%s humanoidRootToBoxOffset=%s"):format(source, tostring(boxSize), tostring(metadata.PivotToBoxOffset), tostring(metadata.PivotToHumanoidRoot), tostring(metadata.HumanoidRootToBoxOffset)))
	return metadata
end

local function captureProtectedPartRestoreMetadata(model: Model, forceRefresh: boolean?): ProtectedPartRestoreMetadata
	local existing = protectedPartRestoreMetadataByModel[model]
	if existing and forceRefresh ~= true then
		return existing
	end
	local currentPivot = model:GetPivot()
	local metadata: ProtectedPartRestoreMetadata = {
		Base = nil,
		EPart = nil,
		XPart = nil,
	}
	for _, partName in ipairs({ "Base", "EPart", "XPart" }) do
		local part = model:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			metadata[partName] = currentPivot:ToObjectSpace(part.CFrame)
		end
	end
	protectedPartRestoreMetadataByModel[model] = metadata
	return metadata
end

local function restoreProtectedPartAlignment(model: Model)
	local metadata = protectedPartRestoreMetadataByModel[model] or captureProtectedPartRestoreMetadata(model, false)
	local currentPivot = model:GetPivot()
	for _, partName in ipairs({ "Base", "EPart", "XPart" }) do
		local relativeCf = metadata[partName]
		local part = model:FindFirstChild(partName, true)
		if relativeCf and part and part:IsA("BasePart") then
			part.CFrame = currentPivot * relativeCf
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function summarizeTemporaryMovementArtifacts(_model: Model): string
	return "model_assembly_untouched"
end

local function cleanupTemporaryMovementArtifacts(_model: Model): string
	-- Carry helper cleanup is explicit via stored helper references only.
	-- Never scan inside the brainrot model for joint-like descendants.
	return "explicit_helper_cleanup_only"
end

local function resolveSlotPlacementPart(slotPart: BasePart): BasePart
	local spawnPart = slotPart:FindFirstChild("Spawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end
	return slotPart
end

local function computeSlotSurfaceCFrame(slotPart: BasePart, placementPart: BasePart): CFrame
	local placementLocalPosition = slotPart.CFrame:PointToObjectSpace(placementPart.Position)
	local surfacePoint = slotPart.CFrame:PointToWorldSpace(Vector3.new(
		placementLocalPosition.X,
		slotPart.Size.Y * 0.5,
		placementLocalPosition.Z
	))
	return CFrame.fromMatrix(surfacePoint, slotPart.CFrame.XVector, slotPart.CFrame.YVector, slotPart.CFrame.ZVector)
end

local function buildSlotFacingCFrame(slotPart: BasePart, position: Vector3): CFrame
	local forward = slotPart.CFrame.LookVector
	local up = slotPart.CFrame.UpVector
	return CFrame.lookAt(position, position + forward, up)
end

local function placeModelOnSlot(model: Model, slotPart: BasePart, placementReason: string?): (boolean, CFrame?)
	local modelPart = ensurePreferredPrimaryPart(model)
	if not modelPart then
		warn(("[BaseSlotService] Captured model %s has no BasePart"):format(model.Name))
		return false, nil
	end

	local preCleanupArtifacts = summarizeTemporaryMovementArtifacts(model)
	local cleanupSummary = cleanupTemporaryMovementArtifacts(model)
	local metadata = slotPlacementMetadataByModel[model] or captureSlotPlacementMetadata(model, placementReason or "live_fallback", false)
	local placementPart = resolveSlotPlacementPart(slotPart)
	local slotSurfaceCf = computeSlotSurfaceCFrame(slotPart, placementPart)
	local desiredBoxPosition = slotSurfaceCf.Position + (slotPart.CFrame.UpVector * (metadata.BoxSize.Y * 0.5))
	local desiredBoxCf = buildSlotFacingCFrame(slotPart, desiredBoxPosition)
	local desiredPivot = nil
	if metadata.PivotToHumanoidRoot and metadata.HumanoidRootToBoxOffset then
		local desiredHumanoidRootPosition = desiredBoxPosition - desiredBoxCf:VectorToWorldSpace(metadata.HumanoidRootToBoxOffset)
		local desiredHumanoidRootCf = buildSlotFacingCFrame(slotPart, desiredHumanoidRootPosition)
		desiredPivot = desiredHumanoidRootCf * metadata.PivotToHumanoidRoot:Inverse()
	else
		local pivotOffsetWorld = desiredBoxCf:VectorToWorldSpace(metadata.PivotToBoxOffset)
		local desiredPivotPosition = desiredBoxPosition - pivotOffsetWorld
		desiredPivot = buildSlotFacingCFrame(slotPart, desiredPivotPosition)
	end
	debugPlacementLog(model, ("placeModelOnSlot reason=%s slot=%s placementPart=%s metadataSource=%s preCleanup=[%s] cleanup=[%s] targetPivot=%s currentPivot=%s"):format(placementReason or "unknown", slotPart:GetFullName(), placementPart:GetFullName(), metadata.Source, preCleanupArtifacts, cleanupSummary, tostring(desiredPivot), tostring(model:GetPivot())))
	model:PivotTo(desiredPivot)
	restoreProtectedPartAlignment(model)
	modelPart.AssemblyLinearVelocity = Vector3.zero
	modelPart.AssemblyAngularVelocity = Vector3.zero
	return true, desiredPivot
end

local function finalizeSlotPlacement(model: Model, slotPart: BasePart, placementReason: string?): boolean
	setModelSlottedPhysics(model)
	local placementSequence = (placementSequenceByModel[model] or 0) + 1
	placementSequenceByModel[model] = placementSequence
	debugPlacementLog(model, ("finalizeSlotPlacement start seq=%d reason=%s slot=%s currentPivot=%s"):format(placementSequence, placementReason or "unknown", slotPart:GetFullName(), tostring(model:GetPivot())))
	local placed, desiredPivot = placeModelOnSlot(model, slotPart, placementReason)
	if not placed or not desiredPivot then
		return false
	end
	debugPlacementLog(model, ("finalizeSlotPlacement end seq=%d reason=%s resultingPivot=%s"):format(placementSequence, placementReason or "unknown", tostring(model:GetPivot())))
	if shouldDebugPlacement() then
		task.delay(0.2, function()
			if placementSequenceByModel[model] ~= placementSequence then
				return
			end
			if not model.Parent then
				return
			end
			local livePivot = model:GetPivot()
			local drift = (livePivot.Position - desiredPivot.Position).Magnitude
			debugPlacementLog(model, ("post-place check seq=%d drift=%.4f livePivot=%s expectedPivot=%s slot=%s"):format(placementSequence, drift, tostring(livePivot), tostring(desiredPivot), slotPart:GetFullName()))
		end)
	end
	return true
end


local function resolveOwnedDisplayTemplate(): BillboardGui?
	local current: Instance = game
	for _, segment in ipairs(baseConfig.OwnedNPCDisplay.TemplatePath) do
		local nextNode = current:FindFirstChild(segment)
		if not nextNode then
			warn(("[BaseSlotService] Missing owned NPC display template path segment %s"):format(segment))
			return nil
		end
		current = nextNode
	end
	if current:IsA("BillboardGui") then
		return current
	end
	warn(("[BaseSlotService] Owned display template must be BillboardGui, got %s"):format(current.ClassName))
	return nil
end

local function resolveDefeatedDisplayTemplate(): BillboardGui?
	local current: Instance = game
	local templatePath = baseConfig.CaptureFlow and baseConfig.CaptureFlow.DefeatedBillboardTemplatePath
	if typeof(templatePath) ~= "table" then
		return nil
	end
	for _, segment in ipairs(templatePath) do
		local nextNode = current:FindFirstChild(segment)
		if not nextNode then
			warn(("[BaseSlotService] Missing defeated capturable display template path segment %s"):format(segment))
			return nil
		end
		current = nextNode
	end
	if current:IsA("BillboardGui") then
		return current
	end
	warn(("[BaseSlotService] Defeated capturable display template must be BillboardGui, got %s"):format(current.ClassName))
	return nil
end

local function getDisplayAnchor(model: Model): BasePart?
	local basePart = model:FindFirstChild("Base", true)
	if basePart and basePart:IsA("BasePart") then
		return basePart
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function formatGeneration(incomePerSecond: number): string
	return CompactNumberFormatter.FormatPerSecond(incomePerSecond)
end

local function formatMultiplierNumber(value: number): string
	local roundedTenths = math.floor((value * 10) + 0.5) / 10
	if math.abs(roundedTenths - math.floor(roundedTenths + 0.0001)) < 0.0001 then
		return tostring(math.floor(roundedTenths + 0.0001))
	end
	return string.format("%.1f", roundedTenths)
end

local function formatGenerationWithMultiplier(effectiveIncomePerSecond: number, multiplier: number): string
	return ("%s (x%s)"):format(formatGeneration(effectiveIncomePerSecond), formatMultiplierNumber(multiplier))
end

local function getPlayerRebirthMultiplier(player: Player?): number
	if not player then
		return 1
	end
	local multiplier = nil
	if DataService and DataService.GetRebirthState then
		local state = DataService.GetRebirthState(player)
		multiplier = state and tonumber(state.Multiplier)
	end
	if not multiplier then
		multiplier = tonumber(player:GetAttribute("RebirthMultiplier"))
	end
	local safeMultiplier = multiplier or 1
	if safeMultiplier < 0 then
		return 0
	end
	return safeMultiplier
end

local function getBaseOwnerRebirthMultiplier(baseModel: Model?): number
	if not (baseModel and BaseService and BaseService.GetOwnerForBase) then
		return 1
	end
	return getPlayerRebirthMultiplier(BaseService.GetOwnerForBase(baseModel))
end

local function applyTextLabelStyle(label: TextLabel, text: string, color: Color3)
	label.Text = text
	label.TextColor3 = color
end

local function getMutationDisplay(mutationId: string?): (string, Color3)
	local mutation = MutationRegistry.GetById(mutationId)
	if mutation then
		return mutation.DisplayName, mutation.Color
	end
	return "Normal", Color3.fromRGB(255, 255, 255)
end

local function formatDefeatedCapturableTime(secondsRemaining: number): string
	local decimalPlaces = spawnConfig.Lifetime and spawnConfig.Lifetime.TimerDecimalPlaces or 1
	return CountdownUtils.FormatTenthsSeconds(secondsRemaining, decimalPlaces)
end

local function getSlotState(slotPart: BasePart)
	return slotStateBySlot[slotPart]
end

local function setSlotState(slotPart: BasePart, definitionId: string, mutationId: string?, level: number)
	slotStateBySlot[slotPart] = {
		DefinitionId = definitionId,
		MutationId = mutationId,
		Level = OwnedNPCLevelMath.GetLevel(level),
	}
end

local function clearSlotState(slotPart: BasePart)
	slotStateBySlot[slotPart] = nil
end

local function getLevelForSlot(slotPart: BasePart): number
	local state = getSlotState(slotPart)
	if not state then
		return OwnedNPCLevelConfig.DefaultLevel
	end
	return OwnedNPCLevelMath.GetLevel(state.Level)
end

local function getDefinitionForSlot(slotPart: BasePart)
	local state = getSlotState(slotPart)
	if not state then
		return nil
	end
	return NPCRegistry.GetDefinitionById(state.DefinitionId)
end

local function getEffectiveIncome(definition: { [string]: any }, mutationId: string?, level: number): number
	return OwnedNPCLevelMath.GetEffectiveIncome(definition.MaxHealth, definition.IncomePerSecond, mutationId, level)
end

local function getEffectiveUpgradeCost(definition: { [string]: any }, level: number): number
	return OwnedNPCLevelMath.GetUpgradeCost(definition.BaseUpgradeCost, level)
end

local function resolveUpgradeNodes(slotPart: BasePart): (GuiButton?, TextLabel?, TextLabel?)
	local slotPath = slotPart:GetFullName()
	local upgradePart = slotPart:FindFirstChild(OwnedNPCLevelConfig.UpgradePartName)
	if not (upgradePart and upgradePart:IsA("BasePart")) then
		debugWarnOnce("MissingUpgradePart::" .. slotPath, ("Slot %s missing BasePart %s"):format(slotPath, OwnedNPCLevelConfig.UpgradePartName))
		return nil, nil, nil
	end
	local upgradeGui = upgradePart:FindFirstChild(OwnedNPCLevelConfig.UpgradeGuiName)
	if not (upgradeGui and upgradeGui:IsA("SurfaceGui")) then
		debugWarnOnce("MissingUpgradeGui::" .. slotPath, ("Slot %s missing SurfaceGui %s"):format(slotPath, OwnedNPCLevelConfig.UpgradeGuiName))
		return nil, nil, nil
	end
	upgradeGui.Enabled = true
	upgradeGui.Active = true
	local button = upgradeGui:FindFirstChild(OwnedNPCLevelConfig.UpgradeButtonName)
	if not (button and button:IsA("GuiButton")) then
		debugWarnOnce("MissingUpgradeButton::" .. slotPath, ("Slot %s missing GuiButton %s"):format(slotPath, OwnedNPCLevelConfig.UpgradeButtonName))
		return nil, nil, nil
	end
	local costLabel = button:FindFirstChild(OwnedNPCLevelConfig.UpgradeCostLabelName)
	if not (costLabel and costLabel:IsA("TextLabel")) then
		return button, nil, nil
	end
	local levelChangeLabel = button:FindFirstChild(OwnedNPCLevelConfig.UpgradeLevelChangeLabelName)
	if not (levelChangeLabel and levelChangeLabel:IsA("TextLabel")) then
		return button, costLabel, nil
	end
	return button, costLabel, levelChangeLabel
end

local function updateUpgradePartForEmptySlot(slotPart: BasePart)
	local button, costLabel, levelChangeLabel = resolveUpgradeNodes(slotPart)
	if not button then
		debugWarnOnce("NoButtonEmpty::" .. slotPart:GetFullName(), ("Cannot set empty UpgradePart state; nodes missing for %s"):format(slotPart:GetFullName()))
		return
	end
	button.Active = false
	button.AutoButtonColor = false
	button:SetAttribute("UpgradeReady", false)
	if costLabel then
		costLabel.Text = OwnedNPCLevelConfig.EmptyCostText
	end
	if levelChangeLabel then
		levelChangeLabel.Text = OwnedNPCLevelConfig.EmptyLevelChangeText
	end
end

local function updateUpgradePartForSlot(slotPart: BasePart, definition: { [string]: any }, level: number)
	local button, costLabel, levelChangeLabel = resolveUpgradeNodes(slotPart)
	if not button then
		debugWarnOnce("NoButtonOccupied::" .. slotPart:GetFullName(), ("Cannot set occupied UpgradePart state; nodes missing for %s"):format(slotPart:GetFullName()))
		return
	end
	local currentLevel = OwnedNPCLevelMath.GetLevel(level)
	local atMaxLevel = OwnedNPCLevelMath.IsMaxLevel(currentLevel)
	button.Active = true
	button.AutoButtonColor = true
	button:SetAttribute("UpgradeReady", true)
	button:SetAttribute("UpgradeAtMaxLevel", atMaxLevel)
	if costLabel then
		if atMaxLevel then
			costLabel.Text = OwnedNPCLevelConfig.MaxCostText
		else
			costLabel.Text = OwnedNPCLevelMath.FormatCurrency(getEffectiveUpgradeCost(definition, currentLevel))
		end
	end
	if levelChangeLabel then
		levelChangeLabel.Text = OwnedNPCLevelMath.GetLevelChangeText(currentLevel)
	end
end

local function stopCapturedIdleAnimation(model: Model)
	local existingTrack = idleTrackByCapturedNPC[model]
	if not existingTrack then
		return
	end
	idleTrackByCapturedNPC[model] = nil
	pcall(function()
		existingTrack:Stop(0)
		existingTrack:Destroy()
	end)
end

local function playCapturedIdleAnimation(model: Model, definition: { [string]: any })
	stopCapturedIdleAnimation(model)

	local idleAnimationId = definition.IdleAnimationId
	if typeof(idleAnimationId) ~= "string" or idleAnimationId == "" then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = idleAnimationId

	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		warn(("[BaseSlotService] Failed to load idle animation %s for %s: %s"):format(idleAnimationId, model.Name, tostring(trackOrErr)))
		return
	end

	local track = trackOrErr :: AnimationTrack
	track.Looped = true
	local played, playErr = pcall(function()
		track:Play(0.1)
	end)
	if not played then
		warn(("[BaseSlotService] Failed to play idle animation %s for %s: %s"):format(idleAnimationId, model.Name, tostring(playErr)))
		track:Destroy()
		return
	end

	idleTrackByCapturedNPC[model] = track
end

local function attachCapturedBillboard(model: Model, definition: { [string]: any }, mutationId: string?, level: number, rebirthMultiplier: number?)
	local existing = model:FindFirstChild("OwnedNPCDisplay")
	local display: BillboardGui? = nil
	if existing and existing:IsA("BillboardGui") then
		display = existing
	elseif existing then
		existing:Destroy()
	end

	if not display then
		local template = resolveOwnedDisplayTemplate()
		if not template then
			return
		end
		display = template:Clone()
		display.Name = "OwnedNPCDisplay"
	end

	local anchor = getDisplayAnchor(model)
	if not anchor then
		warn(("[BaseSlotService] No anchor part for owned NPC UI (%s)"):format(model.Name))
		if display.Parent then
			display:Destroy()
		end
		return
	end

	local rarity = NPCRegistry.GetRarityDefinitions()[definition.RarityId]
	local rarityName = rarity and rarity.DisplayName or tostring(definition.RarityId)
	local rarityColor = rarity and rarity.Color or Color3.fromRGB(255, 255, 255)

	display.Adornee = anchor
	display.Parent = model

	local displayNameLabel = display:FindFirstChild("DisplayName", true)
	if displayNameLabel and displayNameLabel:IsA("TextLabel") then
		applyTextLabelStyle(displayNameLabel, definition.DisplayName, Color3.fromRGB(255, 255, 255))
	end

	local rarityLabel = display:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		applyTextLabelStyle(rarityLabel, rarityName, rarityColor)
	end

	local generationLabel = display:FindFirstChild("Generation", true)
	if generationLabel and generationLabel:IsA("TextLabel") then
		local rawIncome = getEffectiveIncome(definition, mutationId, level)
		local safeMultiplier = tonumber(rebirthMultiplier) or 1
		if safeMultiplier < 0 then
			safeMultiplier = 0
		end
		applyTextLabelStyle(generationLabel, formatGenerationWithMultiplier(rawIncome * safeMultiplier, safeMultiplier), Color3.fromRGB(130, 255, 130))
	end

	local mutationLabel = display:FindFirstChild("Mutation", true)
	if mutationLabel and mutationLabel:IsA("TextLabel") then
		local mutationName, mutationColor = getMutationDisplay(mutationId)
		applyTextLabelStyle(mutationLabel, mutationName, mutationColor)
	end

	local levelLabel = display:FindFirstChild("Level", true)
	if levelLabel and levelLabel:IsA("TextLabel") then
		applyTextLabelStyle(levelLabel, OwnedNPCLevelMath.GetLevelText(level), Color3.fromRGB(255, 255, 255))
	end
end

local function attachOrUpdateDefeatedBillboard(state: DefeatedCapturableState)
	local model = state.Model
	if not (model and model.Parent) then
		return
	end

	local definition = NPCRegistry.GetDefinitionById(state.DefinitionId)
	if not definition then
		return
	end

	local existing = model:FindFirstChild("DefeatGui")
	local display: BillboardGui? = nil
	if existing and existing:IsA("BillboardGui") then
		display = existing
	elseif existing then
		existing:Destroy()
	end

	if not display then
		local template = resolveDefeatedDisplayTemplate()
		if not template then
			return
		end
		display = template:Clone()
		display.Name = "DefeatGui"
	end

	local anchor = getDisplayAnchor(model)
	if not anchor then
		if display.Parent then
			display:Destroy()
		end
		return
	end

	local rarity = NPCRegistry.GetRarityDefinitions()[definition.RarityId]
	local rarityName = rarity and rarity.DisplayName or tostring(definition.RarityId)
	local rarityColor = rarity and rarity.Color or Color3.fromRGB(255, 255, 255)
	local mutationName, mutationColor = getMutationDisplay(state.MutationId)
	local remaining = math.max(0, state.ExpiresAt - os.clock())
	local income = getEffectiveIncome(definition, state.MutationId, OwnedNPCLevelConfig.DefaultLevel)

	display.Adornee = anchor
	display.Parent = model

	local moneyLabel = display:FindFirstChild("MoneyPS", true)
	if moneyLabel and moneyLabel:IsA("TextLabel") then
		applyTextLabelStyle(moneyLabel, formatGeneration(income), Color3.fromRGB(130, 255, 130))
	end

	local mutationLabel = display:FindFirstChild("Mutation", true)
	if mutationLabel and mutationLabel:IsA("TextLabel") then
		applyTextLabelStyle(mutationLabel, mutationName, mutationColor)
	end

	local nameLabel = display:FindFirstChild("Name", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		applyTextLabelStyle(nameLabel, definition.DisplayName, Color3.fromRGB(255, 255, 255))
	end

	local rarityLabel = display:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		applyTextLabelStyle(rarityLabel, rarityName, rarityColor)
	end

	local timeLabel = display:FindFirstChild("Time", true)
	if timeLabel and timeLabel:IsA("TextLabel") then
		applyTextLabelStyle(timeLabel, formatDefeatedCapturableTime(remaining), Color3.fromRGB(255, 255, 255))
	end
end

local function resolveBaseForSlot(slotPart: BasePart): Model?
	if not (BaseService and BaseService.GetAllBases) then
		return nil
	end
	for _, baseModel in ipairs(BaseService.GetAllBases()) do
		if slotPart:IsDescendantOf(baseModel) then
			return baseModel
		end
	end
	return nil
end

local function refreshSlotVisuals(slotPart: BasePart)
	local captured = occupancyBySlot[slotPart]
	local state = getSlotState(slotPart)
	if not captured or not captured.Parent or not state then
		updateUpgradePartForEmptySlot(slotPart)
		return
	end
	local definition = NPCRegistry.GetDefinitionById(state.DefinitionId)
	if not definition then
		updateUpgradePartForEmptySlot(slotPart)
		return
	end
	local level = OwnedNPCLevelMath.GetLevel(state.Level)
	local baseModel = resolveBaseForSlot(slotPart)
	local rebirthMultiplier = getBaseOwnerRebirthMultiplier(baseModel)
	attachCapturedBillboard(captured, definition, state.MutationId, level, rebirthMultiplier)
	updateUpgradePartForSlot(slotPart, definition, level)
end

local function disconnectCapturedLifecycle(model: Model)
	local connection = ancestryConnectionByCapturedNPC[model]
	if connection then
		connection:Disconnect()
		ancestryConnectionByCapturedNPC[model] = nil
	end
	local collisionConnection = collisionConnectionByCapturedNPC[model]
	if collisionConnection then
		collisionConnection:Disconnect()
		collisionConnectionByCapturedNPC[model] = nil
	end
	local collisionPartConnections = collisionPartConnectionByCapturedNPC[model]
	if collisionPartConnections then
		for _, partConnection in pairs(collisionPartConnections) do
			partConnection:Disconnect()
		end
		collisionPartConnectionByCapturedNPC[model] = nil
	end
end

local function bindCapturedPartCollisionLock(model: Model, part: BasePart)
	local byPart = collisionPartConnectionByCapturedNPC[model]
	if not byPart then
		byPart = {}
		collisionPartConnectionByCapturedNPC[model] = byPart
	end
	if byPart[part] then
		return
	end
	part.CanCollide = false
	byPart[part] = part:GetPropertyChangedSignal("CanCollide"):Connect(function()
		part.CanCollide = false
	end)
	part.Destroying:Connect(function()
		local existing = byPart[part]
		if existing then
			existing:Disconnect()
			byPart[part] = nil
		end
	end)
end

local function bindCapturedLifecycle(model: Model, baseModel: Model, slot: BasePart)
	disconnectCapturedLifecycle(model)
	enforceModelNonCollidable(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			bindCapturedPartCollisionLock(model, descendant)
		end
	end
	collisionConnectionByCapturedNPC[model] = model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			bindCapturedPartCollisionLock(model, descendant)
		end
	end)
	ancestryConnectionByCapturedNPC[model] = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and occupancyBySlot[slot] == model then
			occupancyBySlot[slot] = nil
			slotByCapturedNPC[model] = nil
			clearSlotState(slot)
			stopCapturedIdleAnimation(model)
			BaseIncomeService.StopIncome(slot)
			updateUpgradePartForEmptySlot(slot)
			notifySlotChanged(baseModel, slot, nil)
		end
	end)
end



local CARRY_COLLISION_GROUP = "NPC_Carried_NoCollide"
local carryCollisionGroupInitialized = false

local function ensureCarryCollisionGroupConfigured()
	if carryCollisionGroupInitialized then
		return
	end
	local registered = PhysicsService:GetRegisteredCollisionGroups()
	local exists = false
	for _, groupInfo in ipairs(registered) do
		if groupInfo.name == CARRY_COLLISION_GROUP then
			exists = true
			break
		end
	end
	if not exists then
		PhysicsService:RegisterCollisionGroup(CARRY_COLLISION_GROUP)
	end

	for _, groupInfo in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		PhysicsService:CollisionGroupSetCollidable(CARRY_COLLISION_GROUP, groupInfo.name, false)
	end
	PhysicsService:CollisionGroupSetCollidable(CARRY_COLLISION_GROUP, CARRY_COLLISION_GROUP, false)
	carryCollisionGroupInitialized = true
end

enforceModelNonCollidable = function(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end
end

local function setModelInteractionPromptsEnabled(model: Model, enabled: boolean)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = enabled
		end
	end
end


local function setModelCarryPhysics(model: Model, keepAnchored: boolean?)
	ensureCarryCollisionGroupConfigured()
	local shouldAnchor = keepAnchored == true
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant:GetAttribute("OriginalCollisionGroup") == nil then
				descendant:SetAttribute("OriginalCollisionGroup", descendant.CollisionGroup)
			end
			descendant.CollisionGroup = CARRY_COLLISION_GROUP
			descendant.Anchored = shouldAnchor
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

setModelSlottedPhysics = function(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local originalCollisionGroup = descendant:GetAttribute("OriginalCollisionGroup")
			if typeof(originalCollisionGroup) == "string" and originalCollisionGroup ~= "" then
				descendant.CollisionGroup = originalCollisionGroup
			else
				descendant.CollisionGroup = "Default"
			end
			descendant:SetAttribute("OriginalCollisionGroup", nil)
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = true
			descendant.Massless = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function getCarryRootPart(model: Model): BasePart?
	local preferred = ensurePreferredPrimaryPart(model)
	if preferred then
		return preferred
	end
	local humanoidRoot = model:FindFirstChild("HumanoidRootPart", true)
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		return humanoidRoot
	end
	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	if firstPart and firstPart:IsA("BasePart") then
		return firstPart
	end
	return nil
end

local function disconnectCarrySafetyConnections(player: Player, preserveCharacterAdded: boolean?)
	if not preserveCharacterAdded then
		local addedConn = carryCharacterAddedConnectionByPlayer[player]
		if addedConn then
			addedConn:Disconnect()
			carryCharacterAddedConnectionByPlayer[player] = nil
		end
	end

	local removingConn = carryCharacterRemovingConnectionByPlayer[player]
	if removingConn then
		removingConn:Disconnect()
		carryCharacterRemovingConnectionByPlayer[player] = nil
	end

	local diedConn = carryHumanoidDiedConnectionByPlayer[player]
	if diedConn then
		diedConn:Disconnect()
		carryHumanoidDiedConnectionByPlayer[player] = nil
	end
end

local function getCharacterRootPart(player: Player): BasePart?
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

local function attachPlacePrompt(slotPart: BasePart)
	local existing = slotPart:FindFirstChild(baseConfig.OwnedCarry.PlacePromptName)
	if existing then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = baseConfig.OwnedCarry.PlacePromptName
	prompt.ActionText = baseConfig.OwnedCarry.PlaceActionText
	prompt.ObjectText = baseConfig.OwnedCarry.PlaceObjectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = baseConfig.OwnedCarry.PlaceMaxActivationDistance
	prompt.RequiresLineOfSight = baseConfig.OwnedCarry.PlaceRequiresLineOfSight
	prompt.KeyboardKeyCode = baseConfig.OwnedCarry.PlaceKeyboardKeyCode
	prompt.UIOffset = baseConfig.OwnedCarry.PlaceUIOffset
	prompt.Enabled = not baseConfig.OwnedCarry.EnablePlacePromptOnlyWhileCarrying
	prompt.Parent = slotPart
	prompt.Triggered:Connect(function(player)
		local baseModel = nil
		local basesFolder = Workspace:FindFirstChild(baseConfig.BasesFolderName)
		local current: Instance? = slotPart
		while current and current ~= Workspace do
			if current:IsA("Model") then
				if basesFolder and current.Parent == basesFolder then
					baseModel = current
					break
				end
				if not basesFolder and BaseService and BaseService.GetAllBases then
					for _, candidate in ipairs(BaseService.GetAllBases()) do
						if candidate == current then
							baseModel = current
							break
						end
					end
					if baseModel then
						break
					end
				end
			end
			current = current.Parent
		end
		if not baseModel then
			return
		end
		handleCarryPlaceRequest(player, baseModel, slotPart)
	end)
	placePromptBySlot[slotPart] = prompt
	return prompt
end

local function setPlacementPromptsEnabledForBase(baseModel: Model, enabled: boolean)
	for _, slot in ipairs(getOrderedSlots(baseModel)) do
		local prompt = placePromptBySlot[slot] or attachPlacePrompt(slot)
		if prompt then
			prompt.Enabled = enabled
		end
	end
end

local clearCarryWelds: (model: Model?) -> ()
local reconcileSlotOccupancy: (baseModel: Model) -> ()

local function extractSlotPayload(slotPart: BasePart)
	local captured = occupancyBySlot[slotPart]
	local state = getSlotState(slotPart)
	if not captured or not captured.Parent or not state then
		return nil
	end
	return {
		Model = captured,
		DefinitionId = state.DefinitionId,
		MutationId = state.MutationId,
		Level = OwnedNPCLevelMath.GetLevel(state.Level),
	}
end


local function detachPayloadFromSlot(slotPart: BasePart, baseModel: Model?, notifyEmpty: boolean?): any
	local payload = extractSlotPayload(slotPart)
	clearSlotOccupancy(slotPart, notifyEmpty and baseModel or nil)
	if payload and payload.Model and payload.Model.Parent then
		payload.Model:SetAttribute("CapturedSlotPath", nil)
	end
	return payload
end

clearSlotOccupancy = function(slotPart: BasePart, baseModel: Model?)
	local captured = occupancyBySlot[slotPart]
	if captured then
		disconnectCapturedLifecycle(captured)
		slotByCapturedNPC[captured] = nil
	end
	occupancyBySlot[slotPart] = nil
	clearSlotState(slotPart)
	BaseIncomeService.StopIncome(slotPart)
	updateUpgradePartForEmptySlot(slotPart)
	if baseModel then
		notifySlotChanged(baseModel, slotPart, nil)
	end
end

local function placePayloadIntoSlot(baseModel: Model, slotPart: BasePart, payload): boolean
	local captured = payload.Model
	if not captured or not captured.Parent then
		return false
	end
	debugPlacementLog(captured, ("placePayloadIntoSlot start slot=%s definition=%s currentPivot=%s"):format(slotPart:GetFullName(), tostring(payload.DefinitionId), tostring(captured:GetPivot())))
	local definition = NPCRegistry.GetDefinitionById(payload.DefinitionId)
	if not definition then
		warn(("[BaseSlotService] Cannot place payload; missing definition %s"):format(tostring(payload.DefinitionId)))
		return false
	end

	captured:SetAttribute("DefinitionId", payload.DefinitionId)
	captured:SetAttribute("MutationId", payload.MutationId)
	captured:SetAttribute("Captured", true)
	captured:SetAttribute("CapturedSlotPath", slotPart:GetFullName())
	captured:SetAttribute("CarryUserId", nil)
	clearCarryWelds(captured)

	-- Final slot placement is authoritative here: do not schedule later resnaps, because
	-- animated bounding boxes can shift after idle starts and reintroduce offsets.
	if not finalizeSlotPlacement(captured, slotPart, "payload_attach") then
		return false
	end
	setModelInteractionPromptsEnabled(captured, true)

	local level = OwnedNPCLevelMath.GetLevel(payload.Level)
	local effectiveIncome = getEffectiveIncome(definition, payload.MutationId, level)
	captured:SetAttribute("IncomePerSecond", effectiveIncome)
	captured:SetAttribute("Level", level)
	setSlotState(slotPart, payload.DefinitionId, payload.MutationId, level)
	attachCapturedBillboard(captured, definition, payload.MutationId, level, getBaseOwnerRebirthMultiplier(baseModel))
	playCapturedIdleAnimation(captured, definition)
	attachDeletePrompt(captured, baseModel, slotPart)
	attachGrabPrompt(captured, baseModel, slotPart)
	updateUpgradePartForSlot(slotPart, definition, level)

	occupancyBySlot[slotPart] = captured
	slotByCapturedNPC[captured] = slotPart

	bindCapturedLifecycle(captured, baseModel, slotPart)
	BaseIncomeService.StartIncome(baseModel, slotPart, effectiveIncome)
	notifySlotChanged(baseModel, slotPart, { NpcId = payload.DefinitionId, MutationId = payload.MutationId, Level = level })
	return true
end

local function getConfiguredCarryForwardDistance(): number
	local forwardDistance = baseConfig.OwnedCarry.CarryForwardDistance
	if typeof(forwardDistance) ~= "number" then
		return 6
	end
	return forwardDistance
end

local function getConfiguredCarryUpOffset(): number
	local upOffset = baseConfig.OwnedCarry.CarryUpOffset
	if typeof(upOffset) ~= "number" then
		return 1.75
	end
	return upOffset
end

local function getCapturableLifetimeSeconds(definition: { [string]: any }): number
	return definition.CapturableLifetimeSeconds
end

local function captureCarryMotionMetadata(model: Model): CarryMotionMetadata
	local currentPivot = model:GetPivot()
	local boxCf, boxSize = model:GetBoundingBox()
	return {
		PivotToBox = currentPivot:ToObjectSpace(boxCf),
		BoxSize = boxSize,
		SafeForwardDistance = getConfiguredCarryForwardDistance() + (boxSize.Z * 0.5),
	}
end

local function getCarryTargetPivot(player: Player, carryMotion: CarryMotionMetadata): CFrame?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local desiredBoxCf = root.CFrame * CFrame.new(0, getConfiguredCarryUpOffset(), -carryMotion.SafeForwardDistance)
	return desiredBoxCf * carryMotion.PivotToBox:Inverse()
end

local function moveCarriedModelToFrontTarget(player: Player, model: Model, carryMotion: CarryMotionMetadata)
	local targetPivot = getCarryTargetPivot(player, carryMotion)
	if not targetPivot then
		return
	end
	model:PivotTo(targetPivot)
	local modelRoot = getCarryRootPart(model)
	if modelRoot then
		modelRoot.AssemblyLinearVelocity = Vector3.zero
		modelRoot.AssemblyAngularVelocity = Vector3.zero
	end
end

clearCarryWelds = function(model: Model?)
	if not model then
		return
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if (descendant:IsA("WeldConstraint") or descendant:IsA("Weld")) and (descendant.Name == CARRY_WELD_NAME or descendant.Name == CARRY_INTERNAL_WELD_NAME) then
			descendant:Destroy()
		end
	end
end

local function createInternalCarryWelds(model: Model, carryRoot: BasePart)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= carryRoot then
			local existing = descendant:FindFirstChild(CARRY_INTERNAL_WELD_NAME)
			if existing then
				existing:Destroy()
			end
			local internalWeld = Instance.new("WeldConstraint")
			internalWeld.Name = CARRY_INTERNAL_WELD_NAME
			internalWeld.Part0 = carryRoot
			internalWeld.Part1 = descendant
			internalWeld.Parent = descendant
		end
	end
end

local function attachModelToCarrierRoot(player: Player, model: Model, carryMotion: CarryMotionMetadata): WeldConstraint?
	local characterRoot = getCharacterRootPart(player)
	local modelRoot = getCarryRootPart(model)
	if not (characterRoot and modelRoot) then
		return nil
	end
	clearCarryWelds(model)
	setModelCarryPhysics(model, false)
	moveCarriedModelToFrontTarget(player, model, carryMotion)
	createInternalCarryWelds(model, modelRoot)
	local carryWeld = Instance.new("WeldConstraint")
	carryWeld.Name = CARRY_WELD_NAME
	carryWeld.Part0 = characterRoot
	carryWeld.Part1 = modelRoot
	carryWeld.Parent = modelRoot
	pcall(function()
		modelRoot:SetNetworkOwner(player)
	end)
	return carryWeld
end

local function stopCarrying(player: Player)
	local carryState = carryStateByPlayer[player]
	if not carryState then
		refreshPlayerCarryRestrictions(player)
		return
	end
	if carryState.CarryWeld then
		carryState.CarryWeld:Destroy()
		carryState.CarryWeld = nil
	end
	clearCarryWelds(carryState.Model)
	if carryState.BaseModel and baseConfig.OwnedCarry.EnablePlacePromptOnlyWhileCarrying then
		setPlacementPromptsEnabledForBase(carryState.BaseModel, false)
	end
	if carryState.Model and carryState.Model.Parent then
		debugPlacementLog(carryState.Model, ("stopCarrying player=%s sourceSlot=%s currentPivot=%s"):format(player.Name, carryState.SourceSlot and carryState.SourceSlot:GetFullName() or "<nil>", tostring(carryState.Model:GetPivot())))
		setModelCarryPhysics(carryState.Model, true)
		carryState.Model:SetAttribute("CarryUserId", nil)
		setModelInteractionPromptsEnabled(carryState.Model, true)
	end
	carryStateByPlayer[player] = nil
	refreshPlayerCarryRestrictions(player)
end

local function startCarrying(player: Player, baseModel: Model, sourceSlot: BasePart, payload)
	stopCarrying(player)
	local model = payload.Model
	if not model or not model.Parent then
		return false
	end
	setModelCarryPhysics(model, true)
	setModelInteractionPromptsEnabled(model, false)
	stopCapturedIdleAnimation(model)
	model:SetAttribute("CarryUserId", player.UserId)

	local carryMotion = captureCarryMotionMetadata(model)
	local state: CarriedOwnedNPCState = {
		Model = model,
		DefinitionId = payload.DefinitionId,
		MutationId = payload.MutationId,
		Level = payload.Level,
		SourceSlot = sourceSlot,
		BaseModel = baseModel,
		CarryMotion = carryMotion,
		CarryWeld = nil,
	}
	carryStateByPlayer[player] = state

	local targetPivot = getCarryTargetPivot(player, carryMotion)
	debugPlacementLog(model, ("startCarrying player=%s sourceSlot=%s targetCarryPivot=%s safeForwardDistance=%.3f currentPivot=%s"):format(player.Name, sourceSlot:GetFullName(), tostring(targetPivot), carryMotion.SafeForwardDistance, tostring(model:GetPivot())))
	moveCarriedModelToFrontTarget(player, model, carryMotion)

	local carryWeld = attachModelToCarrierRoot(player, model, carryMotion)
	local modelRoot = getCarryRootPart(model)
	if not (carryWeld and modelRoot) then
		stopCarrying(player)
		return false
	end

	state.CarryWeld = carryWeld
	modelRoot.AssemblyLinearVelocity = Vector3.zero
	modelRoot.AssemblyAngularVelocity = Vector3.zero

	if baseConfig.OwnedCarry.EnablePlacePromptOnlyWhileCarrying then
		setPlacementPromptsEnabledForBase(baseModel, true)
	end
	refreshPlayerCarryRestrictions(player)
	return true
end

local function ensureCarriedNPCSafePlacement(player: Player, reason: string)
	local carryState = carryStateByPlayer[player]
	if not carryState then
		return
	end
	local baseModel = carryState.BaseModel
	if not baseModel or not baseModel.Parent then
		stopCarrying(player)
		if carryState.Model and carryState.Model.Parent then
			carryState.Model:Destroy()
		end
		return
	end

	stopCarrying(player)
	debugPlacementLog(carryState.Model, ("ensureCarriedNPCSafePlacement player=%s reason=%s sourceSlot=%s"):format(player.Name, reason, carryState.SourceSlot and carryState.SourceSlot:GetFullName() or "<nil>"))
	local targetSlot = carryState.SourceSlot
	if not targetSlot or targetSlot.Parent == nil or occupancyBySlot[targetSlot] then
		targetSlot = BaseSlotService.FindFirstFreeSlot(baseModel)
	end
	if not targetSlot then
		warn(("[BaseSlotService] Failed safe placement for carried NPC (%s) in %s"):format(reason, baseModel:GetFullName()))
		if carryState.Model and carryState.Model.Parent then
			carryState.Model:Destroy()
		end
		return
	end
	placePayloadIntoSlot(baseModel, targetSlot, carryState)
end

handleCarryPlaceRequest = function(player: Player, baseModel: Model, targetSlot: BasePart)
	local function playPlaceSFX(slot: BasePart)
		GameplaySFXService.PlayForPlayer(player, "BrainrotPlace", slot.Position)
	end
	local carryState = carryStateByPlayer[player]
	if not carryState then
		return
	end
	if carryState.BaseModel ~= baseModel then
		return
	end
	if not BaseService.IsOwner(player, baseModel) then
		return
	end

	local sourceSlot = carryState.SourceSlot
	debugPlacementLog(carryState.Model, ("handleCarryPlaceRequest player=%s sourceSlot=%s targetSlot=%s currentPivot=%s"):format(player.Name, sourceSlot and sourceSlot:GetFullName() or "<nil>", targetSlot:GetFullName(), tostring(carryState.Model and carryState.Model:GetPivot() or nil)))
	local carriedPayload = {
		Model = carryState.Model,
		DefinitionId = carryState.DefinitionId,
		MutationId = carryState.MutationId,
		Level = carryState.Level,
	}
	if not carriedPayload.Model or not carriedPayload.Model.Parent then
		stopCarrying(player)
		return
	end

	stopCarrying(player)

	local targetPayload = extractSlotPayload(targetSlot)
	if not targetPayload then
		if placePayloadIntoSlot(baseModel, targetSlot, carriedPayload) then
			playPlaceSFX(targetSlot)
			return
		end
		if sourceSlot and sourceSlot.Parent and not occupancyBySlot[sourceSlot] then
			if placePayloadIntoSlot(baseModel, sourceSlot, carriedPayload) then
				playPlaceSFX(sourceSlot)
				return
			end
		end
		local fallback = BaseSlotService.FindFirstFreeSlot(baseModel)
		if fallback then
			if placePayloadIntoSlot(baseModel, fallback, carriedPayload) then
				playPlaceSFX(fallback)
				return
			end
		end
		carriedPayload.Model:Destroy()
		return
	end

	if not sourceSlot or sourceSlot.Parent == nil then
		warn(("[BaseSlotService] Swap aborted; missing source slot for player %s"):format(player.Name))
		if placePayloadIntoSlot(baseModel, targetSlot, carriedPayload) then
			playPlaceSFX(targetSlot)
		else
			carriedPayload.Model:Destroy()
		end
		return
	end

	if sourceSlot == targetSlot then
		if placePayloadIntoSlot(baseModel, targetSlot, carriedPayload) then
			playPlaceSFX(targetSlot)
		end
		return
	end

	local detachedTargetPayload = detachPayloadFromSlot(targetSlot, baseModel, true)
	if not detachedTargetPayload then
		if placePayloadIntoSlot(baseModel, targetSlot, carriedPayload) then
			playPlaceSFX(targetSlot)
		else
			carriedPayload.Model:Destroy()
		end
		return
	end

	if not placePayloadIntoSlot(baseModel, targetSlot, carriedPayload) then
		warn("[BaseSlotService] Swap attach failed for carried payload; restoring target payload")
		placePayloadIntoSlot(baseModel, targetSlot, detachedTargetPayload)
		if sourceSlot and sourceSlot.Parent and not occupancyBySlot[sourceSlot] then
			placePayloadIntoSlot(baseModel, sourceSlot, carriedPayload)
		end
		return
	end

	if not placePayloadIntoSlot(baseModel, sourceSlot, detachedTargetPayload) then
		warn("[BaseSlotService] Swap attach failed for target payload; attempting rollback")
		detachPayloadFromSlot(targetSlot, baseModel, true)
		if not placePayloadIntoSlot(baseModel, sourceSlot, carriedPayload) then
			carriedPayload.Model:Destroy()
		end
		if not placePayloadIntoSlot(baseModel, targetSlot, detachedTargetPayload) then
			detachedTargetPayload.Model:Destroy()
		end
		return
	end

	playPlaceSFX(targetSlot)
end

local function resolvePromptPart(captured: Model, preferredPartName: string, promptName: string): BasePart?
	local preferred = captured:FindFirstChild(preferredPartName, true)
	if preferred and preferred:IsA("BasePart") then
		return preferred
	end
	warn(("[BaseSlotService] %s prompt expected part '%s' on %s; falling back"):format(promptName, preferredPartName, captured:GetFullName()))
	local fallback = getDisplayAnchor(captured)
	if fallback then
		return fallback
	end
	return captured.PrimaryPart or captured:FindFirstChildWhichIsA("BasePart", true)
end

attachGrabPrompt = function(captured: Model, baseModel: Model, slotPart: BasePart)
	local adorneePart = resolvePromptPart(captured, "EPart", baseConfig.OwnedCarry.GrabPromptName)
	if not (adorneePart and adorneePart:IsA("BasePart")) then
		return
	end

	local existing = captured:FindFirstChild(baseConfig.OwnedCarry.GrabPromptName, true)
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	elseif existing then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = baseConfig.OwnedCarry.GrabPromptName
	prompt.ActionText = baseConfig.OwnedCarry.GrabActionText
	prompt.ObjectText = baseConfig.OwnedCarry.GrabObjectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = baseConfig.OwnedCarry.GrabMaxActivationDistance
	prompt.RequiresLineOfSight = baseConfig.OwnedCarry.GrabRequiresLineOfSight
	prompt.KeyboardKeyCode = baseConfig.OwnedCarry.GrabKeyboardKeyCode
	prompt.UIOffset = baseConfig.OwnedCarry.GrabUIOffset
	prompt.Parent = adorneePart

	prompt.Triggered:Connect(function(player)
		if carryStateByPlayer[player] then
			return
		end
		if BaseSlotService.IsCarryingDefeatedCapturable(player) then
			return
		end
		if not BaseService.IsOwner(player, baseModel) then
			return
		end
		if occupancyBySlot[slotPart] ~= captured then
			return
		end
		local payload = detachPayloadFromSlot(slotPart, baseModel, true)
		if not payload then
			return
		end
		if not startCarrying(player, baseModel, slotPart, payload) then
			placePayloadIntoSlot(baseModel, slotPart, payload)
			return
		end
		GameplaySFXService.PlayForPlayer(player, "BrainrotGrab", captured:GetPivot().Position)
	end)
end

local function removeCapturedNPC(slotPart: BasePart, reason: string)
	local captured = occupancyBySlot[slotPart]
	if not captured then
		clearSlotState(slotPart)
		BaseIncomeService.StopIncome(slotPart)
		updateUpgradePartForEmptySlot(slotPart)
		return false
	end

	local baseModel = slotPart:FindFirstAncestorOfClass("Model")
	if not baseModel then
		warn(("[BaseSlotService] Slot %s has no base ancestor during removal"):format(slotPart:GetFullName()))
		baseModel = captured:FindFirstAncestorOfClass("Model")
	end

	occupancyBySlot[slotPart] = nil
	slotByCapturedNPC[captured] = nil
	disconnectCapturedLifecycle(captured)
	clearSlotState(slotPart)
	stopCapturedIdleAnimation(captured)
	BaseIncomeService.StopIncome(slotPart)
	updateUpgradePartForEmptySlot(slotPart)

	if captured.Parent then
		captured:Destroy()
	end

	if baseModel then
		notifySlotChanged(baseModel, slotPart, nil)
	end
	return true
end

attachDeletePrompt = function(captured: Model, baseModel: Model, slotPart: BasePart)
	local adorneePart = resolvePromptPart(captured, "XPart", "Delete")
	if not (adorneePart and adorneePart:IsA("BasePart")) then
		warn(("[BaseSlotService] Cannot attach delete prompt; no BasePart in %s"):format(captured:GetFullName()))
		return
	end

	local existing = captured:FindFirstChild("Delete", true)
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Delete"
	prompt.ActionText = baseConfig.DeletePrompt.ActionText
	prompt.ObjectText = baseConfig.DeletePrompt.ObjectText
	prompt.HoldDuration = baseConfig.DeletePrompt.HoldDuration
	prompt.MaxActivationDistance = baseConfig.DeletePrompt.MaxActivationDistance
	prompt.RequiresLineOfSight = baseConfig.DeletePrompt.RequiresLineOfSight
	prompt.KeyboardKeyCode = baseConfig.DeletePrompt.KeyboardKeyCode
	local deleteOffset = baseConfig.DeletePrompt.UIOffset
	if baseConfig.OwnedCarry and baseConfig.OwnedCarry.DeleteUIOffsetWhenGrabEnabled then
		deleteOffset = baseConfig.OwnedCarry.DeleteUIOffsetWhenGrabEnabled
	end
	prompt.UIOffset = deleteOffset
	prompt.Parent = adorneePart

	prompt.Triggered:Connect(function(player)
		if not captured.Parent then
			return
		end
		if BaseSlotService.IsCarryingDefeatedCapturable(player) then
			return
		end
		if not BaseService.IsOwner(player, baseModel) then
			return
		end
		if occupancyBySlot[slotPart] ~= captured then
			return
		end
		removeCapturedNPC(slotPart, "prompt_delete")
	end)
end

function BaseSlotService.RefreshBaseLayout(baseModel: Model)
	reconcileSlotOccupancy(baseModel)
	for _, slot in ipairs(getOrderedSlots(baseModel)) do
		if not placePromptBySlot[slot] or placePromptBySlot[slot].Parent ~= slot then
			attachPlacePrompt(slot)
		end
		local occupant = occupancyBySlot[slot]
		local state = getSlotState(slot)
		if occupant and occupant.Parent and state then
			refreshSlotVisuals(slot)
		else
			updateUpgradePartForEmptySlot(slot)
		end
	end
	if baseConfig.OwnedCarry.EnablePlacePromptOnlyWhileCarrying then
		setPlacementPromptsEnabledForBase(baseModel, false)
		for _, carryState in pairs(carryStateByPlayer) do
			if carryState.BaseModel == baseModel then
				setPlacementPromptsEnabledForBase(baseModel, true)
				break
			end
		end
	end
end

reconcileSlotOccupancy = function(baseModel: Model)
	local knownSlots = {}
	for _, slot in ipairs(getOrderedSlots(baseModel)) do
		knownSlots[slot] = true
		local occupant = occupancyBySlot[slot]
		if occupant and occupant.Parent == nil then
			occupancyBySlot[slot] = nil
			clearSlotState(slot)
			BaseIncomeService.StopIncome(slot)
			updateUpgradePartForEmptySlot(slot)
			notifySlotChanged(baseModel, slot, nil)
		end
	end

	local capturedFolder = baseModel:FindFirstChild(baseConfig.CapturedNPCFolderName)
	if capturedFolder and capturedFolder:IsA("Folder") then
		for _, child in ipairs(capturedFolder:GetChildren()) do
			if child:IsA("Model") then
				local slotPath = child:GetAttribute("CapturedSlotPath")
				if typeof(slotPath) == "string" then
					for slot in pairs(knownSlots) do
						if slot:GetFullName() == slotPath then
							occupancyBySlot[slot] = child
							slotByCapturedNPC[child] = slot
							break
						end
					end
				end
			end
		end
	end
end

local function placeDefinitionIntoSlot(baseModel: Model, slot: BasePart, definition: { [string]: any }, isRestore: boolean, mutationId: string?, level: number?): boolean
	if occupancyBySlot[slot] and occupancyBySlot[slot].Parent then
		warn(("[BaseSlotService] Slot %s already occupied"):format(slot:GetFullName()))
		return false
	end

	local templateFolder = resolveTemplateFolder()
	if not templateFolder then
		warn("[BaseSlotService] Missing templates folder for capture/restore")
		return false
	end
	local template = NPCRegistry.ResolveTemplateModel(templateFolder, definition)
	if not template or not template:IsA("Model") then
		warn(("[BaseSlotService] Missing template %s for definition %s"):format(tostring(definition.TemplateName), tostring(definition.Id)))
		return false
	end

	local captured = template:Clone()
	sanitizeCloneConstraints(captured)
	preAnchorModel(captured)
	NPCVisualUtils.ApplyMutationColorOverride(captured, mutationId)
	captured.Name = definition.DisplayName
	captured:SetAttribute("DefinitionId", definition.Id)
	captured:SetAttribute("Captured", true)
	captured:SetAttribute("AttackRadius", definition.AttackRadius)
	captured:SetAttribute("MutationId", mutationId)
	captured:SetAttribute("CapturedSlotPath", slot:GetFullName())
	captured:SetAttribute("RestoredFromSave", isRestore)
	captured.Parent = getCapturedFolder(baseModel)
	captureSlotPlacementMetadata(captured, isRestore and "restore_clone" or "capture_clone", true)
	captureProtectedPartRestoreMetadata(captured, true)

	if not finalizeSlotPlacement(captured, slot, isRestore and "restore_attach" or "capture_attach") then
		captured:Destroy()
		return false
	end

	local currentLevel = OwnedNPCLevelMath.GetLevel(level)
	local mutatedMaxHealth, _ = MutationRegistry.ApplyMultipliers(definition.MaxHealth, definition.IncomePerSecond, mutationId)
	local effectiveIncome = getEffectiveIncome(definition, mutationId, currentLevel)
	captured:SetAttribute("MaxHealth", mutatedMaxHealth)
	captured:SetAttribute("IncomePerSecond", effectiveIncome)
	captured:SetAttribute("Level", currentLevel)
	setSlotState(slot, definition.Id, mutationId, currentLevel)
	attachCapturedBillboard(captured, definition, mutationId, currentLevel, getBaseOwnerRebirthMultiplier(baseModel))
	playCapturedIdleAnimation(captured, definition)
	attachDeletePrompt(captured, baseModel, slot)
	attachGrabPrompt(captured, baseModel, slot)
	updateUpgradePartForSlot(slot, definition, currentLevel)
	debugLog(("Initialized slot %s with level=%d income=%d mutation=%s"):format(slot.Name, currentLevel, effectiveIncome, tostring(mutationId)))

	occupancyBySlot[slot] = captured
	slotByCapturedNPC[captured] = slot
	bindCapturedLifecycle(captured, baseModel, slot)
	BaseIncomeService.StartIncome(baseModel, slot, effectiveIncome)
	notifySlotChanged(baseModel, slot, { NpcId = definition.Id, MutationId = mutationId, Level = currentLevel })
	return true
end

function BaseSlotService.RegisterSlotChangedCallback(callback: (Player?, Model, string, { [string]: any }?) -> ())
	table.insert(slotChangedCallbacks, callback)
end

function BaseSlotService.FindFirstFreeSlot(baseModel: Model): BasePart?
	reconcileSlotOccupancy(baseModel)
	for _, slot in ipairs(getOrderedSlots(baseModel)) do
		if not occupancyBySlot[slot] then
			return slot
		end
	end
	return nil
end

function BaseSlotService.GetSlotSnapshotForPlayer(player: Player): { [string]: { [string]: any } }
	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel then
		return {}
	end
	reconcileSlotOccupancy(baseModel)
	local snapshot: { [string]: { [string]: any } } = {}
	for _, slot in ipairs(getOrderedSlots(baseModel)) do
		local occupant = occupancyBySlot[slot]
		if occupant and occupant.Parent then
			local state = getSlotState(slot)
			if state then
				snapshot[slot.Name] = {
					NpcId = state.DefinitionId,
					MutationId = state.MutationId,
					Level = OwnedNPCLevelMath.GetLevel(state.Level),
				}
			end
		end
	end
	return snapshot
end

function BaseSlotService.RestoreSlotsForPlayer(player: Player, slotsData: { [string]: any })
	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel then
		warn(("[BaseSlotService] Cannot restore slots for %s without assigned base"):format(player.Name))
		return
	end
	if typeof(slotsData) ~= "table" then
		return
	end

	reconcileSlotOccupancy(baseModel)
	for slotName, slotData in pairs(slotsData) do
		if typeof(slotName) ~= "string" then
			warn(("[BaseSlotService] Invalid saved slot entry for %s"):format(player.Name))
			continue
		end

		local definitionId = nil
		local mutationId = nil
		local level = OwnedNPCLevelConfig.DefaultLevel
		if typeof(slotData) == "string" then
			definitionId = slotData
		elseif typeof(slotData) == "table" then
			if typeof(slotData.NpcId) == "string" then
				definitionId = slotData.NpcId
			end
			if typeof(slotData.MutationId) == "string" then
				mutationId = slotData.MutationId
			end
			if typeof(slotData.Level) == "number" then
				level = OwnedNPCLevelMath.GetLevel(slotData.Level)
			end
		end
		if typeof(definitionId) ~= "string" then
			warn(("[BaseSlotService] Invalid saved definition id for slot %s (%s)"):format(slotName, player.Name))
			continue
		end

		local slot = findSlotByName(baseModel, slotName)
		if not slot then
			warn(("[BaseSlotService] Saved slot %s missing in base %s"):format(slotName, baseModel:GetFullName()))
			continue
		end
		if occupancyBySlot[slot] and occupancyBySlot[slot].Parent then
			warn(("[BaseSlotService] Skip restore; slot %s already occupied"):format(slot:GetFullName()))
			continue
		end

		local definition = NPCRegistry.GetDefinitionById(definitionId)
		if not definition then
			warn(("[BaseSlotService] Saved definition %s missing for %s"):format(definitionId, player.Name))
			continue
		end

		if not placeDefinitionIntoSlot(baseModel, slot, definition, true, mutationId, level) then
			warn(("[BaseSlotService] Failed restore placement for %s in slot %s"):format(definitionId, slot:GetFullName()))
		end
	end
end

function BaseSlotService.ClearBase(baseModel: Model)
	for _, slot in ipairs(getOrderedSlots(baseModel)) do
		removeCapturedNPC(slot, "clear_base")
	end

	local capturedFolder = baseModel:FindFirstChild(baseConfig.CapturedNPCFolderName)
	if capturedFolder and capturedFolder:IsA("Folder") then
		for _, child in ipairs(capturedFolder:GetChildren()) do
			child:Destroy()
		end
	end
end

local function removeAllPromptsAndBillboards(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
end

local function fireCapturableCarryState(player: Player, visible: boolean)
	capturableCarryStateRemote:FireClient(player, {
		Visible = visible,
		CarryLocked = visible,
	})
end

local function getRedeemPart(): BasePart?
	local configuredName = baseConfig.CaptureFlow and baseConfig.CaptureFlow.RedeemPartName or nil
	if typeof(configuredName) ~= "string" or configuredName == "" then
		configuredName = "BrainrotRedeemPart"
	end
	local found = workspace:FindFirstChild(configuredName, true)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

local function isPointInsidePart(point: Vector3, part: BasePart): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end


local function addBlockedSpawnPointId(spawnPointId: string?)
	if typeof(spawnPointId) ~= "string" or spawnPointId == "" then
		return
	end
	blockedSpawnPointCountsById[spawnPointId] = (blockedSpawnPointCountsById[spawnPointId] or 0) + 1
end

local function removeBlockedSpawnPointId(spawnPointId: string?)
	if typeof(spawnPointId) ~= "string" or spawnPointId == "" then
		return
	end
	local count = blockedSpawnPointCountsById[spawnPointId]
	if not count then
		return
	end
	if count <= 1 then
		blockedSpawnPointCountsById[spawnPointId] = nil
	else
		blockedSpawnPointCountsById[spawnPointId] = count - 1
	end
end

local function clearDefeatedCapturableState(state: DefeatedCapturableState)
	if state.CarryWeld then
		state.CarryWeld:Destroy()
		state.CarryWeld = nil
	end
	clearCarryWelds(state.Model)
	if state.GrabPrompt then
		state.GrabPrompt:Destroy()
		state.GrabPrompt = nil
	end
	if state.Carrier then
		fireCapturableCarryState(state.Carrier, false)
		defeatedCapturableCarryByPlayer[state.Carrier] = nil
		refreshPlayerCarryRestrictions(state.Carrier)
		state.Carrier = nil
	end
	if state.Model then
		defeatedCapturableByModel[state.Model] = nil
		if state.Model.Parent then
			state.Model:Destroy()
		end
		state.Model = nil
	end
	removeBlockedSpawnPointId(state.SpawnPointId)
	defeatedCapturableById[state.Id] = nil
end

local function resetDefeatedCapturableToSpawn(state: DefeatedCapturableState)
	local previousCarrier = state.Carrier
	if not (state.Model and state.Model.Parent) then
		return
	end
	if state.CarryWeld then
		state.CarryWeld:Destroy()
		state.CarryWeld = nil
	end
	clearCarryWelds(state.Model)
	setModelSlottedPhysics(state.Model)
	state.Model:PivotTo(state.SpawnCFrame)
	if state.GrabPrompt then
		state.GrabPrompt.Enabled = true
	end
	if state.Carrier then
		fireCapturableCarryState(state.Carrier, false)
		defeatedCapturableCarryByPlayer[state.Carrier] = nil
		refreshPlayerCarryRestrictions(state.Carrier)
		state.Carrier = nil
	end
	if previousCarrier then
		GameplaySFXService.PlayForPlayer(previousCarrier, "BrainrotDrop", state.SpawnCFrame.Position)
	end
	state.PendingPromptPlayer = nil
end

local function expireDefeatedCapturable(state: DefeatedCapturableState)
	if state.Redeemed or state.Expired then
		debugRedeemWarn("Invalid::" .. tostring(state.Id), ("Capturable %d invalid redeemed=%s expired=%s"):format(state.Id, tostring(state.Redeemed), tostring(state.Expired)))
		return
	end
	state.Expired = true
	clearDefeatedCapturableState(state)
end

local function redeemDefeatedCapturable(player: Player, state: DefeatedCapturableState): boolean
	if state.Redeemed or state.Expired then
		return false
	end
	if state.Carrier ~= player then
		return false
	end
	if os.clock() >= state.ExpiresAt then
		expireDefeatedCapturable(state)
		return false
	end
	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel then
		return false
	end
	if not hasFreeSlotForPlayer(player) then
		fireNoFreeSlots(player)
		return false
	end
	local definition = NPCRegistry.GetDefinitionById(state.DefinitionId)
	if not definition then
		return false
	end
	if not BaseSlotService.PlaceCapturedNPC(baseModel, definition, state.MutationId) then
		fireNoFreeSlots(player)
		return false
	end
	GameplaySFXService.PlayForPlayer(player, "BrainrotPlace", baseModel:GetPivot().Position)
	state.Redeemed = true
	clearDefeatedCapturableState(state)
	return true
end

local function tryPromptRedeemForCarrier(player: Player)
	local state = defeatedCapturableCarryByPlayer[player]
	if not state then
		debugRedeemWarn("NoState::" .. player.Name, ("No carried capturable for %s"):format(player.Name))
		return
	end
	if state.PendingPromptPlayer then
		debugRedeemWarn("Pending::" .. tostring(state.Id), ("Capturable %d already has pending prompt for %s"):format(state.Id, state.PendingPromptPlayer.Name))
		return
	end
	if state.Redeemed or state.Expired then
		return
	end
	if os.clock() >= state.ExpiresAt then
		debugRedeemWarn("Expired::" .. tostring(state.Id), ("Capturable %d expired before prompt"):format(state.Id))
		expireDefeatedCapturable(state)
		return
	end

	local debounce = baseConfig.CaptureFlow and baseConfig.CaptureFlow.RedeemTouchDebounceSeconds or 1
	if typeof(debounce) ~= "number" or debounce < 0 then
		debounce = 1
	end
	local now = os.clock()
	local nextAllowed = redeemTouchDebounceByPlayer[player] or 0
	if now < nextAllowed then
		return
	end
	redeemTouchDebounceByPlayer[player] = now + debounce

	local definition = NPCRegistry.GetDefinitionById(state.DefinitionId)
	if not definition then
		debugRedeemWarn("NoDef::" .. tostring(state.Id), ("Missing definition for capturable %d id=%s"):format(state.Id, tostring(state.DefinitionId)))
		return
	end
	state.PendingPromptPlayer = player
	debugRedeemWarn("Prompted::" .. tostring(state.Id), ("Prompting redeem for player=%s capturable=%d part-touch verified"):format(player.Name, state.Id))
	enqueuePendingCapture(player, definition, state.MutationId, state.Id)
end

local function attachDefeatedCapturableGrabPrompt(state: DefeatedCapturableState)
	if not (state.Model and state.Model.Parent) then
		return
	end
	if state.GrabPrompt then
		state.GrabPrompt:Destroy()
	end
	local adornee = state.Model.PrimaryPart or state.Model:FindFirstChildWhichIsA("BasePart", true)
	if not (adornee and adornee:IsA("BasePart")) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DefeatedCapturableGrab"
	prompt.ActionText = baseConfig.OwnedCarry.GrabActionText
	prompt.ObjectText = baseConfig.OwnedCarry.GrabObjectText
	prompt.HoldDuration = capturableFlowConfig.GrabHoldDurationSeconds
	prompt.MaxActivationDistance = baseConfig.OwnedCarry.GrabMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = baseConfig.OwnedCarry.GrabKeyboardKeyCode
	prompt.Parent = adornee
	prompt.Triggered:Connect(function(player)
		if state.Redeemed or state.Expired then
			return
		end
		if os.clock() >= state.ExpiresAt then
			expireDefeatedCapturable(state)
			return
		end
		if state.Carrier and state.Carrier ~= player then
			return
		end
		if defeatedCapturableCarryByPlayer[player] and defeatedCapturableCarryByPlayer[player] ~= state then
			return
		end

		state.Carrier = player
		defeatedCapturableCarryByPlayer[player] = state
		state.PendingPromptPlayer = nil

		local carryWeld = attachModelToCarrierRoot(player, state.Model, state.CarryMotion)
		local modelRoot = getCarryRootPart(state.Model)
		if not (carryWeld and modelRoot) then
			resetDefeatedCapturableToSpawn(state)
			return
		end
		state.CarryWeld = carryWeld
		modelRoot.AssemblyLinearVelocity = Vector3.zero
		modelRoot.AssemblyAngularVelocity = Vector3.zero
		if state.GrabPrompt then
			state.GrabPrompt.Enabled = false
		end
		GameplaySFXService.PlayForPlayer(player, "BrainrotGrab", state.Model:GetPivot().Position)
		fireCapturableCarryState(player, true)
		refreshPlayerCarryRestrictions(player)
	end)
	state.GrabPrompt = prompt
end

local function spawnDefeatedCapturable(definition: { [string]: any }, mutationId: string?, spawnCFrame: CFrame, spawnPointId: string?)
	local templateFolder = resolveTemplateFolder()
	if not templateFolder then
		return
	end
	local template = NPCRegistry.ResolveTemplateModel(templateFolder, definition)
	if not (template and template:IsA("Model")) then
		return
	end
	local model = template:Clone()
	sanitizeCloneConstraints(model)
	preAnchorModel(model)
	removeAllPromptsAndBillboards(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
	model.Name = definition.DisplayName .. "_Defeated"
	model:SetAttribute("DefinitionId", definition.Id)
	model:SetAttribute("MutationId", mutationId)
	model:SetAttribute("Captured", false)
	model:SetAttribute("CarryUserId", nil)
	NPCVisualUtils.ApplyMutationColorOverride(model, mutationId)
	local defeatedFolder = workspace:FindFirstChild("DefeatedCapturables")
	if not (defeatedFolder and defeatedFolder:IsA("Folder")) then
		defeatedFolder = Instance.new("Folder")
		defeatedFolder.Name = "DefeatedCapturables"
		defeatedFolder.Parent = workspace
	end
	model.Parent = defeatedFolder
	model:PivotTo(spawnCFrame)
	setModelSlottedPhysics(model)

	defeatedCapturableId += 1
	local lifetime = getCapturableLifetimeSeconds(definition)
	local timerInterval = spawnConfig.Lifetime and spawnConfig.Lifetime.TimerUpdateIntervalSeconds or 0.1
	local state: DefeatedCapturableState = {
		Id = defeatedCapturableId,
		DefinitionId = definition.Id,
		MutationId = mutationId,
		DisplayName = definition.DisplayName,
		SpawnCFrame = spawnCFrame,
		ExpiresAt = CountdownUtils.AlignExpiryTime(os.clock(), lifetime, timerInterval),
		Model = model,
		Carrier = nil,
		CarryMotion = captureCarryMotionMetadata(model),
		CarryWeld = nil,
		Redeemed = false,
		Expired = false,
		PendingPromptPlayer = nil,
		GrabPrompt = nil,
		SpawnPointId = spawnPointId,
		TransitionBusy = false,
	}
	defeatedCapturableById[state.Id] = state
	defeatedCapturableByModel[model] = state
	addBlockedSpawnPointId(spawnPointId)
	attachOrUpdateDefeatedBillboard(state)
	attachDefeatedCapturableGrabPrompt(state)
	capturableLifecycleRemote:FireAllClients({ Type = "DefeatedCapturableSpawned", Position = spawnCFrame.Position })
end

local function handleDefeatedCapturableDropRequest(player: Player)
	local state = defeatedCapturableCarryByPlayer[player]
	if not state then
		return
	end
	if state.Redeemed or state.Expired then
		return
	end
	resetDefeatedCapturableToSpawn(state)
end

function BaseSlotService.PlaceCapturedNPC(baseModel: Model, definition: { [string]: any }, mutationId: string?): boolean
	local slot = BaseSlotService.FindFirstFreeSlot(baseModel)
	if not slot then
		warn(("[BaseSlotService] No free slot in base %s"):format(baseModel:GetFullName()))
		return false
	end
	return placeDefinitionIntoSlot(baseModel, slot, definition, false, mutationId, OwnedNPCLevelConfig.DefaultLevel)
end

function BaseSlotService.HandleNPCDeath(npcModel: Model, lastHitter: Player?)
	if handledNpcDeathsByModel[npcModel] then
		return
	end
	handledNpcDeathsByModel[npcModel] = true

	local definitionId = npcModel:GetAttribute("DefinitionId")
	if typeof(definitionId) ~= "string" then
		warn("[BaseSlotService] Defeated NPC missing DefinitionId")
		return
	end
	local definition = NPCRegistry.GetDefinitionById(definitionId)
	if not definition then
		warn(("[BaseSlotService] Missing definition for defeated NPC %s"):format(definitionId))
		return
	end
	local mutationId = npcModel:GetAttribute("MutationId")
	local spawnPointId = npcModel:GetAttribute("SpawnPointId")
	if typeof(spawnPointId) ~= "string" then
		spawnPointId = nil
	end
	local deathCFrame = npcModel:GetPivot()
	capturableLifecycleRemote:FireAllClients({
		Type = "DefeatedVFXHook",
		Position = deathCFrame.Position,
		DefinitionId = definitionId,
		MutationId = typeof(mutationId) == "string" and mutationId or nil,
	})

	local delaySeconds = baseConfig.CaptureFlow and baseConfig.CaptureFlow.DefeatedRespawnDelaySeconds or 2
	if typeof(delaySeconds) ~= "number" or delaySeconds < 0 then
		delaySeconds = 2
	end
	task.delay(delaySeconds, function()
		spawnDefeatedCapturable(definition, typeof(mutationId) == "string" and mutationId or nil, deathCFrame, spawnPointId)
		capturableLifecycleRemote:FireAllClients({
			Type = "DefeatedSpawnSFXHook",
			Position = deathCFrame.Position,
			DefinitionId = definitionId,
			MutationId = typeof(mutationId) == "string" and mutationId or nil,
		})
	end)
end



local function trySpendPlayerMoney(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end
	if DataService and DataService.TrySpendMoney then
		return DataService.TrySpendMoney(player, amount)
	end
	return false
end

local function onUpgradeRequest(player: Player, payload)
	if typeof(payload) ~= "table" then
		debugLog(("Ignored upgrade request: payload is %s"):format(typeof(payload)))
		return
	end
	local slotName = payload.SlotName
	if typeof(slotName) ~= "string" then
		debugLog(("Ignored upgrade request: SlotName invalid type=%s"):format(typeof(slotName)))
		return
	end
	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel then
		debugLog(("Player %s has no base for upgrade slot=%s"):format(player.Name, slotName))
		return
	end
	if not BaseService.IsOwner(player, baseModel) then
		debugLog(("Player %s is not owner of base %s"):format(player.Name, baseModel:GetFullName()))
		return
	end
	local slot = findSlotByName(baseModel, slotName)
	if not slot then
		warn(("[BaseSlotService] Upgrade request invalid slot %s for %s"):format(tostring(slotName), player.Name))
		return
	end
	local button = select(1, resolveUpgradeNodes(slot))
	if button and button:GetAttribute("UpgradeReady") == false then
		debugLog(("Slot %s not ready for upgrade (UpgradeReady=false)"):format(slot.Name))
		fireUpgradeFeedback(player, { Type = "NotReady", SlotName = slotName })
		return
	end
	local occupant = occupancyBySlot[slot]
	local state = getSlotState(slot)
	if not occupant or not occupant.Parent or not state then
		debugLog(("Slot %s has no valid occupant/state"):format(slot.Name))
		updateUpgradePartForEmptySlot(slot)
		return
	end
	local occupantDefinitionId = occupant:GetAttribute("DefinitionId")
	if typeof(occupantDefinitionId) ~= "string" or occupantDefinitionId ~= state.DefinitionId then
		debugLog(("Slot %s definition mismatch. occupant=%s state=%s"):format(slot.Name, tostring(occupantDefinitionId), tostring(state.DefinitionId)))
		return
	end
	local definition = NPCRegistry.GetDefinitionById(state.DefinitionId)
	if not definition then
		debugLog(("Missing definition for state id %s on slot %s"):format(tostring(state.DefinitionId), slot.Name))
		return
	end

	local currentLevel = OwnedNPCLevelMath.GetLevel(state.Level)
	state.Level = currentLevel
	occupant:SetAttribute("Level", currentLevel)
	if OwnedNPCLevelMath.IsMaxLevel(currentLevel) then
		debugLog(("Upgrade denied (max level) for %s slot %s level %d"):format(player.Name, slot.Name, currentLevel))
		refreshSlotVisuals(slot)
		fireUpgradeFeedback(player, {
			Type = "MaxLevel",
			SlotName = slotName,
			Level = currentLevel,
		})
		return
	end
	local currentCost = getEffectiveUpgradeCost(definition, currentLevel)
	if not trySpendPlayerMoney(player, currentCost) then
		warn(("[BaseSlotService] Upgrade denied (insufficient funds) for %s slot %s cost %d"):format(player.Name, slot.Name, currentCost))
		fireUpgradeFeedback(player, {
			Type = "InsufficientFunds",
			SlotName = slotName,
			Cost = currentCost,
		})
		return
	end

	local newLevel = OwnedNPCLevelMath.GetNextLevel(currentLevel)
	state.Level = newLevel
	occupant:SetAttribute("Level", newLevel)
	local effectiveIncome = getEffectiveIncome(definition, state.MutationId, newLevel)
	occupant:SetAttribute("IncomePerSecond", effectiveIncome)
	BaseIncomeService.UpdateIncomeRate(slot, effectiveIncome)
	refreshSlotVisuals(slot)
	notifySlotChanged(baseModel, slot, { NpcId = state.DefinitionId, MutationId = state.MutationId, Level = newLevel })
	fireUpgradeFeedback(player, {
		Type = "Upgraded",
		SlotName = slotName,
		Level = newLevel,
		Income = effectiveIncome,
		Cost = currentCost,
	})
	debugLog(("Upgrade success player=%s slot=%s level %d->%d income=%d cost=%d"):format(player.Name, slot.Name, currentLevel, newLevel, effectiveIncome, currentCost))
end

local function onCaptureDecision(player: Player, payload)
	if typeof(payload) ~= "table" then
		return
	end
	local captureId = payload.CaptureId
	local decision = payload.Decision
	if typeof(captureId) ~= "number" or typeof(decision) ~= "string" then
		return
	end

	local pending = resolvePendingCaptureById(player, captureId)
	if not pending then
		return
	end

	if pending.CapturableId then
		debugRedeemWarn("Decision::" .. player.Name, ("Capture decision from %s id=%s decision=%s"):format(player.Name, tostring(pending.CapturableId), tostring(decision)))
		local state = defeatedCapturableById[pending.CapturableId]
		if state then
			state.PendingPromptPlayer = nil
		end
		if state then
			if decision == "Yes" then
				redeemDefeatedCapturable(player, state)
			else
				resetDefeatedCapturableToSpawn(state)
			end
		end
		pumpCapturePrompt(player)
		return
	end

	if decision ~= "Yes" then
		pumpCapturePrompt(player)
		return
	end

	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel then
		fireNoFreeSlots(player)
		pumpCapturePrompt(player)
		return
	end

	if not hasFreeSlotForPlayer(player) then
		fireNoFreeSlots(player)
		pumpCapturePrompt(player)
		return
	end

	local definition = NPCRegistry.GetDefinitionById(pending.DefinitionId)
	if not definition then
		warn(("[BaseSlotService] Pending capture definition missing: %s"):format(tostring(pending.DefinitionId)))
		pumpCapturePrompt(player)
		return
	end

	if not BaseSlotService.PlaceCapturedNPC(baseModel, definition, pending.MutationId) then
		fireNoFreeSlots(player)
	end

	pumpCapturePrompt(player)
end

function BaseSlotService.IsSpawnPointBlocked(spawnPointId: string?): boolean
	if typeof(spawnPointId) ~= "string" or spawnPointId == "" then
		return false
	end
	return (blockedSpawnPointCountsById[spawnPointId] or 0) > 0
end

function BaseSlotService.IsCarryingDefeatedCapturable(player: Player): boolean
	local state = defeatedCapturableCarryByPlayer[player]
	return state ~= nil and not state.Redeemed and not state.Expired
end

function BaseSlotService.IsCarryingAnyBrainrot(player: Player): boolean
	return carryStateByPlayer[player] ~= nil or BaseSlotService.IsCarryingDefeatedCapturable(player)
end

function BaseSlotService.RefreshOwnedGenerationDisplaysForPlayer(player: Player)
	if not (BaseService and BaseService.GetBaseForPlayer) then
		return
	end
	local baseModel = BaseService.GetBaseForPlayer(player)
	if not baseModel then
		return
	end
	for slotPart, _ in pairs(occupancyBySlot) do
		if slotPart:IsDescendantOf(baseModel) then
			refreshSlotVisuals(slotPart)
		end
	end
end

function BaseSlotService.ReleaseDefeatedCapturableForContest(player: Player, reason: string?): boolean
	local state = defeatedCapturableCarryByPlayer[player]
	if not state then
		return false
	end
	if state.Redeemed or state.Expired then
		return false
	end
	if state.Carrier ~= player then
		return false
	end
	if state.TransitionBusy then
		return false
	end
	state.TransitionBusy = true
	local now = os.clock()
	if now >= state.ExpiresAt then
		state.TransitionBusy = false
		expireDefeatedCapturable(state)
		return false
	end
	resetDefeatedCapturableToSpawn(state)
	state.TransitionBusy = false
	debugRedeemWarn("ContestRelease::" .. player.Name, ("Contest release for %s capturable=%d reason=%s"):format(player.Name, state.Id, tostring(reason)))
	return true
end

function BaseSlotService.SetDataService(dataService)
	DataService = dataService
end

function BaseSlotService.Init(baseService, baseIncomeService)
	BaseService = baseService
	BaseIncomeService = baseIncomeService


	for _, baseModel in ipairs(BaseService.GetAllBases()) do
		BaseSlotService.RefreshBaseLayout(baseModel)
	end

	captureDecisionRemote.OnServerEvent:Connect(onCaptureDecision)
	upgradeRequestRemote.OnServerEvent:Connect(onUpgradeRequest)
	capturableDropRequestRemote.OnServerEvent:Connect(function(player)
		handleDefeatedCapturableDropRequest(player)
	end)
	debugLog(("Listening for remote %s and feedback %s"):format(OwnedNPCLevelConfig.RemoteEventName, OwnedNPCLevelConfig.UpgradeFeedbackRemoteEventName))

	NPCStateService.RegisterDeathCallback(function(npcModel, _spawnPoint, lastHitter)
		BaseSlotService.HandleNPCDeath(npcModel, lastHitter)
	end)

	local redeemPart = getRedeemPart()
	if not redeemPart then
		warn("[BaseSlotService] Redeem part not found; capturable redemption touch disabled")
	end


	if redeemDetectionHeartbeatConnection then
		redeemDetectionHeartbeatConnection:Disconnect()
		redeemDetectionHeartbeatConnection = nil
	end
	redeemDetectionHeartbeatConnection = RunService.Heartbeat:Connect(function()
		local activeRedeemPart = getRedeemPart()
		if not activeRedeemPart then
			return
		end

		for player, state in pairs(defeatedCapturableCarryByPlayer) do
			if state and not state.Redeemed and not state.Expired then
				local root = getCharacterRootPart(player)
				local playerInside = root and isPointInsidePart(root.Position, activeRedeemPart)
				if playerInside then
					debugRedeemWarn("Touch::" .. tostring(state.Id), ("Redeem overlap detected player=%s capturable=%d part=%s anchored=%s canCollide=%s"):format(player.Name, state.Id, activeRedeemPart:GetFullName(), tostring(activeRedeemPart.Anchored), tostring(activeRedeemPart.CanCollide)))
					tryPromptRedeemForCarrier(player)
				end
			end
		end
	end)

	BaseService.RegisterReleaseCallback(function(player, baseModel)
		ensureCarriedNPCSafePlacement(player, "base_release")
		cleanupPendingForPlayer(player)
		BaseSlotService.ClearBase(baseModel)
		BaseIncomeService.StopAllForBase(baseModel)
	end)

	local function bindCarrySafetyForCharacter(player: Player, character: Model)
		disconnectCarrySafetyConnections(player, true)
		refreshPlayerCarryRestrictions(player)

		carryCharacterRemovingConnectionByPlayer[player] = player.CharacterRemoving:Connect(function(removingCharacter)
			if removingCharacter ~= character then
				return
			end
			ensureCarriedNPCSafePlacement(player, "character_removing")
			local defeatedState = defeatedCapturableCarryByPlayer[player]
			if defeatedState then
				resetDefeatedCapturableToSpawn(defeatedState)
			end
			disconnectCarrySafetyConnections(player, true)
		end)

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			carryHumanoidDiedConnectionByPlayer[player] = humanoid.Died:Connect(function()
				ensureCarriedNPCSafePlacement(player, "humanoid_died")
				local defeatedState = defeatedCapturableCarryByPlayer[player]
				if defeatedState then
					resetDefeatedCapturableToSpawn(defeatedState)
				end
			end)
		end
	end

	local function bindCarryResetSafety(player: Player)
		refreshPlayerCarryRestrictions(player)
		if rebirthDisplayRefreshConnectionByPlayer[player] then
			rebirthDisplayRefreshConnectionByPlayer[player]:Disconnect()
		end
		rebirthDisplayRefreshConnectionByPlayer[player] = player:GetAttributeChangedSignal("RebirthMultiplier"):Connect(function()
			BaseSlotService.RefreshOwnedGenerationDisplaysForPlayer(player)
		end)
		BaseSlotService.RefreshOwnedGenerationDisplaysForPlayer(player)
		if carryCharacterAddedConnectionByPlayer[player] then
			carryCharacterAddedConnectionByPlayer[player]:Disconnect()
		end
		carryCharacterAddedConnectionByPlayer[player] = player.CharacterAdded:Connect(function(character)
			ensureCarriedNPCSafePlacement(player, "character_added")
			local defeatedState = defeatedCapturableCarryByPlayer[player]
			if defeatedState then
				resetDefeatedCapturableToSpawn(defeatedState)
			end
			bindCarrySafetyForCharacter(player, character)
			refreshPlayerCarryRestrictions(player)
		end)

		if player.Character then
			bindCarrySafetyForCharacter(player, player.Character)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bindCarryResetSafety(player)
	end
	Players.PlayerAdded:Connect(bindCarryResetSafety)

	Players.PlayerRemoving:Connect(function(player)
		ensureCarriedNPCSafePlacement(player, "player_leaving")
		cleanupPendingForPlayer(player)
		redeemTouchDebounceByPlayer[player] = nil
		local defeatedState = defeatedCapturableCarryByPlayer[player]
		if defeatedState then
			resetDefeatedCapturableToSpawn(defeatedState)
		end
		clearTemporaryCarrySpeedPenalty(player)
		player:SetAttribute(getCarryModeAttributeName(), "None")
		player:SetAttribute(getOwnedPlacePromptActiveAttributeName(), false)
		player:SetAttribute(getToolsLockedAttributeName(), false)
		disconnectCarrySafetyConnections(player)
		local rebirthDisplayConnection = rebirthDisplayRefreshConnectionByPlayer[player]
		if rebirthDisplayConnection then
			rebirthDisplayConnection:Disconnect()
			rebirthDisplayRefreshConnectionByPlayer[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			local interval = spawnConfig.Lifetime and spawnConfig.Lifetime.TimerUpdateIntervalSeconds or 0.1
			if typeof(interval) ~= "number" or interval <= 0 then
				interval = 0.1
			end
			task.wait(interval)
			for player, _ in pairs(pendingCaptureQueueByPlayer) do
				pumpCapturePrompt(player)
			end
			local now = os.clock()
			for _, state in pairs(defeatedCapturableById) do
				if not state.Redeemed and not state.Expired then
					if now >= state.ExpiresAt then
						expireDefeatedCapturable(state)
					else
						attachOrUpdateDefeatedBillboard(state)
					end
				end
			end
		end
	end)
end

return BaseSlotService
