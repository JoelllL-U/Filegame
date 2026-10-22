local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local config = require(ReplicatedStorage:WaitForChild("NPCSystem"):WaitForChild("Config"):WaitForChild("NPCSpawnConfig"))
local indicatorConfig = config.ProximityIndicator

if not indicatorConfig or not indicatorConfig.Enabled then
	return
end

local ringStates: { [Model]: any } = {}
local updateAccumulator = 0

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

local function getNPCCenterAndBottomY(npcModel: Model): (Vector3?, number?)
	if not npcModel.Parent then
		return nil, nil
	end
	local boxCf, boxSize = npcModel:GetBoundingBox()
	local center = boxCf.Position
	local bottomY = center.Y - (boxSize.Y * 0.5)
	return center, bottomY
end

local function resolveAttackRadius(npcModel: Model): number
	local attackRadius = npcModel:GetAttribute("AttackRadius")
	if typeof(attackRadius) == "number" and attackRadius > 0 then
		return attackRadius
	end
	return indicatorConfig.DefaultAttackRadius
end

local function createSegment(parent: Folder): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = indicatorConfig.Color
	part.Transparency = indicatorConfig.HiddenTransparency
	part.Size = Vector3.new(indicatorConfig.SegmentLength, indicatorConfig.SegmentHeight, indicatorConfig.SegmentThickness)
	part.Name = "Segment"
	part.Parent = parent
	return part
end

local function ensureRingState(npcModel: Model)
	local existing = ringStates[npcModel]
	if existing then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "NPCProximityRing"
	folder.Parent = Workspace

	local segments = {}
	for _ = 1, indicatorConfig.SegmentCount do
		table.insert(segments, createSegment(folder))
	end

	local state = {
		Model = npcModel,
		Folder = folder,
		Segments = segments,
		Visible = false,
		Tweening = false,
		CurrentScale = indicatorConfig.ScaleInFrom,
		Position = Vector3.zero,
		Y = 0,
		AttackRadius = resolveAttackRadius(npcModel),
	}
	ringStates[npcModel] = state
	return state
end

local function layoutRing(state)
	local count = #state.Segments
	if count == 0 then
		return
	end

	local center = Vector3.new(state.Position.X, state.Y + indicatorConfig.HeightOffset, state.Position.Z)
	local radius = state.AttackRadius * state.CurrentScale
	for i, segment in ipairs(state.Segments) do
		if not segment or not segment.Parent then
			continue
		end

		local angle = ((i - 1) / count) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local position = center + radial * radius

		segment.CFrame = CFrame.fromMatrix(position, tangent, Vector3.yAxis, -radial)
	end
end

local function tweenRing(state, show: boolean)
	if state.Tweening or state.Visible == show then
		return
	end
	state.Tweening = true
	state.Visible = show

	local tweenTime = show and indicatorConfig.TweenInTime or indicatorConfig.TweenOutTime
	local targetTransparency = show and indicatorConfig.VisibleTransparency or indicatorConfig.HiddenTransparency
	local startScale = state.CurrentScale
	local endScale = show and 1 or indicatorConfig.ScaleInFrom
	local startTime = os.clock()

	local tweens = {}
	for _, segment in ipairs(state.Segments) do
		if segment and segment.Parent then
			table.insert(tweens, TweenService:Create(segment, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = targetTransparency,
			}))
		end
	end
	for _, tween in ipairs(tweens) do
		tween:Play()
	end

	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not state.Model.Parent then
			if conn then conn:Disconnect() end
			return
		end
		local alpha = math.clamp((os.clock() - startTime) / tweenTime, 0, 1)
		state.CurrentScale = startScale + ((endScale - startScale) * alpha)
		layoutRing(state)
		if alpha >= 1 then
			state.CurrentScale = endScale
			layoutRing(state)
			state.Tweening = false
			if conn then conn:Disconnect() end
		end
	end)
end

local function cleanupState(npcModel: Model)
	local state = ringStates[npcModel]
	if not state then
		return
	end
	if state.Folder then
		state.Folder:Destroy()
	end
	ringStates[npcModel] = nil
end

local function isValidNPCModel(instance: Instance): boolean
	if not instance:IsA("Model") then
		return false
	end
	if instance:GetAttribute("DefinitionId") == nil then
		return false
	end
	local currentHealth = instance:GetAttribute("CurrentHealth")
	return typeof(currentHealth) == "number" and currentHealth > 0
end

local function ensureNPCTracked(npcModel: Model)
	local state = ensureRingState(npcModel)
	state.AttackRadius = resolveAttackRadius(npcModel)
	local center, bottomY = getNPCCenterAndBottomY(npcModel)
	if not center or not bottomY then
		return
	end
	state.Position = center
	state.Y = bottomY
	layoutRing(state)
end

local function updateAll()
	local root = getCharacterRoot()
	for npcModel, state in pairs(ringStates) do
		if not npcModel.Parent or not isValidNPCModel(npcModel) then
			cleanupState(npcModel)
		else
			state.AttackRadius = resolveAttackRadius(npcModel)
			local center, bottomY = getNPCCenterAndBottomY(npcModel)
			if center and bottomY then
				state.Position = center
				state.Y = bottomY
				layoutRing(state)
			end

			if root and center then
				local distance = (root.Position - center).Magnitude
				local showDistance = state.AttackRadius
				local hideDistance = state.AttackRadius + indicatorConfig.RadiusHysteresisBuffer
				if state.Visible then
					if distance > hideDistance then
						tweenRing(state, false)
					end
				else
					if distance <= showDistance then
						tweenRing(state, true)
					end
				end
			elseif state.Visible then
				tweenRing(state, false)
			end
		end
	end

	local npcContainer = Workspace:FindFirstChild(config.NPCContainerName)
	if npcContainer and npcContainer:IsA("Folder") then
		for _, child in ipairs(npcContainer:GetChildren()) do
			if child:IsA("Model") and isValidNPCModel(child) then
				ensureNPCTracked(child)
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	updateAccumulator += dt
	if updateAccumulator < indicatorConfig.UpdateIntervalSeconds then
		return
	end
	updateAccumulator = 0
	updateAll()
end)

player.CharacterRemoving:Connect(function()
	for _, state in pairs(ringStates) do
		if state.Visible then
			tweenRing(state, false)
		end
	end
end)
