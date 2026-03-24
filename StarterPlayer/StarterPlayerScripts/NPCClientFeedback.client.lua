local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local npcSystem = ReplicatedStorage:WaitForChild("NPCSystem")
local baseConfig = require(npcSystem.Config.BaseConfig)
local capturableFlowConfig = require(npcSystem.Config.CapturableFlowConfig)
local CompactNumberFormatter = require(npcSystem.Shared.CompactNumberFormatter)

local remotesFolder = npcSystem:WaitForChild("Remotes")
local collectionFeedbackRemote = remotesFolder:WaitForChild(baseConfig.Remotes.CollectionFeedbackEventName)
local capturePromptRemote = remotesFolder:WaitForChild(baseConfig.Remotes.CapturePromptEventName)
local captureDecisionRemote = remotesFolder:WaitForChild(baseConfig.Remotes.CaptureDecisionEventName)
local moneySnapshotFunction = remotesFolder:WaitForChild(baseConfig.Remotes.MoneySnapshotFunctionName)
local capturableCarryStateRemote = baseConfig.Remotes.CapturableCarryStateEventName and remotesFolder:WaitForChild(baseConfig.Remotes.CapturableCarryStateEventName, 10)
local capturableDropRequestRemote = baseConfig.Remotes.CapturableDropRequestEventName and remotesFolder:WaitForChild(baseConfig.Remotes.CapturableDropRequestEventName, 10)
local capturableLifecycleRemote = baseConfig.Remotes.CapturableLifecycleEventName and remotesFolder:WaitForChild(baseConfig.Remotes.CapturableLifecycleEventName, 10)

local connections: { [string]: RBXScriptConnection } = {}
local currentCaptureId: number? = nil
local warningTweenIn: Tween? = nil
local warningTweenOut: Tween? = nil
local warningToken = 0
local warningBaseTextTransparency: number? = nil
local warningBaseBackgroundTransparency: number? = nil
local COLLECTION_VFX_HEIGHT_OFFSET = 1.25

local function resolvePath(root: Instance, path: { string }): Instance?
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
	return resolvePath(game, path)
end

local function getPlayerGui(): PlayerGui?
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if gui then
		return gui
	end
	return player:WaitForChild("PlayerGui", 10)
end

local function getMoneyString(): string
	local raw = player:GetAttribute("MoneyString")
	if typeof(raw) == "string" then
		local digits = raw:gsub("[^0-9]", ""):gsub("^0+", "")
		if digits == "" then
			return "0"
		end
		return digits
	end
	return "0"
end

local function requestMoneySnapshotFromServer(): string
	local ok, result = pcall(function()
		return (moneySnapshotFunction :: RemoteFunction):InvokeServer()
	end)
	if not ok then
		return "0"
	end
	if typeof(result) ~= "string" then
		return "0"
	end
	local digits = result:gsub("[^0-9]", ""):gsub("^0+", "")
	if digits == "" then
		return "0"
	end
	return digits
end

local function formatMoney(value: any): string
	return CompactNumberFormatter.FormatCurrency(value, "$")
end

local function resolveMoneyLabel(): TextLabel?
	local playerGui = getPlayerGui()
	if not playerGui then
		return nil
	end
	local moneyIndicator = playerGui:FindFirstChild("MoneyIndicator")
	if not (moneyIndicator and moneyIndicator:IsA("ScreenGui")) then
		return nil
	end
	local moneyFrame = moneyIndicator:FindFirstChild("MoneyFrame")
	if not (moneyFrame and moneyFrame:IsA("Frame")) then
		return nil
	end

	-- Preferred hierarchy used by this project.
	local directMoneyLabel = moneyFrame:FindFirstChild("MoneyLabel")
	if directMoneyLabel and directMoneyLabel:IsA("TextLabel") then
		return directMoneyLabel
	end

	-- Compatibility hierarchy used by the standalone MoneyIndicator local script:
	-- MoneyFrame > Backing > MoneyLabel
	local backing = moneyFrame:FindFirstChild("Backing")
	if backing and backing:IsA("Frame") then
		local nestedMoneyLabel = backing:FindFirstChild("MoneyLabel")
		if nestedMoneyLabel and nestedMoneyLabel:IsA("TextLabel") then
			return nestedMoneyLabel
		end
	end

	return nil
end

