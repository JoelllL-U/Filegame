local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNumber = require(ReplicatedStorage.NPCSystem.Shared.BigNumber)

local baseUpgradeCost = "1000000"
local upgradeCosts = {}
upgradeCosts[1] = baseUpgradeCost
for upgradeIndex = 2, 20 do
	upgradeCosts[upgradeIndex] = BigNumber.MultiplySmall(upgradeCosts[upgradeIndex - 1], 7)
end

local BaseUpgradeConfig = {
	FloorSourceFolderName = "Floors",
	BaseLayoutIdAttributeName = "BaseLayoutId",
	DefaultUnlockedSlots = 10,
	LockedSlotAttributeName = "BaseUpgradeUnlocked",
	DynamicFloorAttributeName = "BaseUpgradeDynamicFloor",
	CurrentUpgradeAttributeName = "BaseUpgradeCount",
	CurrentUnlockedSlotsAttributeName = "BaseUpgradeUnlockedSlotCount",
	LockedSlotTransparency = 1,
	MaxCostText = "MAX",
	ProgressTextTemplate = "%d/%d",
	BaseUpgradeModelName = "BaseUpgrade",
	GUIPartName = "GUIPart",
	SurfaceGuiName = "SurfaceGui",
	AlertGuiName = "AlertGui",
	ButtonName = "Button",
	CostLabelName = "Cost",
	SlotCountLabelName = "SlotCount",
	RemoteEventName = "BaseUpgradeRequest",
	FeedbackRemoteEventName = "BaseUpgradeFeedback",
	FeedbackLabelPath = { "BaseUpgradeFeedbackGui", "BaseUpgradeFeedbackLabel" },
	AffordabilityPollIntervalSeconds = 0.5,
	PurchaseDebounceSeconds = 0.25,
	InsufficientFundsText = "No tienes suficiente dinero!",
	MaxUpgradeText = "Alcanzaste la mejora maxima!",
	FeedbackLabelShowSeconds = 1.2,
	InsufficientSFXPath = { "ReplicatedStorage", "NPCSystem", "ClientAssets", "UpgradeInsufficientSFX" },
	SuccessSFXPath = { "ReplicatedStorage", "NPCSystem", "ClientAssets", "UpgradeSuccessSFX" },
	InsufficientSFXCooldownSeconds = 1,
	DevResetCommand = "/resetbaseupgrades",
	DevResetStudioOnly = true,
	UpgradeCosts = upgradeCosts,
	FloorProgression = {
		{
			FloorName = "Floor2",
			StartSlot = 11,
			EndSlot = 20,
		},
		{
			FloorName = "Floor3",
			StartSlot = 21,
			EndSlot = 30,
		},
	},
}

return BaseUpgradeConfig
