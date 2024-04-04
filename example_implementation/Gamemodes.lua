--!strict
local Types = require("src/Types")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local items = ReplicatedStorage:WaitForChild("Items")

--- A simple victory checker. If only one allegiance is alive, they win.
--- Returns the role name of the winner, or nil if nobody has won yet.
local function TestForOneSurvivingRole(self: Types.Gamemode, round: Types.Round): string?
    local allegiances = {}
    for _, v in self.Roles do
        if not table.find(allegiances, v.Allegiance) then
            table.insert(allegiances, v.Allegiance)
        end
    end

    if #allegiances ~= 2 then
        error("TestForOneSurvivingRole Victory Checker only works if there are 2 teams!")
    end

    local function checkAlive(participant: Types.Participant)
        -- Remember what they took from you: https://github.com/luau-lang/luau/pull/501
        local plr = participant.Player
        if not plr then return end
        local char = plr.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        return hum.Health > 0
    end

    local rolesAlive = {
        [allegiances[1]] = false,
        [allegiances[2]] = false,
    }
    for _, v in round.Participants do
        if checkAlive(v) then
            rolesAlive[v:GetAllegiance().Name] = true
        end
        if rolesAlive[allegiances[1]] and rolesAlive[allegiances[2]] then
            return -- Both roles are still alive, nobody wins yet
        end
    end

    if rolesAlive[allegiances[1]] then
        return allegiances[1]
    end
    return allegiances[2]
end

