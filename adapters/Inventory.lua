--!strict
--[[
    Implementation-specific functions related to managing the inventory. If using the default roblox system, functions can (for example) clone into or destroy items from plr.Backpack.
    Function names must remain the same.
]]

local types = require("src/Types")

local module: types.InventoryManager = {} :: types.InventoryManager

function module.GiveEquipment(plr, item)
    if type(item.Item) == "function" then
        return item.Item(plr, item.Name)
    end

    if not plr.Player then return end
    item.Item:Clone().Parent = plr.Player:FindFirstChild("Backpack")
    return
end

function module.RemoveEquipment(plr, itemName)
    if not plr.Player then return end
    return ((plr.Player:FindFirstChild("Backpack") :: Instance):FindFirstChild(itemName) :: Instance):Destroy()
end

return module