local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local npcSystemFolder = ReplicatedStorage:WaitForChild("NPCSystem")
local baseConfig = require(npcSystemFolder.Config.BaseConfig)
local levelConfig = require(npcSystemFolder.Config.OwnedNPCLevelConfig)
local CompactNumberFormatter = require(npcSystemFolder.Shared.CompactNumberFormatter)

local player = Players.LocalPlayer
local remotesFolder = npcSystemFolder:WaitForChild("Remotes")
local upgradeRemote: RemoteEvent = remotesFolder:WaitForChild(levelConfig.RemoteEventName) :: RemoteEvent
local upgradeFeedbackRemote: RemoteEvent = remotesFolder:WaitForChild(levelConfig.UpgradeFeedbackRemoteEventName) :: RemoteEvent

local buttonConnections: { [GuiButton]: { Activated: RBXScriptConnection, MouseClick: RBXScriptConnection } } = {}
local lastNoBaseLogAt = 0
local insufficientSoundCooldownUntil = 0
local feedbackLabelToken = 0

local function debugLog(message: string)
	if levelConfig.DebugLogs then
		warn("[NPCUpgradeButtons] " .. message)
	end
end

debugLog(("Client started. Remote=%s"):format(levelConfig.RemoteEventName))

local function resolveFromPath(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, segment in ipairs(path) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
	end
	return current
end

local function resolveAsset(path: { string }): Instance?
	local current: Instance? = game
	for _, segment in ipairs(path) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
	end
	return current
end

local function resolveTextLabel(primaryPath: { string }, fallbackPath: { string }?): TextLabel?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local label = resolveFromPath(playerGui, primaryPath)
	if label and label:IsA("TextLabel") then
		return label
	end
	if fallbackPath then
		label = resolveFromPath(playerGui, fallbackPath)
		if label and label:IsA("TextLabel") then
			return label
		end
	end
	return nil
end

local function playSoundFromTemplate(templatePath: { string })
	local template = resolveAsset(templatePath)
	if not (template and template:IsA("Sound")) then
		debugLog(("Missing sound template at path %s"):format(table.concat(templatePath, "/")))
		return
	end
	local sound = template:Clone()
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(2, sound.TimeLength + 0.25))
end

local function showTimedLabel(label: TextLabel, text: string, duration: number)
	feedbackLabelToken += 1
	local token = feedbackLabelToken
	label.Visible = true
	label.Text = text
	task.delay(duration, function()
		if token ~= feedbackLabelToken then
			return
		end
		if label.Parent then
			label.Visible = false
		end
	end)
end

local function showInsufficientFunds(cost: number)
	local label = resolveTextLabel(levelConfig.InsufficientFundsLabelPath, nil)
	if not label then
		debugLog("Missing insufficient funds TextLabel at configured path")
		return
	end
	showTimedLabel(
		label,
		string.format(levelConfig.InsufficientFundsTextTemplate, CompactNumberFormatter.FormatCurrency(cost, levelConfig.CurrencyPrefix)),
		levelConfig.InsufficientFundsLabelShowSeconds
	)
end

local function showMaxLevel(level: number)
	local label = resolveTextLabel(levelConfig.MaxLevelLabelPath, levelConfig.InsufficientFundsLabelPath)
	if not label then
		debugLog("Missing max level TextLabel at configured path")
		return
	end
	showTimedLabel(label, string.format(levelConfig.MaxLevelTextTemplate, level), levelConfig.MaxLevelLabelShowSeconds)
end

local function playInsufficientLikeFeedbackSound()
	if os.clock() >= insufficientSoundCooldownUntil then
		insufficientSoundCooldownUntil = os.clock() + levelConfig.InsufficientFundsSFXCooldownSeconds
		playSoundFromTemplate(levelConfig.InsufficientFundsSFXPath)
	end
end

