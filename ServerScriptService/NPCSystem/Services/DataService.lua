local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local baseConfig = require(ReplicatedStorage.NPCSystem.Config.BaseConfig)
local BigNumber = require(ReplicatedStorage.NPCSystem.Shared.BigNumber)
local OwnedNPCLevelMath = require(ReplicatedStorage.NPCSystem.Shared.OwnedNPCLevelMath)
local BaseUpgradeProgression = require(ReplicatedStorage.NPCSystem.Shared.BaseUpgradeProgression)

local DataService = {}
DataService.__index = DataService

type SaveData = {
	Money: string,
	Slots: { [string]: any },
	BaseUpgrades: number,
	RebirthIndex: number,
	RebirthMultiplier: number,
}

type SessionEntry = {
	Data: SaveData,
	Dirty: boolean,
	SaveScheduled: boolean,
	CanPersist: boolean,
	Loaded: boolean,
	Restored: boolean,
}

local persistenceConfig = baseConfig.Persistence
local dataStore = DataStoreService:GetDataStore(persistenceConfig.DataStoreName)

local BaseService = nil
local BaseSlotService = nil
local BaseCollectionService = nil
local BaseUpgradeService = nil
local moneySnapshotFunction: RemoteFunction? = nil

local sessionByPlayer: { [Player]: SessionEntry } = {}
local BASE_ASSIGNMENT_RETRY_TIMEOUT_SECONDS = 8
local BASE_ASSIGNMENT_RETRY_INTERVAL_SECONDS = 0.1
local warnedMissingBaseSlotMethods: { [string]: boolean } = {}
local registeredBaseSlotChangedCallback = false
local deepCopySlots: (slots: { [string]: any }) -> { [string]: any }
local onSlotChanged: (player: Player?, _baseModel: Model, slotName: string, slotData: { [string]: any }?) -> ()

local function warnMissingBaseSlotMethod(methodName: string)
	if warnedMissingBaseSlotMethods[methodName] then
		return
	end
	warnedMissingBaseSlotMethods[methodName] = true
	warn(("[DataService] BaseSlotService missing %s"):format(methodName))
end

local function getBaseSlotServiceMethod(methodName: string): ((...any) -> ...any)?
	if not BaseSlotService then
		warnMissingBaseSlotMethod(methodName)
		return nil
	end
	local method = BaseSlotService[methodName]
	if typeof(method) ~= "function" then
		warnMissingBaseSlotMethod(methodName)
		return nil
	end
	return method
end

local function getSlotSnapshotForPlayer(player: Player): { [string]: any }
	local method = getBaseSlotServiceMethod("GetSlotSnapshotForPlayer")
	if not method then
		local session = sessionByPlayer[player]
		return session and deepCopySlots(session.Data.Slots) or {}
	end
	local snapshot = method(player)
	return typeof(snapshot) == "table" and snapshot or {}
end

local function restoreSlotsForPlayer(player: Player, slotsData: { [string]: any })
	local method = getBaseSlotServiceMethod("RestoreSlotsForPlayer")
	if not method then
		return
	end
	method(player, slotsData)
end

local function connectBaseSlotChangedCallback()
	if registeredBaseSlotChangedCallback then
		return
	end
	local registerCallback = getBaseSlotServiceMethod("RegisterSlotChangedCallback")
	if registerCallback then
		registerCallback(onSlotChanged)
		registeredBaseSlotChangedCallback = true
	end
end

local function scheduleBaseSlotChangedCallbackRetry()
	task.spawn(function()
		local deadline = os.clock() + BASE_ASSIGNMENT_RETRY_TIMEOUT_SECONDS
		while not registeredBaseSlotChangedCallback and os.clock() < deadline do
			connectBaseSlotChangedCallback()
			if registeredBaseSlotChangedCallback then
				return
			end
			task.wait(BASE_ASSIGNMENT_RETRY_INTERVAL_SECONDS)
		end
	end)
end

deepCopySlots = function(slots: { [string]: any }): { [string]: any }
	local clone: { [string]: any } = {}
	if typeof(slots) ~= "table" then
		return clone
	end
	for slotName, slotData in pairs(slots) do
		if typeof(slotName) ~= "string" then
			continue
		end
		if typeof(slotData) == "string" and slotData ~= "" then
			clone[slotName] = slotData
		elseif typeof(slotData) == "table" and typeof(slotData.NpcId) == "string" and slotData.NpcId ~= "" then
			clone[slotName] = {
				NpcId = slotData.NpcId,
				MutationId = typeof(slotData.MutationId) == "string" and slotData.MutationId or nil,
				Level = OwnedNPCLevelMath.GetLevel(slotData.Level),
			}
		end
	end
	return clone
