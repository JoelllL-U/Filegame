local MineResetCountdownBillboard = {}

function MineResetCountdownBillboard.Create(name: string, adornee: BasePart, studsAboveMine: number, maxDistance: number): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Size = UDim2.fromOffset(260, 48)
	billboard.StudsOffset = Vector3.new(0, studsAboveMine, 0)
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = maxDistance
	billboard.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "CountdownText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = Enum.Font.GothamBold
	label.TextSize = 26
	label.TextScaled = false
	label.TextWrapped = false
	label.Text = "Mine resets in 00:00"
	label.Parent = billboard

	return billboard
end

function MineResetCountdownBillboard.UpdateText(billboard: BillboardGui?, text: string)
	if not billboard then
		return
	end

	local label = billboard:FindFirstChild("CountdownText")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

return MineResetCountdownBillboard
