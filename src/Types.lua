--!strict
local module = {}
export type Integer = number
export type PositiveNumber = number
export type PositiveInteger = number
export type Username = string
export type EquipmentName = string
export type Timestamp = number
export type RoleName = string

export type Asset = "rbxassetid://" | string
export type PauseFailReason = "RoundNotInProgress"

export type Adapter = {
    Configuration: {
        PREPARING_TIME: number,
        HIGHLIGHTS_TIME: number,
    },

    GetKarma: (plr: Player) -> number,
    SetKarma: (plr: Player, karma: number) -> (),

    GiveEquipment: (plr: Participant, item: Equipment) -> EquipmentGiveRejectionReason?, -- Returns a string describing the error if any occured, else nil
    RemoveEquipment: (plr: Participant, item: Equipment) -> (),

    SendMessage: (recipients : {ConnectedParticipant}, message: string, severity: "info" | "warn" | "error", messageType: "update" | "bodyFound" | "disconnect", isGlobal: boolean?) -> (),
    CheckForUpdate: (round: Round) -> boolean,
    SendRoundHighlights: (recipients: {ConnectedParticipant}, highlights: {RoundHighlight}, events: {UserFacingRoundEvent}, scores: {[Participant]: {[ScoreReason]: Integer}}) -> (),
}

export type Equipment = {
    Name: EquipmentName, -- Name of the equipment.
    Description: string, -- Description of this equipment.
    Icon: Asset,         -- Icon of this equipment.
    Cost: Integer,       -- The number of credits that this equipment costs to buy.
    MaxStock: Integer,   -- The maximum times a single Participant can purchase this equipment, per round
    Extras: {[any]: any}?, -- Any extra info about the equipment, for use in custom functions.

    Item: Tool | (participant: Participant, equipmentName: EquipmentName) -> (), -- Either a tool added to inventory, or a function that does something.
}

module.RoleRelationships = {"__All", "__Ally", "__Enemy"}
export type RoleRelationship = "__All" | "__Ally" | "__Enemy" | RoleName -- when keyof() becomes available consider this

export type ScoreReason = "KilledEnemy" | "KilledAlly" | "LeftoverCredits" | "Actions" | string

export type PartialRole = {
    Name: string,   -- Name of the original Role.
    Colour: Color3, -- Colour of the original Role.
}

export type SelfDefenseEntry = {
    Against: Participant, -- A reference to the Participant who is able to freely kill this participant until the entry expires.
    Until: Timestamp,  -- The timestamp at which this Self Defense entry expires. Always compare this, as opposed to checking the presence of an entry against the Participant, because the entry may not be removed.
}

export type RoundHighlight = {
    Name: string,
    Description: string
}

export type RoundPhaseEventType = "Start" | "End" | "Pause" | "Resume" | "NewMapLoaded"
export type RoundEventType = "Round" | "Death" | "MassDeath" --[[ i.e, C4 explosion. Used to determine phyrric victory ]] | "EquipmentPurchased" | "EquipmentGiven" | "EquipmentRemoved" | string -- string used for custom events. Custom events should only be used in a Gamemode, not external framework
export type RoundEvent_Death = {
    Attacker: Participant?,
    Victim: Participant,
    Weapon: Equipment | DeathType,
    CorrectKill: boolean,
    SelfDefense: boolean,
    FreeKill: boolean,
}
export type RoundEvent_MassDeath = {
    Attacker: Participant?,
    Victims: {Participant},
    Weapon: Equipment | DeathType,
    Justified: boolean,
}
export type RoundEvent_Equipment = {
    Target: Participant,
    Equipment: Equipment
}
export type RoundEventData = RoundPhaseEventType | RoundEvent_Death | RoundEvent_MassDeath | RoundEvent_Equipment | any
export type RoundEvent = {
    Timestamp: Timestamp, -- The time that this event occured at.
    Data: RoundEventData,
}

export type RoundEventCategory = "Round" | "Death" | "Equipment"
export type UserFacingRoundEvent = {
    Timestamp: Timestamp,
    Category: RoundEventCategory,
    Icons: {Asset},
    Text: string,
}

