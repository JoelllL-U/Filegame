local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local baseConfig = require(ReplicatedStorage.NPCSystem.Config.BaseConfig)

local BaseService = {}
BaseService.__index = BaseService

local bases: { Model } = {}
local baseByPlayer: { [Player]: Model } = {}
local ownerByBase: { [Model]: Player } = {}
local releaseCallbacks: { (Player, Model) -> () } = {}
local characterAddedConnectionByPlayer: { [Player]: RBXScriptConnection } = {}
local rebirthMultiplierConnectionByPlayer: { [Player]: RBXScriptConnection } = {}
local missingBasesFolderWarned = false
local noAvailableBaseWarnedByUserId: { [number]: boolean } = {}

local function shouldRediscoverBases(): boolean
	if #bases == 0 then
		return true
	end
	for _, baseModel in ipairs(bases) do
		if not baseModel.Parent then
			return true
		end
	end
	return false
end

local function resolveBaseOwnerImageLabel(baseModel: Model): ImageLabel?
	local baseOf = baseModel:FindFirstChild("BaseOf", true)
	if not baseOf then
		return nil
	end
	local guiPart = baseOf:FindFirstChild("GUIPart", true)
	if not guiPart then
		return nil
	end
	local surfaceGui = guiPart:FindFirstChildWhichIsA("SurfaceGui")
	if not surfaceGui then
		return nil
	end
	local imageLabel = surfaceGui:FindFirstChild("PlayerImage", true)
	if imageLabel and imageLabel:IsA("ImageLabel") then
		return imageLabel
	end
	return nil
end

local function updateBaseOwnerImage(baseModel: Model, player: Player?)
	local imageLabel = resolveBaseOwnerImageLabel(baseModel)
	if not imageLabel then
		return
	end
	if not player then
		imageLabel.Image = ""
		return
	end
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and typeof(content) == "string" then
		imageLabel.Image = content
	else
		imageLabel.Image = ""
	end
end

local function formatMultiplierNumber(value: number): string
	local roundedTenths = math.floor((value * 10) + 0.5) / 10
	if math.abs(roundedTenths - math.floor(roundedTenths + 0.0001)) < 0.0001 then
		return tostring(math.floor(roundedTenths + 0.0001))
	end
	return string.format("%.1f", roundedTenths)
end

local function resolveBaseMultiplierTextLabel(baseModel: Model): TextLabel?
	local multiplierPart = baseModel:FindFirstChild("Multiplier", true)
	if not (multiplierPart and multiplierPart:IsA("BasePart")) then
		return nil
	end
	local billboard = multiplierPart:FindFirstChildWhichIsA("BillboardGui")
	if not billboard then
		return nil
	end
	local textLabel = billboard:FindFirstChild("Textlabel", true)
	if textLabel and textLabel:IsA("TextLabel") then
		return textLabel
	end
	return nil
end

local function updateBaseMultiplierLabel(baseModel: Model, multiplier: number?)
	local textLabel = resolveBaseMultiplierTextLabel(baseModel)
	if not textLabel then
		return
	end
	local safeMultiplier = tonumber(multiplier) or 1
	if safeMultiplier < 0 then
		safeMultiplier = 0
	end
	textLabel.Text = ("%sx Money multiplier"):format(formatMultiplierNumber(safeMultiplier))
end

local function getBasesFolder(): Folder?
	local folder = Workspace:FindFirstChild(baseConfig.BasesFolderName)
	if folder and folder:IsA("Folder") then
		missingBasesFolderWarned = false
		return folder
	end
	if not missingBasesFolderWarned then
		warn(("[BaseService] Missing Workspace/%s folder"):format(baseConfig.BasesFolderName))
		missingBasesFolderWarned = true
	end
	return nil
end

local function discoverBases()
	table.clear(bases)
	local folder = getBasesFolder()
	if not folder then
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(bases, child)
		else
			warn(("[BaseService] Ignoring non-Model base %s"):format(child:GetFullName()))
		end
	end
end

local function getSpawnPart(baseModel: Model): BasePart?
	local part = baseModel:FindFirstChild(baseConfig.BaseSpawnPartName, true)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function teleportToBase(player: Player, baseModel: Model)
	if not baseConfig.TeleportToAssignedBaseOnCharacterAdded then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local spawnPart = getSpawnPart(baseModel)
	if not spawnPart then
		warn(("[BaseService] Base %s missing spawn part %s"):format(baseModel:GetFullName(), baseConfig.BaseSpawnPartName))
		return
	end
	root.CFrame = spawnPart.CFrame + Vector3.new(0, baseConfig.CharacterSpawnYOffset, 0)
end

function BaseService.RegisterReleaseCallback(callback: (Player, Model) -> ())
	table.insert(releaseCallbacks, callback)
end

