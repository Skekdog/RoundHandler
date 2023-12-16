local Types = require("Types")

local module: {[string]: Types.Gamemode} = {}

module["Those You Trust"] = {
    Name = "Those You Trust",
    Description = "A group of traitors have infiltrated Spy HQ. Who can you trust, and who can you not..?",

    MinimumPlayers = 2,
    RecommendedPlayers = 6,

    FriendlyFire = true,
    UseKarma = true,
    SelfDefense = true,

    AvailableEquipment = {
        {
            Name = "Crowbar",
            Cost = 0,
            Description = "He who lives by the crowbar, dies by the crowbar.",
            Icon = "rbxassetid://",
            Item = Instance.new("Model"),
        }
    },
    StartingCredits = 0,
    StartingEquipment = {},

    Highlights = {},
    TimeoutVictors = "Innocent",
    PyrrhicVictors = "Traitor",
    Roles = {
        {
            Name = "Innocent",
            Description = "You are an innocent spy! But there are traitors among you...",

            Allegiance = "Innocent",
            Allies = {"Innocent", "Detective"},

            Accessories = {},
            AwardOnDeath = {},

            CorpseResultsPublicised = false,
            StartingCredits = 0,
            StartingEquipment = {},

            Health = 100,
            Speed = 16,
            JumpPower = nil,

            TeamChat = false,
            KnowsRoles = {},

            CanStealCredits = false,
            HighlightRules = {},
            EquipmentShop = {},
            OnRoleAssigned = function() end,
            OnRoleRemoved = function() end,
            VictoryMusic = {},
        }
    },

    AssignRoles = function() end,
    Duration = function(numParticipants) return 120 + (numParticipants * 5) end,
    CheckForVictory = function() end,
    OnDeath = function() end,


}

return module