export type UUID = "00000000-0000-0000-0000-000000000000" | string
export type RoundPhase = "Waiting" | "Preparing" | "Playing" | "Highlights" | "Intermission"
--[[
Round Phases:
    Waiting: Not enough players, waiting indefinitely
    Preparing: Enough players, giving time for others to join
    Playing: Round in progress
    Highlights: Round ended but still loaded
    Intermission: Round unloaded and voting time if applicable
]]
export type Round = {
    ID: UUID,                -- Unique identifier of the round.
    Gamemode: Gamemode,      -- A reference to the current gamemode.
    Map: Folder,             -- A reference to the loaded map folder.

    Winners: Role?,
    Paused: boolean,          -- Whether the round is paused or not.
    TimeMilestone: Timestamp, -- The timestamp of the next round phase. Used by the client for a round timer.
    RoundPhase: RoundPhase,   -- The current round phase.

    Participants: {Participant}, -- A list of participants in this round.

    CalculateUserFacingEvents: (self: Round) -> {UserFacingRoundEvent},
    LogEvent: (self: Round, type: RoundEventType, Data: RoundEventData) -> (), -- Adds an event to the round.
    EventLog: {[RoundEventType]: {RoundEvent}},                                                    -- A list of events that have taken place.

    RoundStartEvent: BindableEvent, -- Fired whenever the round starts (via StartRound(), after all other round start functions have run)
    RoundEndEvent: BindableEvent, -- Fired whenever the round ends (via EndRound(), after all other round end functions have run)

    GetConnectedParticipants: (self: Round) -> {ConnectedParticipant},          -- Returns a list of Participant's whose Player is still connected to the server.
    HasParticipant: (self: Round, name: Username) -> boolean,          -- Returns true if participant is in round. Does not error.
    GetParticipant: (self: Round, name: Username) -> Participant,      -- Returns a participant from a username. Errors if participant is not in round.
    JoinRound: (self: Round, name: Username) -> Participant,           -- Adds a participant to this round
    
    PauseRound: (self: Round) -> PauseFailReason?, -- Pauses the round. Returns a string reason if the round could not be paused.
    StartRound: (self: Round) -> (),              -- Starts this round. Usually shouldn't be called externally.
    EndRound: (self: Round, victors: Role) -> (), -- Ends this round. Usually shouldn't be called externally.

    IsRoundPreparing: (self: Round) -> boolean,  -- Returns true if the current round phase is Preparing or Waiting
    IsRoundOver: (self: Round) -> boolean,       -- Returns true if the current round phase is Highlights or Intermission
    IsRoundInProgress: (self: Round) -> boolean, -- Returns true if the current round phase is Playing

    GetParticipantsWithRole: (self: Round, name: RoleName) -> {Participant},                        -- Returns a list of Participants with the specified role.
    GetRoleInfo: (self: Round, name: RoleName) -> Role,                                             -- Returns a Role.
    CompareRoles: (self: Round, role1: Role, role2: Role, comparison: RoleRelationship) -> boolean, -- Tests whether two roles are related by comparison.
    GetRoleRelationship: (self: Round, role1: Role, role2: Role) -> "__Ally" | "__Enemy",           -- Returns the relationship between two roles. Either Ally or Enemy.
    GetLimitedParticipantInfo: (self: Round, viewer: Player, target: Player) -> PartialRole?,       -- Returns a RoleColour and Name if available to the viewer.

    LoadMap: (self: Round, map: Folder) -> (),   -- Loads a map.

    -- Private members, should not be used from outside the module
    _roundTimerThread: thread?,
    _roundTimerContinueFor: number?
}

