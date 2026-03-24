local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local WeaponShopFormatter = require(ReplicatedStorage.WeaponShop.Shared.WeaponShopFormatter)
local config = require(ReplicatedStorage.WeaponShop.Config.WeaponShopConfig)

local function debugWarn(message)
	if config.EnableDebugWarnings then
		warn(message)
	end
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function resolvePath(pathSegments)
	local current = game
	for _, segment in ipairs(pathSegments) do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	return current
end

local remotesFolder = resolvePath(config.RemotesFolderPath)
if not remotesFolder then
	debugWarn("[WeaponShopUIController] Missing weapon shop remotes folder")
	return
end

local requestShopState = remotesFolder:WaitForChild(config.Remotes.RequestShopStateFunctionName)
local purchaseWeapon = remotesFolder:WaitForChild(config.Remotes.PurchaseWeaponEventName)
local requestEquipWeapon = remotesFolder:WaitForChild(config.Remotes.RequestEquipWeaponEventName)
local requestRobuxPurchase = remotesFolder:WaitForChild(config.Remotes.RequestRobuxPurchaseEventName)
local shopStateUpdated = remotesFolder:WaitForChild(config.Remotes.ShopStateUpdatedEventName)
local purchaseResult = remotesFolder:WaitForChild(config.Remotes.PurchaseResultEventName)

local ui = nil
local latestState = nil
local itemFramesByWeaponId = {}
local lastCountdownText = nil
local outOfStockMessageToken = 0
local insufficientMoneyMessageToken = 0
local outOfStockSoundCooldownUntil = 0
local successSoundCooldownUntil = 0

local function clearGeneratedItems()
	for _, frame in pairs(itemFramesByWeaponId) do
		if frame and frame.Parent then
			frame:Destroy()
		end
	end
	itemFramesByWeaponId = {}
end

local function hasValidGeneratedItems(state)
	if not ui or typeof(state) ~= "table" then
		return false
	end
	local weapons = state.Weapons
	if typeof(weapons) ~= "table" or #weapons == 0 then
		return false
	end
	for _, weapon in ipairs(weapons) do
		local frame = itemFramesByWeaponId[weapon.Id]
		if not frame or frame.Parent ~= ui.Root then
			return false
		end
	end
	return true
end

local function findRequiredDescendants(itemFrame)
	return {
		Icon = itemFrame:FindFirstChild("Item", true) and itemFrame:FindFirstChild("Icon", true),
		Buy = itemFrame:FindFirstChild("Buy"),
		BuyTextLabel = itemFrame:FindFirstChild("Buy") and itemFrame:FindFirstChild("Buy"):FindFirstChild("TextLabel", true),
		RobuxBuy = itemFrame:FindFirstChild("RobuxBuy"),
		Rarity = itemFrame:FindFirstChild("Rarity"),
		RarityTextLabel = itemFrame:FindFirstChild("Rarity") and itemFrame:FindFirstChild("Rarity"):FindFirstChild("TextLabel", true),
		ItemName = itemFrame:FindFirstChild("ItemName"),
		Price = itemFrame:FindFirstChild("Price"),
		Stock = itemFrame:FindFirstChild("Stock"),
	}
end

local function setNestedButtonLabelText(buttonName: string, nestedLabel: Instance?, text: string)
	if nestedLabel and nestedLabel:IsA("TextLabel") then
		nestedLabel.Text = text
		return
	end
	debugWarn(("[WeaponShopUIController] Missing %s/TextLabel; text update skipped"):format(buttonName))
end

local function resolvePathFrom(rootInstance: Instance, pathSegments)
	local current = rootInstance
	for _, segment in ipairs(pathSegments) do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	return current
end

local function playSoundFromTemplate(pathSegments)
	local template = resolvePath(pathSegments)
	if not (template and template:IsA("Sound")) then
		debugWarn("[WeaponShopUIController] Missing OutOfStock sound template")
		return
	end
	local sound = template:Clone()
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(2, sound.TimeLength + 0.25))
end

