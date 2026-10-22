local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local npcSystem = ReplicatedStorage:WaitForChild("NPCSystem")
local baseConfig = require(npcSystem.Config.BaseConfig)
local CompactNumberFormatter = require(npcSystem.Shared.CompactNumberFormatter)

local remotesFolder = npcSystem:WaitForChild("Remotes")
local moneySnapshotFunction = remotesFolder:WaitForChild(baseConfig.Remotes.MoneySnapshotFunctionName)

local leaderstats = player:WaitForChild("leaderstats")
local money = leaderstats:WaitForChild("Money")

local moneyGui = script.Parent
local moneyFrame = moneyGui:WaitForChild("MoneyFrame")
local backing = moneyFrame:WaitForChild("Backing")

local moneyLabel = backing:WaitForChild("MoneyLabel")
local textLabel = backing:WaitForChild("TextLabel")

local function sanitizeDigits(value: any): string
	if typeof(value) == "string" then
		local digits = value:gsub("[^0-9]", ""):gsub("^0+", "")
		if digits == "" then
			return "0"
		end
		return digits
	end
	if typeof(value) == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end
		if value <= 0 then
			return "0"
		end
		return tostring(math.floor(value + 0.0000001))
	end
	return "0"
end

local function fetchSnapshotDigits(): string
	local ok, result = pcall(function()
		return (moneySnapshotFunction :: RemoteFunction):InvokeServer()
	end)
	if not ok then
		return "0"
	end
	return sanitizeDigits(result)
end

local function getDisplayDigits(): string
	-- Primary: backend-replicated high-range money string.
	local attrDigits = sanitizeDigits(player:GetAttribute("MoneyString"))
	if attrDigits ~= "0" then
		return attrDigits
	end

	-- Secondary: authoritative server snapshot for late attribute races.
	local snapshotDigits = fetchSnapshotDigits()
	if snapshotDigits ~= "0" then
		player:SetAttribute("MoneyString", snapshotDigits)
		return snapshotDigits
	end

	-- Last fallback: leaderstats display value.
	return sanitizeDigits(money.Value)
end

local function updateUI()
	moneyLabel.Text = CompactNumberFormatter.FormatCurrency(getDisplayDigits(), "$")
end

player:GetAttributeChangedSignal("MoneyString"):Connect(updateUI)
money:GetPropertyChangedSignal("Value"):Connect(updateUI)
updateUI()
