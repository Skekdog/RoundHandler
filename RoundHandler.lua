--!strict
--!nolint LocalUnused

--[[
    The main RoundHandler. Used to create and interact with rounds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require("Types")
local API = require("API")

local module = {}
local participant: Types.Participant = {} :: Types.Participant
local roundHandler: Types.Round = {} :: Types.Round

module.Rounds = {}

local PREPARING_TIME = 10
local HIGHLIGHTS_TIME = 10
local INTERMISSION_TIME = 10


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

function participant.GetAllegiance(self: Types.Participant): Types.Role?
    if not self.Role then return end
    return self.Round:GetRoleInfo(self.Role.Allegiance or self.Role.Name)
end

function participant.GiveEquipment(self: Types.Participant, equipment: Types.Equipment): nil
    if type(equipment.Item) == "function" then return equipment.Item(self, equipment.Name) end
    return
end

function roundHandler.GetRoleInfo(self: Types.Round, name: Types.RoleName): Types.Role
    for _,v in self.Gamemode.Roles do if v.Name == name then return v end end
    error(("Role '%s' not found in gamemode '%s'"):format(name, self.Gamemode.Name))
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
        GetAllegiance = participant.GetAllegiance,
    }

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

--[[
    Starts the round, assigning everyone's roles and the setting up the timeout condition.
]]

function roundHandler.StartRound(self: Types.Round)
    local gm = self.Gamemode
    local roles = gm.Roles
    local participants = self.Participants
    API.ShuffleInPlace(participants)

    if gm.AssignRoles then gm.AssignRoles(participants) else
        table.sort(roles, function(role1, role2) return role1.AssignmentPriority < role2.AssignmentPriority end)
        local last, num = 0, #participants
        for _,role in roles do
            assert(role.AssignmentProportion)
            for i,v in participants do
                if i > last then
                    if i <= math.floor(num*role.AssignmentProportion) then v:AssignRole(role) else last = i-1; break end
                end
            end
        end
    end
    return
end

function roundHandler.GetRoleRelationship(self: Types.Round, role1: Types.Role, role2: Types.Role): "Ally" | "Enemy"
    return (table.find(role1.Allies, role2.Name) and "Ally") or "Enemy"
end

function roundHandler.CompareRoles(self: Types.Round, role1: Types.Role, role2: Types.Role, comparison: Types.RoleRelationship): boolean
    if role2.Name == comparison then return true end
    if comparison == "All" then return true end
    return self:GetRoleRelationship(role1, role2) == comparison
end

-- Returns a Participant with some fields omitted depending on the target's role or lack there-of
function roundHandler.GetLimitedParticipantInfo(self: Types.Round, viewer: Player, target: Player): Types.Role?
    local viewerParticipant = self:GetParticipant(viewer.Name)
    local targetParticipant = self:GetParticipant(target.Name)
    if not viewerParticipant then return warn(viewer.Name.." is not a Participant of Round "..self.ID..".") end
    if not targetParticipant then return warn(target.Name.." is not a Participant of Round "..self.ID..".") end

    local viewerRole = viewerParticipant.Role
    local targetRole = targetParticipant.Role
    if not viewerRole then return warn(viewer.Name.." role is nil in Round "..self.ID..".") end
    if not targetRole then return warn(target.Name.." role is nil in Round "..self.ID..".") end

    local rules = {}
    for rule, allow in viewerRole.KnowsRoles do
        
    end
end

function roundHandler.EndRound(self: Types.Round, victors: Types.Role)
    return
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

    self.GetRoleInfo = roundHandler.GetRoleInfo
    
    module.Rounds[self.ID] = self
    return self
end

function module.GetRound(identifier: Types.RoundCategory | Types.UUID): Types.Round?
    for _,v in module.Rounds do if v.ID == identifier then return v end end -- Look for ID first
    for _,v in module.Rounds do if v.Category == identifier then return v end end
    return
end

-- Returns whether the gamemode is valid, and a list of issues with the gamemode
function module.ValidateGamemode(gamemode: Types.Gamemode, runFunctions: boolean): (boolean, {string})
    local issues = {}
    local i = function(issue: string) table.insert(issues, issue) end

    -- Test with some functions
    if gamemode.Duration(gamemode.MinimumPlayers) <= 0 then i("Gamemode duration is negative with MinimumPlayers.") end
    if gamemode.Duration(gamemode.MaximumPlayers or 700) <= 0 then i("Gamemode duration is negative with "..tostring(gamemode.MaximumPlayers or "700 (max. size of a server in theory)").." players") end

    local equipmentNames = {}
    for _, equipment in gamemode.AvailableEquipment do table.insert(equipmentNames, equipment.Name) end

    local hasOwnAssignmentFunction = gamemode.AssignRoles ~= nil
    local roleNames = {}
    for _, role in gamemode.Roles do
        table.insert(roleNames, role.Name)
        if not role.AssignmentPriority and not hasOwnAssignmentFunction then i("Role "..role.Name.." does not have an AssignmentPriority. Define Gamemode.AssignRoles() or set a priority.") end
        if not role.AssignmentProportion and not hasOwnAssignmentFunction then i("Role "..role.Name.." does not have an AssignmentProportion. Define Gamemode.AssignRoles() or set a proportion.") end

        if table.find({"All", "Ally", "Enemy"}, role.Name) then i("Role name "..role.Name.." is reserved.") end
        
        for _, equipmentName in role.StartingEquipment do
            if not table.find(equipmentNames, equipmentName) then
                i("Equipment "..equipmentName.." of "..role.Name..".StartingEquipment ".." is not defined in Gamemode.AvailableEquipment.")
            end
        end
        for _, equipmentName in role.EquipmentShop do
            if not table.find(equipmentNames, equipmentName) then
                i("Equipment "..equipmentName.." of "..role.Name..".EquipmentShop ".." is not defined in Gamemode.EquipmentShop.")
            end
        end
    end

    local function validateRoleRelationship(list: {[Types.RoleRelationship]: any}, info: "Role.Table" | string)
        for relationship, _ in list do
            if not table.find({"All", "Ally", "Enemy"}, relationship) and not table.find(roleNames, relationship) then
                i(relationship.." is not a valid RoleRelationship in "..info..".")
            end
        end
    end

    for _, role in gamemode.Roles do
        for _, ally in role.Allies do
            if not table.find(roleNames, ally) then i("Role "..role.Name.." has an undefined Ally: "..ally) end
        end
        if not table.find(roleNames, role.Allegiance) then
            i("Role "..role.Name.." has an undefined Allegiance: "..role.Allegiance)
        end

        validateRoleRelationship(role.KnowsRoles, role.Name..".KnowsRoles")
        validateRoleRelationship(role.HighlightRules, role.Name..".HighlightRules")
        validateRoleRelationship(role.AwardOnDeath, role.Name..".AwardOnDeath")
    end

    return #issues<1, issues
end

return module