local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponShopRegistry = require(ReplicatedStorage.WeaponShop.Config.WeaponShopRegistry)

local WeaponShopRemotes = {}

local function resolvePath(pathSegments)
	local current = game
	for _, segment in ipairs(pathSegments) do
		local nextNode = current:FindFirstChild(segment)
		if not nextNode then
			nextNode = Instance.new("Folder")
			nextNode.Name = segment
			nextNode.Parent = current
		end
		current = nextNode
	end
	return current
end

function WeaponShopRemotes.Create()
	local config = WeaponShopRegistry.GetConfig()
	local remotesFolder = resolvePath(config.RemotesFolderPath)
	local remotes = {}

	local function getOrCreateRemote(className, remoteName)
		local existing = remotesFolder:FindFirstChild(remoteName)
		if existing and existing.ClassName == className then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		local remote = Instance.new(className)
		remote.Name = remoteName
		remote.Parent = remotesFolder
		return remote
	end

	remotes.RequestShopState = getOrCreateRemote("RemoteFunction", config.Remotes.RequestShopStateFunctionName)
	remotes.PurchaseWeapon = getOrCreateRemote("RemoteEvent", config.Remotes.PurchaseWeaponEventName)
	remotes.RequestEquipWeapon = getOrCreateRemote("RemoteEvent", config.Remotes.RequestEquipWeaponEventName)
	remotes.RequestRobuxPurchase = getOrCreateRemote("RemoteEvent", config.Remotes.RequestRobuxPurchaseEventName)
	remotes.ShopStateUpdated = getOrCreateRemote("RemoteEvent", config.Remotes.ShopStateUpdatedEventName)
	remotes.PurchaseResult = getOrCreateRemote("RemoteEvent", config.Remotes.PurchaseResultEventName)

	return remotes
end

return WeaponShopRemotes
