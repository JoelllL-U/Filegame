export type RarityDefinition = {
	Id: string,
	DisplayName: string,
	Color: Color3,
	Weight: number,
}

export type NPCDefinition = {
	Id: string,
	TemplateName: string,
	DisplayName: string,
	MaxHealth: number,
	RarityId: string,
	AttackRadius: number,
	IncomePerSecond: number,
	BaseUpgradeCost: number,
	IdleAnimationId: string?,
	-- Future fields can be added here
}

export type NPCSpawnEntry = {
	Definition: NPCDefinition,
	Template: Model,
	Rarity: RarityDefinition,
}

export type RaritySpawnPoolEntry = {
	Rarity: RarityDefinition,
	NPCEntries: { NPCSpawnEntry },
}

export type NPCState = {
	Model: Model,
	SpawnPoint: BasePart,
	MaxHealth: number,
	CurrentHealth: number,
	DisplayName: string,
	RarityId: string,
	RarityDisplayName: string,
	RarityColor: Color3,
	LastHitter: Player?,
	LastHitterUserId: number?,
	LastHitterName: string?,
	Dead: boolean,
	GenerationPerSecond: number,
	DisplayRoot: Instance?,
	DisplayLifeLabel: TextLabel?,
	LastFlashAt: number,
}

export type SpawnPointState = {
	Part: BasePart,
	ActiveNPC: Model?,
	IsSpawning: boolean,
	CooldownUntil: number,
	CycleToken: number,
}

return {}
