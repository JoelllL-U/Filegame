local MutationDefinitions = {
	Gold = {
		Id = "Gold",
		DisplayName = "Gold",
		Color = Color3.fromRGB(255, 215, 80),
		Weight = 50,
		IncomeMultiplier = 2.0,
		HealthMultiplier = 1.25,
	},
	Corrupted = {
		Id = "Corrupted",
		DisplayName = "Corrupted",
		Color = Color3.fromRGB(170, 80, 255),
		Weight = 100,
		IncomeMultiplier = 1.7,
		HealthMultiplier = 1.5,
	},
	Frozen = {
		Id = "Frozen",
		DisplayName = "Frozen",
		Color = Color3.fromRGB(120, 210, 255),
		Weight = 75,
		IncomeMultiplier = 1.35,
		HealthMultiplier = 1.2,
	},
}

return MutationDefinitions
