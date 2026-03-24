local GameplaySFXConfig = {
	RemoteEventName = "GameplaySFX",
	TemplateFolderPath = { "ReplicatedStorage", "NPCSystem", "ClientAssets", "GameplaySFX" },
	CleanupBufferSeconds = 0.35,
	Defaults = {
		RollOffMinDistance = 8,
		RollOffMaxDistance = 70,
		Volume = 0.75,
		PlaybackSpeed = 1,
		CooldownSeconds = 0.08,
	},
	Events = {
		EnemyHit = {
			TemplateName = "EnemyHit",
			Volume = 0.85,
			PlaybackSpeed = 1.02,
			CooldownSeconds = 0.05,
			Spatial = true,
		},
		EnemyKill = {
			TemplateName = "EnemyKill",
			Volume = 0.95,
			PlaybackSpeed = 1,
			CooldownSeconds = 0.1,
			Spatial = true,
		},
		BrainrotGrab = {
			TemplateName = "BrainrotGrab",
			Volume = 0.8,
			PlaybackSpeed = 1.05,
			CooldownSeconds = 0.08,
			Spatial = true,
		},
		BrainrotDrop = {
			TemplateName = "BrainrotDrop",
			Volume = 0.7,
			PlaybackSpeed = 0.9,
			CooldownSeconds = 0.08,
			Spatial = true,
		},
		BrainrotPlace = {
			TemplateName = "BrainrotPlace",
			Volume = 0.82,
			PlaybackSpeed = 0.98,
			CooldownSeconds = 0.08,
			Spatial = true,
		},
	},
}

return GameplaySFXConfig
