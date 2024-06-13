-- The main RoundHandler. Used to create and interact with rounds.

local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(script.Parent.Types)

local rh: Types.ClientRoundHandler | Types.ServerRoundHandler
if RunService:IsClient() then
    rh = {
        GetRolesMatchingRelationship = function(allRoles, relativeTo, relationship)
            if relationship == "__All" then
                return allRoles
            end
            local roles = {}
            for _, role in allRoles do
                if relationship == "__Enemy" then
                    if not role.Allies or not table.find(role.Allies, relativeTo.Name) then
                        table.insert(roles, role)
                    end
                elseif relationship == "__Ally" then
                    if role.Allies and table.find(role.Allies, relativeTo.Name) then
                        table.insert(roles, role)
                    end
                elseif relationship == role.Name then
                    table.insert(roles, role)
                end
            end
            return roles
        end,

        GetParticipantsWithRole = function(allParticipants, role, thisParticipant)
            local participants = {}
            for _, p in allParticipants do
                if p.Role == role then
                    table.insert(participants, p)
                end
            end
            return participants
        end,
    }
    return rh
end

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

local PREPARING_TIME = Adapter.Configuration.PREPARING_TIME -- Duration of the preparing phase
local HIGHLIGHTS_TIME = Adapter.Configuration.HIGHLIGHTS_TIME -- Duration of the highlights phase
local INTERMISSION_TIME = Adapter.Configuration.INTERMISSION_TIME
local SLAY_VOTES = Adapter.Configuration.SLAY_VOTES

local noRole: Types.Role = {
    Name = "",
    Colour = Color3.new(),
}