local function onUpgradeFeedback(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local feedbackType = payload.Type
	if feedbackType == "InsufficientFunds" then
		local cost = typeof(payload.Cost) == "number" and payload.Cost or 0
		showInsufficientFunds(cost)
		playInsufficientLikeFeedbackSound()
	elseif feedbackType == "MaxLevel" then
		local level = typeof(payload.Level) == "number" and payload.Level or levelConfig.MaxLevel
		showMaxLevel(level)
		playInsufficientLikeFeedbackSound()
	elseif feedbackType == "Upgraded" then
		playSoundFromTemplate(levelConfig.UpgradeSuccessSFXPath)
	end
end

upgradeFeedbackRemote.OnClientEvent:Connect(onUpgradeFeedback)

local function disconnectRemovedButtons()
	for button, connectionPair in pairs(buttonConnections) do
		if button.Parent == nil then
			connectionPair.Activated:Disconnect()
			connectionPair.MouseClick:Disconnect()
			buttonConnections[button] = nil
		end
	end
end

local function getOwnedBase(): Model?
	local basesFolder = Workspace:FindFirstChild(baseConfig.BasesFolderName)
	if not (basesFolder and basesFolder:IsA("Folder")) then
		return nil
	end
	for _, baseModel in ipairs(basesFolder:GetChildren()) do
		if baseModel:IsA("Model") and baseModel:GetAttribute("OwnerUserId") == player.UserId then
			return baseModel
		end
	end
	return nil
end

local function isSlotPart(slot: Instance): boolean
	return slot:IsA("BasePart") and string.match(slot.Name, "^Slot%d+$") ~= nil and slot:GetAttribute("BaseUpgradeUnlocked") ~= false
end

local function bindSlotButton(slot: BasePart)
	local upgradePart = slot:FindFirstChild(levelConfig.UpgradePartName)
	if not (upgradePart and upgradePart:IsA("BasePart")) then
		return
	end
	local upgradeGui = upgradePart:FindFirstChild(levelConfig.UpgradeGuiName)
	if not (upgradeGui and upgradeGui:IsA("SurfaceGui")) then
		return
	end
	local button = upgradeGui:FindFirstChild(levelConfig.UpgradeButtonName)
	if not (button and button:IsA("GuiButton")) then
		return
	end
	if buttonConnections[button] then
		return
	end
	debugLog(("Binding upgrade button for slot=%s"):format(slot.Name))
	local function requestUpgrade()
		debugLog(("Request upgrade fired for slot=%s"):format(slot.Name))
		upgradeRemote:FireServer({
			SlotName = slot.Name,
		})
	end
	button.Active = true
	button.AutoButtonColor = true
	local activatedConn = button.Activated:Connect(requestUpgrade)
	local clickConn = button.MouseButton1Click:Connect(requestUpgrade)
	buttonConnections[button] = {
		Activated = activatedConn,
		MouseClick = clickConn,
	}
end

local function bindOwnedBaseButtons()
	disconnectRemovedButtons()
	local baseModel = getOwnedBase()
	if not baseModel then
		if levelConfig.DebugLogs and (os.clock() - lastNoBaseLogAt) > 3 then
			lastNoBaseLogAt = os.clock()
			debugLog("No owned base found for local player yet")
		end
		return
	end
	local boundCount = 0
	for _, slot in ipairs(baseModel:GetDescendants()) do
		if isSlotPart(slot) then
			local before = 0
			for _ in pairs(buttonConnections) do before += 1 end
			bindSlotButton(slot)
			local after = 0
			for _ in pairs(buttonConnections) do after += 1 end
			if after > before then
				boundCount += 1
			end
		end
	end
	if levelConfig.DebugLogs and boundCount > 0 then
		debugLog(("Bound %d new upgrade button(s) on base %s"):format(boundCount, baseModel.Name))
	end
end

Workspace.DescendantAdded:Connect(function(desc)
	if desc.Name == levelConfig.UpgradeButtonName and desc:IsA("GuiButton") then
		task.defer(bindOwnedBaseButtons)
	end
end)

Workspace.DescendantRemoving:Connect(function(_)
	task.defer(disconnectRemovedButtons)
end)

while true do
	bindOwnedBaseButtons()
	task.wait(1)
end