local function showOutOfStockFeedback()
	if typeof(config.OutOfStockFeedbackLabelPath) == "table" and #config.OutOfStockFeedbackLabelPath > 0 then
		local label = resolvePathFrom(playerGui, config.OutOfStockFeedbackLabelPath)
		if label and label:IsA("TextLabel") then
			outOfStockMessageToken += 1
			local token = outOfStockMessageToken
			label.Text = config.OutOfStockFeedbackText or "OUT OF STOCK"
			label.Visible = true
			local duration = math.max(0.1, tonumber(config.OutOfStockFeedbackDurationSeconds) or 1.5)
			task.delay(duration, function()
				if token ~= outOfStockMessageToken then
					return
				end
				if label.Parent then
					label.Visible = false
				end
			end)
		else
			debugWarn("[WeaponShopUIController] Missing OutOfStockFeedbackLabelPath label")
		end
	end

	if os.clock() >= outOfStockSoundCooldownUntil then
		outOfStockSoundCooldownUntil = os.clock() + math.max(0, tonumber(config.OutOfStockSFXCooldownSeconds) or 0.25)
		playSoundFromTemplate(config.OutOfStockSFXPath or { "ReplicatedStorage", "NPCSystem", "ClientAssets", "UpgradeInsufficientSFX" })
	end
end

local function showInsufficientMoneyFeedback()
	if typeof(config.InsufficientMoneyFeedbackLabelPath) == "table" and #config.InsufficientMoneyFeedbackLabelPath > 0 then
		local label = resolvePathFrom(playerGui, config.InsufficientMoneyFeedbackLabelPath)
		if not (label and label:IsA("TextLabel")) then
			debugWarn("[WeaponShopUIController] Missing InsufficientMoneyFeedbackLabelPath label")
		else
			insufficientMoneyMessageToken += 1
			local token = insufficientMoneyMessageToken
			label.Text = config.InsufficientMoneyFeedbackText or "NOT ENOUGH MONEY"
			label.Visible = true
			local duration = math.max(0.1, tonumber(config.InsufficientMoneyFeedbackDurationSeconds) or 1.5)
			task.delay(duration, function()
				if token ~= insufficientMoneyMessageToken then
					return
				end
				if label.Parent then
					label.Visible = false
				end
			end)
		end
	end

	if os.clock() >= outOfStockSoundCooldownUntil then
		outOfStockSoundCooldownUntil = os.clock() + math.max(0, tonumber(config.OutOfStockSFXCooldownSeconds) or 0.25)
		playSoundFromTemplate(config.OutOfStockSFXPath or { "ReplicatedStorage", "NPCSystem", "ClientAssets", "UpgradeInsufficientSFX" })
	end
end

local function playSuccessFeedback()
	if os.clock() >= successSoundCooldownUntil then
		successSoundCooldownUntil = os.clock() + math.max(0, tonumber(config.SuccessSFXCooldownSeconds) or 0.1)
		playSoundFromTemplate(config.SuccessSFXPath or { "ReplicatedStorage", "NPCSystem", "ClientAssets", "UpgradeSuccessSFX" })
	end
end

local function updateCountdownLabel()
	if not latestState or not ui then
		return
	end
	local rootGui = ui.Root and ui.Root:FindFirstAncestor("Shop")
	if not rootGui then
		return
	end
	local itemShop = rootGui:FindFirstChild("ItemShop")
	if not itemShop then
		return
	end
	local timeFrame = itemShop:FindFirstChild("Time")
	local timeLabel = timeFrame and timeFrame:FindFirstChild("TimeLabel")
	if not (timeLabel and timeLabel:IsA("TextLabel")) then
		return
	end

	local nextResetUnix = tonumber(latestState.NextResetUnix) or 0
	if nextResetUnix <= 0 then
		local fallback = "Next Stock in --:--"
		if lastCountdownText ~= fallback then
			timeLabel.Text = fallback
			lastCountdownText = fallback
		end
		return
	end

	local nowUnix = DateTime.now().UnixTimestamp
	local remaining = math.max(0, nextResetUnix - nowUnix)
	local minutes = math.floor(remaining / 60)
	local seconds = remaining % 60
	local text = ("Next Stock in %d:%02d"):format(minutes, seconds)
	if lastCountdownText ~= text then
		timeLabel.Text = text
		lastCountdownText = text
	end
