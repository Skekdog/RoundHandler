-- Implementation-dependent functions that *should* be customised.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:FindFirstChild("RoundHandler")

if not remotes then
	error("Missing remotes folder (RoundHandler)")
end

local API = require("src/API")
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
            item.Item(item, participant)
            return
        end
    
        local plr = participant.Player
        if not plr.Parent then
            return "PlayerDisconnected"
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
        if not participant.Player.Parent then
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

    SendMessage = function(message, severity, messageType, recipients)
        -- Sends a private server message to each recipient.
        -- The message can be further processed here, such as using rich text to change text colour depending on severity.

        local remote: RemoteEvent = remotes:FindFirstChild("SendMessage") :: RemoteEvent
        
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

        if recipients == true then
            return remote:FireAllClients(message, messageType)
        end
        for _, v in recipients do
            if v.Player then
                remote:FireClient(v.Player, message, messageType)
            end
        end
    end,

    SendRoleAlert = function(recipient, role)
        local remote: RemoteEvent = remotes:FindFirstChild("SendRoleAlert") :: RemoteEvent
        remote:FireClient(recipient.Player, recipient.Round:GetFormattedRole(role), role.Description)
    end,

    SendRoundHighlights = function(recipients, highlights, events, scores)
        local remote: RemoteEvent = remotes:FindFirstChild("SendHighlights") :: RemoteEvent
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

    CalculateDamageModifier = function(karma)
        return 1-((1000 - karma) / 1000)
    end,

    OnCharacterLoad = function(char)
        -- You could, for example, implement ragdolls here
    end,

    OnDeath = function(char)
        -- As above
    end,

    SendSlayVote = function(to, target)
        local remote: RemoteEvent = remotes:FindFirstChild("SlayVote") :: any
        remote:FireClient(to.Player, target.Player)
    end,

    CalculateUserFacingEvents = function(events, winners)
        local userFacingLog: {Types.UserFacingRoundEvent} = {}

        local function getDeathEvent(data: {Attacker: Types.Participant?, Weapon: string | Types.Equipment, Victim: Types.Participant})
            local attacker = data.Attacker
            local weapon = data.Weapon
            local text = data.Victim:GetFormattedName()

            local attackerName
            if attacker then
                attackerName = attacker:GetFormattedName()
            end
            if weapon == "Fall" then
                text ..= " was doomed to fall"
                if attacker then
                    text ..= ` at the hands of {attackerName}`
                end
            elseif weapon == "Drown" then
                text ..= " was doomed to fall"
                if attacker then
                    text ..= ` at the hands of {attackerName}`
                end
            elseif weapon == "Suicide" then
                text ..= " couldn't take it anymore and killed themselves"
            elseif weapon == "Crush" then
                text ..= " was crushed"
                if attacker then
                    text ..= ` by {attackerName}`
                end
            elseif weapon == "Mutation" then
                text ..= "'s DNA was mutated"
                if attacker then
                    text ..= ` by {attackerName}`
                end
            elseif type(weapon) == "table" then
                local attack: Types.WeaponAttackType | "None" = weapon.AttackType
                local name = API.StringWithDeterminer(weapon.Name)
                if attack == "Blade" then
                    text ..= `was stabbed by {name}`
                elseif attack == "Blunt" then
                    text ..= `was bludgeoned by {name}`
                elseif attack == "Explosion" then
                    text ..= `was blown up by {name}`
                elseif attack == "Firearm" then
                    text ..= `was shot by {name}`
                elseif attack == "None" then
                    text ..= `was murdered by magic`
                end
                if attacker then
                    text ..= ` used by {attackerName}`
                end
            end
            text ..= "."
            return text
        end

        for i: Types.RoundEventType, v in events do
            if i == "Death" then
                for _, event in v do
                    local data: Types.RoundEvent_Death = event.Data :: any
                    table.insert(userFacingLog, {
                        Text = getDeathEvent(data),
                        Icons = {},
                        Category = "Death",
                        Timestamp = event.Timestamp,
                    })
                end
            elseif i == "EquipmentGiven" then
                continue
            elseif i == "EquipmentPurchased" then
                for _, event in v do
                    local data: Types.RoundEvent_Equipment = event.Data :: any
                    table.insert(userFacingLog, {
                        Text = `{data.Target} purchased a {data.Equipment.Name}`,
                        Icons = {},
                        Category = "Equipment",
                        Timestamp = event.Timestamp,
                    })
                end
            elseif i == "EquipmentRemoved" then
                continue
            elseif i == "Round" then
                for _, event in v do
                    local phase: Types.RoundPhaseEventType = event.Data :: any
                    local text: string = ""
                    if phase == "Start" then
                        text = "The round begins."
                    elseif phase == "Pause" then
                        text = "The round is paused."
                    elseif phase == "Resume" then
                        text = "The round is resumed."
                    elseif phase == "NewMapLoaded" then
                        text = "A new map is loaded."
                    elseif phase == "End" then
                        text = winners.VictoryText :: string
                    end
                    table.insert(userFacingLog, {
                        Text = text,
                        Icons = {},
                        Category = "Round",
                        Timestamp = event.Timestamp,
                    })
                end
            end
        end

        table.sort(userFacingLog, function(a, b)
            return a.Timestamp < b.Timestamp
        end)

        return userFacingLog
    end,
}

return module