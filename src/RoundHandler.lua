--!strict
-- The main RoundHandler. Used to create and interact with rounds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Adapters = require("src/Adapters")
local Types = require("src/Types")
local API = require("src/API")

local module = {}
local participant: Types.Participant = {} :: Types.Participant
local roundHandler: Types.Round = {} :: Types.Round

module.Rounds = {} :: {[Types.UUID]: Types.Round}

local PREPARING_TIME = Adapters.Configuration.PREPARING_TIME -- Duration of the preparing phase
local HIGHLIGHTS_TIME = Adapters.Configuration.HIGHLIGHTS_TIME -- Duration of the highlights phase
local INTERMISSION_TIME = Adapters.Configuration.INTERMISSION_TIME -- Duration of map voting

local ServerClient = ReplicatedStorage:FindFirstChild("ServerClient") :: Folder -- Replace with wherever Server -> Client (-> Server) remotes are
local ClientServer = ReplicatedStorage:FindFirstChild("ClientServer") :: Folder -- Replace with wherever Client -> Server (-> Client) remotes are

function participant:AssignRole(role: Types.Role, overrideCredits: boolean?, overrideInventory: boolean?)
    self.Role = role
    self.Credits = overrideCredits and role.StartingCredits or (self.Credits + role.StartingCredits)
    return
end

function participant:LeaveRound()
    local plr = self.Player
    for i,v in self.Round.Participants do if v == self then table.remove(self.Round.Participants, i) end end
    if plr and plr.Character then plr.Character:Destroy() end

    if #self.Round.Participants < self.Round.Gamemode.MinimumPlayers then
        local timerThread = self.Round._roundTimerThread
        if not timerThread then
            return
        end
        coroutine.close(timerThread)
    end
    
    return
end

function participant:GetAllegiance(): Types.Role
    if not self.Role then
        error("Participant "..self.Name.." does not have a role")
    end
    return self.Round:GetRoleInfo(self.Role.Allegiance)
end

function participant:GiveEquipment(equipment: Types.Equipment)
    return Adapters.GiveEquipment(self, equipment)
end

function roundHandler:GetRoleInfo(name: Types.RoleName): Types.Role
    for _, v in self.Gamemode.Roles do
        if v.Name == name then
            return v
        end
    end
    error(("Role '%s' not found in gamemode '%s'"):format(name, self.Gamemode.Name))
end

function roundHandler:HasParticipant(name: Types.Username): boolean -- Returns true if Participant is already in Round
    for _, participant in self.Participants do
        if participant.Name == name then
            return true
        end
    end
    return false
end

function roundHandler:GetParticipant(name: Types.Username): Types.Participant -- Returns Participant
    for _, participant in self.Participants do
        if participant.Name == name then
            return participant
        end
    end
    error("Could not find Participant "..name.." in Round "..self.ID)
end

function roundHandler:IsRoundPreparing(): boolean
    return self.RoundPhase == "Waiting" or self.RoundPhase == "Preparing"
end

function roundHandler:IsRoundOver(): boolean
    return self.RoundPhase == "Intermission" or self.RoundPhase == "Highlights"
end

function roundHandler:IsRoundInProgress(): boolean
    return self.RoundPhase == "Playing"
end

