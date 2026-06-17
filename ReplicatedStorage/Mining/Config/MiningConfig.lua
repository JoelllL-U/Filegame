local MiningConfig = {
	BlockSize = Vector3.new(4, 3.308, 3.861),
	GridSpacing = Vector3.new(0, 0, 0),

	ResetIntervalSeconds = 300,
	DefaultDurability = 30,
	PickaxeDamage = 5,
	MineRequestCooldown = 0.2,
	MaxMineDistance = 18,

	Highlight = {
		FillTransparency = 1,
		OutlineTransparency = 0,
		OutlineColor = Color3.new(1, 1, 1),
		DepthMode = Enum.HighlightDepthMode.Occluded,
	},

	ResetCountdown = {
		StudsAboveMine = 8,
		UpdateIntervalSeconds = 0.1,
		MaxDistance = 500,
	},

	References = {
		MineVolumeName = "MineVolume",
		MineExitPointName = "MineExitPoint",
		GeneratedFolderName = "GeneratedMineBlocks",
		MiningRootName = "Mining",
		TemplateFolderName = "BlockTemplates",
		RemotesFolderName = "Remotes",
		RequestMineBlockRemoteName = "RequestMineBlock",
		MineResetCountdownBillboardName = "MineResetCountdownBillboard",
	},
}

return MiningConfig