local function bindMoneyLabel()
	if connections.MoneyStringChanged then
		connections.MoneyStringChanged:Disconnect()
		connections.MoneyStringChanged = nil
	end

	local moneyLabel = resolveMoneyLabel()
	if not moneyLabel then
		warn("[NPCClientFeedback] Missing MoneyIndicator/MoneyFrame/(MoneyLabel or Backing/MoneyLabel)")
		return
	end

	moneyLabel.TextScaled = true
	moneyLabel.TextWrapped = false
	moneyLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local function renderLatestMoney()
		local moneyDigits = getMoneyString()
		if moneyDigits == "0" then
			local serverMoney = requestMoneySnapshotFromServer()
			if serverMoney ~= "0" then
				moneyDigits = serverMoney
				player:SetAttribute("MoneyString", moneyDigits)
			end
		end
		moneyLabel.Text = formatMoney(moneyDigits)
	end

	renderLatestMoney()

	connections.MoneyStringChanged = player:GetAttributeChangedSignal("MoneyString"):Connect(function()
		renderLatestMoney()
	end)
end

local function playCollectionVFX(worldPosition: Vector3)
	local template = resolveAsset(baseConfig.CollectionFeedback.VFXTemplatePath)
	if not template then
		warn("[NPCClientFeedback] Missing collection VFX template")
		return
	end
	local clone = template:Clone()

	if clone:IsA("ParticleEmitter") then
		local holder = Instance.new("Part")
		holder.Name = "CollectionVFXPart"
		holder.Transparency = 1
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.CFrame = CFrame.new(worldPosition)
		holder.Parent = workspace
		clone.Parent = holder
		clone:Emit(math.max(1, clone:GetAttribute("EmitCount") or 15))
		Debris:AddItem(holder, baseConfig.CollectionFeedback.VFXLifetimeSeconds)
		return
	end

	if clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			clone:PivotTo(CFrame.new(worldPosition))
		end
		clone.Parent = workspace
		Debris:AddItem(clone, baseConfig.CollectionFeedback.VFXLifetimeSeconds)
		return
	end

	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CFrame = CFrame.new(worldPosition)
		clone.Parent = workspace
		Debris:AddItem(clone, baseConfig.CollectionFeedback.VFXLifetimeSeconds)
		return
	end

	warn("[NPCClientFeedback] Unsupported VFX template type: " .. clone.ClassName)
	clone:Destroy()
end

local function playCollectionSFX(worldPosition: Vector3)
	local template = resolveAsset(baseConfig.CollectionFeedback.SoundTemplatePath)
	if not template or not template:IsA("Sound") then
		warn("[NPCClientFeedback] Missing collection SFX template")
		return
	end
	local soundHolder = Instance.new("Part")
	soundHolder.Name = "CollectionSFXPart"
	soundHolder.Transparency = 1
	soundHolder.Anchored = true
	soundHolder.CanCollide = false
	soundHolder.CanQuery = false
	soundHolder.CanTouch = false
	soundHolder.Size = Vector3.new(0.2, 0.2, 0.2)
	soundHolder.CFrame = CFrame.new(worldPosition)
	soundHolder.Parent = workspace

	local sound = template:Clone()
	sound.Parent = soundHolder
	sound:Play()
	Debris:AddItem(soundHolder, math.max(baseConfig.CollectionFeedback.SoundLifetimeSeconds, sound.TimeLength + 0.25))
end

local function resolveSlotWarningGuiAndLabel(): (ScreenGui?, TextLabel?)
	local playerGui = getPlayerGui()
	if not playerGui then
		return nil, nil
	end
	local slotWarningGui = playerGui:FindFirstChild("SlotWarningGui")
	if not (slotWarningGui and slotWarningGui:IsA("ScreenGui")) then
		return nil, nil
	end
	local slotWarningLabel = slotWarningGui:FindFirstChild("SlotWarningLabel")
	if slotWarningLabel and slotWarningLabel:IsA("TextLabel") then
		return slotWarningGui, slotWarningLabel
	end
	return slotWarningGui, nil
end

local function showNoFreeSlotsLabel(optionalText: string?)
	local warningGui, label = resolveSlotWarningGuiAndLabel()
	if not warningGui then
		warn("[NPCClientFeedback] Missing SlotWarningGui")
		return
	end
	if not label then
		warn("[NPCClientFeedback] Missing SlotWarningLabel")
		return
	end

	warningToken += 1
	local thisToken = warningToken
	if warningTweenIn then
		warningTweenIn:Cancel()
	end
	if warningTweenOut then
		warningTweenOut:Cancel()
	end

	if warningBaseTextTransparency == nil then
		warningBaseTextTransparency = label.TextTransparency
	end
	if warningBaseBackgroundTransparency == nil then
		warningBaseBackgroundTransparency = label.BackgroundTransparency
	end

	label.Text = optionalText or baseConfig.UI.NoFreeSlotsText
	warningGui.Enabled = true
	label.Visible = true
	label.TextTransparency = 1
	label.BackgroundTransparency = warningBaseBackgroundTransparency

	warningTweenIn = TweenService:Create(
		label,
		TweenInfo.new(baseConfig.UI.NoFreeSlotsFadeInSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = warningBaseTextTransparency }
	)
	warningTweenIn:Play()

	local totalWarningSeconds = 3
	local holdSeconds = math.max(0, totalWarningSeconds - baseConfig.UI.NoFreeSlotsFadeInSeconds - baseConfig.UI.NoFreeSlotsFadeOutSeconds)
	task.delay(baseConfig.UI.NoFreeSlotsFadeInSeconds + holdSeconds, function()
		if thisToken ~= warningToken or not label.Parent then
			return
		end
		warningTweenOut = TweenService:Create(
			label,
			TweenInfo.new(baseConfig.UI.NoFreeSlotsFadeOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }
		)
		warningTweenOut.Completed:Connect(function()
			if thisToken ~= warningToken or not label.Parent then
				return
			end
			label.Visible = false
			warningGui.Enabled = false
		end)
		warningTweenOut:Play()
	end)
