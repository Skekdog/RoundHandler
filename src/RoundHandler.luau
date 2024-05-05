-- The main RoundHandler. Used to create and interact with rounds.

local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Adapters = require(script.Parent.Adapters)
local Types = require(script.Parent.Types)
local API = require(script.Parent.API)

local module = {
    Rounds = {}
}

local PREPARING_TIME = Adapters.Configuration.PREPARING_TIME -- Duration of the preparing phase
local HIGHLIGHTS_TIME = Adapters.Configuration.HIGHLIGHTS_TIME -- Duration of the highlights phase
local SLAY_VOTES = Adapters.Configuration.SLAY_VOTES

local function onDeath(self: Types.Participant)
    local round = self.Round

    if not self:IsDead() then
        -- Ideally Participant:Kill() would always be used, but sometimes things like reset character happen
        self:Kill()
    end
    
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
    Adapters.OnDeath(self.Character)
    self.Round.Gamemode:OnDeath(self)
end

--[=[
    @class Participant
]=]
local function newParticipant(round: Types.Round, plr: Player): Types.Participant
    local Participant = {}

    --[=[
        @prop Round Round
        @within Participant

        A reference to the [Round].
    ]=]
    Participant.Round = round

    --[=[
        @prop Player Player
        @within Participant

        The Participant's [Player]. Will never be nil, but may be :Destroyed. Be aware of the implications that has.
    ]=]
    Participant.Player = plr

    --[=[
        @prop Karma number
        @within Participant

        A live track of the Participant's karma. May be different to [Adapters.GetKarma], which is only updated at the end of the [Round].
    ]=]
    Participant.Karma = if round.Gamemode.UseKarma then Adapters.GetKarma(plr) else 1000

    --[=[
        @prop Credits Integer
        @within Participant

        The Participant's credits. Credits are used for purchasing equipment, and can be awarded by being a certain role, killing enemies, or looting corpses.
    ]=]
    Participant.Credits = 0

    --[=[
        @prop Score ParticipantScoring
        @within Participant

        Keep track of this Participant's score, separated by reason.
    ]=]
    Participant.Score = {}

    --[=[
        @prop Status ParticipantStatus
        @within Participant

        Whether the Participant is Alive, Missing, or Dead.
        A Participant is Missing when they are killed until someone searches their body.
    ]=]
    Participant.Status = "Alive" :: any

    --[=[
        @prop SearchedBy {Participant}
        @within Participant

        A list of Participants who have searched this corpse and who can now view the information whenever.
    ]=]
    Participant.SearchedBy = {}

    --[=[
        @prop KilledByWeapon Equipment | DeathType
        @within Participant

        How this Participant died. Either [Equipment] or [DeathType].
    ]=]
    Participant.KilledByWeapon = "Suicide" :: any

    --[=[
        @prop KilledAt Timestamp
        @within Participant

        The UNIX Timestamp of when this Participant died, as returned by [Workspace:GetServerTimeNow].
    ]=]
    Participant.KilledAt = 0

    --[=[
        @prop KilledInSelfDefense boolean
        @within Participant

        True if killed by a Participant who was using self-defense.
    ]=]
    Participant.KilledInSelfDefense = false

    --[=[
        @prop KilledAsFreeKill boolean
        @within Participant

        True if the Participant was killed when [Participant.FreeKillReasons] was not empty.
    ]=]
    Participant.KilledAsFreeKill = false

    --[=[
        @prop KilledByHeadshot boolean
        @within Participant

        True if the Participant was killed by a headshot. No surprises there.
    ]=]
    Participant.KilledByHeadshot = false

    --[=[
        @prop FreeKillReasons {string}
        @within Participant

        A list of reasons for the Participant being a free kill. If not empty, the Participant is a free kill and can be killed by allies without penalty.
    ]=]
    Participant.FreeKillReasons = {}

    --[=[
        @prop SelfDefenseList {SelfDefenseEntry}
        @within Participant

        A list of Participants who can be freely killed by this Participant in self defense.
        Also stores for how long the self defense applies.
    ]=]
    Participant.SelfDefenseList = {}

    --[=[
        @prop KillList {Participant}
        @within Participant

        A list of Participants who have been killed by this Participant.
    ]=]
    Participant.KillList = {}

    --[=[
        @prop SlayVotes {Participant}
        @within Participant

        A list of Participants who have voted to slay this Participant after being RDM'ed by them.
    ]=]
    Participant.SlayVotes = {}

    --[=[
        @prop EquipmentPurchases {[Equipment]: Integer}
        @within Participant

        A dictionary of Equipment to the number of times that this Participant has purchased it.
    ]=]
    Participant.EquipmentPurchases = {}

    --[=[
        @within Participant
        @param from Participant -- The Participant attempting to slay this Participant
        @return boolean -- Whether the vote succeeded
    ]=]
    function Participant.TryAddSlayVote(self: Types.Participant, from: Types.Participant): boolean
        if from.KilledAsFreeKill or table.find(self.SlayVotes, from) or self:IsDead() then
            return false
        end

        for _, v in self.KillList do
            if v :: any == from then
                table.insert(self.SlayVotes, from)
                if #self.SlayVotes >= SLAY_VOTES then
                    self:Kill()
                end
                return true
            end
        end

        return false
    end

    --[=[
        @within Participant
        @return boolean -- True if Status is "Missing" or "Dead"
    ]=]
    function Participant.IsDead(self: Types.Participant)
        return (self.Status == "Missing") or (self.Status == "Dead")
    end

    --[=[
        @within Participant
        @param target Participant -- The Participant to view
        @return PartialParticipant -- Status is adjusted for this [Role.CanSeeMissing]
    ]=]
    function Participant.ViewPartialParticipant(self: Types.Participant, target: Types.Participant): Types.PartialParticipant
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
    end

    --[=[
        @within Participant
        @param target Participant -- The Participant to view
        @return PartialRole --
    ]=]
    function Participant.TryViewParticipantRole(self: Types.Participant, target: Types.Participant): Types.PartialRole?
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
    end

    --[=[
        @within Participant
        @param role Role -- The [Role] to assign
    ]=]
    function Participant.AssignRole(self: Types.Participant, role: Types.Role): ()
        local previousRole = self.Role
        self.Role = role
        self.Credits += role.StartingCredits
        for _, v in role.StartingEquipment do
            Adapters.GiveEquipment(self, self.Round:GetEquipment(v))
        end
        Adapters.SendRoleAlert(self, role)
        role:OnRoleAssigned(self)
        if previousRole then
            previousRole:OnRoleRemoved(self)
        end
    end

    --[=[
        @within Participant
        @param target Participant -- The Participant to search
        @return CorpseInfo -- Info about this Participant's corpse
    ]=]
    function Participant.SearchCorpse(self: Types.Participant, target: Types.Participant): Types.CorpseInfo
        if not target:IsDead() then
            error(`Target {target.Player.Name} is not dead`)
        end

        if not table.find(target.SearchedBy, self) then
            if self:GetRole().CorpseResultsPublicised then
                target.SearchedBy = self.Round.Participants
            else
                table.insert(target.SearchedBy, self)
            end
        end

        if target.Status == "Missing" then
            Adapters.SendMessage(`{self.Player.Name} found the body of {target:GetFormattedName()}. They were a {target.Round:GetFormattedRole(target:GetRole())}!`, "info", "bodyFound", self.Round.Participants)
            target.Status = "Dead"
        end

        if self:GetRole().CanStealCredits and (target.Credits > 0) then
            Adapters.SendMessage(`You have found {target.Credits} credits on the corpse of {target:GetFormattedName()}.`, "info", "creditsEarned", {self})
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
            Name = target:GetFormattedName(),
            Role = target:GetRole(),
            DeathTime = target.KilledAt,
            SelfDefense = target.KilledInSelfDefense,
            FreeKill = #target.FreeKillReasons > 0,
            Headshot = target.KilledByHeadshot,
            EquipmentList = equipmentList,
            MurderWeapon = target.KilledByWeapon,
        }
    end

    --[=[
        @within Participant
        @return Role -- Returns this Participant's Role
        @error ParticipantRoleIsNil -- Raised if Role is not set, i.e, [Round] has not started yet.
    ]=]
    function Participant.GetRole(self: Types.Participant): Types.Role
        if not self.Role then
            error(`Participant {self.Player.Name} Role is nil`)
        end
        return self.Role
    end

    --[=[
        @within Participant
        @return Role -- This Participant's Role's Allegiance.
        @error ParticipantRoleIsNil -- Raised if Role is not set, i.e, [Round] has not started yet.
    ]=]
    function Participant.GetAllegiance(self: Types.Participant): Types.Role
        if not self.Role then
            error(`Participant {self.Player.Name} Role is nil`)
        end
        return self.Round:GetRoleFromName(self.Role.Allegiance)
    end

    --[=[
        @within Participant
    ]=]
    function Participant.LeaveRound(self: Types.Participant): ()
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
            if self:GetRole().AnnounceDisconnect then
                Adapters.SendMessage(`{self:GetFormattedName()} has disconnected. They were a {self.Round:GetFormattedRole(self:GetRole())}.`, "info", "disconnect", self.Round.Participants)
            end
            self:Kill()
        end
    end

    --[=[
        @within Participant
        @param Equipment -- The Equipment to give
        @return EquipmentGiveRejectionReason? -- A string describing why giving the item failed, if it failed.
    ]=]
    Participant.GiveEquipment = Adapters.GiveEquipment

    --[=[
        @within Participant
        @param Equipment -- The Equipment to remove
        @return EquipmentRemoveRejectionReason? -- A string describing why removing the item failed, if it failed.
    ]=]
    Participant.RemoveEquipment = Adapters.RemoveEquipment

    --[=[
        @within Participant
        @param Equipment -- The Equipment to purchase
        @return EquipmentGiveRejectionReason? -- A string describing why purchasing the item failed, if it failed.
    ]=]
    function Participant.PurchaseEquipment(self: Types.Participant, equipment: Types.Equipment): Types.EquipmentPurchaseRejectionReason?
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
    end

    --[=[
        @within Participant
        @param Equipment -- The Equipment to give
        @return EquipmentGiveRejectionReason? -- A string describing why giving the item failed, if it failed.
    ]=]
    function Participant.AddKill(self: Types.Participant, victim: Types.Participant, ignoreKarma: boolean): ()
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
    end

    function Participant.AddSelfDefense(self: Types.Participant, against: Types.Participant, duration: number): ()
        if not self.Round.Gamemode.SelfDefense then -- no point if it's not enabled
            return
        end
        table.insert(self.SelfDefenseList, {
            Against = against,
            Until = workspace:GetServerTimeNow() + duration
        })
    end

    function Participant.HasSelfDefenseAgainst(self: Types.Participant, against: Types.Participant): boolean
        if not self.Round.Gamemode.SelfDefense then -- if self defense is not enabled we don't care
            return false
        end
        for _, v in self.SelfDefenseList do
            if (v.Against :: any == against) and (v.Until < workspace:GetServerTimeNow()) then
                return true
            end
        end
        return false
    end

    function Participant.AddScore(self: Types.Participant, reason: Types.ScoreReason, amount: number)
        if not self.Score[reason] then
            self.Score[reason] = amount
        else
            self.Score[reason] += amount
        end
    end

    function Participant.GetFormattedName(self: Types.Participant): any
        local role = self.Role
        if role then
            return `<font color='{API.Color3ToHex(role.Colour)}'>{self.Player.Name}</font>`
        end
        return self.Player.Name
    end

    function Participant.Kill(self: Types.Participant, attacker: Types.Participant?, weapon: Types.Equipment?, headshot: boolean?, ignoreKarma: boolean?): ()
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
    end

    Participant.Character = nil :: any

    return Participant
    --[[
    return {
        Player = plr,
        Character = nil :: any, -- We can't actually set Character here, because plr hasn't loaded in yet
        Name = plr.Name,
        Round = round,

        Karma = if round.Gamemode.UseKarma then Adapters.GetKarma(plr) else 1000,
        Role = nil,
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

        EquipmentPurchases = {},

        IsDead = function(self)
            
        end,

        

        

        
        

        

        
    }
    ]]
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

        DoMassDeath = function(self, victims, weapon, attacker: Types.Participant?, noGuilt: boolean?)
            table.sort(victims, function(a, b)
                return a:GetRole() == self.Gamemode.PhyrricVictors
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
            error(`Could not find Participant {name} in Round {self.ID}`)
        end,
        TryGetParticipant = function(self, name)
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
            if self:TryGetParticipant(plr.Name) then
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
                Adapters.OnCharacterLoad(char)
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
            if self:IsRoundInProgress() then
                error("Attempt to start round whilst it is already in progress")
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
                error("Round must be in progress to pause")
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

        EndRound = function(self, victors)
            self:LogEvent("Round", "End")
            self.RoundPhase = "Highlights"

            local scores = {}
            for _, v in self.Participants do
                scores[v:GetFormattedName()] = v.Score
            end

            local events = Adapters.CalculateUserFacingEvents(self.EventLog, victors)
            local highlights = self.Gamemode:CalculateRoundHighlights(self)

            self.RoundEndInfo = {
                Winners = victors,
                Events = events,
                Scores = scores,
                Highlights = highlights
            }

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

            self.RoundEndEvent:Fire()

            self.RoundEndEvent:Destroy()
            self.RoundStartEvent:Destroy()

            self.Map:Destroy()

            module.Rounds[self.ID] = nil
        end,
        LoadMap = function(self, map)
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
                        
                        weapon.Touched:Connect(function(part)
                            local plr = Players:GetPlayerFromCharacter(part.Parent :: any)
                            if plr then
                                local participant = self:TryGetParticipant(plr.Name)
                                if participant then
                                    local equipment = self:TryGetEquipment(weapon.Name)
                                    if not equipment then
                                        return warn(`{weapon.Name} not found as Equipment`)
                                    end
                                    participant:GiveEquipment(equipment)
                                    weapon:Destroy()
                                end
                            end
                        end)
                    end
                elseif v.Name == "Props" then
                    for _, prop: Types.Prop in (v:GetChildren() :: any) do
                        if not prop:IsA("BasePart") then
                            continue
                        end

                        prop.Humanoid.Died:Connect(function()
                            if prop:FindFirstChild("OnBreak") then
                                (require)(prop.OnBreak)()
                            end
                        end)
                    end
                elseif v.Name == "Lighting" then
                    for _, property: any in v:GetChildren() do
                        (Lighting :: any)[property.Name] = property.Value
                    end
                end
        
                v.Parent = mapFolder
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

        TryGetEquipment = function(self, name)
            for _, v in self.Gamemode.AvailableEquipment do
                if v.Name == name then
                    return v
                end
            end
            return
        end,
        GetEquipment = function(self, name)
            for _, v in self.Gamemode.AvailableEquipment do
                if v.Name == name then
                    return v
                end
            end
            error(`Equipment {name} not found`)
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