-- Based off of GMod TTT.

local Types = require("src/Types")
local common = require("examples/gamemodes/Common")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local items = ReplicatedStorage.Items

local module: Types.Gamemode = {
    Name = "Those You Trust",
    Description = "Spy HQ has been infiltrated by Traitor spies. Can you separate those you trust, from those you shouldn't?",

    EngineVersion = "0.0.1",

    MinimumPlayers = 1,
    RecommendedPlayers = 4,
    MaximumPlayers = 32,
    
    TimeoutVictors = function(self)
        return self.Roles[3]
    end,
    PhyrricVictors = "Traitor",

    CalculateRoundHighlights = function(self, round)
        local weaponList = common.GetWeaponHighlights(round.EventLog)
        local highlights: {Types.RoundHighlight} = {}
        
        for equipmentName, v in weaponList do
            local username = v[1]
            local amount = v[2]

            local name = ""
            local description = ""

            if amount < 2 then
                continue
            end

            if equipmentName == "Crowbar" then
                if amount >= 4 then
                    name = "Gordonite"
                    description = `{username} smeared their Crowbar in the brains of no less than {amount} people.`
                else
                    name = "It's like a crow's beak"
                    description = `{username} thought their Crowbar looked funny and showed it to {amount} people.`
                end
            elseif equipmentName == "Pistol" then
                if amount >= 4 then
                    name = "Persistent Little Bugger"
                    description = `{username} scored {amount} kills with their pistol. They then went on and hugged someone to death.`
                else
                    name = "Small Arms Slaughter"
                    description = `{username} killed a small army of {amount} using only their pistol. Presumably had a tiny shotgun installed in the barrel.`
                end
            end

            table.insert(highlights, {
                Name = name,
                Description = description
            })
        end


        local deathLog = round.EventLog.Death
        local firstKill: (Types.RoundEvent_Death & {Attacker: Types.Participant})?
        local eventIndex = 1
        while (eventIndex < #deathLog) and (not firstKill) do
            eventIndex += 1
            firstKill = deathLog[eventIndex]
            if not firstKill or not firstKill.Attacker then
                firstKill = nil
            end
        end
        if firstKill then
            local aRole = firstKill.Attacker.Role.Allegiance
            local vRole = firstKill.Victim.Role.Allegiance

            local attackerName = firstKill.Attacker.FormattedName
            if (aRole == "Traitor") and (vRole == "Traitor") then
                table.insert(highlights, {
                    Name = "First Bloody Stupid Kill",
                    Description = `{attackerName} scored the first kill by shooting a fellow traitor. Good job.`
                })
            elseif (aRole == "Innocent") and (vRole == "Traitor") then
                table.insert(highlights, {
                    Name = "First Blow",
                    Description = `{attackerName} struck the first blow for the innocents by making the first death a traitor's.`
                })
            elseif ((aRole == "Innocent") and (vRole == "Innocent")) and ((not firstKill.SelfDefense) and (not firstKill.FreeKill)) then
                table.insert(highlights, {
                    Name = "First Blooper",
                    Description = `{attackerName} was the first to kill. Too bad it was an innocent comrade.`
                })
            elseif (aRole == "Traitor") and (vRole == "Innocent") then
                table.insert(highlights, {
                    Name = "First Blood",
                    Description = `{attackerName} delivered the first innocent death at a traitor's hands.`
                })
            end
        end

        local mostAllyKills: {any} = {"", 0} -- username, amount
        local mostEnemyKills: {any} = {"", 0} -- username, amount
        for _, participant in round.Participants do
            local allyKills = 0
            local enemyKills = 0
            for _, kill in participant.KillList do
                if (round:GetRoleRelationship(participant.Role, kill.Role) == "__Ally") then
                    if (not kill.KilledInSelfDefense) then
                        allyKills += 1
                    end
                else
                    enemyKills += 1
                end
            end

            if allyKills > mostAllyKills[2] then
                mostAllyKills = {participant.Player.Name, allyKills}
            end
            if enemyKills > mostEnemyKills[2] then
                mostEnemyKills = {participant.Player.Name, enemyKills}
            end
        end

        if mostAllyKills[2] > 3 then
            table.insert(highlights, {
                Name = "Roleplayer",
                Description = `{mostAllyKills[1]} was role-playing a madman, honest. That's why they killed most of their team.`
            })
        elseif mostAllyKills[2] == 2 then
            table.insert(highlights, {
                Name = "Double Oops",
                Description = `{mostAllyKills[1]} had their finger "slip" twice when they were just aiming at a "buddy".`
            })
        elseif mostAllyKills[2] == 1 then
            table.insert(highlights, {
                Name = "Butterfingers",
                Description = `{mostAllyKills[1]} had their finger slip when they were just aiming at a buddy.`
            })
        end

        return highlights
    end,

    FriendlyFire = true,
    SelfDefense = true,
    UseKarma = true,

    StartingCredits = 0,
    StartingEquipment = {"Crowbar"},
    AvailableEquipment = {
        {
            Name = "Crowbar",
            Description = "Become a Gordonite",
            Cost = 0,
            Icon = "rbxassetid://",
            MaxStock = 1,

            AttackType = "Blunt",
            NoGuilt = false,

            Item = items.Crowbar
        },
        {
            Name = "Pistol",
            Description = "Reliable",
            Cost = 0,
            Icon = "rbxassetid://",
            MaxStock = 1,

            AttackType = "Firearm",
            NoGuilt = false,

            Item = items.Pistol
        },
        {
            Name = "Grenade",
            Description = "Boom",
            Cost = 1,
            Icon = "rbxassetid://",
            MaxStock = 1,

            AttackType = "Explosion",
            NoGuilt = false,

            Item = items.Grenade
        },
        {
            Name = "Radar",
            Description = "Beep... beep... beep",
            Cost = 1,
            Icon = "rbxassetid://",
            MaxStock = 1,

            AttackType = "None",
            NoGuilt = true,

            Item = function(item, participant)
                print(`{participant.Player.Name} got radar`)
            end,
        },
        {
            Name = "C4",
            Description = "Kaboom",
            Cost = 1,
            Icon = "rbxassetid://",
            MaxStock = 2,
            Item = items.C4,

            AttackType = "Explosion",
            NoGuilt = true,
        }
    },

    Roles = {
        {
            Name = "Traitor",
            FormattedName = "<font color='#ff0000>Traitor</font>",
            Description = "Work with the other Traitors to defeat all the Innocents. Keep your role secret.",
            Colour = Color3.new(1, 0, 0),
            Extras = {
                AssignmentProportion = 0.25,
                AssignmentPriority = 1,
            },

            Allies = {"Traitor"},
            Allegiance = "Traitor",
            VictoryMusic = {},
            VictoryText = "The dastardly traitors have won the round!",

            AnnounceDisconnect = true,
            CanStealCredits = true,
            AwardOnDeath = {
                Detective = 1,
            },
            CorpseResultsPublicised = false,
            CanSeeMissing = true,

            StartingCredits = 2,
            StartingEquipment = {},
            EquipmentShop = {"Grenade"},

            Accessories = {},
            Health = 100,
            Speed = 16,
            JumpPower = 18,

            HighlightRules = {
                __Ally = true,
            },
            KnowsRoles = {
                Traitor = true,
                Detective = true,
            },
            TeamChat = true,

            OnRoleAssigned = function() end,
            OnRoleRemoved = function() end,
        },
        {
            Name = "Detective",
            FormattedName = "<font color='#0000ff>Detective</font>",
            Description = "Work with the Innocents to identify the Traitors.",
            Colour = Color3.new(0, 0, 1),
            Extras = {
                AssignmentProportion = 0.125,
                AssignmentPriority = 2,
            },

            Allies = {"Innocent", "Detective"},
            Allegiance = "Innocent",

            AnnounceDisconnect = true,
            CanStealCredits = true,
            AwardOnDeath = {
                Traitor = 1,
            },
            CorpseResultsPublicised = true,
            CanSeeMissing = false,

            StartingCredits = 2,
            StartingEquipment = {},
            EquipmentShop = {"Radar"},

            Accessories = {},
            Health = 100,
            Speed = 16,
            JumpPower = 18,

            HighlightRules = {},
            KnowsRoles = {
                Detective = true,
            },
            TeamChat = false,

            OnRoleAssigned = function() end,
            OnRoleRemoved = function() end,
        },
        {
            Name = "Innocent",
            FormattedName = "<font color='#00ff00>Innocent</font>",
            Description = "Survive the Traitors.",
            Colour = Color3.new(0, 1, 0),
            Extras = {
                AssignmentProportion = 0.625,
                AssignmentPriority = 3,
            },

            Allies = {"Detective", "Innocent"},
            Allegiance = "Innocent",
            VictoryMusic = {},
            VictoryText = "The loveable innocents have won the round!",

            AnnounceDisconnect = false,
            CanStealCredits = false,
            AwardOnDeath = {},
            CorpseResultsPublicised = false,
            CanSeeMissing = false,

            StartingCredits = 0,
            StartingEquipment = {},
            EquipmentShop = {},

            Accessories = {},
            Health = 100,
            Speed = 16,
            JumpPower = 18,

            HighlightRules = {},
            KnowsRoles = {
                Detective = true,
            },
            TeamChat = false,

            OnRoleAssigned = function() end,
            OnRoleRemoved = function() end,
        }
    },

    AssignRoles = function(self, participants)
        -- Participants are already shuffled, no need to do it here
        local roles = self.Roles
        -- Sort roles by lowest AssignmentPriority. These roles will be assigned first.
        -- The greatest value for AssignmentPriority is used as a backup role for anyone who did not receive their role.
        -- Lower AssignmentPriority values will be used first, if there are not enough players for a proper round.
        -- e.g, Traitor will be assigned first, then detective. In a one player server, there will only be a Traitor.
        table.sort(roles, function(role1, role2)
            assert(role1.Extras and role2.Extras) -- Extras is not standard, but this gamemode also isn't standard.
            return role1.Extras.AssignmentPriority < role2.Extras.AssignmentPriority
        end)
        
        local roleToAssign, roleToAssignIndex = roles[1], 1
        local total, subtractFromI = #participants, 0
        for i, v in participants do
            assert(roleToAssign.Extras) -- Extras is still not standard, but this gamemode also still isn't standard.
            
            -- The greatest AssignmentPriority is used as a bargain bin, anyone who wasn't assigned to the other roles gets assigned here
            if ((i - subtractFromI) > math.max(total * roleToAssign.Extras.AssignmentProportion, 1)) and roleToAssignIndex < #roles then
                -- If we have already assigned enough people to this role, start assigning to the next role
                
                roleToAssignIndex += 1
                roleToAssign = roles[roleToAssignIndex] -- Go to the next role
                subtractFromI = i - 1 -- Start counting for how many people to assign from where we start assigning. -1 because lua is 1-indexed
            end
            v:AssignRole(roleToAssign) -- Hand it over to the module to assign the role
        end
    end,

    OnDeath = function(self, victim)
        local round = victim.Round

        local winner = common.TestForOneSurvivingRole(self, round)
        if winner then
            round:EndRound(round:GetRoleFromName(winner))
        end
    end,
    
    Duration = function(self, numParticipants)
        return 120 + (numParticipants * 10)
    end,

    OnCharacterLoad = function(self, char)
        local healthScript = char:FindFirstChild("Health")
        if healthScript then
            healthScript:Destroy()
        end
    end
}

return module