function roundHandler:JoinRound(name: Types.Username): Types.Participant -- Adds a player to the round and returns a new Participant if successful. For the sake of consistency, `plr` is a `string` of the player's username.
    if self:HasParticipant(name) then
        error(name.." is already a Participant in Round "..self.ID)
    end
    if not self:IsRoundPreparing() then
       error("Failed to add "..name.." to Round "..self.ID.." because the Round has already started")
    end
    local plr = Players:FindFirstChild(name) :: Instance
    if (not plr) or (not plr:IsA("Player")) then 
        error("Attempt to add non-Player participant: "..tostring(plr))
    end

    local _participant: Types.Participant = {
        Player = plr,
        Name = plr.Name,
        Round = self :: Types.Round,

        Role = nil,
        Credits = 0,
        Score = {},

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

    local spawns = (workspace:FindFirstChild("__Spawns_"..self.ID) :: Folder):GetChildren()
    plr.CharacterAppearanceLoaded:Once(function(char)
        local chosen = math.random(1, #spawns)
        char:PivotTo((spawns[chosen] :: BasePart).CFrame)
        local hum: Humanoid = char:WaitForChild("Humanoid") :: Humanoid
        hum.Died:Once(function()
            if self:IsRoundPreparing() then
                -- Respawn if the round hasn't started
                _participant:LeaveRound()
                self:JoinRound(name)
                return
            end
            self.Gamemode:OnDeath(_participant)
        end)
    end)
    plr:LoadCharacter()

    if #self.Participants >= self.Gamemode.MinimumPlayers then
        self._roundTimerThread = task.delay(PREPARING_TIME, self.StartRound, self)
    end

    return participant
end

-- (un)Pauses the round. Timer will resume at the same duration
function roundHandler:PauseRound(): Types.PauseFailReason?
    if not self:IsRoundInProgress() then return "RoundNotInProgress" end
    self.Paused = not self.Paused
    if self.Paused then
        self._roundTimerContinueFor = self._roundTimerTargetDuration - (workspace:GetServerTimeNow() - self._roundTimerResumedAt)
    end
    return
end

-- Starts the round, assigning roles and setting up the timeout condition.
function roundHandler:StartRound()
    local gm = self.Gamemode
    local participants = self.Participants
    API.ShuffleInPlace(participants)

    gm:AssignRoles(participants)

    return self.RoundStartEvent:Fire()
end

function roundHandler:GetRoleRelationship(role1: Types.Role, role2: Types.Role): "Ally" | "Enemy"
    return (table.find(role1.Allies, role2.Name) and "Ally") or "Enemy"
end

function roundHandler:CompareRoles(role1: Types.Role, role2: Types.Role, comparison: Types.RoleRelationship): boolean
    if comparison == "All" then return true end
    return self:GetRoleRelationship(role1, role2) == comparison
end

-- Returns a Participant with some fields omitted depending on the target's role or lack there-of
function roundHandler:GetLimitedParticipantInfo(viewer: Player, target: Player): Types.PartialRole?
    local viewerParticipant = self:GetParticipant(viewer.Name)
    local targetParticipant = self:GetParticipant(target.Name)
    if not viewerParticipant then return self:warn(viewer.Name.." is not a Participant of Round "..self.ID..".") end
    if not targetParticipant then return self:warn(target.Name.." is not a Participant of Round "..self.ID..".") end

    local viewerRole = viewerParticipant.Role
    local targetRole = targetParticipant.Role
    if not viewerRole then return self:warn(viewer.Name.." role is nil in Round "..self.ID..".") end
    if not targetRole then return self:warn(target.Name.." role is nil in Round "..self.ID..".") end

    local relation = self:GetRoleRelationship(viewerRole, targetRole)

    local partialInfo = {
        Name = targetRole.Name,
        Colour = targetRole.Colour,
    }
    
    -- First check for explicit role name, then for Ally/Enemy.

    if viewerRole.KnowsRoles[targetRole.Name] == false then return end
    if viewerRole.KnowsRoles[targetRole.Name] then return partialInfo end

    if (relation == "Ally" or relation == "Enemy") and (viewerRole.KnowsRoles[relation]) then return partialInfo end
    if (relation == "Ally" or relation == "Enemy") and (viewerRole.KnowsRoles[relation] == false) then return end

    if viewerRole.KnowsRoles["All"] then
        return partialInfo
    end
    return
end

function roundHandler:EndRound(victors: Types.Role)
    self.RoundPhase = "Highlights"
    for _, v in self.Participants do
        ServerClient:FindFirstChild("")
    end

    local updateNeeded = Adapters.CheckForUpdate(self)
    if updateNeeded then
        Players.PlayerAdded:Connect(function(plr)
            plr:Kick("This server is shutting down.")
        end)
        Adapters.SendMessage(Players:GetPlayers(), "This server is outdated and will restart soon.", "error")
    end

    -- Destroy the round
    task.wait(HIGHLIGHTS_TIME)

    Adapters.SendMessage(Players:GetPlayers(), "Server restarting...", "error")
    TeleportService:TeleportAsync(game.PlaceId, Players:GetPlayers())

    self.RoundEndEvent:Fire()

    self.RoundEndEvent:Destroy()
    self.RoundStartEvent:Destroy()

    module.Rounds[self.ID] = nil
    return
end

function roundHandler:warn(message: string)
    return warn(message.." from Round: "..self.ID, 2)
end

function module.LoadMap(map: Folder, id: Types.UUID): nil -- Loads a map.
    map = map:Clone()

    local physicalMap = map:FindFirstChild("Map")
    if not physicalMap then return error(map.Name.." is missing a Map folder!") end

    local spawns = workspace:FindFirstChild("__Spawns_"..id) or API.NamedInstance("Folder", "__Spawns_"..id, workspace)
    local weapons = workspace:FindFirstChild("__Weapons_"..id) or API.NamedInstance("Folder", "__Weapons_"..id, workspace)
    local bounds

    Instance.new("Folder", ReplicatedStorage).Name = "Lighting_"..id
    Instance.new("Folder", ReplicatedStorage).Name = "FIBLighting_"..id

    local oldMap = workspace:FindFirstChild("__Map_"..id)
    if oldMap then
        for _, v in oldMap:GetChildren() do
            v:ClearAllChildren() 
        end
    else
        oldMap = Instance.new("Folder")
        if not oldMap then error("Somehow failed to create a Folder instance!") end -- This line only exists to shut up the type-checker

        bounds = API.NamedInstance("Folder", "Bounds", oldMap)
        API.NamedInstance("Folder", "Props", oldMap)
        API.NamedInstance("Folder", "Map", oldMap)

        oldMap.Name = "__Map_"..id
        oldMap.Parent = workspace
    end

    for _, v in physicalMap:GetChildren() do
        v.Parent = (workspace:FindFirstChild("__Map_"..id) :: Folder):FindFirstChild("Map")
    end

    for _, v in map:GetChildren() do
        task.wait()
        if v.Name == "Spawns" then
            spawns:ClearAllChildren()
            for _, spawn in v:GetChildren() do
                if not spawn:IsA("BasePart") then
                    continue
                end
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
            local prev = ReplicatedStorage:FindFirstChild(v.Name..id)
            if prev then
                prev:ClearAllChildren()
            end
            v.Parent = ReplicatedStorage
            continue
        end
        if v.Name == "Bounds" then
            for _, bound in v:GetChildren() do
                if not bound:IsA("BasePart") then
                    continue
                end
                bound.CanCollide = false
                bound.Transparency = 1
                bound.Parent = bounds
            end
            continue
        end
        if v.Name == "WeaponSpawns" then
            weapons:ClearAllChildren()
            for _, weapon in v:GetChildren() do
                if not weapon:IsA("BasePart") then
                    continue
                end
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

function module.CreateRound(map: Folder, gamemode: Types.Gamemode): Types.Round -- Creates a new Round and returns it.
    local self: Types.Round = {
        ID = HttpService:GenerateGUID(),
        Gamemode = gamemode,

        TimeMilestone = workspace:GetServerTimeNow()+PREPARING_TIME,
        RoundPhase = "Waiting",
        Paused = false,

        RoundStartEvent = Instance.new("BindableEvent"),
        RoundEndEvent = Instance.new("BindableEvent"),

        Participants = {},
        EventLog = {},

        HasParticipant = roundHandler.HasParticipant,
        GetParticipant = roundHandler.GetParticipant,
        JoinRound = roundHandler.JoinRound,

        GetRoleInfo = roundHandler.GetRoleInfo,

        StartRound = roundHandler.StartRound,
        PauseRound = roundHandler.PauseRound,
        EndRound = roundHandler.EndRound,
        
        IsRoundPreparing = roundHandler.IsRoundPreparing,
        IsRoundInProgress = roundHandler.IsRoundInProgress,
        IsRoundOver = roundHandler.IsRoundOver,

        CompareRoles = roundHandler.CompareRoles,
        GetLimitedParticipantInfo = roundHandler.GetLimitedParticipantInfo,
        GetRoleRelationship = roundHandler.GetRoleRelationship,

        warn = roundHandler.warn,
        error = roundHandler.error,

        _roundTimerThread = nil,
        _roundTimerContinueFor = 0,
        _roundTimerResumedAt = 0,
        _roundTimerTargetDuration = 0,
    }

    module.LoadMap(map, self.ID)
    
    module.Rounds[self.ID] = self
    return self
end

function module.GetRound(identifier: Types.UUID): Types.Round
    for _,v in module.Rounds do
        if v.ID == identifier then
            return v
        end
    end
    error("Could not find round with ID: "..identifier)
end

return module