end

local function setButtonEnabled(button, enabled)
	button.AutoButtonColor = enabled
	button.Active = enabled
	button.Selectable = enabled
	button.TextTransparency = enabled and 0 or 0.35
end

local function tryResolveShopNodes()
	local shopGui = playerGui:FindFirstChild("Shop")
	if not shopGui then
		return nil
	end
	local itemShop = shopGui:FindFirstChild("ItemShop")
	local items = itemShop and itemShop:FindFirstChild("Items")
	local other = items and items:FindFirstChild("Other")
	if not (other and other:IsA("ScrollingFrame")) then
		return nil
	end
	local template = other:FindFirstChild("1")
	if not (template and template:IsA("Frame")) then
		return nil
	end
	return {
		Root = other,
		Template = template,
	}
end

local function applyState()
	if not latestState or not ui then
		return
	end
	local equippedWeaponIds = latestState.EquippedWeaponIds or {}
	local weaponStatesById = latestState.WeaponStatesById or {}
	for _, weapon in ipairs(latestState.Weapons or {}) do
		local frame = itemFramesByWeaponId[weapon.Id]
		if frame then
			local nodes = findRequiredDescendants(frame)
			local stateEntry = weaponStatesById[weapon.Id] or {}
			local owned = stateEntry.Owned == true or (latestState.OwnedWeapons and latestState.OwnedWeapons[weapon.Id] == true)
			local equipped = stateEntry.Equipped == true or equippedWeaponIds[weapon.Id] == true or latestState.EquippedWeaponId == weapon.Id
			local stock = (latestState.StockByWeapon and latestState.StockByWeapon[weapon.Id]) or 0

			if nodes.Icon and nodes.Icon:IsA("ImageLabel") then
				nodes.Icon.Image = weapon.Icon or ""
			end
			if nodes.ItemName and nodes.ItemName:IsA("TextLabel") then
				nodes.ItemName.Text = weapon.DisplayName
			end
			if nodes.Price and nodes.Price:IsA("TextLabel") then
				nodes.Price.Text = WeaponShopFormatter.FormatPrice(weapon.Price)
			end
			if nodes.Stock and nodes.Stock:IsA("TextLabel") then
				nodes.Stock.Text = WeaponShopFormatter.FormatStock(stock)
			end
			if nodes.Rarity and nodes.Rarity:IsA("TextButton") then
				setNestedButtonLabelText("Rarity", nodes.RarityTextLabel, weapon.RarityName)
				nodes.Rarity.BackgroundColor3 = weapon.RarityColor
				if nodes.RarityTextLabel and nodes.RarityTextLabel:IsA("TextLabel") then
					nodes.RarityTextLabel.TextColor3 = weapon.RarityColor
				end
			end

			if nodes.Buy and nodes.Buy:IsA("TextButton") then
				local buttonText = typeof(stateEntry.ButtonText) == "string" and stateEntry.ButtonText or (owned and (equipped and "Equipped" or "Equip") or "Buy")
				local buttonEnabled = typeof(stateEntry.ButtonEnabled) == "boolean" and stateEntry.ButtonEnabled or (not equipped)
				setNestedButtonLabelText("Buy", nodes.BuyTextLabel, buttonText)
				setButtonEnabled(nodes.Buy, buttonEnabled)
			end

			if nodes.RobuxBuy and nodes.RobuxBuy:IsA("TextButton") then
				if owned then
					setButtonEnabled(nodes.RobuxBuy, false)
				else
					setButtonEnabled(nodes.RobuxBuy, weapon.RobuxProductId and weapon.RobuxProductId > 0)
				end
			end
		end
	end
