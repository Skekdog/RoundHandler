-- The Murder gamemode. A secret murderer tries to kill every bystander, one of whom has a secret weapon.
-- Showcases effective usage of OnDeath to drop a weapon where the Sheriff dies.
-- Shows usage of the EventLog to determine good round highlights.

local Types = require("src/Types")
local common = require("examples/gamemodes/Common")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local items = ReplicatedStorage:FindFirstChild("Items") :: Folder

local module: Types.Gamemode = {
    Name = "Murder",
    Description = "Survive the murderer.",
    EngineVersion = "0.0.1",

    MaximumPlayers = 700,
    RecommendedPlayers = 4,
    MinimumPlayers = 2,

    PhyrricVictors = "Innocent",
    TimeoutVictors = function(self)
        return self.Roles[1]
    end,

    CalculateRoundHighlights = function(self, round)
        local highlights: {Types.RoundHighlight} = {}

        local murdererDeath: Types.RoundEvent_Death
        for _, v in round.EventLog["Death"] do
            local data: Types.RoundEvent_Death = v.Data :: any
            if data.Victim:GetAllegiance().Name == "Murderer" then
                murdererDeath = data
                break
            end
        end

        if murdererDeath and murdererDeath.Attacker then
            local title, description = "", ""
            if murdererDeath.Attacker:GetRole().Name == "Innocent" then
                title = "Now you're a hero"
                description = `{murdererDeath.Attacker:GetFormattedName()} found a gun on the floor, did a backflip, shot the bad guy in the face and then saved the day!`
            else
                title = "New sheriff in town"
                description = `{murdererDeath.Attacker:GetFormattedName()} asserted their authority by shooting a crazed killer in the face!`
            end

            table.insert(highlights, {
                Name = title,
                Description = description
            })
        end

        local murderer = round:GetParticipantsWithRole("Murderer")[1]
        local murdererName = murderer:GetFormattedName()
        local mKills = #murderer.KillList
        local title, description = "", ""
        if mKills > 10 then
            title = "Mass Murderer"
            description = `Local man {murdererName} goes on unhinged murder spree, kills {mKills}.`
        elseif mKills > 6 then
            title = "Serial Killer"
            description = `{murdererName} suspected for the accidental stabbings of {mKills} people.`
        elseif mKills > 3 then
            title = "Killer"
            description = `{murdererName} had a bone to pick with {mKills} people.`
        elseif mKills > 1 then
            title = "Murderer"
            description = `{murdererName} did a murder on {mKills} people. Claims they "looked at me funny".`
        elseif mKills == 1 then
            title = "Agree to Disagree"
            description = `{murdererName} settled their differences with someone using a knife.`
        else
            title = "Cereal Killer"
            description = `{murderer} was upset with their breakfast cereal and so blew it up.`
        end

        table.insert(highlights, {
            Name = title,
            Description = description
        })

        return highlights
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
            Item = items:FindFirstChild("Knife") :: Tool,
            MaxStock = 1,
        },
        {
            Name = "Gun",
            Description = "Shooty shoot shoot.",
            Cost = 0,
            Icon = "rbxassetid://",
            Item = items:FindFirstChild("Gun") :: Tool,
            MaxStock = 1,
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
            CanSeeMissing = false,

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
            CanSeeMissing = false,
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
            StartingEquipment = {"Knife"},

            AnnounceDisconnect = true,
            CanStealCredits = false,
            EquipmentShop = {},
            AwardOnDeath = {},

            Accessories = {},
            Health = 100,
            JumpPower = 18,
            Speed = 16,

            CorpseResultsPublicised = false,
            CanSeeMissing = true,

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

        local role = victim:GetRole()
        if role.Name == "Bystander" then
            local assailant
            for _, v in round.Participants do
                for _, kill in v.KillList do
                    if kill.Player.Name == victim.Player.Name then
                        assailant = v
                        break
                    end
                    if assailant then
                        break
                    end
                end
            end

            if assailant and (assailant:GetRole().Name == "Sheriff") then
                assailant:Kill()
            end
        elseif role.Name == "Sheriff" then
            local char = victim.Character
            if char.Parent then
                local gun: Part = ((round:GetEquipment("Gun").Item :: any):FindFirstChild("Handle") :: Part):Clone()
				
				local particles = Instance.new("Sparkles")
				particles.Parent = gun
				
				gun:PivotTo(char:GetPivot())
				gun.Anchored = false
				gun.Name = "Gun"
				gun.Parent = round.Map

                gun.Touched:Connect(function(part)
                    local plr = Players:GetPlayerFromCharacter(part.Parent :: Model)
                    if not plr then
                        return
                    end

                    local participant = round:GetParticipant(plr.Name)
                    if (participant:GetAllegiance().Name ~= "Bystander") or (participant:IsDead()) then
                        return
                    end

                    participant:GiveEquipment(self.AvailableEquipment[2])
                    gun:Destroy()
                end)
            end
        end

        local winner = common.TestForOneSurvivingRole(self, round)
        if winner then
            round:EndRound(round:GetRoleInfo(winner))
        end
    end,

    OnCharacterLoad = function() end
}

return module