function BaseService.GetBaseForPlayer(player: Player): Model?
	return baseByPlayer[player]
end

function BaseService.GetOwnerForBase(baseModel: Model): Player?
	return ownerByBase[baseModel]
end

function BaseService.IsOwner(player: Player, baseModel: Model): boolean
	return ownerByBase[baseModel] == player and baseByPlayer[player] == baseModel
end

function BaseService.AssignBase(player: Player): Model?
	if baseByPlayer[player] then
		return baseByPlayer[player]
	end
	if shouldRediscoverBases() then
		discoverBases()
	end

	for _, baseModel in ipairs(bases) do
		if not ownerByBase[baseModel] then
			ownerByBase[baseModel] = player
			baseByPlayer[player] = baseModel
			baseModel:SetAttribute("OwnerUserId", player.UserId)
			baseModel:SetAttribute("OwnerName", player.Name)
			updateBaseOwnerImage(baseModel, player)
			updateBaseMultiplierLabel(baseModel, tonumber(player:GetAttribute("RebirthMultiplier")) or 1)
			noAvailableBaseWarnedByUserId[player.UserId] = nil
			teleportToBase(player, baseModel)
			return baseModel
		end
	end

	if shouldRediscoverBases() then
		discoverBases()
		for _, baseModel in ipairs(bases) do
			if not ownerByBase[baseModel] then
				ownerByBase[baseModel] = player
				baseByPlayer[player] = baseModel
				baseModel:SetAttribute("OwnerUserId", player.UserId)
				baseModel:SetAttribute("OwnerName", player.Name)
				updateBaseOwnerImage(baseModel, player)
				updateBaseMultiplierLabel(baseModel, tonumber(player:GetAttribute("RebirthMultiplier")) or 1)
				noAvailableBaseWarnedByUserId[player.UserId] = nil
				teleportToBase(player, baseModel)
				return baseModel
			end
		end
	end

	if not noAvailableBaseWarnedByUserId[player.UserId] then
		warn(("[BaseService] No available base for %s"):format(player.Name))
		noAvailableBaseWarnedByUserId[player.UserId] = true
	end
	return nil
end

function BaseService.ReleaseBase(player: Player)
	local baseModel = baseByPlayer[player]
	if not baseModel then
		return
	end
	ownerByBase[baseModel] = nil
	baseByPlayer[player] = nil
	baseModel:SetAttribute("OwnerUserId", nil)
	baseModel:SetAttribute("OwnerName", nil)
	noAvailableBaseWarnedByUserId[player.UserId] = nil
	updateBaseOwnerImage(baseModel, nil)
	updateBaseMultiplierLabel(baseModel, 1)
	for _, callback in ipairs(releaseCallbacks) do
		callback(player, baseModel)
	end
end

function BaseService.UpdatePlayerBaseMultiplier(player: Player, multiplier: number)
	local baseModel = baseByPlayer[player]
	if not baseModel then
		return
	end
	updateBaseMultiplierLabel(baseModel, multiplier)
end

function BaseService.GetAllBases(): { Model }
	return bases
end

function BaseService.BindPlayer(player: Player): Model?
	local baseModel = BaseService.AssignBase(player)
	if characterAddedConnectionByPlayer[player] then
		characterAddedConnectionByPlayer[player]:Disconnect()
	end
	characterAddedConnectionByPlayer[player] = player.CharacterAdded:Connect(function()
		local assigned = baseByPlayer[player]
		if assigned then
			teleportToBase(player, assigned)
		end
	end)
	if rebirthMultiplierConnectionByPlayer[player] then
		rebirthMultiplierConnectionByPlayer[player]:Disconnect()
	end
	rebirthMultiplierConnectionByPlayer[player] = player:GetAttributeChangedSignal("RebirthMultiplier"):Connect(function()
		BaseService.UpdatePlayerBaseMultiplier(player, tonumber(player:GetAttribute("RebirthMultiplier")) or 1)
	end)
	BaseService.UpdatePlayerBaseMultiplier(player, tonumber(player:GetAttribute("RebirthMultiplier")) or 1)
	return baseModel
end

function BaseService.UnbindPlayer(player: Player)
	local connection = characterAddedConnectionByPlayer[player]
	if connection then
		connection:Disconnect()
		characterAddedConnectionByPlayer[player] = nil
	end
	local multiplierConnection = rebirthMultiplierConnectionByPlayer[player]
	if multiplierConnection then
		multiplierConnection:Disconnect()
		rebirthMultiplierConnectionByPlayer[player] = nil
	end
	BaseService.ReleaseBase(player)
end

function BaseService.Init()
	discoverBases()
	for _, baseModel in ipairs(bases) do
		updateBaseOwnerImage(baseModel, nil)
		updateBaseMultiplierLabel(baseModel, 1)
	end
end

return BaseService