end

local function makeDefaultData(): SaveData
	return {
		Money = "0",
		Slots = {},
		BaseUpgrades = 0,
		RebirthIndex = 0,
		RebirthMultiplier = 1,
	}
end

local function sanitizeRebirthMultiplier(value: any): number
	local asNumber = tonumber(value)
	if not asNumber or asNumber ~= asNumber or asNumber == math.huge or asNumber == -math.huge then
		return 1
	end
	if asNumber < 0 then
		return 0
	end
	return asNumber
end

local function sanitizeLoadedData(raw: any): SaveData
	local sanitized = makeDefaultData()
	if typeof(raw) ~= "table" then
		return sanitized
	end

	local money = raw.Money
	if money ~= nil then
		sanitized.Money = BigNumber.Sanitize(money)
	end

	sanitized.Slots = deepCopySlots(raw.Slots)
	sanitized.BaseUpgrades = BaseUpgradeProgression.ClampUpgradeCount(raw.BaseUpgrades)
	sanitized.RebirthIndex = math.max(0, math.floor(tonumber(raw.RebirthIndex) or 0))
	sanitized.RebirthMultiplier = sanitizeRebirthMultiplier(raw.RebirthMultiplier)
	return sanitized
end

local function getDataStoreKey(player: Player): string
	return persistenceConfig.KeyPrefix .. tostring(player.UserId)
end

local function getRetryDelay(attempt: number): number
	return persistenceConfig.InitialBackoffSeconds * (2 ^ (attempt - 1))
end

local function ensureLeaderstatsMoneyDisplay(player: Player): IntValue?
	local folderName = baseConfig.Currency.LeaderstatsFolderName
	local statName = baseConfig.Currency.StatName
	local createIfMissing = baseConfig.Currency.CreateIfMissing

	local leaderstats = player:FindFirstChild(folderName)
	if not leaderstats and createIfMissing then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = folderName
		leaderstats.Parent = player
	end
	if not leaderstats then
		return nil
	end

	local stat = leaderstats:FindFirstChild(statName)
	if not stat and createIfMissing then
		stat = Instance.new("IntValue")
		stat.Name = statName
		stat.Value = 0
		stat.Parent = leaderstats
	end
	if not stat or not stat:IsA("IntValue") then
		return nil
	end

	return stat
end

local function applyMoneyDisplay(player: Player, moneyString: string)
	local safeMoney = BigNumber.Sanitize(moneyString)
	player:SetAttribute("MoneyString", safeMoney)

	local moneyStat = ensureLeaderstatsMoneyDisplay(player)
	if moneyStat then
		moneyStat.Value = BigNumber.ToDisplayNumber(safeMoney, 9_000_000_000_000_000_000)
	end
end

local function readLatestSnapshot(player: Player): SaveData
	local session = sessionByPlayer[player]
	if not session then
		return makeDefaultData()
	end

	local snapshot: SaveData = {
		Money = BigNumber.Sanitize(session.Data.Money),
		Slots = deepCopySlots(session.Data.Slots),
		BaseUpgrades = BaseUpgradeProgression.ClampUpgradeCount(session.Data.BaseUpgrades),
		RebirthIndex = math.max(0, math.floor(tonumber(session.Data.RebirthIndex) or 0)),
		RebirthMultiplier = sanitizeRebirthMultiplier(session.Data.RebirthMultiplier),
	}

	snapshot.Slots = getSlotSnapshotForPlayer(player)
	if BaseUpgradeService and BaseUpgradeService.GetUpgradeCountForPlayer then
		snapshot.BaseUpgrades = BaseUpgradeService.GetUpgradeCountForPlayer(player)
	end

	return snapshot
end

local function loadFromDataStore(player: Player): (boolean, SaveData)
	local key = getDataStoreKey(player)
	for attempt = 1, persistenceConfig.MaxRetries do
		local success, result = pcall(function()
			return dataStore:GetAsync(key)
		end)
		if success then
			return true, sanitizeLoadedData(result)
		end
		warn(("[DataService] GetAsync failed for %s (attempt %d/%d): %s"):format(player.Name, attempt, persistenceConfig.MaxRetries, tostring(result)))
		if attempt < persistenceConfig.MaxRetries then
			task.wait(getRetryDelay(attempt))
		end
	end
	return false, makeDefaultData()
