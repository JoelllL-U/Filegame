local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local player = Players.LocalPlayer
local npcSystem = ReplicatedStorage:WaitForChild("NPCSystem")
local baseConfig = require(npcSystem:WaitForChild("Config"):WaitForChild("BaseConfig"))
local config = require(ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Config"):WaitForChild("NPCSpawnConfig"))
local remotesFolder = npcSystem:WaitForChild("Remotes")
local damageRemote = remotesFolder:WaitForChild(config.Damage.RemoteEventName)
local carryRestrictionsConfig = baseConfig.CarryRestrictions or {}
local toolsLockedAttributeName = carryRestrictionsConfig.ToolsLockedAttributeName or "BrainrotCarryToolsLocked"

local toolConnections: { [Tool]: RBXScriptConnection } = {}
local satchelControllerCache = nil

local function isSatchelController(candidate: any): boolean
	return typeof(candidate) == "table"
		and typeof(candidate.SetBackpackEnabled) == "function"
		and typeof(candidate.OpenClose) == "function"
end

local function callSatchelMethod(controller, methodName: string, ...): (boolean, any)
	local method = controller and controller[methodName]
	if typeof(method) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(method, controller, ...)
	if ok then
		return true, result
	end
	return pcall(method, ...)
end

local function readSatchelOpenState(controller): boolean?
	local state = controller and controller.IsOpen
	if typeof(state) == "boolean" then
		return state
	end
	if typeof(state) == "function" then
		local ok, result = callSatchelMethod(controller, "IsOpen")
		if ok and typeof(result) == "boolean" then
			return result
		end
	end

	local visible = controller and controller.Visible
	if typeof(visible) == "boolean" then
		return visible
	end
	local opened = controller and controller.Opened
	if typeof(opened) == "boolean" then
		return opened
	end
	return nil
end

local function findSatchelModuleIn(container: Instance?): any
	if not container then
		return nil
	end
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("ModuleScript") and string.find(string.lower(descendant.Name), "satchel", 1, true) then
			local ok, result = pcall(require, descendant)
			if ok and isSatchelController(result) then
				return result
			end
		end
	end
	return nil
end

local function resolveSatchelController(): any
	if isSatchelController(satchelControllerCache) then
		return satchelControllerCache
	end

	local globalSatchel = rawget(_G, "Satchel")
	if isSatchelController(globalSatchel) then
		satchelControllerCache = globalSatchel
		return satchelControllerCache
	end

	local sharedSatchel = rawget(shared, "Satchel")
	if isSatchelController(sharedSatchel) then
		satchelControllerCache = sharedSatchel
		return satchelControllerCache
	end

	local fromPlayerScripts = findSatchelModuleIn(player:FindFirstChild("PlayerScripts"))
	if isSatchelController(fromPlayerScripts) then
		satchelControllerCache = fromPlayerScripts
		return satchelControllerCache
	end

	local fromStarterPlayerScripts = findSatchelModuleIn(StarterPlayer:FindFirstChild("StarterPlayerScripts"))
	if isSatchelController(fromStarterPlayerScripts) then
		satchelControllerCache = fromStarterPlayerScripts
		return satchelControllerCache
	end

	local fromReplicatedStorage = findSatchelModuleIn(ReplicatedStorage)
	if isSatchelController(fromReplicatedStorage) then
		satchelControllerCache = fromReplicatedStorage
		return satchelControllerCache
	end

	return nil
end

local function setSatchelBackpackEnabled(enabled: boolean)
	local controller = resolveSatchelController()
	if not controller then
		return
	end
	callSatchelMethod(controller, "SetBackpackEnabled", enabled)
end

local function closeSatchelIfOpen()
	local controller = resolveSatchelController()
	if not controller then
		return
	end
	local isOpen = readSatchelOpenState(controller)
	if isOpen == true then
		callSatchelMethod(controller, "OpenClose")
	end
end

local function shouldBindTool(tool: Tool): boolean
	return tool:GetAttribute("NPCCombatTool") == true
		or tool:GetAttribute("ShopManagedWeapon") == true
		or typeof(tool:GetAttribute("Damage")) == "number"
		or typeof(tool:GetAttribute("AttackRange")) == "number"
end

local function buildAttackPayload(): { [string]: any }
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return {
		CameraCFrame = camera and camera.CFrame or nil,
		CameraLookVector = camera and camera.CFrame.LookVector or nil,
		Origin = root and root.Position or nil,
	}
end

local function areToolsLocked(): boolean
	return player:GetAttribute(toolsLockedAttributeName) == true
end

local function applyToolCarryLockState()
	local toolsLocked = areToolsLocked()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if toolsLocked then
		closeSatchelIfOpen()
		setSatchelBackpackEnabled(false)
		if humanoid then
			humanoid:UnequipTools()
		end
		return
	end
	setSatchelBackpackEnabled(true)
end

local function bindTool(tool: Tool)
	if toolConnections[tool] then
		return
	end
	toolConnections[tool] = tool.Activated:Connect(function()
		if areToolsLocked() then
			return
		end
		if not shouldBindTool(tool) then
			return
		end
		damageRemote:FireServer(tool, buildAttackPayload())
	end)
	tool.Destroying:Connect(function()
		local connection = toolConnections[tool]
		if connection then
			connection:Disconnect()
			toolConnections[tool] = nil
		end
	end)
end

local function scan(container: Instance?)
	if not container then
		return
	end
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Tool") then
			bindTool(descendant)
		end
	end
end

local function onCharacterAdded(character: Model)
	applyToolCarryLockState()
	scan(character)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Tool") then
			bindTool(descendant)
		end
	end)
end

local backpack = player:WaitForChild("Backpack")
scan(backpack)
backpack.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Tool") then
		bindTool(descendant)
	end
end)

local playerScripts = player:WaitForChild("PlayerScripts")
playerScripts.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ModuleScript") and string.find(string.lower(descendant.Name), "satchel", 1, true) then
		satchelControllerCache = nil
		applyToolCarryLockState()
	end
end)

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
player:GetAttributeChangedSignal(toolsLockedAttributeName):Connect(applyToolCarryLockState)
applyToolCarryLockState()
