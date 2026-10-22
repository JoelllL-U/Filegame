local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local miningRoot = ReplicatedStorage:WaitForChild("Mining")
local configFolder = miningRoot:WaitForChild("Config")
local shared = miningRoot:WaitForChild("Shared")

local MiningConfig = require(configFolder:WaitForChild("MiningConfig"))
local MiningConstants = require(shared:WaitForChild("MiningConstants"))

local BlockStateService = require(script.Parent:WaitForChild("BlockStateService"))

local MineGenerationService = {}

local currentCycleId = 0
local isGenerating = false

local function getMineVolume(): BasePart?
	local mineVolume = Workspace:FindFirstChild(MiningConfig.References.MineVolumeName)
	if mineVolume and mineVolume:IsA("BasePart") then
		return mineVolume
	end
	return nil
end

local function getGeneratedFolder(): Folder
	local folder = Workspace:FindFirstChild(MiningConfig.References.GeneratedFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = MiningConfig.References.GeneratedFolderName
	folder.Parent = Workspace
	return folder
end

local function getTemplates(): { Instance }
	local templateRoot = miningRoot:FindFirstChild(MiningConfig.References.TemplateFolderName)
	if not templateRoot or not templateRoot:IsA("Folder") then
		return {}
	end

	local templates = {}
	for _, child in ipairs(templateRoot:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Model") then
			templates[#templates + 1] = child
		end
	end

	return templates
end

local function getCellCounts(size: Vector3, blockSize: Vector3, spacing: Vector3): Vector3int16
	local stepX = blockSize.X + spacing.X
	local stepY = blockSize.Y + spacing.Y
	local stepZ = blockSize.Z + spacing.Z
	local epsilon = 1e-5

	if stepX <= 0 or stepY <= 0 or stepZ <= 0 then
		return Vector3int16.new(0, 0, 0)
	end

	local xCount = math.max(0, math.floor(((size.X + spacing.X) / stepX) + epsilon))
	local yCount = math.max(0, math.floor(((size.Y + spacing.Y) / stepY) + epsilon))
	local zCount = math.max(0, math.floor(((size.Z + spacing.Z) / stepZ) + epsilon))
	return Vector3int16.new(xCount, yCount, zCount)
end

local function getTemplateDurability(template: Instance): number
	local maxDurability = template:GetAttribute(MiningConstants.Attributes.MaxDurability)
	if typeof(maxDurability) == "number" and maxDurability > 0 then
		return maxDurability
	end
	return MiningConfig.DefaultDurability
end

local function placeClone(clone: Instance, cellCFrame: CFrame)
	if clone:IsA("BasePart") then
		clone.Size = MiningConfig.BlockSize
		clone.Anchored = true
		clone.CFrame = cellCFrame
	elseif clone:IsA("Model") then
		local modelPart = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
		if not modelPart then
			return false
		end
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		clone:PivotTo(cellCFrame)
	else
		return false
	end
	return true
end

function MineGenerationService.GetCurrentCycleId(): number
	return currentCycleId
end

function MineGenerationService.ClearMineBlocks()
	local folder = getGeneratedFolder()
	BlockStateService.ClearAll()
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

function MineGenerationService.RegenerateMine(): boolean
	if isGenerating then
		return false
	end
	isGenerating = true

	MineGenerationService.ClearMineBlocks()

	local mineVolume = getMineVolume()
	if not mineVolume then
		warn("MineVolume missing or invalid; mine generation skipped")
		isGenerating = false
		return false
	end

	local templates = getTemplates()
	if #templates == 0 then
		warn("No valid templates found in ReplicatedStorage/Mining/BlockTemplates")
		isGenerating = false
		currentCycleId += 1
		return false
	end

	currentCycleId += 1
	local folder = getGeneratedFolder()
	local counts = getCellCounts(mineVolume.Size, MiningConfig.BlockSize, MiningConfig.GridSpacing)

	local step = MiningConfig.BlockSize + MiningConfig.GridSpacing
	local startOffset = Vector3.new(
		(-mineVolume.Size.X / 2) + (MiningConfig.BlockSize.X / 2),
		(-mineVolume.Size.Y / 2) + (MiningConfig.BlockSize.Y / 2),
		(-mineVolume.Size.Z / 2) + (MiningConfig.BlockSize.Z / 2)
	)

	for x = 0, counts.X - 1 do
		for y = 0, counts.Y - 1 do
			for z = 0, counts.Z - 1 do
				local template = templates[math.random(1, #templates)]
				local clone = template:Clone()
				local localOffset = Vector3.new(startOffset.X + (x * step.X), startOffset.Y + (y * step.Y), startOffset.Z + (z * step.Z))
				local targetCFrame = mineVolume.CFrame * CFrame.new(localOffset)

				if placeClone(clone, targetCFrame) then
					clone.Parent = folder
					BlockStateService.RegisterBlock(clone, getTemplateDurability(template), currentCycleId)
				else
					clone:Destroy()
				end
			end
		end
	end

	isGenerating = false
	return true
end

return MineGenerationService