--[[
    Represents a Gamemode with a specific set of rules.
    Must be defined manually. Roles form a significant part of Gamemodes.
]]
export type Gamemode = {
    Name: string,          -- Name of the gamemode.
    Description: string,   -- Description of the gamemode.
    Extras: {[any]: any}?, -- Any extra info about the gamemode, for use in custom functions.

    EngineVersion: string,   -- Indicates the engine version that this gamemode was designed for.
    GamemodeVersion: string, -- Indicates the version of this gamemode.

    MinimumPlayers: PositiveInteger,     -- The gamemode will not start without at least this many players.
    RecommendedPlayers: PositiveInteger, -- The gamemode will not appear in voting without at least this many players.
    MaximumPlayers: PositiveInteger,     -- The gamemode will not appear in voting if there are more players than this value.

    TimeoutVictors: (self: Gamemode, round: Round) -> Role, -- Which role wins if the round timer expires?
    PhyrricVictors: (self: Gamemode, round: Round) -> Role, -- Which role wins if everyone dies at the same time?

    CalculateRoundHighlights: (self: Gamemode, round: Round) -> {RoundHighlight},
    CalculateNonDefaultUserFacingEvents: ((self: Gamemode, round: Round) -> {UserFacingRoundEvent})?, -- Calculates the user facing event log for non-default events. Only needed if this Gamemode uses custom events. If any custom event is not converted, it will not be displayed to players.

    FriendlyFire: boolean, -- Whether allies can damage each other. Has no bearing on self-defense.
    SelfDefense: boolean,  -- Whether self-defense is allowed.
    UseKarma: boolean,     -- Whether karma will be affected by this round, and whether it will have an effect in this round.

    StartingCredits: Integer,           -- Amount of credits to start with.
    StartingEquipment: {EquipmentName}, -- Equipment to start with.
    AvailableEquipment: {Equipment},    -- All equipment that is available, including standard weapons.

    Roles: {Role}, -- Defines roles for this gamemode.

    Duration: (self: Gamemode, numParticipants: PositiveInteger) -> PositiveNumber, -- Function that determines how long a round will last. Defaults to 120 + (numParticipants * 15)
    OnDeath: (self: Gamemode, victim: Participant) -> (),                  -- Called when a Participant in this gamemode dies.
    AssignRoles: (self: Gamemode, participants: {Participant}) -> (),      -- Function that assigns all Participants roles.
}

--[[
    Represents a Participant Role.
    Contains info such as Allies, Credits, etc.
    Must be defined in a Gamemode.
]]
export type Role = {
    Name: string,        -- Name of this role.
    Description: string, -- Description of this role.
    Colour: Color3,      -- Colour of this role. Not color.
    Extras: {[any]: any}?, -- Any extra info about the role, for use in custom functions.

    Allegiance: RoleName,  -- i.e, Detective wins as Innocent. Does not necessarily impact Ally / Enemy status.
    VictoryMusic: {Sound}?, -- Music that plays when this role wins. Must not be nil for the Allegiance roles, no effect on other roles.
    VictoryText: string?,  -- Text shown in event log. Must not be nil for the Allegiance roles, no effect on other roles.
    
    StartingCredits: Integer,           -- Added onto gamemode StartingCredits.
    StartingEquipment: {EquipmentName}, -- Added onto gamemode StartingEquipment.
    EquipmentShop: {EquipmentName},     -- List of equipment available to this role.

    AnnounceDisconnect: boolean,                 -- If true, a message is sent to all participants when this player leaves the round.
    CorpseResultsPublicised: boolean,            -- Whether this role will publicise the results from searching a corpse.
    CanStealCredits: boolean,                    -- Whether this role can steal credits from corpses.
    AwardOnDeath: {[RoleRelationship]: Integer}, -- How many credits to award to other roles when this role is killed.

    Accessories: {Asset}, -- A list of accessories to add to the character.
    Health: number,       -- Sets Health and MaxHealth (of Humanoid).
    Speed: number,        -- Sets normal WalkSpeed. Modifiers are usually flat.
    JumpPower: number,    -- Sets JumpPower (of Humanoid).

    Allies: {RoleName},                            -- Allies to this role. Own role is not an ally by default.
    HighlightRules: {[RoleRelationship]: boolean}, -- Determines which roles will be highlighted for this role.
    KnowsRoles: {[RoleRelationship]: boolean},     -- Determines which roles will be revealed to this role.
    TeamChat: boolean,                             -- Can this role chat in private to other role members?

    OnRoleAssigned: (self: Role, participant: Participant) -> (), -- Any extra code that should run for AssignRole.
    OnRoleRemoved: (self: Role, participant: Participant) -> (),  -- Any extra code that should run when AssignRole is called on a Participant that previously had this role.
}

