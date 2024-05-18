-- The main RoundHandler. Used to create and interact with rounds.

local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Adapters = require(script.Parent.Adapters)
local Types = require(script.Parent.Types)
local API = require(script.Parent.API)

-- The main module. New rounds are created from here via module.CreateRound().
local module = {
    Rounds = {}
}

local PREPARING_TIME = Adapters.Configuration.PREPARING_TIME -- Duration of the preparing phase
local HIGHLIGHTS_TIME = Adapters.Configuration.HIGHLIGHTS_TIME -- Duration of the highlights phase
local SLAY_VOTES = Adapters.Configuration.SLAY_VOTES

local noRole: Types.Role = {
    Name = "",
    FormattedName = "",
    Description = "",
    Colour = Color3.new(),
    Allegiance = "",
    StartingCredits = 0,
    StartingEquipment = {},
    EquipmentShop = {},
    AnnounceDisconnect = false,
    CorpseResultsPublicised = false,
    CanSeeMissing = false,
    CanStealCredits = false,
    AwardOnDeath = {},
    Accessories = {},
    Health = 0,
    Speed = 0,
    JumpPower = 0,
    Allies = {},
    HighlightRules = {},
    KnowsRoles = {},
    TeamChat = false,
    OnRoleAssigned = function() end,
    OnRoleRemoved = function() end,
}

local function onDeath(self: Types.Participant)
    local round = self.Round

    if not self:IsDead() then
        -- Ideally Participant:Kill() would always be used, but sometimes things like reset character happen
        self:Kill()
    end
    
    local killer = self.KilledByParticipant
    local isCorrectKill, isSelfDefense = false, false
    if killer then
        isCorrectKill = round:GetRoleRelationship(self.Role, killer.Role) == "__Ally"
        isSelfDefense = killer:HasSelfDefenseAgainst(self)
        killer:AddKill(self, false)
    end

    local data: Types.RoundEvent_Death = {
        CorrectKill = isCorrectKill,
        FreeKill = #self.FreeKillReasons > 0,
        SelfDefense = isSelfDefense,
        Victim = self,
        Weapon = self.KilledByWeapon,
        Attacker = killer,
    }

    self.Round:LogEvent("Death", data)
    Adapters.OnDeath(self)
    self.Round.Gamemode:OnDeath(self)
end

