--!strict

-- Contains various modifiable functions to fit with a particular implementation of RoundHandler
-- That was a lot of words and it doesn't really mean anything :)

local Types = require("src/Types")

local module: Types.Adapter = {
    Configuration = {
        HIGHLIGHTS_TIME = 10, -- Time to spend after the round ends before destroying the round
        PREPARING_TIME = 10, -- Time to spend after a round is created where players can join the round
        INTERMISSION_TIME = 10, -- ?
    },

    GiveEquipment = function(plr, item)
        -- Gives an item to a player. If the item is a function, calls it. The standard implementation uses the Backpack.
        if type(item.Item) == "function" then
            return item.Item(plr, item.Name)
        end
    
        if not plr.Player then 
            return
        end
        item.Item:Clone().Parent = plr.Player:FindFirstChild("Backpack")
        return
    end,

    RemoveEquipment = function(plr, itemName)
        -- Removes an item from a player. The standard implementation uses the Backpack.
        if not plr.Player then
            return
        end
        return ((plr.Player:FindFirstChild("Backpack") :: Backpack):FindFirstChild(itemName) :: Tool):Destroy()
    end,

    CheckForUpdate = function(round)
        -- Return true if a server restart is needed, false if not.
        -- This could be checking a key in a DataStore for example.
        -- Updates will be checked for at the end of every round.
    
        -- The Round object is provided to allow decisions based on whether a Round is important enough for a restart.
    
        -- Additional processing, such as saving player data, can also be done here.
    
        return false
    end,

    SendMessage = function(recipients, message, severity)
        -- Sends a private server message to each recipient.
        -- The message can be further processed here, such as using rich text to change text colour depending on severity.
        
        print(("Sending %s '%s' to {%s}"):format(severity, message, table.concat(recipients, ", ")))
    end
}

return module