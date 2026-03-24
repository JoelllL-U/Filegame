local RebirthConfig = {
	Remotes = {
		GetStateFunctionName = "GetRebirthState",
		RequestRebirthFunctionName = "RequestRebirth",
		StateChangedEventName = "RebirthStateChanged",
	},
	ProgressBar = {
		BackgroundMinScale = 0,
		BackgroundMaxScale = 1,
	},
	UI = {
		OpenScaleFrom = 0.82,
		OpenTweenSeconds = 0.22,
		CloseTweenSeconds = 0.18,
	},
	Tiers = {
		{
			RequiredMoney = "10000",
			Multiplier = 1.5,
			RewardMoney = "5000",
		},
		{
			RequiredMoney = "100000",
			Multiplier = 2,
			RewardMoney = "25000",
		},
		{
			RequiredMoney = "1000000",
			Multiplier = 3,
			RewardMoney = "100000",
		},
	},
}

return RebirthConfig
