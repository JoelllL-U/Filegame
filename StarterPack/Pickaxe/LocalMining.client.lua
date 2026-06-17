local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local tool = script.Parent

local miningRoot = ReplicatedStorage:WaitForChild("Mining")
local configFolder = miningRoot:WaitForChild("Config")
local shared = miningRoot:WaitForChild("Shared")
local remotesFolder = miningRoot:WaitForChild("Remotes")

local MiningConfig = require(configFolder:WaitForChild("MiningConfig"))
local MiningConstants = require(shared:WaitForChild("MiningConstants"))
local requestMineBlock = remotesFolder:WaitForChild(MiningConfig.References.RequestMineBlockRemoteName)

local highlight: Highlight? = nil
local hoverBlock: Instance? = nil
local lastClickAt = 0
local equipped = false
local renderConnection: RBXScriptConnection? = nil

local function ensureHighlight(): Highlight
	if highlight and highlight.Parent then
		return highlight
	end

	highlight = Instance.new("Highlight")
	highlight.Name = "MiningHoverHighlight"
	highlight.FillTransparency = MiningConfig.Highlight.FillTransparency
	highlight.OutlineTransparency = MiningConfig.Highlight.OutlineTransparency
	highlight.OutlineColor = MiningConfig.Highlight.OutlineColor
	highlight.DepthMode = MiningConfig.Highlight.DepthMode
	highlight.Enabled = false
	highlight.Parent = tool
	return highlight
end

local function clearHover()
	hoverBlock = nil
	if highlight then
		highlight.Adornee = nil
		highlight.Enabled = false
	end
end

local function resolveMineBlock(target: Instance?): Instance?
	local cursor = target
	while cursor do
		if cursor:GetAttribute(MiningConstants.Attributes.IsMineBlock) == true then
			return cursor
		end
		cursor = cursor.Parent
	end
	return nil
end

local function updateHover()
	if not equipped then
		clearHover()
		return
	end

	local target = mouse.Target
	local block = resolveMineBlock(target)
	if not block or block:GetAttribute(MiningConstants.Attributes.CurrentDurability) == nil then
		clearHover()
		return
	end

	if block:GetAttribute(MiningConstants.Attributes.CurrentDurability) <= 0 then
		clearHover()
		return
	end

	hoverBlock = block
	local currentHighlight = ensureHighlight()
	currentHighlight.Adornee = block
	currentHighlight.Enabled = true
end

local function tryMine()
	if not equipped then
		return
	end
	if not hoverBlock or not hoverBlock.Parent then
		clearHover()
		return
	end

	local now = os.clock()
	if now - lastClickAt < MiningConfig.MineRequestCooldown then
		return
	end
	lastClickAt = now
	requestMineBlock:FireServer(hoverBlock)
end

local function onEquipped()
	equipped = true
	ensureHighlight()
	if renderConnection then
		renderConnection:Disconnect()
	end
	renderConnection = RunService.RenderStepped:Connect(updateHover)
end

local function onUnequipped()
	equipped = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	clearHover()
end

tool.Equipped:Connect(onEquipped)
tool.Unequipped:Connect(onUnequipped)
tool.Activated:Connect(tryMine)

script.Destroying:Connect(function()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end)
