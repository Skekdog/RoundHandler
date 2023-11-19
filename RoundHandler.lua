--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Types = require("Types")
local API = require("API")

local module = {}
local participant: Types.Participant = {} :: Types.Participant
local roundHandler = {}

module.Rounds = {}

local PREPARING_TIME = 10
-- local HIGHLIGHTS_TIME = 10
-- local INTERMISSION_TIME = 10


-- self is explicitly defined to specify the type.

function participant.AssignRole(self: Types.Participant, role: Types.Role, overrideCredits: boolean?, overrideInventory: boolean?)
    self.Role = role
    self.Credits = overrideCredits and role.StartingCredits or (self.Credits + role.StartingCredits)
    return
end

function participant.LeaveRound(self: Types.Participant)
    local plr = self.Player
    for i,v in self.Round.Participants do if v == self then table.remove(self.Round.Participants,i) end end
    if plr and plr.Character then plr.Character:Destroy() end
    return
end

function participant.GetRole(self: Types.Participant, useAllegiance: boolean): Types.Role?
    if not self.Role then return end
    if useAllegiance then return self.Round:GetRoleObject(self.Role.Allegiance) end
    return self.Round:GetRoleObject(self.Role.Name)
end

function participant.GiveEquipment(self: Types.Participant, equipment: Types.Equipment): nil
    if type(equipment.Item) == "function" then return equipment.Item(self, equipment.Name) end
    return
end


function roundHandler.CheckForVictory(self: Types.Round): boolean?
    return
end

function roundHandler.GetParticipant(self: Types.Round, name: Types.Username): Types.Participant? -- Returns Participant if successful.
    for _, participant in self.Participants do
        if participant.Name == name then return participant end
    end
    return
end

