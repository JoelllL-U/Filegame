local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local miningRoot = ReplicatedStorage:WaitForChild("Mining")
local configFolder = miningRoot:WaitForChild("Config")
local uiFolder = miningRoot:FindFirstChild("UI")

local MiningConfig = require(configFolder:WaitForChild("MiningConfig"))
local MineGenerationService = require(script.Parent:WaitForChild("MineGenerationService"))

local MineResetCountdownBillboard = nil
if uiFolder and uiFolder:IsA("Folder") then
	local countdownModule = uiFolder:FindFirstChild("MineResetCountdownBillboard")
	if countdownModule and countdownModule:IsA("ModuleScript") then
		MineResetCountdownBillboard = require(countdownModule)
	else
		warn("MineResetCountdownBillboard missing in ReplicatedStorage/Mining/UI; countdown UI disabled")
	end
else
	warn("ReplicatedStorage/Mining/UI missing; countdown UI disabled")
end

local MineResetService = {}

local resetLock = false
local started = false
local nextResetAt = 0
local countdownBillboard: BillboardGui? = nil

local function isAliveCharacter(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function getMineVolume(): BasePart?
	local mineVolume = Workspace:FindFirstChild(MiningConfig.References.MineVolumeName)
	if mineVolume and mineVolume:IsA("BasePart") then
		return mineVolume
	end
	return nil
end

local function getExitPoint(): BasePart?
	local exitPoint = Workspace:FindFirstChild(MiningConfig.References.MineExitPointName)
	if exitPoint and exitPoint:IsA("BasePart") then
		return exitPoint
	end
	return nil
end

local function formatCountdown(secondsRemaining: number): string
	local totalSeconds = math.max(0, math.ceil(secondsRemaining))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("Mine resets in %02d:%02d", minutes, seconds)
end

local function ensureCountdownBillboard(mineVolume: BasePart?): BillboardGui?
	if not MineResetCountdownBillboard then
		return nil
	end

	if not mineVolume then
		return nil
	end

	local name = MiningConfig.References.MineResetCountdownBillboardName
	local existing = mineVolume:FindFirstChild(name)
	if existing and existing:IsA("BillboardGui") then
		countdownBillboard = existing
		countdownBillboard.Adornee = mineVolume
		countdownBillboard.StudsOffset = Vector3.new(0, MiningConfig.ResetCountdown.StudsAboveMine, 0)
		countdownBillboard.MaxDistance = MiningConfig.ResetCountdown.MaxDistance
		return countdownBillboard
	end

	if countdownBillboard and countdownBillboard.Parent then
		countdownBillboard:Destroy()
		countdownBillboard = nil
	end

	countdownBillboard = MineResetCountdownBillboard.Create(
		name,
		mineVolume,
		MiningConfig.ResetCountdown.StudsAboveMine,
		MiningConfig.ResetCountdown.MaxDistance
	)
	countdownBillboard.Parent = mineVolume
	return countdownBillboard
end

local function isInsideVolume(volume: BasePart, point: Vector3): boolean
	local localPoint = volume.CFrame:PointToObjectSpace(point)
	local half = volume.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function teleportOutOfMine(player: Player, exitPoint: BasePart)
	local character = player.Character
	if not character or not isAliveCharacter(character) then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	root.CFrame = exitPoint.CFrame + Vector3.new(0, 4, 0)
end

local function updateCountdownUi()
	if not MineResetCountdownBillboard then
		return
	end

	local mineVolume = getMineVolume()
	local ui = ensureCountdownBillboard(mineVolume)
	if not ui then
		return
	end

	local remaining = nextResetAt - os.clock()
	MineResetCountdownBillboard.UpdateText(ui, formatCountdown(remaining))
end

function MineResetService.IsResetting(): boolean
	return resetLock
end

function MineResetService.PerformReset()
	if resetLock then
		return
	end
	resetLock = true

	local mineVolume = getMineVolume()
	local exitPoint = getExitPoint()

	if mineVolume and exitPoint then
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and isInsideVolume(mineVolume, root.Position) then
				teleportOutOfMine(player, exitPoint)
			end
		end
	end

	MineGenerationService.RegenerateMine()
	nextResetAt = os.clock() + MiningConfig.ResetIntervalSeconds
	updateCountdownUi()
	resetLock = false
end

function MineResetService.Start()
	if started then
		return
	end
	started = true
	nextResetAt = os.clock() + MiningConfig.ResetIntervalSeconds
	updateCountdownUi()

	task.spawn(function()
		while started do
			local remaining = nextResetAt - os.clock()
			if remaining <= 0 then
				MineResetService.PerformReset()
			else
				updateCountdownUi()
				task.wait(MiningConfig.ResetCountdown.UpdateIntervalSeconds)
			end
		end
	end)
end

return MineResetService
