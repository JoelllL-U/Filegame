local ReplicatedStorage = game:GetService("ReplicatedStorage")

local miningRoot = ReplicatedStorage:WaitForChild("Mining")
local shared = miningRoot:WaitForChild("Shared")
local uiFolder = miningRoot:WaitForChild("UI")

local MiningConstants = require(shared:WaitForChild("MiningConstants"))
local BlockHealthBillboard = require(uiFolder:WaitForChild("BlockHealthBillboard"))

local attributes = MiningConstants.Attributes

local BlockStateService = {}

local blockRecords: { [Instance]: any } = {}

local function resolveAdornee(blockInstance: Instance): BasePart?
	if blockInstance:IsA("BasePart") then
		return blockInstance
	end
	if blockInstance:IsA("Model") then
		return blockInstance.PrimaryPart or blockInstance:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function setDurabilityAttributes(blockInstance: Instance, maxDurability: number, currentDurability: number, cycleId: number)
	blockInstance:SetAttribute(attributes.IsMineBlock, true)
	blockInstance:SetAttribute(attributes.MaxDurability, maxDurability)
	blockInstance:SetAttribute(attributes.CurrentDurability, currentDurability)
	blockInstance:SetAttribute(attributes.MineCycleId, cycleId)
end

function BlockStateService.RegisterBlock(blockInstance: Instance, maxDurability: number, cycleId: number): boolean
	if blockRecords[blockInstance] then
		return false
	end
	if maxDurability <= 0 then
		maxDurability = 1
	end

	if blockInstance:IsA("BasePart") then
		blockInstance.Anchored = true
	elseif blockInstance:IsA("Model") then
		for _, descendant in ipairs(blockInstance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
	else
		return false
	end

	local adornee = resolveAdornee(blockInstance)
	if not adornee then
		return false
	end

	setDurabilityAttributes(blockInstance, maxDurability, maxDurability, cycleId)

	local healthUi = BlockHealthBillboard.Create(adornee)
	healthUi.Parent = blockInstance
	BlockHealthBillboard.Update(healthUi, maxDurability, maxDurability)

	local record = {
		instance = blockInstance,
		maxDurability = maxDurability,
		currentDurability = maxDurability,
		cycleId = cycleId,
		healthUi = healthUi,
		connections = {},
	}

	record.connections[#record.connections + 1] = blockInstance.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			BlockStateService.UnregisterBlock(blockInstance)
		end
	end)

	blockRecords[blockInstance] = record
	return true
end

function BlockStateService.UnregisterBlock(blockInstance: Instance)
	local record = blockRecords[blockInstance]
	if not record then
		return
	end

	for _, connection in ipairs(record.connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end

	if record.healthUi then
		record.healthUi:Destroy()
	end

	blockRecords[blockInstance] = nil
end

function BlockStateService.ResolveMineBlockFromInstance(target: Instance?): Instance?
	local cursor = target
	while cursor do
		if cursor:GetAttribute(attributes.IsMineBlock) == true then
			return cursor
		end
		cursor = cursor.Parent
	end
	return nil
end

function BlockStateService.GetRecord(blockInstance: Instance)
	return blockRecords[blockInstance]
end

function BlockStateService.ApplyDamage(blockInstance: Instance, damage: number): (boolean, number)
	local record = blockRecords[blockInstance]
	if not record or damage <= 0 then
		return false, 0
	end
	if not blockInstance.Parent then
		BlockStateService.UnregisterBlock(blockInstance)
		return false, 0
	end
	if record.currentDurability <= 0 then
		return false, 0
	end

	record.currentDurability = math.max(0, record.currentDurability - damage)
	blockInstance:SetAttribute(attributes.CurrentDurability, record.currentDurability)
	BlockHealthBillboard.Update(record.healthUi, record.currentDurability, record.maxDurability)

	if record.currentDurability <= 0 then
		BlockStateService.UnregisterBlock(blockInstance)
		blockInstance:Destroy()
	end

	return true, record.currentDurability
end

function BlockStateService.ClearAll()
	for blockInstance, _ in pairs(blockRecords) do
		if blockInstance and blockInstance.Parent then
			blockInstance:Destroy()
		end
		BlockStateService.UnregisterBlock(blockInstance)
	end
end

return BlockStateService