function roundHandler.JoinRound(self: Types.Round, name: Types.Username): Types.Participant? -- Adds a player to the round and returns a new Participant if successful. For the sake of consistency, `plr` is a `string` of the player's username.
    if self:GetParticipant(name) or ((self.RoundPhase ~= "Waiting") and (self.RoundPhase ~= "Preparing")) then return end
    local plr: Player = Players:FindFirstChild(name) :: Player
    if not plr then return end

    local _participant: Types.Participant = {
        Player = plr,
        Name = plr.Name,
        Round = self :: Types.Round,

        Role = nil,
        Credits = 0,
        Score = 0,

        Deceased = false,
        SearchedBy = {},
        KilledBy = "Other",
        KilledByWeapon = nil,
        KilledInSelfDefense = false,

        FreeKill = false,
        FreeKillReasons = {},

        SelfDefenseList = {},
        KillList = {},

        SlayVotes = 0,

        EquipmentPurchases = {},

        AssignRole = participant.AssignRole,
        LeaveRound = participant.LeaveRound,
        GiveEquipment = participant.GiveEquipment,
        GetRole = participant.GetRole,
    } :: Types.Participant

    table.insert(self.Participants, _participant)

    local spawns = (workspace:FindFirstChild("__Spawns_"..self.Category) :: Folder):GetChildren()
    plr.CharacterAppearanceLoaded:Once(function(char)
        local chosen = math.random(1,#spawns)
        char:PivotTo((spawns[chosen] :: BasePart).CFrame)
        local hum: Humanoid = char:WaitForChild("Humanoid") :: Humanoid
        hum.Died:Connect(self.Gamemode.OnDeath and function() self.Gamemode.OnDeath(participant) end or function()
            
        end)
    end)
    plr:LoadCharacter()

    return participant
end

function roundHandler.StartRound(self: Types.Round) -- Starts the round, assigning everyone's roles. Also sets up the timeout condition.
    local gm = self.Gamemode
    local roles = gm.Roles
    local participants = self.Participants
    API.ShuffleInPlace(participants)

    if gm.AssignRoles then gm.AssignRoles(participants) else
        table.sort(roles, function(role1, role2) return role1.AssignmentPriority < role2.AssignmentPriority end)
        local last, num = 0, #participants
        for _,role in roles do
            for i,v in participants do
                if i > last then
                    if i <= math.floor(num*role.AssignmentProportion) then v:AssignRole(role) else last = i-1; break end
                end
            end
        end
    end
end

function roundHandler.EndRound(self: Types.Round, victors: Types.Role)
    
end

function roundHandler.GetRoleObject(self: Types.Round, name: Types.RoleName): Types.Role
    for _,v in self.Gamemode.Roles do if v.Name == name then return v end end
    error(("Role '%s' not found in gamemode '%s'"):format(name, self.Gamemode.Name))
end

function module.LoadMap(map: Folder, category: string): nil -- Loads a map.
    map = map:Clone()

    local physicalMap = map:FindFirstChild("Map")
    if not physicalMap then return error(map.Name.." is missing a Map folder!") end

    local spawns = workspace:FindFirstChild("__Spawns_"..category) or API.NamedInstance("Folder", "__Spawns_"..category, workspace)
    local weapons = workspace:FindFirstChild("__Weapons_"..category) or API.NamedInstance("Folder", "__Weapons_"..category, workspace)
    local bounds

    Instance.new("Folder",ReplicatedStorage).Name = "Lighting_"..category
    Instance.new("Folder",ReplicatedStorage).Name = "FIBLighting_"..category

    local oldMap = workspace:FindFirstChild("__Map_"..category)
    if oldMap then for _, v in oldMap:GetChildren() do v:ClearAllChildren() end else
        oldMap = Instance.new("Folder")
        if not oldMap then error("Type-checker should not have been shut up...") end -- Shuts the type-checker up

        bounds = API.NamedInstance("Folder", "Bounds", oldMap)
        API.NamedInstance("Folder", "Props", oldMap)
        API.NamedInstance("Folder", "Map", oldMap)

        oldMap.Name = "__Map_"..category
        oldMap.Parent = workspace
    end

    for _, v in physicalMap:GetChildren() do v.Parent = (workspace:FindFirstChild("__Map_"..category):: Folder):FindFirstChild("Map") end

    for _, v in map:GetChildren() do
        task.wait()
        if v.Name == "Spawns" then
            spawns:ClearAllChildren()
            for _, spawn in v:GetChildren() do
                if not spawn:IsA("BasePart") then continue end
                spawn.Anchored = true
                spawn.Transparency = 1
                spawn.CanCollide = false
                spawn.CanTouch = false
                spawn.CanQuery = false
                spawn.Parent = spawns
            end
            continue
        end
        if v.Name == "Lighting" or v.Name == "FIBLighting" then -- Lighting is handled on client
            local prev = ReplicatedStorage:FindFirstChild(v.Name..category)
            if prev then prev:ClearAllChildren() end
            v.Parent = ReplicatedStorage
            continue
        end
        if v.Name == "Bounds" then
            for _, bound in v:GetChildren() do
                if not bound:IsA("BasePart") then continue end
                bound.CanCollide = false
                bound.Transparency = 1
                bound.Parent = bounds
            end
            continue
        end
        if v.Name == "WeaponSpawns" then
            weapons:ClearAllChildren()
            for _, weapon in v:GetChildren() do
                if not weapon:IsA("BasePart") then continue end
                weapon.CanCollide = true
                weapon.CanTouch = true
                weapon.Anchored = false
                weapon.Parent = weapons
            end
            continue
        end
    end
    return
end

--Gamemode and map should be non-negotiable. ? for testing purposes.
function module.CreateRound(map: Folder, gamemode: Types.Gamemode?, category: Types.RoundCategory?): Types.Round -- Creates a new Round and returns it.
    local self: Types.Round = {} :: Types.Round

    self.ID = HttpService:GenerateGUID() -- Randomly generated UUID for... ID purposes.
    self.Category = category or "Main" -- Category used for simultaneous rounds.

    module.LoadMap(map,self.Category)

    self.Gamemode = gamemode :: Types.Gamemode -- The current gamemode.

    self.TimeMilestone = workspace:GetServerTimeNow()+PREPARING_TIME -- Timestamp of the next round phase.
    self.RoundPhase = "Waiting" -- Current round phase. Waiting - not enough players; Preparing - enough players, giving time for others to join; Playing - round in progress; Highlights - round ended, but still loaded; Intermission - round unloaded, voting time if applicable.

    self.Participants = {} :: {Types.Participant} -- List of all Participants.
    self.EventLog = {} :: {Types.Event} -- List of all Events.

    self.GetParticipant = roundHandler.GetParticipant
    self.JoinRound = roundHandler.JoinRound
    
    self.StartRound = roundHandler.StartRound -- Starts the round, assigning everyone's roles. Also sets up the timeout condition.
    self.EndRound = roundHandler.EndRound

    self.GetRoleObject = roundHandler.GetRoleObject
    
    module.Rounds[self.ID] = self
    return self
end

function module.GetRound(identifier: Types.RoundCategory | Types.UUID): Types.Round?
    for _,v in module.Rounds do if v.ID == identifier then return v end end -- Look for ID first
    for _,v in module.Rounds do if v.Category == identifier then return v end end
    return nil
end

return module