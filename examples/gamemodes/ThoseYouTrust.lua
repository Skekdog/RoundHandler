--!strict
local Types = require("src/Types.lua")
local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Items")

local ThoseYouTrust: Types.Gamemode = {
    Name = "Those You Trust",
    Description = "",

    EngineVersion = "0.0.1",
    GamemodeVersion = "0.0.1",

    MinimumPlayers = 1,
    RecommendedPlayers = 4,
    MaximumPlayers = 32,

    PyrrhicVictors = "Traitor",
    TimeoutVictors = "Innocent",
    Highlights = {},

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

            Item = items:FindFirstChild("Crowbar") :: Model
        },
        {
            Name = "Grenade",
            Description = "Boom",
            Cost = 1,
            Icon = "rbxassetid://",

            Item = items:FindFirstChild("Grenade") :: Model
        },
        {
            Name = "Radar",
            Description = "Beep... beep... beep",
            Cost = 1,
            Icon = "rbxassetid://",

            Item = function(participant, item)
                print(participant.Name.." got radar")
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
                Ally = true,
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
        local roles = self.Roles
        table.sort(roles, function(role1, role2)
            assert(role1.Extras and role2.Extras)
            return role1.Extras.AssignmentPriority < role2.Extras.AssignmentPriority
        end)
        local last, num = 0, #participants
        for _,role in roles do
            assert(role.Extras)
            for i,v in participants do
                if i > last then
                    if i <= math.floor(num*role.Extras.AssignmentProportion) then v:AssignRole(role) else last = i-1; break end
                end
            end
        end
    end,
    OnDeath = function(self, victim)

    end,
    Duration = function(self, numParticipants)
        return 120 + (numParticipants * 10)
    end,
    CheckForVictory = function(self, round)
        
    end
}



return ThoseYouTrust