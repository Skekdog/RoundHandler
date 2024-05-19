-- Implementation-dependent functions that *should* be customised.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local remotes = ReplicatedStorage.RoundHandler

local API = require(script.Parent.API)
local Types = require(script.Parent.Types)

local module: Types.Adapter = {
    Configuration = {
        HIGHLIGHTS_TIME = 10, -- Time to spend after the round ends before destroying the round
        PREPARING_TIME = 10, -- Time to spend after a round is created where players can join the round
        INTERMISSION_TIME = 10,
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
        
        local backpack = plr.Backpack
        if backpack:FindFirstChild(item.Item.Name) then
            return "EquipmentAlreadyInInventory"
        end
        item.Item:Clone().Parent = backpack
        return
    end,

    RemoveEquipment = function(participant, item)
        -- Removes an item from a player. The standard implementation uses the Backpack.
        local plr = participant.Player
        if not plr.Parent then
            return
        end

        local tool = plr.Backpack:FindFirstChild(item.Name)
        if not tool then
            return
        end
        tool:Destroy()
    end,

    CheckForUpdate = function(round)
        -- Return true if a server restart is needed, false if not.
        -- This could be checking a key in a DataStore for example.
        -- Updates will be checked for at the end of every round.
    
        -- The Round object is provided to allow decisions based on whether a Round is important enough for a restart.
    
        -- Additional processing, such as saving player data, can also be done here.

        if RunService:IsStudio() then
            return false
        end
    
        return false
    end,

    SendMessage = function(message, severity, messageType, recipients)
        -- Sends a private server message to each recipient.
        -- The message can be further processed here, such as using rich text to change text colour depending on severity.

        local remote = remotes.SendMessage
        
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
        return
    end,

    SendRoleAlert = function(recipient, role)
        local remote = remotes.SendRoleAlert
        remote:FireClient(recipient.Player, recipient.Role.FormattedName, role.Description)
    end,

    SendRoundHighlights = function(recipients, highlights, events, scores)
        local remote = remotes.SendRoundHighlights
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

    SetDefaultLighting = function()
        -- All values sourced from https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json
        Lighting.Ambient = Color3.new(0.5, 0.5, 0.5)
        Lighting.Brightness = 1
        Lighting.ClockTime = 14
        Lighting.ColorShift_Bottom = Color3.new()
        Lighting.ColorShift_Top = Color3.new()
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.ExposureCompensation = 0
        Lighting.FogColor = Color3.new(0.75, 0.75, 0.75)
        Lighting.FogEnd = 100000
        Lighting.FogStart = 0
        Lighting.GeographicLatitude = 41.7332993
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.new(0.5, 0.5, 0.5)
        Lighting.ShadowSoftness = 0.5
        Lighting.TimeOfDay = "14:00:00"
    end,

    SendSlayVote = function(to, target)
        local remote = remotes.SlayVote
        remote:FireClient(to.Player, target.Player)
    end,

    DoIntermission = function(round)
        local roundNumber = (ServerStorage:GetAttribute("RoundNumber") or -1) + 1 -- or -1, because +1, so then == 0, so % 5 == 0.
        ServerStorage:SetAttribute("RoundNumber", roundNumber)
        if roundNumber % 5 == 0 then
            -- also enable map voting here, or whatever
            return true
        end
        return false
    end,

    CalculateUserFacingEvents = function(events: Types.RoundEventLog, winners)
        local userFacingLog: {Types.UserFacingRoundEvent} = {}

        local function getDeathEvent(data: Types.RoundEvent_Death)
            local attacker = data.Attacker
            local weapon = data.Weapon
            local text = data.Victim.FormattedName

            local attackerName
            if attacker then
                attackerName = attacker.FormattedName
            end
            if weapon == "Fall" then
                text ..= " was doomed to fall"
                if attacker then
                    text ..= ` at the hands of {attackerName}`
                end
            elseif weapon == "Drown" then
                text ..= " was doomed to drown"
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
                local attack = weapon.AttackType
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

        for _, v in events.MetaEvent do
            local event = {
                Text = "",
                Icons = {},
                Category = "MetaEvent" :: Types.RoundEventCategory,
                Timestamp = v.Timestamp,
            }
            if v.Data.RoundPhase then
                event.Text = "The round begins."
            elseif v.Data.NewMap then
                event.Text = `The map changes to {v.Data.NewMap}.`
            elseif v.Data.Winners then
                event.Text = v.Data.Winners.VictoryText :: string
            end
            table.insert(userFacingLog, event)
        end

        for _, v in events.CorpseSearched do
            local event = {
                Text = "",
                Icons = {},
                Category = "CorpseSearched" :: Types.RoundEventCategory,
                Timestamp = v.Timestamp,
            }
            if v.Data.CreditsFound then
                event.Text = `{v.Data.Participant} found {v.Data.CreditsFound} credits on the body of {v.Data.Corpse}.`
            else
                event.Text = `{v.Data.Participant} found the body of {v.Data.Corpse}.`
            end
            table.insert(userFacingLog, event)
        end

        for _, v in events.Death do
            table.insert(userFacingLog, {
                Text = getDeathEvent(v.Data),
                Icons = {},
                Category = "Death",
                Timestamp = v.Timestamp
            })
        end

        table.sort(userFacingLog, function(a, b)
            return a.Timestamp < b.Timestamp
        end)

        return userFacingLog
    end,
}

return module