local function newParticipant(round, plr): Types.Participant
    return {
        Player = plr,
        Kind = "Participant",
        Character = nil :: any, -- We can't actually set Character here, because plr hasn't loaded in yet
        FormattedName = plr.Name,
        Round = round,

        Karma = if round.Gamemode.UseKarma then Adapter.GetKarma(plr) else 1000,
        Role = noRole,
        Credits = 0,
        Score = {},

        Status = "Alive",
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
        TryAddSlayVote = function(self, from)
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
            if not ownRole or not targetRole or not ownRole.KnowsRoles then
                return
            end

            local verdict = nil
            for _, relation in ownRole.KnowsRoles do
                -- Explicit references to the role name take priority over things like ally or enemy
                if relation == ownRole.Name then
                    verdict = true
                    break
                elseif not verdict then
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
            self.FormattedName = `<font color='#{role.Colour:ToHex()}'>{self.Player.Name}</font>`
            self.Credits += role.StartingCredits or 0

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
                if role.Accessories then
                    for _, accessory in role.Accessories do
                        hum:AddAccessory(accessory:Clone())
                    end
                end
            end

            Adapter.SendRoleAlert(self, role)
            if role.OnRoleAssigned then
                role.OnRoleAssigned(role, self)
            end
            if previousRole and previousRole.OnRoleRemoved then
                previousRole.OnRoleRemoved(previousRole, self)
            end
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
                if not table.find(target.SearchedBy, self) then
                    if self.Role.CorpseResultsPublicised then
                        target.SearchedBy = self.Round.Participants
                    else
                        table.insert(target.SearchedBy, self)
                    end
                end
            end

            if target.Status == "Missing" then
                Adapter.SendMessage(`{self.Player.Name} found the body of {target.FormattedName}. They were a {target.Role.FormattedName}!`, "info", "bodyFound", self.Round.Participants)
                target.Status = "Dead"
            end

            if self.Role.CanStealCredits and (target.Credits > 0) then
                event = {
                    Participant = self,
                    Corpse = target,
                    CreditsFound = target.Credits,
                }
                Adapter.SendMessage(`You have found {target.Credits} credits on the corpse of {target.FormattedName}.`, "info", "creditsEarned", {self})
                self.Credits += target.Credits
                target.Credits = 0
            end

            if event then
                self.Round:LogEvent("CorpseSearched", event)
            end

            local equipmentList = {}
            for i in target.EquipmentPurchases do
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
                FreeKill = target.FreeKill,
                Headshot = target.KilledByHeadshot,
                EquipmentList = equipmentList,
                MurderWeapon = target.KilledByWeapon,
            }
        end,

        LeaveRound = function(self, persistTimer)
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
            else
                if self.Role.AnnounceDisconnect then
                    Adapter.SendMessage(`{self.FormattedName} has disconnected. They were a {self.Role.FormattedName}.`, "info", "disconnect", self.Round.Participants)
                end
                self:Kill()
            end
        end,

        GiveEquipment = Adapter.GiveEquipment,
        RemoveEquipment = Adapter.RemoveEquipment,

        PurchaseEquipment = function(self, equipment)
            local purchases = self.EquipmentPurchases
            if (purchases[equipment.Name] or 0) >= (equipment.MaxStock or math.huge) then
                return "NotInStock"
            end
            if self.Credits < (equipment.Cost or 0) then
                return "NotEnoughCredits"
            end
            if self.EquipmentPurchases[equipment.Name] then
                self.EquipmentPurchases[equipment.Name] += 1
            else
                self.EquipmentPurchases[equipment.Name] = 0
            end
            self.Credits -= equipment.Cost or 0
            return self:GiveEquipment(equipment)
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

        Kill = function(self, attacker, weapon, headshot, ignoreKarma)
            if self:IsDead() then
                return
            end
            self.Status = "Missing"
            self.KilledAsFreeKill = self.FreeKill
            self.KilledAt = workspace:GetServerTimeNow()
            self.KilledByHeadshot = headshot or false
            self.KilledByParticipant = attacker
            self.KilledByWeapon = weapon or "Suicide"

            local isCorrectKill = true
            if attacker then
                isCorrectKill = not round:IsRoleAlliedWith(self.Role, attacker.Role)
                self.KilledInSelfDefense = attacker:HasSelfDefenseAgainst(self)
                self.KilledByParticipant = attacker
                attacker:AddKill(self, ignoreKarma or true)
            end

            local hum = self.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.Health = 0
            end

            local data: Types.RoundEvent_Death = {
                CorrectKill = isCorrectKill,
                FreeKill = self.FreeKill,
                SelfDefense = self.KilledInSelfDefense,
                Victim = self,
                Weapon = self.KilledByWeapon,
                Attacker = attacker,
            }

            self.Round:LogEvent("Death", data)
            Adapter.OnDeath(self)

            if self.Round.Gamemode.OnDeath then
                self.Round.Gamemode.OnDeath(self.Round.Gamemode, self)
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
            participant.Credits = self.Gamemode.StartingCredits or 0
        
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

                hum.Died:Once(function()
                    if self:IsRoundPreparing() then
                        -- Respawn if the round hasn't started
                        participant:LeaveRound(true)
                        self:JoinRound(plr)
                        return
                    end

                    participant:Kill()
                end)
            end)
            plr:LoadCharacter()

            if self.Gamemode.StartingEquipment then
                for _, v in self.Gamemode.StartingEquipment do
                    Adapter.GiveEquipment(participant, self:GetEquipment(v) :: Types.Equipment)
                end 
            end
        
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
                local victors: Types.Role
                if type(self.Gamemode.TimeoutVictors) == "string" then
                    victors = self:GetRoleFromName(self.Gamemode.TimeoutVictors)
                else
                    victors = self:GetRoleFromName(self.Gamemode.TimeoutVictors(self.Gamemode, self))
                end
                self:EndRound(victors)
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
                    local victors: Types.Role
                    if type(self.Gamemode.TimeoutVictors) == "string" then
                        victors = self:GetRoleFromName(self.Gamemode.TimeoutVictors)
                    else
                        victors = self:GetRoleFromName(self.Gamemode.TimeoutVictors(self.Gamemode, self))
                    end
                    self:EndRound(victors)
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
            if self._roundTimerThread and self._roundTimerThread ~= coroutine.running() then
                task.cancel(self._roundTimerThread)
            end
            self:LogEvent("MetaEvent", {Winners = victors})
            self.RoundPhase = "Highlights"
            self.TimeMilestone = workspace:GetServerTimeNow() + Adapter.Configuration.HIGHLIGHTS_TIME

            local scores = {}
            for _, v in self.Participants do
                scores[v.FormattedName] = v.Score
            end

            local events = Adapter.CalculateUserFacingEvents(self.EventLog, victors)
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
            Adapter.SendRoundHighlights(self.Participants, highlights, events, scores, victors)

            local updateNeeded = Adapter.CheckForUpdate(self)
            if updateNeeded then
                Adapter.SendMessage("This server is outdated and will restart soon.", "error", "update", true)
            end

            -- Destroy the round
            task.wait(HIGHLIGHTS_TIME)

            if updateNeeded then
                Adapter.SendMessage("Server restarting...", "error", "update", true)
                local acc, _ = TeleportService:ReserveServer(game.PlaceId)
                TeleportService:TeleportToPrivateServer(game.PlaceId, acc, Players:GetPlayers())
                Players.PlayerAdded:Connect(function(plr)
                    plr:Kick("This server is shutting down for an update.")
                end)
            else
                if Adapter.DoIntermission(self) then
                    self.RoundPhase = "Intermission"
                    self.TimeMilestone = workspace:GetServerTimeNow() + INTERMISSION_TIME
                    self.RoundPhaseChangeEvent:Fire("Intermission")
                    task.wait(INTERMISSION_TIME)
                end
            end

            self.Map:Destroy()
            self.RoundPhase = "Destroy"
            self.RoundPhaseChangeEvent:Fire("Destroy")

            for _, participant in self.Participants do
                Adapter.ClearAllEquipment(participant)
            end

            if self.MaterialVariantsFolder then
                self.MaterialVariantsFolder:Destroy()
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
            Adapter.SetDefaultLighting()
            self:LogEvent("MetaEvent", {NewMap = map.Name})
            map = map:Clone()
        
            local mapFolder = Instance.new("Folder")
            mapFolder.Name = `__Map_{self.ID}`

            map.Map.Parent = mapFolder

            local props = map:FindFirstChild("Props") :: Types.PropsStructure
            if props then
                for _, propInstance in props:GetChildren() do
                    local onBreak = propInstance:FindFirstChild("OnBreak")
                    local prop: Types.Prop = {
                        Kind = "Prop",
                        PropInstance = propInstance,
                        Humanoid = propInstance:FindFirstChild("Humanoid") :: Humanoid?,
                        OnBreak = function(self)
                            if onBreak then
                                (require)(onBreak)(self.Attacker)
                            end
                        end
                    }
                    self._props[propInstance] = prop
                    if prop.Humanoid then
                        prop.Humanoid.Died:Once(prop.OnBreak)
                    end
                end
                props.Parent = mapFolder
            end

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
                        return warn(weapon.Name.." not found as Equipment")
                    end

                    participant:GiveEquipment(equipment)
                    weapon:Destroy()
                    return
                end)
            end

            local weaponSpawns = map:FindFirstChild("WeaponSpawns") :: Types.WeaponSpawnsStructure
            if weaponSpawns then
                for _, weapon in weaponSpawns:GetChildren() do
                    onWeaponAdded(weapon)
                end
                weaponSpawns.ChildAdded:Connect(onWeaponAdded)
                weaponSpawns.Parent = mapFolder
            end

            for _, playerSpawn in map.Spawns:GetChildren() do
                playerSpawn.Anchored = true
                playerSpawn.Transparency = 1
                playerSpawn.CanCollide = false
                playerSpawn.CanTouch = false
                playerSpawn.CanQuery = false
                playerSpawn:ClearAllChildren()
            end
            map.Spawns.Parent = mapFolder

            local lighting = map:FindFirstChild("Lighting") :: Types.LightingStructure?
            if lighting and Adapter.Configuration.LOAD_LIGHTING_SETTINGS then
                for _, setting in lighting:GetChildren() do
                    if setting:IsA("Color3Value") or setting:IsA("BoolValue") or setting:IsA("NumberValue") or setting:IsA("StringValue") then
                        (Lighting :: any)[setting.Name] = setting.Value
                    else
                        setting.Parent = Lighting
                    end
                end
                lighting.Parent = mapFolder
            end

            local matVariants = map:FindFirstChild("MaterialVariants") :: Types.MaterialVariantsStructure?
            if matVariants then
                matVariants.Name = "Variants_"..mapFolder.Name
                self.MaterialVariantsFolder = matVariants
                matVariants.Parent = MaterialService
            end

            workspace.Terrain:Clear()
            local region = map:FindFirstChild("TerrainRegion")
            if region then
                workspace.Terrain:PasteRegion(region, Vector3int16.new(-32000, -32000, -32000), true)
            end

            if Adapter.Configuration.LOAD_TERRAIN_SETTINGS then
                local terrainColors = map:FindFirstChild("TerrainColors") :: Types.TerrainColorsStructure?
                if terrainColors then
                    for _, v in terrainColors:GetChildren() do
                        workspace.Terrain:SetMaterialColor((Enum :: any).Material[v.Name], v.Value)
                    end
                end

                local waterSettings = map:FindFirstChild("WaterSettings") :: Types.WaterSettingsStructure?
                if waterSettings then
                    for _, v in waterSettings:GetChildren() do
                        (workspace :: any).Terrain[v.Name] = v.Value
                    end
                end
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
    for _, v in module.Rounds do
        if v.ID == identifier then
            return v
        end
    end
    error(`Could not find round with ID: {identifier}`)
end

return module