local function newParticipant(round, plr): Types.Participant
    return {
        Player = plr,
        Character = nil :: any, -- We can't actually set Character here, because plr hasn't loaded in yet
        FormattedName = plr.Name,
        Round = round,

        Karma = if round.Gamemode.UseKarma then Adapters.GetKarma(plr) else 1000,
        Role = noRole,
        Credits = 0,
        Score = {},

        Status = "Alive",
        SearchedBy = {},
        KilledByWeapon = "Suicide",
        KilledAt = 0,
        KilledByParticipant = nil,
        KilledInSelfDefense = false,
        KilledAsFreeKill = false,
        KilledByHeadshot = false,

        FreeKill = false,
        FreeKillReasons = {},

        SelfDefenseList = {},
        KillList = {},

        SlayVotes = {},
        TryAddSlayVote = function(self, from: Types.Participant)
            if from.KilledAsFreeKill or table.find(self.SlayVotes, from) or self:IsDead() then
                return false
            end
    
            for _, v in self.KillList do
                if v.Player == from.Player then -- Comparing the Participants directly causes a type error. Presumably adding an __eq metamethod would solve this, but I don't want to do that because metatables make typechecking so much more annoying.
                    table.insert(self.SlayVotes, from)
                    if #self.SlayVotes >= SLAY_VOTES then
                        self:Kill()
                    end
                    return true
                end
            end

            return false
        end,

        EquipmentPurchases = {},

        IsDead = function(self)
            return (self.Status == "Missing") or (self.Status == "Dead")
        end,

        ViewPartialParticipant = function(self, target)
            local canSeeMissing = false
            if self.Role and self.Role.CanSeeMissing then
                canSeeMissing = true
            end
            local status = target.Status
            if (status == "Missing") and (not canSeeMissing) then
                status = "Alive"
            end
            return {
                Player = target.Player,
                Role = self:TryViewParticipantRole(target),
                Status = status :: "Alive" | "Dead" | "Missing"
            }
        end,

        TryViewParticipantRole = function(self, target)
            local ownRole = self.Role
            local targetRole = target.Role
            if not ownRole or not targetRole then
                return
            end

            local verdict = nil
            for relation, knows in ownRole.KnowsRoles do
                -- Explicit references to the role name take priority over things like ally or enemy
                if relation == ownRole.Name then
                    verdict = knows
                    break
                elseif verdict == nil then
                    verdict = self.Round:CompareRoles(ownRole, targetRole, relation)
                end
            end

            if not verdict then
                return
            end

            return targetRole
        end,

        AssignRole = function(self, role)
            local previousRole = self.Role
            self.Role = role
            self.FormattedName = `<font color='#{API.Color3ToHex(role.Colour)}'>{self.Player.Name}</font>`
            self.Credits += role.StartingCredits
            for _, v in role.StartingEquipment do
                Adapters.GiveEquipment(self, self.Round:GetEquipment(v) :: Types.Equipment)
            end
            Adapters.SendRoleAlert(self, role)
            role:OnRoleAssigned(self)
            if previousRole then
                previousRole:OnRoleRemoved(self)
            end
        end,

        SearchCorpse = function(self, target)
            if not target:IsDead() then
                error(`Target {target.Player.Name} is not dead`)
            end

            if not table.find(target.SearchedBy, self) then
                if self.Role.CorpseResultsPublicised then
                    target.SearchedBy = self.Round.Participants
                else
                    table.insert(target.SearchedBy, self)
                end
            end

            if target.Status == "Missing" then
                Adapters.SendMessage(`{self.Player.Name} found the body of {target.FormattedName}. They were a {target.Role.FormattedName}!`, "info", "bodyFound", self.Round.Participants)
                target.Status = "Dead"
            end

            if self.Role.CanStealCredits and (target.Credits > 0) then
                Adapters.SendMessage(`You have found {target.Credits} credits on the corpse of {target.FormattedName}.`, "info", "creditsEarned", {self})
                self.Credits += target.Credits
                target.Credits = 0
            end

            local equipmentList = {}
            for i, _ in target.EquipmentPurchases do
                local equipment = self.Round:GetEquipment(i)
                if type(equipment) == "function" then
                    table.insert(equipmentList, equipment)
                end
            end
            return {
                Name = target.FormattedName,
                Role = target.Role,
                DeathTime = target.KilledAt,
                SelfDefense = target.KilledInSelfDefense,
                FreeKill = #target.FreeKillReasons > 0,
                Headshot = target.KilledByHeadshot,
                EquipmentList = equipmentList,
                MurderWeapon = target.KilledByWeapon,
            }
        end,

        LeaveRound = function(self)
            if self.Round:IsRoundPreparing() then
                local index = table.find(self.Round.Participants, self)
                if index then
                    table.remove(self.Round.Participants, index)
                end

                if #self.Round.Participants < self.Round.Gamemode.MinimumPlayers then
                    local timerThread = self.Round._roundTimerThread
                    if not timerThread then
                        return
                    end
                    task.cancel(timerThread)
                end
            else
                if self.Role.AnnounceDisconnect then
                    Adapters.SendMessage(`{self.FormattedName} has disconnected. They were a {self.Role.FormattedName}.`, "info", "disconnect", self.Round.Participants)
                end
                self:Kill()
            end
        end,

        GiveEquipment = Adapters.GiveEquipment,
        RemoveEquipment = Adapters.RemoveEquipment,

        PurchaseEquipment = function(self, equipment)
            local purchases = self.EquipmentPurchases
            if (purchases[equipment.Name] or 0) >= equipment.MaxStock then
                return "NotInStock"
            end
            if self.Credits < equipment.Cost then
                return "NotEnoughCredits"
            end
            if self.EquipmentPurchases[equipment.Name] then
                self.EquipmentPurchases[equipment.Name] += 1
            else
                self.EquipmentPurchases[equipment.Name] = 0
            end
            return self:GiveEquipment(equipment)
        end,

        AddKill = function(self, victim, ignoreKarma)
            local round = self.Round
            if not round:IsRoundInProgress() then
                return
            end
            if not ignoreKarma then
                local isAlly = round:GetRoleRelationship(victim.Role, self.Role) == "__Ally"
                if isAlly and ((#victim.FreeKillReasons == 0) or not self:HasSelfDefenseAgainst(victim)) then
                    table.insert(self.FreeKillReasons, "Teamkill")
                    Adapters.SendSlayVote(victim, self)
                end
            end
            table.insert(self.KillList, victim)
        end,

        AddSelfDefense = function(self, against, duration)
            if not self.Round.Gamemode.SelfDefense then -- no point if it's not enabled
                return
            end
            table.insert(self.SelfDefenseList, {
                Against = against,
                Until = workspace:GetServerTimeNow() + duration
            })
        end,

        HasSelfDefenseAgainst = function(self, against)
            if not self.Round.Gamemode.SelfDefense then -- if self defense is not enabled we don't care
                return false
            end
            for _, v in self.SelfDefenseList do
                if (v.Against.Player == against.Player) and (v.Until < workspace:GetServerTimeNow()) then -- see comment for TryAddSlayVote
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

        GetFormattedName = function(self)
            local role = self.Role
            if role then
                return `<font color='{API.Color3ToHex(role.Colour)}'>{self.Player.Name}</font>`
            end
            return self.Player.Name
        end,

        Kill = function(self, attacker, weapon, headshot, ignoreKarma)
            self.Status = "Missing"
            self.KilledAsFreeKill = #self.FreeKillReasons > 0
            self.KilledAt = workspace:GetServerTimeNow()
            self.KilledByHeadshot = headshot or false
            self.KilledByParticipant = attacker or nil
            self.KilledByWeapon = weapon or "Suicide"

            if attacker then
                self.KilledInSelfDefense = attacker:HasSelfDefenseAgainst(self)
                self.KilledByParticipant = attacker
                attacker:AddKill(self, ignoreKarma or true)
            end

            local hum = self.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.Health = 0
            end
        end,

        IsDamageJustifiedAgainst = function(self, target)
            if self.Round:CompareRoles(self.Role, self.Role, "__Enemy") then
                return true
            end
            if self:HasSelfDefenseAgainst(target) then
                return true
            end

            if #target.FreeKillReasons > 0 then
                return true
            end
            return false
        end
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

        RoundPhaseChangeEvent = Instance.new("BindableEvent") :: BindableEvent & Types.RoundPhaseChangeEvent,

        Participants = {},
        EventLog = {MetaEvent = {}, CorpseSearched = {}, Death = {}},

        _props = {},

        DoMassDeath = function(self, victims, weapon, attacker: Types.Participant?, noGuilt: boolean?)
            table.sort(victims, function(a, b)
                return a.Role == self.Gamemode.PhyrricVictors
            end)

            for _, v in victims do
                v:Kill(attacker, weapon, false, noGuilt)
            end
        end,

        GetFormattedRole = function(self, role)
            return `<font color='{API.Color3ToHex(role.Colour)}'>{role.Name}</font>`
        end,

        GetParticipant = function(self, name)
            for _, participant in self.Participants do
                if participant.Player.Name == name then
                    return participant
                end
            end
            return
        end,
        GetParticipantsWithRole  = function(self, roleName)
            local role = self:GetRoleFromName(roleName)
            local participants = {}
            for _, v in self.Participants do
                if v.Role == role then
                    table.insert(participants, v)
                end
            end
            return participants
        end,
        
        JoinRound = function(self, plr)
            if self:GetParticipant(plr.Name) then
                error(`{plr.Name} is already a Participant in Round {self.ID}`)
            end
            if not self:IsRoundPreparing() then
               error(`Failed to add {plr.Name} to Round {self.ID} because the Round has already started`)
            end
        
            local participant = newParticipant(self, plr)
            participant.Credits = self.Gamemode.StartingCredits
        
            table.insert(self.Participants, participant)
        
            plr.Destroying:Connect(function()
                participant:LeaveRound()
            end)
        
            local spawns = (self.Map.Spawns):GetChildren()
            plr.CharacterAppearanceLoaded:Once(function(char)
                local chosen = math.random(1, #spawns)
                char:PivotTo((spawns[chosen] :: BasePart).CFrame)
                local hum: Humanoid = char:WaitForChild("Humanoid") :: Humanoid
                participant.Character = char
                Adapters.OnCharacterLoad(participant)
                self.Gamemode:OnCharacterLoad(char)
                hum.Died:Once(function()
                    if self:IsRoundPreparing() then
                        -- Respawn if the round hasn't started
                        participant:LeaveRound()
                        self:JoinRound(plr)
                        return
                    end

                    onDeath(participant)
                end)
            end)
            plr:LoadCharacter()

            for _, v in self.Gamemode.StartingEquipment do
                local index = 0
                for i, a in self.Gamemode.AvailableEquipment do
                    if a.Name == v then
                        index = i
                        break
                    end
                end
                Adapters.GiveEquipment(participant, self.Gamemode.AvailableEquipment[index])
            end
        
            if (#self.Participants >= self.Gamemode.MinimumPlayers) and (not self._roundTimerThread) then
                self._roundTimerThread = task.delay(PREPARING_TIME, self.StartRound, self)
            end

            Adapters.SendMessage(`The round will begin in {math.round(self.TimeMilestone-workspace:GetServerTimeNow())}s. Prepare yourself.`, "info", "timeToRoundStart", {participant})
            
            if self.Gamemode.UseKarma then
                Adapters.SendMessage(`Your karma is {participant.Karma}. You will deal {Adapters.CalculateDamageModifier(participant.Karma)*100}% damage this round.`, "info", "karma", {participant})
            end

            return participant
        end,
        StartRound = function(self)
            if not self:IsRoundPreparing() then
                error("Attempt to start round whilst it is already in progress")
            end
            self.RoundPhase = "Playing"
            self:LogEvent("MetaEvent", {RoundPhase = "Start"})
            local gm = self.Gamemode
            local participants = self.Participants
            API.ShuffleInPlace(participants)

            local duration = self.Gamemode:Duration(#self.Participants)
            self.TimeMilestone = workspace:GetServerTimeNow() + duration
            self._roundTimerThread = task.delay(duration, function()
                self:EndRound(self.Gamemode:TimeoutVictors(self))
            end)

            gm:AssignRoles(participants)

            return self.RoundPhaseChangeEvent:Fire("Playing")
        end,
        PauseRound = function(self)
            if not self:IsRoundInProgress() then
                error("Round must be in progress to pause")
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
                self._roundTimerThread = task.delay(self._roundTimerContinueFor, function()
                    self:EndRound(self.Gamemode:TimeoutVictors(self))
                end)
            end
            return
        end,

        GetPartialRound = function(self)
            return {
                Gamemode = self.Gamemode,
                RoundPhase = self.RoundPhase,
                Map = self.Map,
                Paused = self.Paused,
                TimeMilestone = self.TimeMilestone,
                RoundEndInfo = self.RoundEndInfo,
            }
        end,

        GetProp = function(self, propInstance)
            return self._props[propInstance] or error(`Prop {propInstance.Name} was not found`)
        end,

        EndRound = function(self, victors)
            if self:IsRoundOver() then
                error("Round is already ended")
            end
            if self._roundTimerThread then
                task.cancel(self._roundTimerThread)
            end
            self:LogEvent("MetaEvent", {Winners = victors})
            self.RoundPhase = "Highlights"
            self.TimeMilestone = workspace:GetServerTimeNow() + Adapters.Configuration.HIGHLIGHTS_TIME

            local scores = {}
            for _, v in self.Participants do
                scores[v.FormattedName] = v.Score
            end

            local events = Adapters.CalculateUserFacingEvents(self.EventLog, victors)
            local highlights = self.Gamemode:CalculateRoundHighlights(self)

            assert(victors.VictoryMusic)
            self.RoundEndInfo = {
                Winners = victors,
                Events = events,
                Scores = scores,
                Highlights = highlights,
                Music = victors.VictoryMusic[math.random(1, math.max(#victors.VictoryMusic, 1))]
            }

            self.RoundPhaseChangeEvent:Fire("Highlights")
            Adapters.SendRoundHighlights(self.Participants, highlights, events, scores)

            local updateNeeded = Adapters.CheckForUpdate(self)
            if updateNeeded then
                Adapters.SendMessage("This server is outdated and will restart soon.", "error", "update", true)
            end

            -- Destroy the round
            task.wait(HIGHLIGHTS_TIME)

            if updateNeeded then
                Adapters.SendMessage("Server restarting...", "error", "update", true)
                TeleportService:TeleportAsync(game.PlaceId, Players:GetPlayers())
                Players.PlayerAdded:Connect(function(plr)
                    plr:Kick("This server is shutting down for an update.")
                end)
            end

            self.Map:Destroy()
            self.RoundPhaseChangeEvent:Fire("Intermission")

            module.Rounds[self.ID] = nil
        end,
        LoadMap = function(self, map)
            Adapters.SetDefaultLighting()
            self:LogEvent("MetaEvent", {NewMap = map.Name})
            map = map:Clone()
        
            local mapFolder = Instance.new("Folder")
            mapFolder.Name = `__Map_{self.ID}`

            map.Map.Parent = mapFolder
            
            for _, propInstance in map.Props:GetChildren() do
                local onBreak = propInstance:FindFirstChild("OnBreak")
                local prop: Types.Prop = {
                    PropInstance = propInstance,
                    Attacker = nil,
                    Humanoid = propInstance.Humanoid,
                    OnBreak = function(self)
                        if onBreak then
                            (require)(onBreak)(self.Attacker)
                        end
                    end
                }
                self._props[propInstance] = prop
                prop.Humanoid.Died:Once(prop.OnBreak)
            end
            map.Props.Parent = mapFolder

            local function onWeaponAdded(weapon: any)
                weapon.Anchored = false
                weapon.Touched:Once(function(part)
                    local plr = Players:GetPlayerFromCharacter(part.Parent :: Model)
                    if not plr then
                        return
                    end

                    local participant = self:GetParticipant(plr.Name)
                    if not participant then
                        return
                    end

                    local equipment = self:GetEquipment(weapon.Name)
                    if not equipment then
                        return warn(weapon.Name.." not found as Equipment.")
                    end

                    participant:GiveEquipment(equipment)
                    weapon:Destroy()
                end)
            end
            for _, weapon in map.WeaponSpawns:GetChildren() do
                onWeaponAdded(weapon)
            end
            map.WeaponSpawns.ChildAdded:Connect(onWeaponAdded)
            map.WeaponSpawns.Parent = mapFolder

            for _, spawn in map.Spawns:GetChildren() do
                spawn.Anchored = true
                spawn.Transparency = 1
                spawn.CanCollide = false
                spawn.CanTouch = false
                spawn.CanQuery = false
                spawn:ClearAllChildren()
            end
            map.Spawns.Parent = mapFolder

            local lighting = map:FindFirstChild("Lighting")
            if lighting then
                for _, setting in lighting:GetChildren() do
                    (Lighting :: any)[setting.Name] = setting.Value
                end
                lighting.Parent = mapFolder
            end
            
            self.Map = mapFolder :: Types.MapStructure
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

        GetEquipment = function(self, name)
            for _, v in self.Gamemode.AvailableEquipment do
                if v.Name == name then
                    return v
                end
            end
            return
        end,
        GetRoleFromName = function(self, roleName)
            for _, v in self.Gamemode.Roles do
                if v.Name == roleName then
                    return v
                end
            end
            error(`Role {roleName} not found`)
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

        LogEvent = function(self, type, data)
            local event: Types.RoundEvent<Types.RoundEventData> = {
                Timestamp = workspace:GetServerTimeNow(),
                Data = data,
            }
            table.insert(self.EventLog[type], event)
        end,

        _roundTimerThread = nil,
        _roundTimerContinueFor = nil,
    }
end

function module.CreateRound(map: Types.MapStructure, gamemode: Types.Gamemode): Types.Round -- Creates a new Round and returns it.
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