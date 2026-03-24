local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local npcSystemFolder = ReplicatedStorage:WaitForChild("NPCSystem")
local baseConfig = require(npcSystemFolder.Config.BaseConfig)
local baseUpgradeConfig = require(npcSystemFolder.Config.BaseUpgradeConfig)
local BaseUpgradeProgression = require(npcSystemFolder.Shared.BaseUpgradeProgression)
local BigNumber = require(npcSystemFolder.Shared.BigNumber)

local remotesFolder = npcSystemFolder:WaitForChild("Remotes")
local upgradeRequestRemote: RemoteEvent = remotesFolder:WaitForChild(baseUpgradeConfig.RemoteEventName) :: RemoteEvent
local upgradeFeedbackRemote: RemoteEvent = remotesFolder:WaitForChild(baseUpgradeConfig.FeedbackRemoteEventName) :: RemoteEvent
local moneySnapshotFunction: RemoteFunction = remotesFolder:WaitForChild(baseConfig.Remotes.MoneySnapshotFunctionName) :: RemoteFunction

local buttonConnections: { [GuiButton]: { Activated: RBXScriptConnection } } = {}
local feedbackToken = 0
local insufficientSoundCooldownUntil = 0

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

local function getAllBaseModels(): { Model }
	local basesFolder = Workspace:FindFirstChild(baseConfig.BasesFolderName)
	if not (basesFolder and basesFolder:IsA("Folder")) then
		return {}
	end
	local models = {}
	for _, child in ipairs(basesFolder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end
	return models
end

local function playSoundFromTemplate(templatePath: { string })
	local template = resolveAsset(templatePath)
	if not (template and template:IsA("Sound")) then
		return
	end
	local sound = template:Clone()
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(2, sound.TimeLength + 0.25))
end

local function showFeedbackLabel(text: string)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local label = resolveFromPath(playerGui, baseUpgradeConfig.FeedbackLabelPath)
	if not (label and label:IsA("TextLabel")) then
		return
	end
	feedbackToken += 1
	local token = feedbackToken
	label.Text = text
	label.Visible = true
	task.delay(baseUpgradeConfig.FeedbackLabelShowSeconds, function()
		if token ~= feedbackToken then
			return
		end
		if label.Parent then
			label.Visible = false
		end
	end)
end

local function sanitizeMoneyString(value: any): string
	return BigNumber.Sanitize(value)
end

local function requestMoneySnapshot(): string
	local ok, result = pcall(function()
		return moneySnapshotFunction:InvokeServer()
	end)
	if not ok then
		return "0"
	end
	return sanitizeMoneyString(result)
end

local function getMoneyString(): string
	local moneyString = sanitizeMoneyString(player:GetAttribute("MoneyString"))
	if moneyString ~= "0" then
		return moneyString
	end
	local snapshot = requestMoneySnapshot()
	if snapshot ~= "0" then
		player:SetAttribute("MoneyString", snapshot)
		return snapshot
	end
	local leaderstats = player:FindFirstChild(baseConfig.Currency.LeaderstatsFolderName)
	if leaderstats then
		local stat = leaderstats:FindFirstChild(baseConfig.Currency.StatName)
		if stat and stat:IsA("IntValue") then
			return sanitizeMoneyString(stat.Value)
		end
	end
	return "0"
end

local function playInsufficientLikeSFX()
	if os.clock() < insufficientSoundCooldownUntil then
		return
	end
	insufficientSoundCooldownUntil = os.clock() + baseUpgradeConfig.InsufficientSFXCooldownSeconds
	playSoundFromTemplate(baseUpgradeConfig.InsufficientSFXPath)
end