end

local function resolveQuestionGuiAndFrame(): (ScreenGui?, Frame?)
	local playerGui = getPlayerGui()
	if not playerGui then
		return nil, nil
	end
	local questionGui = playerGui:FindFirstChild("QuestionGui")
	if not (questionGui and questionGui:IsA("ScreenGui")) then
		return nil, nil
	end
	local questionFrame = questionGui:FindFirstChild("QuestionFrame")
	if questionFrame and questionFrame:IsA("Frame") then
		return questionGui, questionFrame
	end
	return questionGui, nil
end

local function hideQuestionPrompt()
	local questionGui, questionFrame = resolveQuestionGuiAndFrame()
	if questionFrame then
		questionFrame.Visible = false
	end
	if questionGui then
		questionGui.Enabled = false
	end
end

local function showCapturePrompt(captureId: number, npcName: string)
	local gui, frame = resolveQuestionGuiAndFrame()
	if not gui then
		warn("[NPCClientFeedback] Missing QuestionGui")
		return
	end
	if not frame then
		warn("[NPCClientFeedback] Missing QuestionFrame")
		return
	end

	local promptText = frame:FindFirstChild("Text")
	local yesButton = frame:FindFirstChild("Yes")
	local noButton = frame:FindFirstChild("No")
	if not (promptText and promptText:IsA("TextLabel")) then
		warn("[NPCClientFeedback] Missing Question Text label")
		return
	end
	if not (yesButton and yesButton:IsA("TextButton")) then
		warn("[NPCClientFeedback] Missing Yes button")
		return
	end
	if not (noButton and noButton:IsA("TextButton")) then
		warn("[NPCClientFeedback] Missing No button")
		return
	end

	currentCaptureId = captureId
	promptText.Text = string.format(baseConfig.UI.CapturePromptTemplate, npcName)
	frame.Visible = true
	gui.Enabled = true

	if connections.YesButton then
		connections.YesButton:Disconnect()
	end
	if connections.NoButton then
		connections.NoButton:Disconnect()
	end

	local resolved = false
	connections.YesButton = yesButton.Activated:Connect(function()
		if resolved or not currentCaptureId then
			return
		end
		resolved = true
		captureDecisionRemote:FireServer({ CaptureId = currentCaptureId, Decision = "Yes" })
		currentCaptureId = nil
		hideQuestionPrompt()
	end)

	connections.NoButton = noButton.Activated:Connect(function()
		if resolved or not currentCaptureId then
			return
		end
		resolved = true
		captureDecisionRemote:FireServer({ CaptureId = currentCaptureId, Decision = "No" })
		currentCaptureId = nil
		hideQuestionPrompt()
	end)
end


local dropButtonConnection: RBXScriptConnection? = nil

local warnedMissingCapturableDropButton = false

local function resolveCapturableDropButton(): TextButton?
	local playerGui = getPlayerGui()
	if not playerGui then
		return nil
	end
	local uiConfig = capturableFlowConfig.CarryUI
	local screenGui = playerGui:FindFirstChild(uiConfig.ScreenGuiName)
	if not (screenGui and screenGui:IsA("ScreenGui")) then
		if not warnedMissingCapturableDropButton then
			warn(("[NPCClientFeedback] Missing existing carry gui %s in PlayerGui"):format(uiConfig.ScreenGuiName))
			warnedMissingCapturableDropButton = true
		end
		return nil
	end
	local button = screenGui:FindFirstChild(uiConfig.DropButtonName)
	if button and button:IsA("TextButton") then
		return button
	end
	if not warnedMissingCapturableDropButton then
		warn(("[NPCClientFeedback] Missing existing carry gui button %s/%s"):format(uiConfig.ScreenGuiName, uiConfig.DropButtonName))
		warnedMissingCapturableDropButton = true
	end
	return nil
end

