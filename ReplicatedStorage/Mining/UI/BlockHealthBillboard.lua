local BlockHealthBillboard = {}

local function getFill(frame: Frame): Frame?
	local barBackground = frame:FindFirstChild("BarBackground")
	if not barBackground or not barBackground:IsA("Frame") then
		return nil
	end
	local fill = barBackground:FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		return fill
	end
	return nil
end

function BlockHealthBillboard.Create(adornee: BasePart): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BlockHealthBillboard"
	billboard.Size = UDim2.fromOffset(70, 14)
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 10
	billboard.Adornee = adornee
	billboard.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = billboard

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.fromScale(1, 1)
	barBackground.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = frame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(74, 196, 86)
	fill.BorderSizePixel = 0
	fill.Parent = barBackground

	return billboard
end

function BlockHealthBillboard.Update(billboard: BillboardGui?, currentDurability: number, maxDurability: number)
	if not billboard or maxDurability <= 0 then
		return
	end

	local frame = billboard:FindFirstChild("Frame")
	if not frame or not frame:IsA("Frame") then
		return
	end

	local fill = getFill(frame)
	if not fill then
		return
	end

	local ratio = math.clamp(currentDurability / maxDurability, 0, 1)
	fill.Size = UDim2.fromScale(ratio, 1)
	billboard.Enabled = ratio < 1
end

return BlockHealthBillboard