end

local function saveToDataStore(player: Player, snapshot: SaveData): boolean
	local key = getDataStoreKey(player)
	for attempt = 1, persistenceConfig.MaxRetries do
		local success, updateError = pcall(function()
			dataStore:UpdateAsync(key, function(existing)
				local old = sanitizeLoadedData(existing)
				local nextData: SaveData = {
					Money = old.Money,
					Slots = old.Slots,
					BaseUpgrades = old.BaseUpgrades,
					RebirthIndex = old.RebirthIndex,
					RebirthMultiplier = old.RebirthMultiplier,
				}
				nextData.Money = BigNumber.Sanitize(snapshot.Money)
				nextData.Slots = deepCopySlots(snapshot.Slots)
				nextData.BaseUpgrades = BaseUpgradeProgression.ClampUpgradeCount(snapshot.BaseUpgrades)
				nextData.RebirthIndex = math.max(0, math.floor(tonumber(snapshot.RebirthIndex) or 0))
				nextData.RebirthMultiplier = sanitizeRebirthMultiplier(snapshot.RebirthMultiplier)
				return nextData
			end)
		end)
		if success then
			return true
		end
		warn(("[DataService] UpdateAsync failed for %s (attempt %d/%d): %s"):format(player.Name, attempt, persistenceConfig.MaxRetries, tostring(updateError)))
		if attempt < persistenceConfig.MaxRetries then
			task.wait(getRetryDelay(attempt))
		end
	end
	return false
end

local function markDirtyAndScheduleSave(player: Player)
	local session = sessionByPlayer[player]
	if not session or not session.CanPersist then
		return
	end
	session.Dirty = true
	if session.SaveScheduled then
		return
	end
	session.SaveScheduled = true

	task.delay(persistenceConfig.SaveDebounceSeconds, function()
		local latest = sessionByPlayer[player]
		if not latest then
			return
		end
		latest.SaveScheduled = false
		if not latest.Dirty or not latest.CanPersist then
			return
		end
		local snapshot = readLatestSnapshot(player)
		if saveToDataStore(player, snapshot) then
			latest.Data = snapshot
			latest.Dirty = false
		end
	end)
end

function DataService.IsLoaded(player: Player): boolean
	local session = sessionByPlayer[player]
	return session ~= nil and session.Loaded == true
end

function DataService.GetMoneyString(player: Player): string
	local session = sessionByPlayer[player]
	if not session then
		return "0"
	end
	return BigNumber.Sanitize(session.Data.Money)
end

function DataService.SetMoney(player: Player, amount: any)
	local session = sessionByPlayer[player]
	if not session then
		return
	end
	session.Data.Money = BigNumber.Sanitize(amount)
	applyMoneyDisplay(player, session.Data.Money)
	markDirtyAndScheduleSave(player)
end

