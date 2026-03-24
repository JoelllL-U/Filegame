local CapturableFlowConfig = {
	GrabHoldDurationSeconds = 2,
	CarryUI = {
		ScreenGuiName = "BrainrotCarryGui",
		DisplayOrder = 50,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DropButtonName = "DropButton",
		DropButtonText = "Drop",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.92),
		Size = UDim2.fromOffset(180, 54),
		BackgroundColor3 = Color3.fromRGB(31, 31, 31),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 22,
		CornerRadius = UDim.new(0, 14),
		StrokeColor3 = Color3.fromRGB(255, 255, 255),
		StrokeTransparency = 0.15,
		StrokeThickness = 1.5,
	},
}

return CapturableFlowConfig
