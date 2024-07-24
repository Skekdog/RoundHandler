local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(script.Parent.Types)

local _adapter = ServerScriptService:FindFirstChild("Adapter") :: ObjectValue?
assert(_adapter, "ServerScriptService must have an Adapter ObjectValue, which points to a valid ModuleScript.")
assert(_adapter.ClassName == "ObjectValue", "Adapter must be an ObjectValue.")
assert(_adapter.Value and _adapter.Value.ClassName == "ModuleScript", "Adapter ObjectValue must be set to a valid ModuleScript.")
local Adapter: Types.Adapter = (require)(_adapter.Value)
_adapter = nil

-- The main module. New rounds are created from here via module.CreateRound().
local module = {
    Rounds = {}
}

local PREPARING_TIME = Adapter.PREPARING_TIME -- Duration of the preparing phase
local HIGHLIGHTS_TIME = Adapter.HIGHLIGHTS_TIME -- Duration of the highlights phase
local INTERMISSION_TIME = Adapter.INTERMISSION_TIME
local SLAY_VOTES = Adapter.SLAY_VOTES

module.NoRole = {
    Kind = "Role",
    Name = "",
    Colour = Color3.new(),
} :: Types.Role

local function getGamemodeRoleString(round: Types.Round, role: Types.Role): Types.GamemodeRoleString
    return round.Gamemode.Name.."__"..role.Name
end

local function unloadMap(round: Types.Round): ()
    Adapter.SetDefaultLighting()
    Adapter.SetDefaultTerrain()
    workspace.Terrain:Clear()

    workspace.Gravity = Adapter.DEFAULT_GRAVITY

    round.Map:Destroy()
    if round.MaterialVariantsFolder then
        round.MaterialVariantsFolder:Destroy()
    end
end