end

local function buildItems(state)
	if not ui then
		return
	end
	clearGeneratedItems()
	for index, weapon in ipairs(state.Weapons or {}) do
		local weaponId = weapon.Id
		local clone = ui.Template:Clone()
		clone.Name = tostring(index)
		clone.Visible = true
		clone.Parent = ui.Root
		itemFramesByWeaponId[weaponId] = clone
		local nodes = findRequiredDescendants(clone)
		if nodes.Buy and nodes.Buy:IsA("TextButton") then
			local lastPressAt = 0
			local function onBuyPressed()
				local now = os.clock()
				if now - lastPressAt < 0.08 then
					return
				end
				lastPressAt = now
				if not latestState then
					return
				end
				local stateEntry = latestState.WeaponStatesById and latestState.WeaponStatesById[weaponId]
				local owned = (stateEntry and stateEntry.Owned == true) or (latestState.OwnedWeapons and latestState.OwnedWeapons[weaponId] == true)
				if owned then
					requestEquipWeapon:FireServer(weaponId)
				else
					purchaseWeapon:FireServer(weaponId)
				end
			end
			nodes.Buy.Activated:Connect(onBuyPressed)
			nodes.Buy.MouseButton1Click:Connect(onBuyPressed)
		end
		if nodes.RobuxBuy and nodes.RobuxBuy:IsA("TextButton") then
			local lastPressAt = 0
			local function onRobuxPressed()
				local now = os.clock()
				if now - lastPressAt < 0.08 then
					return
				end
				lastPressAt = now
				requestRobuxPurchase:FireServer(weaponId)
			end
			nodes.RobuxBuy.Activated:Connect(onRobuxPressed)
			nodes.RobuxBuy.MouseButton1Click:Connect(onRobuxPressed)
		end
	end
	applyState()
end

local function bindUiIfReady()
	local resolved = tryResolveShopNodes()
	if not resolved then
		return false
	end
	if ui and ui.Root == resolved.Root and ui.Template == resolved.Template then
		return true
	end
	clearGeneratedItems()
	ui = resolved
	ui.Template.Visible = false
	if latestState then
		buildItems(latestState)
	end
	return true
end

local function setState(newState)
	if typeof(newState) ~= "table" then
		return
	end
	latestState = newState
	if not bindUiIfReady() then
		return
	end
	updateCountdownLabel()
	if not hasValidGeneratedItems(newState) then
		buildItems(newState)
	else
		applyState()
	end
end

shopStateUpdated.OnClientEvent:Connect(function(newState)
	setState(newState)
end)

purchaseResult.OnClientEvent:Connect(function(result)
	if typeof(result) ~= "table" then
		return
	end
	if result.Success then
		if result.Code == "PURCHASED" or result.Code == "EQUIPPED" then
			playSuccessFeedback()
		end
		return
	end
	debugWarn(("[WeaponShopUIController] Action failed: %s"):format(tostring(result.Code)))
	if result.Code == "OUT_OF_STOCK" then
		showOutOfStockFeedback()
	elseif result.Code == "NOT_ENOUGH_MONEY" then
		showInsufficientMoneyFeedback()
	end
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Shop" then
		task.defer(function()
			bindUiIfReady()
			if latestState and not hasValidGeneratedItems(latestState) then
				buildItems(latestState)
			end
		end)
	end
end)

task.spawn(function()
	while not bindUiIfReady() do
		task.wait(0.5)
	end
	if latestState and not hasValidGeneratedItems(latestState) then
		buildItems(latestState)
	end
end)

RunService.RenderStepped:Connect(function()
	updateCountdownLabel()
end)

local initialState = requestShopState:InvokeServer()
setState(initialState)