local module: {[string]: Types.Gamemode} = {
    ThoseYouTrust = {
        Name = "Those You Trust",
        Description = "Spy HQ has been infiltrated by Traitor spies. Can you separate those you trust, from those you shouldn't?",
    
        EngineVersion = "0.0.1",
        GamemodeVersion = "0.0.1",
    
        MinimumPlayers = 1,
        RecommendedPlayers = 4,
        MaximumPlayers = 32,
    
        PyrrhicVictors = "Traitor",
        TimeoutVictors = function()
            return "Innocent"
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
    
                Item = items:FindFirstChild("Crowbar") :: Tool
            },
            {
                Name = "Grenade",
                Description = "Boom",
                Cost = 1,
                Icon = "rbxassetid://",
    
                Item = items:FindFirstChild("Grenade") :: Tool
            },
            {
                Name = "Radar",
                Description = "Beep... beep... beep",
                Cost = 1,
                Icon = "rbxassetid://",
    
                Item = function(participant, item)
                    print(`{participant.Name} got radar`)
                end
            },
        },
    
        Roles = {
            {
                Name = "Traitor",
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
    
            local winner = TestForOneSurvivingRole(self, round)
            if winner then
                round:EndRound(round:GetRoleInfo(winner))
            end
        end,
        
        Duration = function(self, numParticipants)
            return 120 + (numParticipants * 10)
        end
    },

    Murder = {
        Name = "Murder",
        Description = "Survive the murderer.",
        EngineVersion = "0.0.1",
        GamemodeVersion = "0.0.1",
    
        MaximumPlayers = 700,
        RecommendedPlayers = 4,
        MinimumPlayers = 2,
    
        PyrrhicVictors = "Murderer",
        TimeoutVictors = function()
            return "Bystander"
        end,
    
        FriendlyFire = true,
        SelfDefense = false,
        UseKarma = false,
    
        StartingCredits = 0,
        StartingEquipment = {},
        AvailableEquipment = {
            {
                Name = "Knife",
                Description = "Stabby stab stab.",
                Cost = 0,
                Icon = "rbxassetid://",
                Item = ReplicatedStorage:FindFirstChild("Knife") :: Tool
            },
            {
                Name = "Gun",
                Description = "Shooty shoot shoot.",
                Cost = 0,
                Icon = "rbxassetid://",
                Item = ReplicatedStorage:FindFirstChild("Gun") :: Tool
            },
        },
    
        Roles = {
            {
                Name = "Bystander",
                Description = "There is a Murderer on the loose. Survive them.",
                Colour = Color3.new(0, 1, 0),
    
                Allegiance = "Bystander",
                Allies = {"Bystander", "Sheriff"},

                VictoryText = "The loveable bystanders have survived the day!",
                VictoryMusic = {},
    
                StartingCredits = 0,
                StartingEquipment = {},
    
                AnnounceDisconnect = false,
                CanStealCredits = false,
                EquipmentShop = {},
                AwardOnDeath = {},
    
                Accessories = {},
                Health = 100,
                JumpPower = 18,
                Speed = 16,
    
                CorpseResultsPublicised = false,
    
                HighlightRules = {},
                KnowsRoles = {},
                TeamChat = false,
    
                OnRoleAssigned = function() end,
                OnRoleRemoved = function() end,
            },
            {
                Name = "Sheriff",
                Description = "There is a Murderer on the loose. Protect the bystanders.",
                Colour = Color3.new(0, 0, 1),
    
                Allegiance = "Bystander",
                Allies = {"Bystander", "Sheriff"},
    
                StartingCredits = 0,
                StartingEquipment = {"Gun"},
    
                AnnounceDisconnect = false,
                CanStealCredits = false,
                EquipmentShop = {},
                AwardOnDeath = {},
    
                Accessories = {},
                Health = 100,
                JumpPower = 18,
                Speed = 16,
    
                CorpseResultsPublicised = false,
    
                HighlightRules = {},
                KnowsRoles = {},
                TeamChat = false,
    
                OnRoleAssigned = function() end,
                OnRoleRemoved = function() end,
            },
            {
                Name = "Murderer",
                Description = "Leave nobody alive.",
                Colour = Color3.new(1, 0, 0),
    
                Allegiance = "Murderer",
                Allies = {"Murderer"},

                VictoryText = "The evil murderer has won the round...",
                VictoryMusic = {},
    
                StartingCredits = 0,
                StartingEquipment = {},
    
                AnnounceDisconnect = true,
                CanStealCredits = false,
                EquipmentShop = {},
                AwardOnDeath = {},
    
                Accessories = {},
                Health = 100,
                JumpPower = 18,
                Speed = 16,
    
                CorpseResultsPublicised = false,
    
                HighlightRules = {},
                KnowsRoles = {},
                TeamChat = false,
    
                OnRoleAssigned = function() end,
                OnRoleRemoved = function() end,
            },
        },
    
        AssignRoles = function(self, participants)
            -- Participants are already shuffled, no need to do it here
            for i, v in participants do
                if i == 1 then
                    v:AssignRole(self.Roles[3])
                elseif i == 2 then
                    v:AssignRole(self.Roles[2])
                else
                    v:AssignRole(self.Roles[1])
                end
            end
        end,
    
        Duration = function(self, numParticipants)
            return 180
        end,
    
        OnDeath = function(self, victim)
            local round = victim.Round

            local role = victim.Role
            if role then
                if role.Name == "Bystander" then
                    local assailant
                    for _, v in round.Participants do
                        for _, kill in v.KillList do
                            if kill.Name == victim.Name then
                                assailant = v
                                break
                            end
                            if assailant then
                                break
                            end
                        end
                    end

                    if assailant and assailant.Role and (assailant.Role.Name == "Sheriff") and assailant.Character then
                        local hum = assailant.Character:FindFirstChildOfClass("Humanoid")
                        if hum then
                            hum.Health = 0
                        end
                    end
                    return
                elseif role.Name == "Sheriff" then
                    local char = victim.Character
                    if char and char:IsDescendantOf(workspace) then
                        local gun = (items:FindFirstChild("Gun") :: Tool):Clone()
                        local handle = gun:FindFirstChild("Handle") :: Part
                        gun:PivotTo(char:GetPivot())
                        
                        local particles = Instance.new("Sparkles")
                        particles.Parent = handle

                        handle.Touched:Connect(function(part)
                            local plr = Players:GetPlayerFromCharacter(part.Parent :: Model)
                            if not plr then
                                return
                            end

                            local participant = round:GetParticipant(plr.Name)
                            if participant:GetAllegiance().Name ~= "Bystander" then
                                return
                            end

                            participant:GiveEquipment(self.AvailableEquipment[2])
                            gun:Destroy()

                            -- Does handle.Touched get disconnected?
                        end)
                    end
                end
            end
    
            local winner = TestForOneSurvivingRole(self, round)
            if winner then
                round:EndRound(round:GetRoleInfo(winner))
            end
        end
    }
}

return module