--[[
    Represents a Participant in a Round, storing player-related attributes
    such as Role, death info and Credits.
    Independent of Player.
    Created by Round:JoinRound().
]]
export type FreeKillReason = "Teamkill" | string
export type DeathType = "Firearm" | "Blunt" | "Blade" | "Drown" | "Fall" | "Crush" | "Explosion" | "Suicide" | "Mutation"
export type EquipmentGiveRejectionReason = string -- for use in Adapters.GiveEquipment
export type EquipmentPurchaseRejectionReason = "NotEnoughCredits" | "NotInStock" | EquipmentGiveRejectionReason
-- Mutation: DNA mutated by teleporter (in a deadly way)
export type Participant = {
    Player: Player?,  -- A reference to the Player object. Can be nil if the Player has disconnected.
    Character: Model?, -- A reference to the Player's character. Generally should not be nil even if the player disconnects, but could be nil if they fall into the void.
    Name: string,     -- Separates Participant from Player, in case of disconnection.
    Round: Round,     -- A reference to the round.
    
    Role: Role?,                     -- A reference to their role. nil if Round hasn't started.
    Credits: number,                 -- Available credits that can be spent in Equipment Shop.
    Score: {[ScoreReason]: Integer},           -- Dictionary of score reason = total score for this reason

    Karma: number,                  -- The Participant's current karma. When the round ends, this is applied using Adapters.SetKarma() if applicable. Initially set by Adapters.GetKarma().
    Deceased: boolean,              -- Dead or not
    SearchedBy: {Participant},      -- A list of Participants who have searched this corpse.
    KilledBy: DeathType,            -- How this Participant died.
    KilledByWeapon: EquipmentName?, -- If DeathType is 'Firearm', indicates the weapon used.
    KilledInSelfDefense: boolean,   -- Whether they were killed in self defense.
    
    FreeKillReasons: {FreeKillReason}, -- A list of all the reasons this Participant is a Free Kill, if any. Free kill can be checked by #FreeKillReasons == 0.
    SlayVotes: PositiveInteger,                -- The number of players who voted to Slay this Participant due to being RDM'ed by them.

    SelfDefenseList: {SelfDefenseEntry}, -- A list of participants who this participant can freely kill in self-defense.
    KillList: {Participant},                -- A list of references to Participants this player has killed.
    EquipmentPurchases: {[EquipmentName]: PositiveInteger?}, -- The equipment this participant purchased, and how many times.
    
    AddScore: (self: Participant, reason: ScoreReason, amount: Integer) -> (),         -- Adds score to this Participant
    AddKill: (self: Participant, victim: Participant, ignoreKarma: boolean) -> (),     -- Adds a kill to this Participant's kill list. By default, also checks if the kill was correct and sets FreeKill as needed, but this can be disable with ignoreKarma = true.
    AddSelfDefense: (self: Participant, against: Participant, duration: number) -> (), -- Adds a self defense entry against a Participant
    HasSelfDefenseAgainst: (self: Participant, against: Participant) -> boolean,        -- Returns true if this Participant is allowed to hurt the `against` participant in self defense.

    LeaveRound: (self: Participant) -> (),                         -- Removes this Participant from the Round.
    GetAllegiance: (self: Participant) -> Role,                     -- Returns this participant's Role allegiance.
    AssignRole: (self: Participant, role: Role, overrideCredits: boolean?, overrideInventory: boolean?) -> (), -- Assigns Role to this Participant. By default does not override inventory or credits.
    
    PurchaseEquipment: (self: Participant, equipment: Equipment) -> EquipmentPurchaseRejectionReason?, -- Deducts credits and stock and gives equipment. If GiveEquipment rejects, purchase also rejects.
    GiveEquipment: (self: Participant, equipment: Equipment) -> EquipmentGiveRejectionReason?, -- Adds this equipment to the participant's inventory.
    RemoveEquipment: (self: Participant, equipment: Equipment) -> (), -- Removes this equipment from the Participant's inventory.
}
export type ConnectedParticipant = Participant & {Player: Player} -- Represents a connected Participant, i.e Player is not nil

-- Defines all custom types used by RoundHandler.
return module