local RarityDefinitions = {
	Common = {
		Id = "Common",
		DisplayName = "Common",
		Color = Color3.fromRGB(200, 200, 200),
		Weight = 1,
	},
	Rare = {
		Id = "Rare",
		DisplayName = "Rare",
		Color = Color3.fromRGB(77, 159, 255),
		Weight = 50,
	},
	Epic = {
		Id = "Epic",
		DisplayName = "Epic",
		Color = Color3.fromRGB(179, 88, 255),
		Weight = 150,
	},
	Legendary = {
		Id = "Legendary",
		DisplayName = "Legendary",
		Color = Color3.fromRGB(255, 170, 60),
		Weight = 500,
	},
	Mythic = {
		Id = "Mythic",
		DisplayName = "Mythic",
		Color = Color3.fromRGB(255, 64, 64),
		Weight = 1200,
	},
	Secret = {
		Id = "Secret",
		DisplayName = "Secret",
		Color = Color3.fromRGB(255, 85, 127),
		Weight = 2500,
	},
}

return RarityDefinitions
