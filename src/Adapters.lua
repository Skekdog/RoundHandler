--!strict

-- Contains various modifiable functions to fit with a particular implementation of RoundHandler
-- That was a lot of words and it doesn't really mean anything :)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

    RemoveEquipment = function(plr, item)
        -- Removes an item from a player. The standard implementation uses the Backpack.
        if not plr.Player then
            return
        end
        return ((plr.Player:FindFirstChild("Backpack") :: Backpack):FindFirstChild(item.Name) :: Tool):Destroy()
    end,

    CheckForUpdate = function(round)
        -- Return true if a server restart is needed, false if not.
        -- This could be checking a key in a DataStore for example.
        -- Updates will be checked for at the end of every round.
    
        -- The Round object is provided to allow decisions based on whether a Round is important enough for a restart.
    
        -- Additional processing, such as saving player data, can also be done here.
    
        return false
    end,

    SendMessage = function(recipients, message, severity, messageType, isGlobal)
        -- If isGlobal = true, then recipients is empty. The adapter is expected to send this message to all connected players (Players:GetPlayers()).
        -- Sends a private server message to each recipient.
        -- The message can be further processed here, such as using rich text to change text colour depending on severity.
        
        local fontColour = ""
        -- These colours suck
        if severity == "error" then
            fontColour = "#ff0000"
        elseif severity == "warn" then
            fontColour = "#ffff00"
        elseif severity == "info" then
            fontColour = "#0000ff"
        end

        message = ("<font color='%s'>%s</font>"):format(fontColour, message)

        local remote: RemoteEvent = ReplicatedStorage:FindFirstChild("SendMessage") :: RemoteEvent

        if isGlobal then
            return remote:FireAllClients(message)
        end
        for _, v in recipients do
            remote:FireClient(v.Player, message)
        end
    end,

    SendRoundHighlights = function(recipients, highlights, events, scores)
        local remote: RemoteEvent = ReplicatedStorage:FindFirstChild("SendHighlights") :: RemoteEvent
        for _, v in recipients do
            remote:FireClient(v.Player, highlights, events, scores)
        end
    end,

    GetKarma = function(plr)
        -- This is only used when first adding the Participant to the round, Participant.Karma is used for the duration of the round.
        -- SetKarma() is used when the round ends.

        return plr:GetAttribute("Karma")
    end,

    SetKarma = function(plr, karma)
        plr:SetAttribute("Karma", karma)
    end
}

return module