local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local miningRoot = ReplicatedStorage:WaitForChild("Mining")
local configFolder = miningRoot:WaitForChild("Config")

local MiningConfig = require(configFolder:WaitForChild("MiningConfig"))

local MineGenerationService = require(script.Parent:WaitForChild("MineGenerationService"))
local BlockStateService = require(script.Parent:WaitForChild("BlockStateService"))

local MiningValidationService = {}

local requestMineBlockRemote: RemoteEvent? = nil
local isResettingCallback: (() -> boolean)? = nil
local mineCooldownByUserId: { [number]: number } = {}

local function hasEquippedPickaxe(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local tool = character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool.Name == "Pickaxe"
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end
	return nil
end

local function validateRequest(player: Player, target: Instance?): Instance?
	if isResettingCallback and isResettingCallback() then
		return nil
	end

	if not hasEquippedPickaxe(player) then
		return nil
	end

	local now = os.clock()
	local previousRequestAt = mineCooldownByUserId[player.UserId] or 0
	if now - previousRequestAt < MiningConfig.MineRequestCooldown then
		return nil
	end
	mineCooldownByUserId[player.UserId] = now

	local blockInstance = BlockStateService.ResolveMineBlockFromInstance(target)
	if not blockInstance or not blockInstance.Parent then
		return nil
	end

	local blockRecord = BlockStateService.GetRecord(blockInstance)
	if not blockRecord then
		return nil
	end

	if blockRecord.cycleId ~= MineGenerationService.GetCurrentCycleId() then
		return nil
	end

	if blockRecord.currentDurability <= 0 then
		return nil
	end

	local rootPart = getCharacterRoot(player)
	if not rootPart then
		return nil
	end

	local targetPosition
	if blockInstance:IsA("BasePart") then
		targetPosition = blockInstance.Position
	elseif blockInstance:IsA("Model") then
		local primaryPart = blockInstance.PrimaryPart or blockInstance:FindFirstChildWhichIsA("BasePart")
		if not primaryPart then
			return nil
		end
		targetPosition = primaryPart.Position
	else
		return nil
	end

	if (rootPart.Position - targetPosition).Magnitude > MiningConfig.MaxMineDistance then
		return nil
	end

	return blockInstance
end

function MiningValidationService.Init(remote: RemoteEvent, resetCallback: (() -> boolean)?)
	requestMineBlockRemote = remote
	isResettingCallback = resetCallback

	requestMineBlockRemote.OnServerEvent:Connect(function(player, target)
		local validBlock = validateRequest(player, target)
		if not validBlock then
			return
		end
		BlockStateService.ApplyDamage(validBlock, MiningConfig.PickaxeDamage)
	end)

	Players.PlayerRemoving:Connect(function(player)
		mineCooldownByUserId[player.UserId] = nil
	end)
end

return MiningValidationService
