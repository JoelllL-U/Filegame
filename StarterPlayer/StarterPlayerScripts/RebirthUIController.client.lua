local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RebirthConfig = require(ReplicatedStorage.NPCSystem.Config.RebirthConfig)
local CompactNumberFormatter = require(ReplicatedStorage.NPCSystem.Shared.CompactNumberFormatter)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local rootGui = playerGui:WaitForChild("GUI")
local rebirthFrame = rootGui:WaitForChild("Rebirth")
local bar = rebirthFrame:WaitForChild("Bar")
local barProgress = bar:WaitForChild("Progress")
local barText = bar:WaitForChild("Text")
local recive = rebirthFrame:WaitForChild("Recive")
local reciveCoinsText = recive:WaitForChild("Coins"):WaitForChild("Text")
local reciveMultiplierText = recive:WaitForChild("Multiplier"):WaitForChild("Text")
local closeButton = rebirthFrame:WaitForChild("Close")
local rebirthButton = rebirthFrame:WaitForChild("RebirthButton")
local openButton = rootGui:WaitForChild("Bottons"):WaitForChild("BottonREBIRTH"):WaitForChild("abrir")

local remotesFolder = ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Remotes")
local getStateFunction = remotesFolder:WaitForChild(RebirthConfig.Remotes.GetStateFunctionName) :: RemoteFunction
local requestRebirthFunction = remotesFolder:WaitForChild(RebirthConfig.Remotes.RequestRebirthFunctionName) :: RemoteFunction
local stateChangedEvent = remotesFolder:WaitForChild(RebirthConfig.Remotes.StateChangedEventName) :: RemoteEvent

local uiScale = rebirthFrame:FindFirstChildOfClass("UIScale")
if not uiScale then
	uiScale = Instance.new("UIScale")
	uiScale.Scale = RebirthConfig.UI.OpenScaleFrom
	uiScale.Parent = rebirthFrame
end

local isVisible = false
local isAnimating = false
local latestState = nil

local function getFormattedMoney(value: any): string
	return CompactNumberFormatter.FormatCurrency(value, "$")
end

local function updateUI(state)
	latestState = state
	if typeof(state) ~= "table" then
		return
	end

	local progress = math.clamp(tonumber(state.Progress) or 0, 0, 1)
	barProgress.Size = UDim2.new(progress, 0, 1, 0)

	local displayMoneyText = state.Display and state.Display.MoneyText
	if typeof(displayMoneyText) ~= "string" or displayMoneyText == "" then
		local currentMoney = getFormattedMoney(state.CurrentMoney or "0")
		local requiredMoney = getFormattedMoney(state.NextRequiredMoney or "0")
		displayMoneyText = ("%s/%s"):format(currentMoney, requiredMoney)
	end
	barText.Text = displayMoneyText

	local rewardText = state.Display and state.Display.RewardText
	if typeof(rewardText) ~= "string" or rewardText == "" then
		rewardText = getFormattedMoney(state.NextRewardMoney or "0")
	end
	reciveCoinsText.Text = rewardText

	local multiplierText = state.Display and state.Display.MultiplierText
	if typeof(multiplierText) ~= "string" or multiplierText == "" then
		multiplierText = ("x%s"):format(tostring(state.NextMultiplier or 1))
	end
	reciveMultiplierText.Text = multiplierText

	local isMax = state.IsMax == true
	rebirthButton.Active = not isMax
	rebirthButton.AutoButtonColor = not isMax
	rebirthButton.ImageTransparency = isMax and 0.4 or 0
end

local function requestAndRefresh()
	local success, state = pcall(function()
		return getStateFunction:InvokeServer()
	end)
	if success then
		updateUI(state)
	end
end

local function animateVisible(targetVisible: boolean)
	if isAnimating then
		return
	end
	isAnimating = true

	if targetVisible then
		rebirthFrame.Visible = true
		local openTween = TweenService:Create(
			uiScale,
			TweenInfo.new(RebirthConfig.UI.OpenTweenSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		openTween:Play()
		openTween.Completed:Wait()
		isVisible = true
	else
		local closeTween = TweenService:Create(
			uiScale,
			TweenInfo.new(RebirthConfig.UI.CloseTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = RebirthConfig.UI.OpenScaleFrom }
		)
		closeTween:Play()
		closeTween.Completed:Wait()
		rebirthFrame.Visible = false
		isVisible = false
	end

	isAnimating = false
end

openButton.MouseButton1Click:Connect(function()
	requestAndRefresh()
	animateVisible(true)
end)

closeButton.MouseButton1Click:Connect(function()
	animateVisible(false)
end)

rebirthButton.MouseButton1Click:Connect(function()
	local success, response = pcall(function()
		return requestRebirthFunction:InvokeServer()
	end)
	if success and typeof(response) == "table" and response.State then
		updateUI(response.State)
	else
		requestAndRefresh()
	end
end)

stateChangedEvent.OnClientEvent:Connect(function(state)
	updateUI(state)
end)

player:GetAttributeChangedSignal("MoneyString"):Connect(function()
	if isVisible then
		requestAndRefresh()
	end
end)

rebirthFrame.Visible = false
uiScale.Scale = RebirthConfig.UI.OpenScaleFrom
requestAndRefresh()
