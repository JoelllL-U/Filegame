local NPCVisualConfig = {
	MutationHighlight = {
		Name = "MutationHighlight",
		FillTransparency = 0.45,
		OutlineTransparency = 1,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	},
	MutationVisuals = {
		Gold = {
			ModelColor = Color3.fromRGB(255, 215, 80),
			EasyVisuals = {
				Preset = "RainbowStroke",
				Speed = 0.01,
				Size = 6,
			},
		},
		Corrupted = {
			ModelColor = Color3.fromRGB(170, 80, 255),
			EasyVisuals = {
				Preset = "RainbowStroke",
				Speed = 0.0125,
				Size = 6,
			},
		},
		Frozen = {
			ModelColor = Color3.fromRGB(120, 210, 255),
			EasyVisuals = {
				Preset = "RainbowStroke",
				Speed = 0.015,
				Size = 5,
			},
		},
	},
	RarityVisuals = {
		Common = {
			EasyVisuals = nil,
		},
		Rare = {
			EasyVisuals = {
				Preset = "RainbowStroke",
				Speed = 0.02,
				Size = 4,
			},
		},
		Epic = {
			EasyVisuals = {
				Preset = "RainbowStroke",
				Speed = 0.015,
				Size = 5,
			},
		},
		Legendary = {
			EasyVisuals = {
				Preset = "RainbowStroke",
				Speed = 0.01,
				Size = 6,
			},
		},
		Secret = {
			EasyVisuals = {
				Preset = "RainbowStroke",
				Speed = 0.0075,
				Size = 7,
			},
		},
	},
}

return NPCVisualConfig