function DataService.AddMoney(player: Player, amount: any)
	local session = sessionByPlayer[player]
	if not session then
		return
	end
	local addend = BigNumber.Sanitize(amount)
	if addend == "0" then
		return
	end
	local multiplier = sanitizeRebirthMultiplier(session.Data.RebirthMultiplier)
	if multiplier > 0 and multiplier ~= 1 then
		local scaledMultiplier = math.max(0, math.floor((multiplier * 1000) + 0.5))
		if scaledMultiplier == 0 then
			addend = "0"
		elseif scaledMultiplier ~= 1000 then
			local function multiplyByInt(digits: string, factor: number): string
				if digits == "0" or factor <= 0 then
					return "0"
				end
				local i = #digits
				local carry = 0
				local out = table.create(#digits + 16)
				while i > 0 or carry > 0 do
					local d = 0
					if i > 0 then
						d = string.byte(digits, i) - 48
						i -= 1
					end
					local p = (d * factor) + carry
					carry = math.floor(p / 10)
					table.insert(out, 1, string.char(48 + (p % 10)))
				end
				return BigNumber.Sanitize(table.concat(out))
			end
			local function divideByInt(digits: string, divisor: number): string
				if digits == "0" or divisor <= 0 then
					return "0"
				end
				local remainder = 0
				local out = table.create(#digits)
				for i = 1, #digits do
					local d = string.byte(digits, i) - 48
					local value = (remainder * 10) + d
					local q = math.floor(value / divisor)
					remainder = value - (q * divisor)
					table.insert(out, string.char(48 + q))
				end
				return BigNumber.Sanitize(table.concat(out))
			end
			addend = divideByInt(multiplyByInt(addend, scaledMultiplier), 1000)
		end
	end
	if addend == "0" then
		return
	end
	session.Data.Money = BigNumber.Add(session.Data.Money, addend)
	applyMoneyDisplay(player, session.Data.Money)
	markDirtyAndScheduleSave(player)
end

function DataService.TrySpendMoney(player: Player, amount: any): boolean
	local session = sessionByPlayer[player]
	if not session then
		return false
	end
	local cost = BigNumber.Sanitize(amount)
	if cost == "0" then
		return true
	end
	if BigNumber.Compare(session.Data.Money, cost) < 0 then
		return false
	end
	session.Data.Money = BigNumber.Subtract(session.Data.Money, cost)
	applyMoneyDisplay(player, session.Data.Money)
	markDirtyAndScheduleSave(player)
	return true
end

local function tryRestoreLoadedBaseState(player: Player): boolean
	local session = sessionByPlayer[player]
	if not session or session.Restored or not session.Loaded then
		return false
	end
	local assignedBase = BaseService.GetBaseForPlayer(player) or BaseService.BindPlayer(player)
	if not assignedBase then
		return false
	end
	if BaseUpgradeService and BaseUpgradeService.RestoreBaseForPlayer then
		BaseUpgradeService.RestoreBaseForPlayer(player, session.Data.BaseUpgrades)
	end
	restoreSlotsForPlayer(player, session.Data.Slots)
	session.Restored = true
	session.Data.Slots = getSlotSnapshotForPlayer(player)
	if BaseUpgradeService and BaseUpgradeService.GetUpgradeCountForPlayer then
		session.Data.BaseUpgrades = BaseUpgradeService.GetUpgradeCountForPlayer(player)
	end
	return true
end

local function ensureBaseAssignedForPlayer(player: Player)
	local assignedBase = BaseService.GetBaseForPlayer(player) or BaseService.BindPlayer(player)
	if assignedBase then
		tryRestoreLoadedBaseState(player)
		return
	end

	task.spawn(function()
		local deadline = os.clock() + BASE_ASSIGNMENT_RETRY_TIMEOUT_SECONDS
		while player.Parent and os.clock() < deadline do
			local resolvedBase = BaseService.GetBaseForPlayer(player) or BaseService.BindPlayer(player)
			if resolvedBase then
				tryRestoreLoadedBaseState(player)
				return
			end
			task.wait(BASE_ASSIGNMENT_RETRY_INTERVAL_SECONDS)
		end
		if player.Parent and not BaseService.GetBaseForPlayer(player) then
			warn(("[DataService] Timed out waiting to assign base for %s"):format(player.Name))
		end
	end)
end

local function loadAndRestorePlayer(player: Player)
	sessionByPlayer[player] = {
		Data = makeDefaultData(),
		Dirty = false,
		SaveScheduled = false,
		CanPersist = false,
		Loaded = false,
		Restored = false,
	}

	applyMoneyDisplay(player, "0")
	ensureBaseAssignedForPlayer(player)

	task.spawn(function()
		local loaded, data = loadFromDataStore(player)
		local session = sessionByPlayer[player]
		if not session then
			return
		end

			session.Data = data
			session.CanPersist = loaded
			session.Loaded = true
			session.Restored = false
			player:SetAttribute("RebirthIndex", data.RebirthIndex)
			player:SetAttribute("RebirthMultiplier", data.RebirthMultiplier)

		if not loaded then
			warn(("[DataService] Persistence unavailable for %s this session; data will not be saved to avoid wipes"):format(player.Name))
		end

		applyMoneyDisplay(player, data.Money)
		if not tryRestoreLoadedBaseState(player) then
			ensureBaseAssignedForPlayer(player)
		end
	end)
end

function DataService.SaveNow(player: Player): boolean
	local session = sessionByPlayer[player]
	if not session then
		return false
	end
	if not session.CanPersist then
		return false
	end

	local snapshot = readLatestSnapshot(player)
	local saved = saveToDataStore(player, snapshot)
	if saved then
		session.Data = snapshot
		session.Dirty = false
	end
	return saved
end

function DataService.GetRebirthState(player: Player): { Index: number, Multiplier: number }
	local session = sessionByPlayer[player]
	if not session then
		return {
			Index = 0,
			Multiplier = 1,
		}
	end
	return {
		Index = math.max(0, math.floor(tonumber(session.Data.RebirthIndex) or 0)),
		Multiplier = sanitizeRebirthMultiplier(session.Data.RebirthMultiplier),
	}
end

function DataService.SetRebirthState(player: Player, rebirthIndex: number, rebirthMultiplier: number)
	local session = sessionByPlayer[player]
	if not session then
		return
	end
	session.Data.RebirthIndex = math.max(0, math.floor(tonumber(rebirthIndex) or 0))
	session.Data.RebirthMultiplier = sanitizeRebirthMultiplier(rebirthMultiplier)
	player:SetAttribute("RebirthIndex", session.Data.RebirthIndex)
	player:SetAttribute("RebirthMultiplier", session.Data.RebirthMultiplier)
	markDirtyAndScheduleSave(player)
end

onSlotChanged = function(player: Player?, _baseModel: Model, slotName: string, slotData: { [string]: any }?)
	if not player then
		return
	end
	local session = sessionByPlayer[player]
	if not session then
		return
	end
	if slotData and typeof(slotData.NpcId) == "string" then
		session.Data.Slots[slotName] = {
			NpcId = slotData.NpcId,
			MutationId = typeof(slotData.MutationId) == "string" and slotData.MutationId or nil,
			Level = OwnedNPCLevelMath.GetLevel(slotData.Level),
		}
	else
		session.Data.Slots[slotName] = nil
	end
	markDirtyAndScheduleSave(player)
end

local function cleanupPlayerSession(player: Player)
	sessionByPlayer[player] = nil
end

function DataService.Init(baseService, baseSlotService, baseCollectionService, baseUpgradeService)
	BaseService = baseService
	BaseSlotService = baseSlotService
	BaseCollectionService = baseCollectionService
	BaseUpgradeService = baseUpgradeService

	if BaseSlotService and BaseSlotService.SetDataService then
		BaseSlotService.SetDataService(DataService)
	else
		warn("[DataService] BaseSlotService missing SetDataService")
	end
	connectBaseSlotChangedCallback()
	if not registeredBaseSlotChangedCallback then
		scheduleBaseSlotChangedCallbackRetry()
	end
	if BaseCollectionService and BaseCollectionService.SetDataService then
		BaseCollectionService.SetDataService(DataService)
	else
		warn("[DataService] BaseCollectionService missing SetDataService")
	end
	if BaseUpgradeService then
		if BaseUpgradeService.SetDataService then
			BaseUpgradeService.SetDataService(DataService)
		else
			warn("[DataService] BaseUpgradeService missing SetDataService")
		end
		if BaseUpgradeService.RegisterChangedCallback then
			BaseUpgradeService.RegisterChangedCallback(function(player, _baseModel, upgradeCount)
				local session = sessionByPlayer[player]
				if not session then
					return
				end
				session.Data.BaseUpgrades = BaseUpgradeProgression.ClampUpgradeCount(upgradeCount)
				markDirtyAndScheduleSave(player)
			end)
		else
			warn("[DataService] BaseUpgradeService missing RegisterChangedCallback")
		end
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Remotes")
	local remoteName = baseConfig.Remotes.MoneySnapshotFunctionName
	local existing = remotesFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		moneySnapshotFunction = existing
	elseif existing then
		existing:Destroy()
		moneySnapshotFunction = nil
	end
	if not moneySnapshotFunction then
		moneySnapshotFunction = Instance.new("RemoteFunction")
		moneySnapshotFunction.Name = remoteName
		moneySnapshotFunction.Parent = remotesFolder
	end
	moneySnapshotFunction.OnServerInvoke = function(player: Player)
		return DataService.GetMoneyString(player)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		loadAndRestorePlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		loadAndRestorePlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		DataService.SaveNow(player)
		BaseService.UnbindPlayer(player)
		cleanupPlayerSession(player)
	end)

	game:BindToClose(function()
		local deadline = os.clock() + persistenceConfig.ShutdownSaveTimeoutSeconds
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.SaveNow(player)
		end
		while os.clock() < deadline do
			local anyScheduled = false
			for _, session in pairs(sessionByPlayer) do
				if session.SaveScheduled then
					anyScheduled = true
					break
				end
			end
			if not anyScheduled then
				break
			end
			task.wait(0.1)
		end
	end)
end

return DataService
