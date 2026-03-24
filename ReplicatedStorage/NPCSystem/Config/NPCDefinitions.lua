local NPCDefinitions = {
	Slime = {
		Id = "Slime",
		TemplateName = "Slime",
		DisplayName = "Slime",
		MaxHealth = 100,
		RarityId = "Common",
		AttackRadius = 7,
		IncomePerSecond = 2,
		BaseUpgradeCost = 100,
		AliveLifetimeSeconds = 60,
		CapturableLifetimeSeconds = 25,
		IdleAnimationId = "", -- Optional; set rbxassetid://... to enable captured idle animation
	},
	Goblin = {
		Id = "Goblin",
		TemplateName = "Goblin",
		DisplayName = "Goblin",
		MaxHealth = 180,
		RarityId = "Rare",
		AttackRadius = 8.5,
		IncomePerSecond = 4,
		BaseUpgradeCost = 225,
		AliveLifetimeSeconds = 75,
		CapturableLifetimeSeconds = 30,
	},
	Knight = {
		Id = "Knight",
		TemplateName = "Knight",
		DisplayName = "Knight",
		MaxHealth = 320,
		RarityId = "Epic",
		AttackRadius = 10.5,
		IncomePerSecond = 7,
		BaseUpgradeCost = 400,
		AliveLifetimeSeconds = 90,
		CapturableLifetimeSeconds = 35,
	},
}

return NPCDefinitions