local function onUpgradeFeedback(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Type == "InsufficientFunds" then
		showFeedbackLabel(baseUpgradeConfig.InsufficientFundsText)
		playInsufficientLikeSFX()
	elseif payload.Type == "Maxed" then
		showFeedbackLabel(baseUpgradeConfig.MaxUpgradeText)
		playInsufficientLikeSFX()
	elseif payload.Type == "Upgraded" then
		playSoundFromTemplate(baseUpgradeConfig.SuccessSFXPath)
	end
end

upgradeFeedbackRemote.OnClientEvent:Connect(onUpgradeFeedback)

local function disconnectRemovedButtons()
	for button, connections in pairs(buttonConnections) do
		if button.Parent == nil then
			connections.Activated:Disconnect()
			buttonConnections[button] = nil
		end
	end
end

local function bindButton(button: GuiButton)
	if buttonConnections[button] then
		return
	end
	local function requestUpgrade()
		upgradeRequestRemote:FireServer()
	end
	buttonConnections[button] = {
		Activated = button.Activated:Connect(requestUpgrade),
	}
end

local function bindOwnedBaseButton()
	disconnectRemovedButtons()
	local baseModel = getOwnedBase()
	if not baseModel then
		return
	end
	local upgradeModel = baseModel:FindFirstChild(baseUpgradeConfig.BaseUpgradeModelName, true)
	if not (upgradeModel and upgradeModel:IsA("Model")) then
		return
	end
	local guiPart = upgradeModel:FindFirstChild(baseUpgradeConfig.GUIPartName, true)
	if not (guiPart and guiPart:IsA("BasePart")) then
		return
	end
	local surfaceGui = guiPart:FindFirstChild(baseUpgradeConfig.SurfaceGuiName)
	if not (surfaceGui and surfaceGui:IsA("SurfaceGui")) then
		return
	end
	local button = surfaceGui:FindFirstChild(baseUpgradeConfig.ButtonName)
	if button and button:IsA("GuiButton") then
		bindButton(button)
	end
end

local function resolveAlertGui(baseModel: Model): BillboardGui?
	local upgradeModel = baseModel:FindFirstChild(baseUpgradeConfig.BaseUpgradeModelName, true)
	if not (upgradeModel and upgradeModel:IsA("Model")) then
		return nil
	end
	local guiPart = upgradeModel:FindFirstChild(baseUpgradeConfig.GUIPartName, true)
	if not (guiPart and guiPart:IsA("BasePart")) then
		return nil
	end
	local alertGui = guiPart:FindFirstChild(baseUpgradeConfig.AlertGuiName)
	if alertGui and alertGui:IsA("BillboardGui") then
		return alertGui
	end
	return nil
end

local function updateAlertGuiVisibility()
	local ownedBase = getOwnedBase()
	local currentMoney = getMoneyString()

	for _, baseModel in ipairs(getAllBaseModels()) do
		local alertGui = resolveAlertGui(baseModel)
		if not alertGui then
			continue
		end

		local shouldEnable = false
		if baseModel == ownedBase and baseModel:GetAttribute("OwnerUserId") == player.UserId then
			local upgradeCount = baseModel:GetAttribute(baseUpgradeConfig.CurrentUpgradeAttributeName)
			local currentCost = BaseUpgradeProgression.GetCurrentCost(upgradeCount)
			shouldEnable = currentCost ~= nil and BigNumber.Compare(currentMoney, currentCost) >= 0
		end

		alertGui.Enabled = shouldEnable
	end
end

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name == baseUpgradeConfig.ButtonName and descendant:IsA("GuiButton") then
		task.defer(bindOwnedBaseButton)
	end
	if descendant.Name == baseUpgradeConfig.AlertGuiName and descendant:IsA("BillboardGui") then
		task.defer(updateAlertGuiVisibility)
	end
end)

Workspace.DescendantRemoving:Connect(function()
	task.defer(disconnectRemovedButtons)
	task.defer(updateAlertGuiVisibility)
end)

player:GetAttributeChangedSignal("MoneyString"):Connect(updateAlertGuiVisibility)

while true do
	bindOwnedBaseButton()
	updateAlertGuiVisibility()
	task.wait(baseUpgradeConfig.AffordabilityPollIntervalSeconds)
end