local function newParticipant(round, plr): Types.Participant
    return {
        Player = plr,
        Kind = "Participant",
        Character = nil :: any, -- We can't actually set Character here, because plr hasn't loaded in yet
        FormattedName = plr.Name,
        Round = round,
        Extras = {},

        Karma = if round.Gamemode.UseKarma then Adapter.GetKarma(plr) else 1000,
        Role = module.NoRole,
        Score = {},

        _credits = 0,
        _status = "Alive",
        GetCredits = function(self)
            return self._credits
        end,
        SetCredits = function(self, credits)
            self._credits = credits
            self.CreditsChanged:Fire(self:ViewPartialSelf())
        end,
        GetStatus = function(self)
            return self._status
        end,
        SetStatus = function(self, status)
            self._status = status
            self.StatusChanged:Fire(self:ViewPartialSelf())
        end,

        HasHealth = function(self)
            return true
        end,

        CreditsChanged = Instance.new("BindableEvent") :: BindableEvent & Types.Signal<Types.Participant>,
        StatusChanged = Instance.new("BindableEvent") :: BindableEvent & Types.Signal<Types.Participant>,
        RoleChanged = Instance.new("BindableEvent") :: BindableEvent & Types.Signal<Types.Participant>,

        SearchedBy = {},
        KilledByWeapon = "Suicide",
        KilledAt = 0,
        KilledInSelfDefense = false,
        KilledAsFreeKill = false,
        KilledByHeadshot = false,

        FreeKill = false,

        SelfDefenseList = {},
        KillList = {},

        SlayVotes = {},

        ViewPartialSelf = function(self)
            return {
                Kind = "ClientOwnParticipant",
                Player = self.Player,
                FormattedName = self.FormattedName,
                Role = getGamemodeRoleString(round, self.Role),
                Status = self._status,
                Credits = self._credits,
                EquipmentPurchases = self.EquipmentPurchases,
            }
        end,

        TryAddSlayVote = function(self, from)
            if from.KilledAsFreeKill or table.find(self.SlayVotes, from) or self:IsDead() then
                return false
            end
    
            for _, v in self.KillList do
                if v.Player == from.Player then -- Comparing the Participants directly causes a type error. Presumably adding an __eq metamethod would solve this, but I don't want to do that because metatables make typechecking so much more annoying.
                    table.insert(self.SlayVotes, from)
                    if #self.SlayVotes >= SLAY_VOTES then
                        self:TakeDamage(math.huge)
                    end
                    return true
                end
            end

            return false
        end,

        EquipmentPurchases = {},
        _roleAccessories = {},

        IsDead = function(self)
            return (self._status == "Missing") or (self._status == "Dead")
        end,

        ViewPartialParticipant = function(self, viewer)
            local canSeeMissing = false
            if viewer and viewer.Role and viewer.Role.CanSeeMissing then
                canSeeMissing = true
            end

            local status: Types.ParticipantStatus = self._status
            if (status == "Missing") and (not canSeeMissing) then
                status = "Alive"
            end
            
            return {
                Kind = "ClientParticipant",
                Player = self.Player,
                FormattedName = self.FormattedName,
                Role = getGamemodeRoleString(round, self:TryViewParticipantRole(viewer)),
                Status = status,
            }
        end,

        RejoinRound = function(self)
            if self.Round:IsRoundInProgress() then
                error("Cannot rejoin a round that is in progress")
            end

            self:LeaveRound(true)

            task.defer(function()
                if self.Round:IsRoundInProgress() then
                    return
                end
                
                self.Round:JoinRound(plr)
            end)
        end,

        TryViewParticipantRole = function(self, viewer)
            if self.Round:IsRoundOver() then
                return self.Role
            end
            if not viewer or not viewer.Role.KnowsRoles then
                return module.NoRole
            end

            for _, v: Types.RoleRelationship in viewer.Role.KnowsRoles do
                if v == "__All" then
                    return self.Role
                elseif v == "__Enemy" and not self.Round:IsRoleAlliedWith(self.Role, viewer.Role) then
                    return self.Role
                elseif v == "__Ally" and self.Round:IsRoleAlliedWith(self.Role, viewer.Role) then
                    return self.Role
                elseif v == self.Role.Name then
                    return self.Role
                end
            end

            return module.NoRole
        end,

        GetHealth = function(self)
            if self:IsDead() then
                return 0
            end
            local hum = self.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                return hum.Health
            end
            return 0
        end,

        AssignRole = function(self, role)
            local previousRole = self.Role
            self.Role = role
            self.FormattedName = `<font color='#{role.Colour:ToHex()}'>{self.Player.Name}</font>`
            self:SetCredits(self._credits + (role.StartingCredits or 0))

            if role.StartingEquipment then
                for _, v in role.StartingEquipment do
                    Adapter.GiveEquipment(self, self.Round:GetEquipment(v) :: Types.Equipment)
                end
            end

            if self.Character:IsDescendantOf(workspace) then
                local hum = self.Character:FindFirstChildOfClass("Humanoid")
                assert(hum)
                if role.Health then
                    hum.MaxHealth = role.Health
                    hum.Health = role.Health
                end
                if role.JumpPower then
                    hum.JumpPower = role.JumpPower
                end
                if role.Speed then
                    hum.WalkSpeed = role.Speed
                end

                for _, v in self._roleAccessories do
                    v:Destroy()
                end

                if role.Accessories then
                    for _, v in role.Accessories do
                        local accessory = InsertService:LoadAsset(v):FindFirstChildOfClass("Accessory")
                        if not accessory then
                            continue
                        end

                        hum:AddAccessory(accessory)
                        table.insert(self._roleAccessories, accessory)
                    end
                end
            end

            self.RoleChanged:Fire(self:ViewPartialSelf())

            Adapter.SendRoleAlert(self, role)
            if role.OnRoleAssigned then
                role.OnRoleAssigned(role, self)
            end
            if previousRole and previousRole.OnRoleRemoved then
                previousRole.OnRoleRemoved(previousRole, self)
            end
        end,

        ViewCorpse = function(self)
            if not self:IsDead() then
                error(`Target {self.Player.Name} is not dead`)
            end

            local equipmentList = {}
            for i in self.EquipmentPurchases do
                local equipment = self.Round:GetEquipment(i)
                if equipment and type(equipment.Item) == "function" then
                    table.insert(equipmentList, equipment)
                end
            end

            local killList = {}
            for _, v in self.KillList do
                table.insert(killList, v.FormattedName)
            end

            return {
                Player = self.Player,
                FormattedName = self.FormattedName,
                Role = self.Role,
                DeathTime = self.KilledAt,
                SelfDefense = self.KilledInSelfDefense,
                FreeKill = self.FreeKill,
                Headshot = self.KilledByHeadshot,
                EquipmentList = equipmentList,
                KillList = killList,
                MurderWeapon = self.KilledByWeapon,
                DNAExpiry = self.DNAExpiry,
            }
        end,

        SearchCorpse = function(self, target)
            if not target:IsDead() then
                error(`Target {target.Player.Name} is not dead`)
            end

            local event: Types.RoundEvent_CorpseSearched?
            if #target.SearchedBy < 1 then
                event = {
                    Participant = self,
                    Corpse = target,
                }
            end

            if not table.find(target.SearchedBy, self) then
                if self.Role.CorpseResultsPublicised then
                    target.SearchedBy = self.Round.Participants
                    for _, v in self.Round.Participants do
                        Adapter.OnCorpseResult(v, target)
                    end
                else
                    table.insert(target.SearchedBy, self)
                    Adapter.OnCorpseResult(self, target)
                end
            end

            if target._status == "Missing" then
                if self.Role.PointsForSearchingCorpse then
                    self:AddScore("Bodies Found", self.Role.PointsForSearchingCorpse)
                end
                
                Adapter.SendMessage(`{self.FormattedName} found the body of {target.FormattedName}. They were a {target.Role.FormattedName}!`, "info", "bodyFound", self.Round.Participants)
                target:SetStatus("Dead")
            end

            if self.Role.CanStealCredits and (target._credits > 0) then
                event = {
                    Participant = self,
                    Corpse = target,
                    CreditsFound = target._credits,
                }
                Adapter.SendMessage(`You have found {target._credits} credits on the corpse of {target.FormattedName}.`, "info", "creditsEarned", {self})
                self:SetCredits(self._credits + target._credits)
                target:SetCredits(0)
            end

            if event then
                self.Round:LogEvent("CorpseSearched", event)
            end
        end,

        LeaveRound = function(self, persistTimer)
            self.Removed = true
            if self.Round:IsRoundPreparing() then
                local index = table.find(self.Round.Participants, self)
                if index then
                    table.remove(self.Round.Participants, index)
                end

                if (#self.Round.Participants < self.Round.Gamemode.MinimumPlayers) and (not persistTimer) then
                    local timerThread = self.Round._roundTimerThread
                    if not timerThread then
                        return
                    end
                    task.cancel(timerThread)
                end

                Adapter.ClearAllEquipment(self)
            else
                if self.Role.AnnounceDisconnect then
                    Adapter.SendMessage(`{self.FormattedName} has disconnected. They were a {self.Role.FormattedName}.`, "info", "disconnect", self.Round.Participants)
                end
                self:SetStatus("Dead")
                self.Round:LogEvent("MetaEvent", {
                    DisconnectedParticipant = self,
                })
                if self.Round.Gamemode.OnDeath then
                    self.Round.Gamemode.OnDeath(self.Round.Gamemode, self)
                end
            end
        end,

        PurchaseEquipment = function(self, equipment)
            if self:IsDead() then
                return "Dead"
            end
            local purchases = self.EquipmentPurchases
            if (purchases[equipment.Name] or 0) >= (equipment.MaxStock or math.huge) then
                return "NotInStock"
            end

            local response = Adapter.GiveEquipment(self, equipment)
            if response then
                return response
            end

            if self._credits < (equipment.Cost or 0) then
                return "NotEnoughCredits"
            end
            if self.EquipmentPurchases[equipment.Name] then
                self.EquipmentPurchases[equipment.Name] += 1
            else
                self.EquipmentPurchases[equipment.Name] = 1
            end
            self:SetCredits(self._credits - (equipment.Cost or 0))
            return
        end,

        AddKill = function(self, victim, ignoreKarma)
            local round = self.Round
            if not round:IsRoundInProgress() then
                return
            end
            if not ignoreKarma then
                local isAlly = round:IsRoleAlliedWith(victim.Role, self.Role)
                if isAlly and (victim.FreeKill or not self:HasSelfDefenseAgainst(victim)) then
                    self.FreeKill = true
                    Adapter.SendSlayVote(victim, self)
                end
            end
            table.insert(self.KillList, victim)
        end,

        AddSelfDefense = function(self, against, duration)
            if not self.Round.Gamemode.SelfDefense then -- no point if it's not enabled
                return
            end
            if against == self then
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
                if (v.Against.Player == against.Player) and (v.Until > workspace:GetServerTimeNow()) then -- see comment for TryAddSlayVote
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

        TakeDamage = function(self, damage, attacker, weapon, headshot, ignoreKarma)
            if self:IsDead() then
                return
            end

            local hum = self.Character:FindFirstChildOfClass("Humanoid")
            if not hum then
                return
            end

            if attacker and not attacker:HasSelfDefenseAgainst(self) then
                self:AddSelfDefense(attacker, self.Round.Gamemode.SelfDefenseDuration or 5)
            end

            hum.Health -= damage

            if hum.Health <= 0 then
                self:SetStatus("Missing")
                if round:IsRoundPreparing() then
                    return self:RejoinRound()
                end
                self.KilledAsFreeKill = self.FreeKill
                self.KilledAt = workspace:GetServerTimeNow()
                self.KilledByHeadshot = headshot or false
                self.KilledByParticipant = attacker
                self.KilledByWeapon = weapon or "Suicide"

                local isCorrectKill = true
                if attacker then
                    isCorrectKill = not round:IsRoleAlliedWith(self.Role, attacker.Role)
                    self.KilledInSelfDefense = attacker:HasSelfDefenseAgainst(self)
                    attacker:AddKill(self, ignoreKarma or true)

                    if typeof(weapon) == "table" and not weapon.NoDNA then
                        local DNADuration = (200 - (attacker.Character:GetPivot().Position - self.Character:GetPivot().Position).Magnitude) / 2
                        if DNADuration > 0 then
                            self.DNAExpiry = self.KilledAt + DNADuration
                        end
                    end
                end

                if self.KilledByWeapon == "Suicide" then
                    self.KilledByParticipant = self
                end

                local data: Types.RoundEvent_Death = {
                    CorrectKill = isCorrectKill,
                    FreeKill = self.FreeKill,
                    SelfDefense = self.KilledInSelfDefense,
                    Victim = self,
                    Weapon = self.KilledByWeapon,
                    Attacker = self.KilledByParticipant,
                }
    
                self.Round:LogEvent("Death", data)

                task.defer(function()
                    Adapter.OnDeath(self)
                    if self.Round.Gamemode.OnDeath then
                        self.Round.Gamemode.OnDeath(self.Round.Gamemode, self)
                    end
                end)
            end
        end,

        IsDamageJustifiedAgainst = function(self, target)
            return target.FreeKill or self:HasSelfDefenseAgainst(target) or self.Round:CompareRoles(self.Role, target.Role, "__Enemy")
        end
    }
end

local function newRound(gamemode): Types.Round
    return {
        ID = HttpService:GenerateGUID(),
        Gamemode = gamemode,
        Map = nil :: any,

        TimeMilestone = workspace:GetServerTimeNow() + PREPARING_TIME,
        RoundPhase = "Waiting",
        Paused = false,

        RoundPhaseChangeEvent = Instance.new("BindableEvent") :: BindableEvent & Types.Signal<Types.RoundPhase>,

        Participants = {},
        EventLog = {MetaEvent = {}, CorpseSearched = {}, Death = {}},

        _props = {},

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
            participant:SetCredits(self.Gamemode.StartingCredits or 0)
        
            table.insert(self.Participants, participant)
        
            plr.Destroying:Connect(function()
                participant:LeaveRound()
            end)
        
            local spawns = self.Map.Spawns:GetChildren()
            plr.CharacterAppearanceLoaded:Once(function(char)
                local hum = char:WaitForChild("Humanoid") :: Humanoid
                if not char.Parent then
                    char.AncestryChanged:Wait() -- There doesn't seem to be any documentation for "when should character be parented?". If we don't wait then we won't be at the correct spawn
                    task.wait() -- Also appears that waiting a frame is also necessary. Very fun!
                end
                local chosen = spawns[math.random(1, #spawns)]
                char:PivotTo(chosen.CFrame)
                participant.Character = char
                Adapter.OnCharacterLoad(participant)

                if self.Gamemode.OnCharacterLoad then
                    self.Gamemode.OnCharacterLoad(self.Gamemode, char)
                end

                if self.Gamemode.StartingEquipment then
                    for _, v in self.Gamemode.StartingEquipment do
                        Adapter.GiveEquipment(participant, self:GetEquipment(v) :: Types.Equipment)
                    end 
                end

                hum.Died:Once(function()
                    if participant.Removed then
                        return
                    end
                    if self:IsRoundPreparing() then
                        return participant:RejoinRound()
                    end

                    participant:TakeDamage(math.huge)
                end)
            end)

            task.spawn(plr.LoadCharacter, plr)
        
            if (#self.Participants >= self.Gamemode.MinimumPlayers) and (not self._roundTimerThread) then
                self._roundTimerThread = task.delay(PREPARING_TIME, self.StartRound, self)
            end

            Adapter.SendMessage(`The round will begin in {math.round(self.TimeMilestone-workspace:GetServerTimeNow())}s. Prepare yourself.`, "info", "timeToRoundStart", {participant})
            
            if self.Gamemode.UseKarma then
                Adapter.SendMessage(`Your karma is {participant.Karma}. You will deal {Adapter.CalculateDamageModifier(participant.Karma)*100}% damage this round.`, "info", "karma", {participant})
            end

            return participant
        end,
        StartRound = function(self)
            if not self:IsRoundPreparing() then
                error("Attempt to start round whilst it is not preparing")
            end

            for _, v in self.Participants do
                if not v.Character then
                    repeat
                        task.wait()
                    until not v.Player:IsDescendantOf(Players) or v.Character
                end
            end

            self.RoundPhase = "Playing"
            self:LogEvent("MetaEvent", {RoundPhase = "Start"})
            local gm = self.Gamemode
            local participants = self.Participants
            Random.new(os.clock()):Shuffle(participants)

            local duration: number
            if type(self.Gamemode.Duration) == "number" then
                duration = self.Gamemode.Duration
            else
                duration = self.Gamemode.Duration(self.Gamemode, #self.Participants)
            end
            self.TimeMilestone = workspace:GetServerTimeNow() + duration
            self._roundTimerThread = task.delay(duration, function()
                local victors: Types.Victor
                if type(self.Gamemode.TimeoutVictors) == "string" then
                    victors = self:GetRoleFromName(self.Gamemode.TimeoutVictors)
                else
                    victors = self.Gamemode.TimeoutVictors(self.Gamemode, self)
                end
                self:EndRound(victors, true)
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
                    local victors: Types.Victor
                    if type(self.Gamemode.TimeoutVictors) == "string" then
                        victors = self:GetRoleFromName(self.Gamemode.TimeoutVictors)
                    else
                        victors = self.Gamemode.TimeoutVictors(self.Gamemode, self)
                    end
                    self:EndRound(victors, true)
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

        EndRound = function(self, victors, timeout)
            if self:IsRoundOver() then
                error("Round is already ended")
            end
            if self._roundTimerThread and self._roundTimerThread ~= coroutine.running() then
                task.cancel(self._roundTimerThread)
            end
            self:LogEvent("MetaEvent", {Winners = victors})
            self.RoundPhase = "Highlights"
            self.TimeMilestone = workspace:GetServerTimeNow() + Adapter.HIGHLIGHTS_TIME

            local scores = {}
            for _, v in self.Participants do
                scores[v.FormattedName] = v.Score
            end

            local events = Adapter.CalculateUserFacingEvents(self.EventLog, victors)
            local highlights = self.Gamemode:CalculateRoundHighlights(self)

            local victoryMusic
            local winners: Types.ClientParticipant | Types.Role
            if victors.Kind == "Participant" then
                victoryMusic = victors.Role.VictoryMusic
                winners = victors:ViewPartialParticipant()
            else
                victoryMusic = victors.VictoryMusic
                if victors.Allegiance then
                    winners = self:GetRoleFromName(victors.Allegiance)
                else
                    winners = victors
                end
            end

            if timeout and gamemode.TimeoutMusic then
                victoryMusic = gamemode.TimeoutMusic
            end

            assert(victoryMusic)

            self.RoundEndInfo = {
                Winners = winners,
                Events = events,
                Scores = scores,
                Highlights = highlights,
                Music = victoryMusic[math.random(1, math.max(#victoryMusic, 1))]
            }

            self.RoundPhaseChangeEvent:Fire("Highlights")
            Adapter.SendRoundHighlights(self.Participants, highlights, events, scores, victors)

            local updateNeeded = Adapter.CheckForUpdate(self, HIGHLIGHTS_TIME)
            if updateNeeded then
                Adapter.SendMessage("This server is outdated and will restart soon.", "error", "update", true)
            end

            -- Destroy the round
            task.wait(HIGHLIGHTS_TIME)

            if updateNeeded then
                Adapter.SendMessage("Server restarting...", "error", "update", true)
            else
                if Adapter.DoIntermission(self) then
                    self.RoundPhase = "Intermission"
                    self.TimeMilestone = workspace:GetServerTimeNow() + INTERMISSION_TIME
                    self.RoundPhaseChangeEvent:Fire("Intermission")
                    task.wait(INTERMISSION_TIME)
                end
            end

            unloadMap(self)
            self.RoundPhase = "Destroy"
            self.RoundPhaseChangeEvent:Fire("Destroy")

            for _, participant in self.Participants do
                Adapter.ClearAllEquipment(participant)
            end

            for _, v in self.Participants do
                if v.Character.Parent then
                    v.Player.Character = nil
                    v.Character:Destroy()
                end
            end

            module.Rounds[self.ID] = nil
        end,
        LoadMap = function(self, map)
            self:LogEvent("MetaEvent", {NewMap = map.Name})
            map = map:Clone()
        
            local mapFolder = Instance.new("Folder")
            mapFolder.Name = `__Map_{self.ID}`

            local scripts = {}
            for _, v in (map :: Types.MapStructureCast):GetDescendants() do
                if v:IsA("Script") then
                    v:SetAttribute("__NoEnable", not v.Enabled)
                    v.Enabled = false
                    table.insert(scripts, v)
                end
            end

            map.Map.Parent = mapFolder

            local props = map:FindFirstChild("Props")
            if props then
                local function loadProp(propInstance: Types.PropInstance)
                    local prop: Types.Prop = {
                        Kind = "Prop",
                        IsDead = false,
                        PropInstance = propInstance,
                        TakeDamage = function(self, damage, attacker)
                            if not self:HasHealth() then
                                error("Prop is not alive")
                            end
                            self.Attacker = attacker
                            propInstance:SetAttribute("Health", self:GetHealth() - damage)
                        end,
                        OnBreak = function(self)
                            if not propInstance:GetAttribute("NoDestroy") then
                                propInstance:Destroy()
                            end
                            self.IsDead = true
                        end,
                        GetHealth = function(self)
                            return propInstance:GetAttribute("Health") :: number or error("Prop is not alive")
                        end,
                        HasHealth = function(self)
                            return propInstance:GetAttribute("Health") ~= nil
                        end
                    }
                    self._props[propInstance] = prop
                    if prop:HasHealth() then
                        local con
                        con = propInstance:GetAttributeChangedSignal("Health"):Connect(function()
                            local health = propInstance:GetAttribute("Health")
                            if prop.IsDead then
                                return con:Disconnect()
                            end
                            if health <= 0 then
                                prop.IsDead = true
                                prop:OnBreak()
                                con:Disconnect()
                            end
                        end)
                    end
                    Adapter.LoadProp(self, prop)
                end
                for _, propInstance in props:GetChildren() do
                    loadProp(propInstance)
                end
                props.ChildAdded:Connect(loadProp :: (Instance) -> ())
                props.Parent = mapFolder
            end

            local weaponSpawns = map:FindFirstChild("WeaponSpawns")
            if weaponSpawns then
                for _, weapon in weaponSpawns:GetChildren() do
                    Adapter.LoadWeaponSpawn(self, weapon)
                end
                weaponSpawns.ChildAdded:Connect(function(part)
                    Adapter.LoadWeaponSpawn(self, part :: BasePart)
                end)
                weaponSpawns.Parent = mapFolder
            end

            local bounds = map:FindFirstChild("Bounds")
            if bounds then
                for _, bound in bounds:GetChildren() do
                    bound.CanTouch = false
                    bound.CanQuery = false
                    bound.CollisionGroup = Adapter.BOUNDS_COLLISION_GROUP
                    Adapter.LoadBound(self, bound)
                end
                bounds.Parent = mapFolder
            end

            local windows = map:FindFirstChild("Windows")
            if windows then
                windows.Parent = mapFolder
            end

            local gravity = map:FindFirstChild("Gravity")
            if gravity and Adapter.LOAD_GRAVITY_SETTING then
                workspace.Gravity = gravity.Value
            end

            map.Spawns.Parent = mapFolder

            local lighting = map:FindFirstChild("Lighting")
            if lighting and Adapter.LOAD_LIGHTING_SETTINGS then
                for _, setting in lighting:GetChildren() do
                    if setting:IsA("Color3Value") or setting:IsA("BoolValue") or setting:IsA("NumberValue") or setting:IsA("StringValue") then
                        (Lighting :: any)[setting.Name] = setting.Value
                    else
                        setting.Parent = Lighting
                    end
                end
                lighting.Parent = mapFolder
            end

            local matVariants = map:FindFirstChild("MaterialVariants")
            if matVariants then
                matVariants.Name = "Variants_"..mapFolder.Name
                self.MaterialVariantsFolder = matVariants
                matVariants.Parent = MaterialService
            end

            local region = map:FindFirstChild("TerrainRegion")
            if region then
                workspace.Terrain:PasteRegion(region, Vector3int16.new(-32000, -32000, -32000), false)
            end

            if Adapter.LOAD_TERRAIN_SETTINGS then
                local terrainColors = map:FindFirstChild("TerrainColors")
                if terrainColors then
                    for _, v in terrainColors:GetChildren() do
                        workspace.Terrain:SetMaterialColor((Enum :: any).Material[v.Name], v.Value)
                    end
                end

                local waterSettings = map:FindFirstChild("WaterSettings")
                if waterSettings then
                    for _, v in waterSettings:GetChildren() do
                        (workspace :: any).Terrain[v.Name] = v.Value
                    end
                end
            end

            for _, v in map:GetChildren() do
                v.Parent = mapFolder
            end

            self.Map = mapFolder :: Types.MapStructureCast
            mapFolder.Parent = workspace

            task.defer(function()
                for _, v in scripts do
                    v.Enabled = not v:GetAttribute("__NoEnable")
                end
            end)
        end,
        
        IsRoundPreparing = function(self)
            return self.RoundPhase == "Waiting" or self.RoundPhase == "Preparing"
        end,
        IsRoundInProgress = function(self)
            return self.RoundPhase == "Playing"
        end,
        IsRoundOver = function(self)
            return self.RoundPhase == "Intermission" or self.RoundPhase == "Highlights" or self.RoundPhase == "Destroy"
        end,

        GetEquipment = function(self, name)
            if not self.Gamemode.AvailableEquipment then
                return warn("No available equipment")
            end
            for _, v in self.Gamemode.AvailableEquipment do
                if v.Name == name then
                    return v
                end
            end
            return warn("Could not find equipment with name "..name)
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
            if comparison == "__Ally" then
                return self:IsRoleAlliedWith(role1, role2)
            else
                return not self:IsRoleAlliedWith(role1, role2)
            end
        end,
        
        IsRoleAlliedWith = function(self, role1, role2)
            if not role1.Allies then
                return false
            end
            return table.find(role1.Allies, role2.Name) ~= nil
        end,

        LogEvent = function(self, type, data)
            local event: Types.RoundEvent<typeof(data)> = {
                Timestamp = workspace:GetServerTimeNow(),
                Data = data,
            }
            table.insert(self.EventLog[type], event)
        end,
    }
end

function module.CreateRound(map: Types.MapStructure, gamemode: Types.Gamemode): Types.Round -- Creates a new Round and returns it.
    local self: Types.Round = newRound(gamemode)
    self:LoadMap(map)
    
    module.Rounds[self.ID] = self
    return self
end

function module.GetRound(identifier: Types.UUID): Types.Round
    return module.Rounds[identifier] or error(`Could not find round with ID: {identifier}`)
end

return module