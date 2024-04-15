-- The main RoundHandler. Used to create and interact with rounds.

local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Adapters = require("src/Adapters")
local Types = require("src/Types")
local API = require("src/API")

--- The main module. New rounds are created from here via module.CreateRound().
local module = {
    Rounds = {}
}

local PREPARING_TIME = Adapters.Configuration.PREPARING_TIME -- Duration of the preparing phase
local HIGHLIGHTS_TIME = Adapters.Configuration.HIGHLIGHTS_TIME -- Duration of the highlights phase

local function onDeath(self: Types.Participant, weapon: (Types.Equipment | Types.DeathType)?)
    -- create ragdoll and set properties
    local round = self.Round

    self.Deceased = true
    self.KilledByWeapon = if weapon then weapon else self.KilledByWeapon
    
    local killer = self.KilledByParticipant

    local isCorrectKill, isSelfDefense = false, false
    if killer then
        isCorrectKill = round:GetRoleRelationship(self:GetRole(), killer:GetRole()) == "__Ally"
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
    self.Round.Gamemode:OnDeath(self)
end

local function newParticipant(round, plr): Types.Participant
    return {
        Player = plr,
        Character = nil, -- We can't actually set Character here, because plr hasn't loaded in yet
        Name = plr.Name,
        Round = round,

        Karma = if round.Gamemode.UseKarma then Adapters.GetKarma(plr) else 1000,
        Role = nil,
        Credits = 0,
        Score = {},

        Deceased = false,
        SearchedBy = {},
        KilledByWeapon = "Suicide",
        KilledAt = 0,
        KilledByParticipant = nil,
        KilledInSelfDefense = false,
        KilledAsFreeKill = false,

        FreeKill = false,
        FreeKillReasons = {},

        SelfDefenseList = {},
        KillList = {},

        SlayVotes = {},

        EquipmentPurchases = {},

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

            return {
                Name = targetRole.Name,
                Colour = targetRole.Colour
            }
        end,

        AssignRole = function(self, role, overrideCredits, overrideInventory)
            self.Role = role
            self.Credits = if overrideCredits then role.StartingCredits else (self.Credits + role.StartingCredits)
            for _, v in role.StartingEquipment do
                Adapters.GiveEquipment(self, self.Round:GetEquipment(v))
            end
            Adapters.SendMessage({self :: any}, `You are now a {self:GetFormattedRole()}`, "info", "roleAlert")
            role:OnRoleAssigned(self)
        end,

        SearchCorpse = function(self, target)
            if not target.Deceased then
                error(`Target {target.Player.Name} is not dead!`)
            end

            if not table.find(target.SearchedBy, self) then
                if self:GetRole().CorpseResultsPublicised then
                    target.SearchedBy = self.Round.Participants
                else
                    table.insert(target.SearchedBy, self)
                end
                Adapters.SendMessage(self.Round.Participants, `{self.Player.Name} found the body of {target:GetFormattedName()}. They were a {target:GetFormattedRole()}!`, "info", "bodyFound")
            end

            if self:GetRole().CanStealCredits then
                Adapters.SendMessage({self}, `You have found {target.Credits} credits on the corpse of {target:GetFormattedName()}.`, "info", "creditsEarned")
                self.Credits += target.Credits
                target.Credits = 0
            end

            return {
                Name = target:GetFormattedName(),
                Role = target:GetRole(),
                DeathTime = target.KilledAt,
                SelfDefense = target.KilledInSelfDefense,
                FreeKill = #target.FreeKillReasons > 0,
                Headshot = false,
                EquipmentList = {},
                MurderWeapon = target.KilledByWeapon,
            }
        end,

        GetRole = function(self)
            if not self.Role then
                error(`Participant {self.Player.Name} does not have a Role!`)
            end
            return self.Role
        end,
        GetAllegiance = function(self)
            if not self.Role then
                error(`Participant {self.Player.Name} does not have a Role!`)
            end
            return self.Round:GetRoleInfo(self.Role.Allegiance)
        end,

        LeaveRound = function(self, doNotCreateCorpse)
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
            end
        
            if self.Role and self.Role.AnnounceDisconnect then
                Adapters.SendMessage(self.Round.Participants, (`{self:GetFormattedName()} has disconnected. They were a {self:GetFormattedRole()}.`), "info", "disconnect")
            end
        
            if not doNotCreateCorpse then
                onDeath(self, "Suicide")
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
            return self:GiveEquipment(equipment)
        end,

        AddKill = function(self, victim, ignoreKarma)
            local round = self.Round
            if not round:IsRoundInProgress() then
                return
            end
            if not ignoreKarma then
                local isAlly = round:GetRoleRelationship(victim:GetRole(), self:GetRole()) == "__Ally"
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

        GetFormattedName = function(self)
            local role = self.Role
            if role then
                return `<font color='{API.Color3ToHex(role.Colour)}'>{self.Player.Name}</font>`
            end
            return self.Player.Name
        end,

        GetFormattedRole = function(self)
            local role = self:GetRole()
            return `<font color='{API.Color3ToHex(role.Colour)}'>{role.Name}</font>`
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

        RoundStartEvent = Instance.new("BindableEvent"),
        RoundEndEvent = Instance.new("BindableEvent"),

        Participants = {},
        EventLog = {},

        GetParticipant = function(self, name)
            for _, participant in self.Participants do
                if participant.Player.Name == name then
                    return participant
                end
            end
            error(`Could not find Participant {name} in Round {self.ID}`)
        end,
        HasParticipant = function(self, name)
            for _, participant in self.Participants do
                if participant.Player.Name == name then
                    return true
                end
            end
            return false
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
        
        JoinRound = function(self, plr)
            if self:HasParticipant(plr.Name) then
                error(`{plr.Name} is already a Participant in Round {self.ID}`)
            end
            if not self:IsRoundPreparing() then
               error(`Failed to add {plr.Name} to Round {self.ID} because the Round has already started`)
            end
        
            local participant = newParticipant(self, plr)
            participant.Credits = self.Gamemode.StartingCredits
        
            table.insert(self.Participants, participant)
        
            plr.Destroying:Connect(function()
                participant:LeaveRound(false)
            end)
        
            local spawns = (self.Map:FindFirstChild("Spawns") :: Folder):GetChildren()
            plr.CharacterAppearanceLoaded:Once(function(char)
                local chosen = math.random(1, #spawns)
                char:PivotTo((spawns[chosen] :: BasePart).CFrame)
                local hum: Humanoid = char:WaitForChild("Humanoid") :: Humanoid
                participant.Character = char
                Adapters.OnCharacterLoad(char)
                self.Gamemode:OnCharacterLoad(char)
                hum.Died:Once(function()
                    if self:IsRoundPreparing() then
                        -- Respawn if the round hasn't started
                        participant:LeaveRound(true)
                        self:JoinRound(plr)
                        return
                    end
        
                    -- participant.KilledBy can be set by a script before they die
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
        
            return participant
        end,
        StartRound = function(self)
            if self:IsRoundInProgress() then
                error("Attempt to start round whilst it is already in progress!")
            end
            self.RoundPhase = "Playing"
            self:LogEvent("Round", "Start")
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
            self:LogEvent("Round", if self.Paused then "Pause" else "Resume")
            
            if self.Paused then
                assert(self._roundTimerThread)
                task.cancel(self._roundTimerThread)
                self._roundTimerThread = nil
                self._roundTimerContinueFor = self.TimeMilestone - workspace:GetServerTimeNow()
            else
                assert(self._roundTimerContinueFor)
                self.TimeMilestone = self._roundTimerContinueFor + workspace:GetServerTimeNow()
                self._roundTimerThread = task.delay(self._roundTimerContinueFor, self.EndRound, self, self.Gamemode:TimeoutVictors(self))
            end
            return
        end,
        EndRound = function(self, victors)
            self:LogEvent("Round", "End")
            self.RoundPhase = "Highlights"
            self.Winners = victors

            local scores = {}
            for _, v in self.Participants do
                scores[v] = v.Score
            end
            Adapters.SendRoundHighlights(self.Participants, self.Gamemode:CalculateRoundHighlights(self), self:CalculateUserFacingEvents(), scores)

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

            self.Map:Destroy()

            module.Rounds[self.ID] = nil
        end,
        LoadMap = function(self, map)
            if not map:FindFirstChild("Map") then
                error(`Map {map.Name} does not have a Map folder!`)
            end
            if not map:FindFirstChild("Spawns") then
                error(`Map {map.Name} does not have a Spawns folder!`)
            end
        
            self:LogEvent("Round", "NewMapLoaded")
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
                    
                elseif v.Name == "Lighting" then
                    for _, property: any in v:GetChildren() do
                        (Lighting :: any)[property] = property.Value
                    end
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

        GetEquipment = function(self, name)
            for _, v in self.Gamemode.AvailableEquipment do
                if v.Name == name then
                    return v
                end
            end
            error(`Equipment {name} not found!`)
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

        LogEvent = function(self, type, data)
            local event: Types.RoundEvent = {
                Timestamp = workspace:GetServerTimeNow(),
                Data = data,
            }
            if not self.EventLog[type] then
                self.EventLog[type] = {event}
                return
            end
            table.insert(self.EventLog[type], event)
        end,

        CalculateUserFacingEvents = function(self)
            local userFacingLog: {Types.UserFacingRoundEvent} = {}

            local function getDeathEvent(data: {Attacker: Types.Participant?, Weapon: string | Types.Equipment, Victim: Types.Participant})
                local attacker = data.Attacker
                local weapon = data.Weapon
                local text = data.Victim:GetFormattedName()

                local attackerName
                if attacker then
                    attackerName = attacker:GetFormattedName()
                end
                if weapon == "Fall" then
                    text ..= " was doomed to fall"
                    if attacker then
                        text ..= ` at the hands of {attackerName}`
                    end
                elseif weapon == "Drown" then
                    text ..= " was doomed to fall"
                    if attacker then
                        text ..= ` at the hands of {attackerName}`
                    end
                elseif weapon == "Suicide" then
                    text ..= " couldn't take it anymore and killed themselves"
                elseif weapon == "Crush" then
                    text ..= " was crushed"
                    if attacker then
                        text ..= ` by {attackerName}`
                    end
                elseif weapon == "Mutation" then
                    text ..= "'s DNA was mutated"
                    if attacker then
                        text ..= ` by {attackerName}`
                    end
                elseif type(weapon) == "table" then
                    text ..= ` died to a {weapon.Name}`
                    if attacker then
                        text ..= ` used by {attackerName}`
                    end
                end
                text ..= "."
                return text
            end

            for i: Types.RoundEventType, v in self.EventLog do
                if i == "Death" then
                    for _, event in v do
                        local data: Types.RoundEvent_Death = event.Data :: any
                        table.insert(userFacingLog, {
                            Text = getDeathEvent(data),
                            Icons = {},
                            Category = "Death",
                            Timestamp = event.Timestamp,
                        })
                    end
                elseif i == "MassDeath" then
                    for _, event in v do
                        local data: Types.RoundEvent_MassDeath = event.Data :: any
                        for _, participant in data.Victims do
                            table.insert(userFacingLog, {
                                Text = getDeathEvent({Attacker = data.Attacker, Victim = participant, Weapon = data.Weapon}),
                                Icons = {},
                                Category = "Death",
                                Timestamp = event.Timestamp
                            })
                        end
                    end
                elseif i == "EquipmentGiven" then
                    for _, event in v do
                        local data: Types.RoundEvent_Equipment = event.Data :: any
                        table.insert(userFacingLog, {
                            Text = `{data.Target} received a {data.Equipment.Name}`,
                            Icons = {},
                            Category = "Equipment",
                            Timestamp = event.Timestamp,
                        })
                    end
                elseif i == "EquipmentPurchased" then
                    for _, event in v do
                        local data: Types.RoundEvent_Equipment = event.Data :: any
                        table.insert(userFacingLog, {
                            Text = `{data.Target} purchased a {data.Equipment.Name}`,
                            Icons = {},
                            Category = "Equipment",
                            Timestamp = event.Timestamp,
                        })
                    end
                elseif i == "EquipmentRemoved" then
                    for _, event in v do
                        local data: Types.RoundEvent_Equipment = event.Data :: any
                        table.insert(userFacingLog, {
                            Text = `{data.Target} lost a {data.Equipment.Name}`,
                            Icons = {},
                            Category = "Equipment",
                            Timestamp = event.Timestamp,
                        })
                    end
                elseif i == "Round" then
                    for _, event in v do
                        local phase: Types.RoundPhaseEventType = event.Data :: any
                        local text: string = ""
                        if phase == "Start" then
                            text = "The round begins."
                        elseif phase == "Pause" then
                            text = "The round is paused."
                        elseif phase == "Resume" then
                            text = "The round is resumed."
                        elseif phase == "NewMapLoaded" then
                            text = "A new map is loaded."
                        elseif phase == "End" then
                            assert(self.Winners and self.Winners.VictoryText)
                            text = self.Winners.VictoryText
                        end
                        table.insert(userFacingLog, {
                            Text = text,
                            Icons = {},
                            Category = "Round",
                            Timestamp = event.Timestamp,
                        })
                    end
                end
            end

            table.sort(userFacingLog, function(a, b)
                return a.Timestamp < b.Timestamp
            end)

            return userFacingLog
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