local function bindCapturableDropButton(visible: boolean)
	local button = resolveCapturableDropButton()
	if not button then
		return
	end
	button.Visible = visible
	if dropButtonConnection then
		dropButtonConnection:Disconnect()
		dropButtonConnection = nil
	end
	if visible then
		dropButtonConnection = button.Activated:Connect(function()
			if capturableDropRequestRemote then
				capturableDropRequestRemote:FireServer({})
			end
		end)
	end
end

if capturableCarryStateRemote and capturableCarryStateRemote:IsA("RemoteEvent") then
	capturableCarryStateRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		bindCapturableDropButton(payload.Visible == true)
	end)
end


local function playDefeatedVFX(worldPosition: Vector3)
	local templatePath = baseConfig.CaptureFlow and baseConfig.CaptureFlow.DefeatedVFXTemplatePath
	local template = (typeof(templatePath) == "table") and resolveAsset(templatePath) or nil
	if not template then
		return
	end
	local clone = template:Clone()
	if clone:IsA("Model") then
		clone:PivotTo(CFrame.new(worldPosition))
		clone.Parent = workspace
		Debris:AddItem(clone, 3)
		return
	end
	if clone:IsA("ParticleEmitter") then
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1,1,1)
		holder.CFrame = CFrame.new(worldPosition)
		holder.Parent = workspace
		clone.Parent = holder
		clone:Emit(math.max(8, clone.Rate))
		Debris:AddItem(holder, 3)
		return
	end
	if clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(worldPosition)
		clone.Parent = workspace
		Debris:AddItem(clone, 3)
		return
	end
	clone:Destroy()
end

local function playDefeatedSFX(worldPosition: Vector3)
	local templatePath = baseConfig.CaptureFlow and baseConfig.CaptureFlow.DefeatedSFXTemplatePath
	local template = (typeof(templatePath) == "table") and resolveAsset(templatePath) or nil
	if not template then
		return
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1,1,1)
	holder.CFrame = CFrame.new(worldPosition)
	holder.Parent = workspace
	local sound: Sound? = nil
	if template:IsA("Sound") then
		sound = template:Clone()
	elseif template:IsA("BasePart") then
		local embedded = template:FindFirstChildWhichIsA("Sound")
		if embedded then
			sound = embedded:Clone()
		end
	end
	if not sound then
		holder:Destroy()
		return
	end
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, math.max(sound.TimeLength + 0.5, 3))
end

if capturableLifecycleRemote and capturableLifecycleRemote:IsA("RemoteEvent") then
	capturableLifecycleRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.Type == "DefeatedVFXHook" and typeof(payload.Position) == "Vector3" then
			playDefeatedVFX(payload.Position)
			return
		end
		if payload.Type == "DefeatedSpawnSFXHook" and typeof(payload.Position) == "Vector3" then
			playDefeatedSFX(payload.Position)
			return
		end
	end)
end

collectionFeedbackRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local amount = payload.Amount
	if typeof(amount) ~= "number" or amount <= 0 then
		return
	end
	local worldPosition = payload.WorldPosition
	if typeof(worldPosition) ~= "Vector3" then
		local collectPart = payload.CollectPart
		if collectPart and collectPart:IsA("BasePart") then
			worldPosition = collectPart.Position
		else
			return
		end
	end
	local elevatedVFXPosition = worldPosition + Vector3.new(0, COLLECTION_VFX_HEIGHT_OFFSET, 0)
	playCollectionVFX(elevatedVFXPosition)
	playCollectionSFX(worldPosition)
end)

capturePromptRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Type == "NoFreeSlots" then
		showNoFreeSlotsLabel(payload.Text)
		return
	end
	if payload.Type ~= "Prompt" then
		return
	end
	if typeof(payload.CaptureId) ~= "number" then
		return
	end
	local npcName = payload.NpcName
	if typeof(npcName) ~= "string" or npcName == "" then
		npcName = "Unknown"
	end
	showCapturePrompt(payload.CaptureId, npcName)
end)


local playerGui = getPlayerGui()
if playerGui then
	playerGui.DescendantAdded:Connect(function(desc)
		if desc:IsA("TextLabel") then
			task.defer(bindMoneyLabel)
		end
		if desc:IsA("Frame") and desc.Name == "QuestionFrame" then
			desc.Visible = false
		end
	end)
end

task.spawn(function()
	for _ = 1, 30 do
		bindMoneyLabel()
		task.wait(0.25)
	end
end)

hideQuestionPrompt()
bindCapturableDropButton(false)
local initWarningGui = getPlayerGui() and getPlayerGui():FindFirstChild("SlotWarningGui")
if initWarningGui and initWarningGui:IsA("ScreenGui") then
	initWarningGui.Enabled = false
end
