--!strict
-- The main RoundHandler. Used to create and interact with rounds.

local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Adapters = require("src/Adapters")
local Types = require("src/Types")
local API = require("src/API")

--- The main module. New rounds are created from here via module.CreateRound().
local module = {}
module.Rounds = {} :: {[Types.UUID]: Types.Round}

local PREPARING_TIME = Adapters.Configuration.PREPARING_TIME -- Duration of the preparing phase
local HIGHLIGHTS_TIME = Adapters.Configuration.HIGHLIGHTS_TIME -- Duration of the highlights phase

local function onDeath(self: Types.Participant, killedBy: Types.DeathType?, weapon: Types.EquipmentName?)
    -- create ragdoll and set properties
    self.Deceased = true
    self.KilledBy = if killedBy then killedBy else self.KilledBy
    self.KilledByWeapon = if weapon then weapon else self.KilledByWeapon
    
    self.Round.Gamemode:OnDeath(self)
end

local function newParticipant(round, plr): Types.Participant
    return {
        Player = plr,
        Name = plr.Name,
        Round = round,

        Karma = if round.Gamemode.UseKarma then Adapters.GetKarma(plr) else 1000,
        Role = nil,
        Credits = 0,
        Score = {},

        Deceased = false,
        SearchedBy = {},
        KilledBy = "Suicide",
        KilledByWeapon = nil,
        KilledInSelfDefense = false,

        FreeKill = false,
        FreeKillReasons = {},

        SelfDefenseList = {},
        KillList = {},

        SlayVotes = 0,

        EquipmentPurchases = {},

        AssignRole = function(self, role: Types.Role, overrideCredits: boolean?, overrideInventory: boolean?)
            self.Role = role
            self.Credits = if overrideCredits then role.StartingCredits else (self.Credits + role.StartingCredits)
            role:OnRoleAssigned(self)
        end,

        GetAllegiance = function(self)
            if not self.Role then
                error(`Participant {self.Name} does not have a role`)
            end
            return self.Round:GetRoleInfo(self.Role.Allegiance)
        end,

        LeaveRound = function(self)
            local plr = self.Player

            local index = table.find(self.Round.Participants, self)
            if index then
                table.remove(self.Round.Participants, index)
            end
        
            if plr and plr.Character then
                plr.Character:Destroy()
            end
        
            if #self.Round.Participants < self.Round.Gamemode.MinimumPlayers then
                local timerThread = self.Round._roundTimerThread
                if not timerThread then
                    return
                end
                task.cancel(timerThread)
            end
        
            if self.Role and self.Role.AnnounceDisconnect then
                Adapters.SendMessage(self.Round:GetConnectedParticipants(), (`{self.Name} has disconnected. They were a {self.Role.Name}.`), "info", "disconnect")
            end
        
            onDeath(self, "Suicide")
        end,

        GiveEquipment = Adapters.GiveEquipment,
        RemoveEquipment = Adapters.RemoveEquipment,

        PurchaseEquipment = function(self, equipment)
            local purchases = self.EquipmentPurchases
            if purchases[equipment.Name] >= equipment.MaxStock then
                return "NotInStock"
            end
            if self.Credits < equipment.Cost then
                return "NotEnoughCredits"
            end
            return self:GiveEquipment(equipment)
        end,

        AddKill = function(self, victim, ignoreKarma)
            local round = self.Round
            if not round:IsRoundInProgress() then
                return
            end
            if not ignoreKarma then
                assert(victim.Role and self.Role)

                local isAlly = round:GetRoleRelationship(victim.Role, self.Role) == "__Ally"
                if isAlly and ((#victim.FreeKillReasons == 0) or not self:HasSelfDefenseAgainst(victim)) then
                    table.insert(self.FreeKillReasons, "Teamkill")
                end
            end
            table.insert(self.KillList, victim)
        end,

        AddSelfDefense = function(self, against, duration)
            table.insert(self.SelfDefenseList, {
                Against = against,
                Until = workspace:GetServerTimeNow() + duration
            })
        end,

        HasSelfDefenseAgainst = function(self, against)
            for _, v in self.SelfDefenseList do
                if (v.Against == against) and (v.Until < workspace:GetServerTimeNow()) then
                    return true
                end
            end
            return false
        end,

        AddScore = function(self, reason, amount)
            if not self.Score[reason] then
                self.Score[reason] = amount
            else
                self.Score[reason] += amount
            end
        end,
    }
end

local function newRound(gamemode): Types.Round
    return {
        ID = HttpService:GenerateGUID(),
        Gamemode = gamemode,
        Map = nil :: any,

        TimeMilestone = workspace:GetServerTimeNow()+PREPARING_TIME,
        RoundPhase = "Waiting",
        Paused = false,

        RoundStartEvent = Instance.new("BindableEvent"),
        RoundEndEvent = Instance.new("BindableEvent"),

        Participants = {},
        EventLog = {},

        GetConnectedParticipants = function(self)
            local participants = {}
            for _, v in self.Participants do
                if v.Player and v.Player:IsDescendantOf(Players) then
                    table.insert(participants, v :: Types.ConnectedParticipant)
                end
            end
            return participants
        end,
        GetParticipant = function(self, name)
            for _, participant in self.Participants do
                if participant.Name == name then
                    return participant
                end
            end
            error(`Could not find Participant "{name} in Round {self.ID}`)
        end,
        HasParticipant = function(self, name)
            for _, participant in self.Participants do
                if participant.Name == name then
                    return true
                end
            end
            return false
        end,
        GetLimitedParticipantInfo = function(self, viewer, target)
            local viewerParticipant = self:GetParticipant(viewer.Name)
            local targetParticipant = self:GetParticipant(target.Name)
            if not viewerParticipant then return warn(`{viewer.Name} is not a Participant of Round {self.ID}.`) end
            if not targetParticipant then return warn(`{target.Name} is not a Participant of Round {self.ID}.`) end

            local viewerRole = viewerParticipant.Role
            local targetRole = targetParticipant.Role
            if not viewerRole then return warn(`{viewer.Name} role is nil in Round {self.ID}.`) end
            if not targetRole then return warn(`{target.Name} role is nil in Round {self.ID}.`) end

            local relation = self:GetRoleRelationship(viewerRole, targetRole)

            local partialInfo = {
                Name = targetRole.Name,
                Colour = targetRole.Colour,
            }
            
            -- First check for explicit role name, then for Ally/Enemy.

            if viewerRole.KnowsRoles[targetRole.Name] == false then return end
            if viewerRole.KnowsRoles[targetRole.Name] then return partialInfo end

            if (relation == "__Ally" or relation == "__Enemy") and (viewerRole.KnowsRoles[relation]) then return partialInfo end
            if (relation == "__Ally" or relation == "__Enemy") and (viewerRole.KnowsRoles[relation] == false) then return end

            if viewerRole.KnowsRoles["__All"] then
                return partialInfo
            end
            return
        end,
        GetParticipantsWithRole  = function(self, roleName)
            local role = self:GetRoleInfo(roleName)
            local participants = {}
            for _, v in self.Participants do
                if v.Role == role then
                    table.insert(participants, v)
                end
            end
            return participants
        end,
        
        JoinRound = function(self, name)
            if self:HasParticipant(name) then
                error(`{name} is already a Participant in Round {self.ID}`)
            end
            if not self:IsRoundPreparing() then
               error(`Failed to add {name} to Round {self.ID} because the Round has already started`)
            end
            local plr = Players:FindFirstChild(name) :: Instance
            if (not plr) or (not plr:IsA("Player")) then 
                error(`Attempt to add non-Player participant: {tostring(plr)}`)
            end
        
            local participant = newParticipant(self, plr)
        
            table.insert(self.Participants, participant)
        
            plr.Destroying:Connect(function()
                participant:LeaveRound()
            end)
        
            local spawns = (self.Map:FindFirstChild(`Spawns{self.ID}`) :: Folder):GetChildren()
            plr.CharacterAppearanceLoaded:Once(function(char)
                local chosen = math.random(1, #spawns)
                char:PivotTo((spawns[chosen] :: BasePart).CFrame)
                local hum: Humanoid = char:WaitForChild("Humanoid") :: Humanoid
                hum.Died:Once(function()
                    if self:IsRoundPreparing() then
                        -- Respawn if the round hasn't started
                        participant:LeaveRound()
                        self:JoinRound(name)
                        return
                    end
        
                    -- participant.KilledBy can be set by a script before they die
                    onDeath(participant)
                end)
            end)
            plr:LoadCharacter()
        
            if #self.Participants >= self.Gamemode.MinimumPlayers then
                self._roundTimerThread = task.delay(PREPARING_TIME, self.StartRound, self)
            end
        
            return participant
        end,
        StartRound = function(self)
            local gm = self.Gamemode
            local participants = self.Participants
            API.ShuffleInPlace(participants)

            gm:AssignRoles(participants)

            return self.RoundStartEvent:Fire()
        end,
        PauseRound = function(self)
            if not self:IsRoundInProgress() then
                return "RoundNotInProgress"
            end
        
            self.Paused = not self.Paused
            
            if self.Paused then
                assert(self._roundTimerThread)
                task.cancel(self._roundTimerThread)
                self._roundTimerThread = nil
                self._roundTimerContinueFor = self.TimeMilestone - workspace:GetServerTimeNow()
            else
                assert(self._roundTimerContinueFor)
                self.TimeMilestone = self._roundTimerContinueFor + workspace:GetServerTimeNow()
                self._roundTimerThread = task.delay(self._roundTimerContinueFor, self.EndRound, self, self:GetRoleInfo(self.Gamemode.TimeoutVictors(self)))
            end
            return
        end,
        EndRound = function(self, victors)
            self.RoundPhase = "Highlights"
            self.Winners = victors

            local scores = {}
            for _, v in self.Participants do
                scores[v] = v.Score
            end
            Adapters.SendRoundHighlights(self:GetConnectedParticipants(), {}, self.EventLog, scores)

            local updateNeeded = Adapters.CheckForUpdate(self)
            if updateNeeded then
                Adapters.SendMessage({}, "This server is outdated and will restart soon.", "error", "update", true)
            end

            -- Destroy the round
            task.wait(HIGHLIGHTS_TIME)

            if updateNeeded then
                Adapters.SendMessage({}, "Server restarting...", "error", "update", true)
                TeleportService:TeleportAsync(game.PlaceId, Players:GetPlayers())
                Players.PlayerAdded:Connect(function(plr)
                    plr:Kick("This server is shutting down for an update.")
                end)
            end

            self.RoundEndEvent:Fire()

            self.RoundEndEvent:Destroy()
            self.RoundStartEvent:Destroy()

            module.Rounds[self.ID] = nil
        end,
        LoadMap = function(self, map)
            if map:FindFirstChild("Map") then
                error(`Map {map.Name} does not have a Map folder!`)
            end
        
            map = map:Clone()
        
            local mapFolder = Instance.new("Folder")
            mapFolder.Name = `__Map_{self.ID}`
        
            for _, v in map:GetChildren() do
                task.wait()
                if v.Name == "Spawns" then
                    for _, spawn in v:GetChildren() do
                        if not spawn:IsA("BasePart") then
                            continue
                        end
                        spawn.Anchored = true
                        spawn.Transparency = 1
                        spawn.CanCollide = false
                        spawn.CanTouch = false
                        spawn.CanQuery = false
                    end
                elseif v.Name == "WeaponSpawns" then
                    for _, weapon in v:GetChildren() do
                        if not weapon:IsA("BasePart") then
                            continue
                        end
                        weapon.CanCollide = true
                        weapon.CanTouch = true
                        weapon.Anchored = false
                    end
                elseif v.Name == "Props" then
                    
                end
        
                v.Parent = mapFolder
            end
            
            self.Map = mapFolder
            mapFolder.Parent = workspace
        end,
        
        IsRoundPreparing = function(self)
            return self.RoundPhase == "Waiting" or self.RoundPhase == "Preparing"
        end,
        IsRoundInProgress = function(self)
            return self.RoundPhase == "Playing"
        end,
        IsRoundOver = function(self)
            return self.RoundPhase == "Intermission" or self.RoundPhase == "Highlights"
        end,

        GetRoleInfo = function(self, roleName)
            for _, v in self.Gamemode.Roles do
                if v.Name == roleName then
                    return v
                end
            end
            error(`Role '{roleName}' not found in gamemode '{self.Gamemode.Name}'`)
        end,
        CompareRoles = function(self, role1, role2, comparison)
            if comparison == "__All" then
                return true
            end
            return self:GetRoleRelationship(role1, role2) == comparison
        end,
        
        GetRoleRelationship = function(self, role1, role2)
            return (table.find(role1.Allies, role2.Name) and "__Ally") or "__Enemy"
        end,

        AddEvent = function(self, text, category, icons)
            local event: Types.RoundEvent = {
                Text = text,
                Category = category,
                Time = workspace:GetServerTimeNow(),
                Icons = icons
            }
            table.insert(self.EventLog, event)
        end,

        _roundTimerThread = nil,
        _roundTimerContinueFor = nil,
    }
end

function module.CreateRound(map: Folder, gamemode: Types.Gamemode): Types.Round --- Creates a new Round and returns it.
    local self: Types.Round = newRound(gamemode)
    self:LoadMap(map)
    
    module.Rounds[self.ID] = self
    return self
end

function module.GetRound(identifier: Types.UUID): Types.Round
    for _, v in module.Rounds do
        if v.ID == identifier then
            return v
        end
    end
    error(`Could not find round with ID: {identifier}`)
end

return module