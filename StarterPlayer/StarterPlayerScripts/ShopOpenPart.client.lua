local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local config = require(ReplicatedStorage.WeaponShop.Config.WeaponShopConfig)

local OPEN_PART_NAME = "OpenShopPart"
local TWEEN_SECONDS = 1

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lastWarnAtByKey = {}

local function debugWarn(message)
	if config.EnableDebugWarnings then
		warn(message)
	end
end

local function debugWarnThrottled(key: string, message: string, intervalSeconds: number)
	if not config.EnableDebugWarnings then
		return
	end
	local now = os.clock()
	local last = lastWarnAtByKey[key]
	if last and now - last < intervalSeconds then
		return
	end
	lastWarnAtByKey[key] = now
	warn(message)
end

local function isPointInsidePart(part: BasePart, worldPoint: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local half = part.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function getCharacterRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local state = {
	OpenPart = nil :: BasePart?,
	ShopGui = nil :: ScreenGui?,
	ItemShop = nil :: Frame?,
	OpenPosition = nil :: UDim2?,
	ClosedPosition = nil :: UDim2?,
	ActiveTween = nil :: Tween?,
	IsOpen = false,
	TouchingCharacterParts = 0,
	TouchingParts = {} :: { [BasePart]: boolean },
	TouchConnection = nil :: RBXScriptConnection?,
	TouchEndedConnection = nil :: RBXScriptConnection?,
}

local function resetTouchTracking()
	state.TouchingCharacterParts = 0
	state.TouchingParts = {}
end

local function resolveOpenPart(): BasePart?
	if state.OpenPart and state.OpenPart.Parent then
		return state.OpenPart
	end
	local candidate = Workspace:FindFirstChild(OPEN_PART_NAME)
	if not candidate then
		debugWarnThrottled("missing_open_part", ("[ShopOpenPart] Waiting for Workspace.%s"):format(OPEN_PART_NAME), 5)
		state.OpenPart = nil
		return nil
	end
	if not candidate:IsA("BasePart") then
		debugWarnThrottled("invalid_open_part", ("[ShopOpenPart] %s exists but is not a BasePart"):format(OPEN_PART_NAME), 5)
		state.OpenPart = nil
		return nil
	end
	state.OpenPart = candidate
	resetTouchTracking()
	if state.TouchConnection then
		state.TouchConnection:Disconnect()
	end
	if state.TouchEndedConnection then
		state.TouchEndedConnection:Disconnect()
	end
	state.TouchConnection = candidate.Touched:Connect(function(otherPart)
		local character = player.Character
		if not character or not otherPart:IsDescendantOf(character) then
			return
		end
		if not state.TouchingParts[otherPart] then
			state.TouchingParts[otherPart] = true
			state.TouchingCharacterParts += 1
			debugWarnThrottled("touch_enter", "[ShopOpenPart] Character touched open part", 0.25)
		end
	end)
	state.TouchEndedConnection = candidate.TouchEnded:Connect(function(otherPart)
		if state.TouchingParts[otherPart] then
			state.TouchingParts[otherPart] = nil
			state.TouchingCharacterParts = math.max(0, state.TouchingCharacterParts - 1)
			debugWarnThrottled("touch_exit", "[ShopOpenPart] Character left open part touch", 0.25)
		end
	end)
	debugWarn(("[ShopOpenPart] Bound trigger part %s"):format(candidate:GetFullName()))
	return state.OpenPart
end

local function resolveShopNodes(): (ScreenGui?, Frame?)
	if state.ShopGui and state.ShopGui.Parent and state.ItemShop and state.ItemShop.Parent then
		return state.ShopGui, state.ItemShop
	end

	local shopGui = playerGui:FindFirstChild("Shop")
	if not (shopGui and shopGui:IsA("ScreenGui")) then
		debugWarnThrottled("missing_shop_gui", "[ShopOpenPart] Waiting for PlayerGui.Shop ScreenGui", 5)
		state.ShopGui = nil
		state.ItemShop = nil
		return nil, nil
	end

	local itemShop = shopGui:FindFirstChild("ItemShop")
	if not (itemShop and itemShop:IsA("Frame")) then
		debugWarnThrottled("missing_item_shop", "[ShopOpenPart] Waiting for Shop.ItemShop Frame", 5)
		state.ShopGui = shopGui
		state.ItemShop = nil
		return shopGui, nil
	end

	state.ShopGui = shopGui
	state.ItemShop = itemShop
	state.OpenPosition = itemShop.Position
	state.ClosedPosition = state.OpenPosition + UDim2.new(1, 0, 0, 0)
	debugWarn(("[ShopOpenPart] Bound ItemShop frame at %s"):format(shopGui:GetFullName()))

	if not state.IsOpen then
		itemShop.Visible = false
		itemShop.Position = state.ClosedPosition
		shopGui.Enabled = false
	end

	return shopGui, itemShop
end

local tweenInfo = TweenInfo.new(TWEEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function playTween(targetPosition: UDim2, onComplete)
	if not state.ItemShop then
		return
	end
	if state.ActiveTween then
		state.ActiveTween:Cancel()
		state.ActiveTween = nil
	end
	state.ItemShop.Visible = true
	state.ActiveTween = TweenService:Create(state.ItemShop, tweenInfo, { Position = targetPosition })
	state.ActiveTween.Completed:Once(function()
		state.ActiveTween = nil
		if onComplete then
			onComplete()
		end
	end)
	state.ActiveTween:Play()
end

local function openShop(reason: string)
	if state.IsOpen then
		return
	end
	if not (state.ShopGui and state.ItemShop and state.OpenPosition) then
		return
	end
	state.IsOpen = true
	state.ShopGui.Enabled = true
	state.ItemShop.Visible = true
	debugWarn(("[ShopOpenPart] Opening shop (%s)"):format(reason))
	playTween(state.OpenPosition, nil)
end

local function closeShop(reason: string)
	if not state.IsOpen then
		return
	end
	if not (state.ShopGui and state.ItemShop and state.ClosedPosition) then
		state.IsOpen = false
		return
	end
	state.IsOpen = false
	debugWarn(("[ShopOpenPart] Closing shop (%s)"):format(reason))
	playTween(state.ClosedPosition, function()
		if state.IsOpen then
			return
		end
		if state.ItemShop then
			state.ItemShop.Visible = false
		end
		if state.ShopGui then
			state.ShopGui.Enabled = false
		end
	end)
end

RunService.RenderStepped:Connect(function()
	resolveOpenPart()
	resolveShopNodes()

	local root = getCharacterRoot()
	if not root then
		closeShop("no_root")
		return
	end

	if not (state.OpenPart and state.ShopGui and state.ItemShop) then
		closeShop("missing_bindings")
		return
	end

	local insideByPosition = isPointInsidePart(state.OpenPart, root.Position)
	local insideByTouch = state.TouchingCharacterParts > 0
	if insideByTouch or insideByPosition then
		openShop(insideByTouch and "touch" or "position")
	else
		closeShop("outside")
	end
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Shop" then
		debugWarn("[ShopOpenPart] Detected Shop GUI added to PlayerGui")
		state.ShopGui = nil
		state.ItemShop = nil
		state.OpenPosition = nil
		state.ClosedPosition = nil
	end
end)

player.CharacterAdded:Connect(function()
	resetTouchTracking()
	closeShop("character_added")
end)
