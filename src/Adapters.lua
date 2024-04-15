-- Implementation-dependent functions that *should* be customised.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require("src/Types")

local module: Types.Adapter = {
    Configuration = {
        HIGHLIGHTS_TIME = 10, -- Time to spend after the round ends before destroying the round
        PREPARING_TIME = 10, -- Time to spend after a round is created where players can join the round
        SLAY_VOTES = 2, -- Minimum number of votes to slay someone, at which point they will be slain
    },

    GiveEquipment = function(participant, item)
        -- Gives an item to a player. If the item is a function, calls it. The standard implementation uses the Backpack.
        -- Returns a string if there was an issue giving the item.
        if type(item.Item) == "function" then
            item.Item(participant, item.Name)
            return
        end
    
        local plr = participant.Player
        if not plr then 
            return "PlayerNotFound"
        end
        
        local backpack = plr:FindFirstChildOfClass("Backpack")
        if backpack and backpack:FindFirstChild(item.Item.Name) then
            return "EquipmentAlreadyInInventory"
        end
        item.Item:Clone().Parent = backpack
        return
    end,

    RemoveEquipment = function(participant, item)
        -- Removes an item from a player. The standard implementation uses the Backpack.
        if not participant.Player then
            return
        end
        return ((participant.Player:FindFirstChild("Backpack") :: Backpack):FindFirstChild(item.Name) :: Tool):Destroy()
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

        local remote: RemoteEvent = ReplicatedStorage:FindFirstChild("SendMessage") :: RemoteEvent
        
        if messageType ~= "roleAlert" then
            local fontColour = ""
            -- These colours suck
            if severity == "error" then
                fontColour = "#ff0000"
            elseif severity == "warn" then
                fontColour = "#ffff00"
            elseif severity == "info" then
                fontColour = "#0000ff"
            end
            message = `<font color='{fontColour}'>{message}</font>`
        end

        if isGlobal then
            return remote:FireAllClients(message)
        end
        for _, v in recipients do
            if v.Player then
                remote:FireClient(v.Player, message)
            end
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
    end,

    OnCharacterLoad = function(char)
        -- You could, for example, implement ragdolls here
    end,

    SendSlayVote = function(to, target)
        local remote: RemoteEvent = ReplicatedStorage:FindFirstChild("SlayVote") :: any
        if not to.Player then
            error("Attempt to send slay vote to disconnected Participant.")
        end
        remote:FireClient(to.Player, target.Player)
    end,
}

return module