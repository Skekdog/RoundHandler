--!strict
export type Integer = number
export type PositiveNumber = number
export type Username = string
export type EquipmentName = string
export type Timestamp = number
export type RoleName = string

export type Asset = "rbxassetid://" | string
export type PauseFailReason = "RoundNotInProgress"

--[[
Round Phases:
    Waiting: Not enough players, waiting indefinitely
    Preparing: Enough players, giving time for others to join
    Playing: Round in progress
    Highlights: Round ended but still loaded
    Intermission: Round unloaded and voting time if applicable
]]
export type RoundPhase = "Waiting" | "Preparing" | "Playing" | "Highlights" | "Intermission"

--[[
Round Event Types:
    Round: Started, paused, ended, etc.
    Death: Participant died
    Damage: Participant took damage
    Search: A corpse was searched, or credits were taken
    Purchase: Something purchased in equipment shop
    Equipment: Something picked up (includes whether it was taken from a corpse or living player)
]]
export type RoundEventType = "Round" | "Death" | "Damage" | "Search" | "Purchase" | "Equipment"

export type ScoreReason = "Friendly Fire" | "Enemy Killed" | "Actions"
export type FreeKillReason = "Teamkill" | string
export type DeathType = "Firearm" | "Blunt" | "Blade" | "Drown" | "Fall" | "Crush" | "Explosion" | "Suicide" | "Mutation" | "Other"
-- Mutation: DNA mutated by teleporter (in a deadly way)

export type UUID = "00000000-0000-0000-0000-000000000000" | string
export type RoundTime = "00:00" | string

--[[
    Represents a Self Defense entry in a Participant's SelfDefenseList.
]]
export type SelfDefenseEntry = {
    Against: Username, -- The Participant that this Participant can now freely kill.
    Until: Timestamp,  -- The timestamp at which this Self Defense entry expires. Always compare this, as opposed to checking the presence of an entry against Username, because the entry may not be removed.
}

--[[
    Represents a Participant in a Round, storing player-related attributes
    such as Role, death info and Credits.
    Independent of Player.
    Created by Round:JoinRound().
]]
export type Participant = {
    Player: Player?, -- A reference to the Player object. Can be nil if the Player has disconnected.
    Name: string,    -- Separates Participant from Player, in case of disconnection.
    Round: Round,    -- A reference to the round.

    Role: Role?,                     -- A reference to their role. nil if Round hasn't started.
    Credits: number,                 -- Available credits that can be spent in Equipment Shop.
    Score: {[ScoreReason]: Integer}, -- Dictionary of score reason : total score for this reason

    Deceased: boolean,              -- Dead or not
    SearchedBy: {Username},         -- A list of usernames who have searched this corpse. '__All' means that a role with CorpseResultsPublicised searched this corpse, and everyone can now view it remotely.
    KilledBy: DeathType,            -- How this participant died.
    KilledByWeapon: EquipmentName?, -- If DeathType is 'Firearm', indicates the weapon used.
    KilledInSelfDefense: boolean,   -- Whether they were killed in self defense.

    FreeKill: boolean,                 -- Whether this participant is a Free Kill.
    FreeKillReasons: {FreeKillReason}, -- A list of all the reasons they are a Free Kill.
    SlayVotes: Integer,                -- The number of players who voted to Slay this Participant due to being RDM'ed by them.

    SelfDefenseList: {SelfDefenseEntry}, -- A list of participants who this participant can freely kill in self-defense.
    KillList: {Username},                -- A list of usernames this participant has killed.

    EquipmentPurchases: {[EquipmentName]: Integer?}, -- The equipment this participant purchased, and how many times.

    AssignRole: (self: Participant, role: Role, overrideCredits: boolean?, overrideInventory: boolean?) -> nil, -- Assigns Role to this Participant. By default does not override inventory or credits.
    LeaveRound: (self: Participant) -> nil,                                                                     -- Removes this Participant from the Round.

    GetAllegiance: (self: Participant) -> Role?,                     -- Returns this participant's Role allegiance.
    GiveEquipment: (self: Participant, equipment: Equipment) -> nil, -- Adds this equipment to the participant's inventory.
}

--[[
    Represents an item, possibly purchased from the Equipment shop.
    All items available in a Round should be in Gamemode.AvailableEquipment.
]]
export type Equipment = {
    Name: EquipmentName, -- Name of the equipment.
    Description: string, -- Description of this equipment.
    Icon: Asset,         -- Icon of this equipment.
    Cost: Integer,       -- The number of credits that this equipment costs to buy.
    Extras: {[any]: any}?, -- Any extra info about the equipment, for use in custom functions.

    Item: Model | (participant: Participant, equipmentName: EquipmentName) -> nil, -- Either a tool added to inventory, or a function that does something.
}

--[[
    Represents an Event that occured during a Round.
    Non-unique, multiple of the same Event can exist in the same Round.
]]
export type Event = {
    RoundTime: RoundTime,     -- The local time that this event occured at.
    Text: string,             -- The user-facing text of this event.
    Category: RoundEventType, -- The category that this event falls under.
    Correct: boolean?,        -- true if a Tick should be displayed, false if Cross, nil if nothing should be displayed.
    FreeKill: boolean,        -- true if Free Kill icon should be displayed
    SelfDefense: boolean,     -- true if Self Defense icon should be displayed
}

--[[
    Represents a game Round, identified by a UUID or category.
    Responsible for managing Participants, deaths, timers, etc.
    Created by RoundHandler.CreateRound().
]]
export type Round = {
    ID: UUID,                -- Unique identifier of the round
    Gamemode: Gamemode,      -- A reference to the current gamemode.

    Paused: boolean,          -- Whether the round is paused or not.
    TimeMilestone: Timestamp, -- The timestamp of the next round phase. Used by the client for a round timer.
    RoundPhase: RoundPhase,   -- The current round phase.

    Participants: {Participant}, -- A list of participants in this round.
    EventLog: {Event},           -- A list of events that have taken place.

    GetParticipant: (self: Round, name: Username) -> Participant?, -- Returns a participant from a username
    JoinRound: (self: Round, name: Username) -> Participant?,      -- Adds a participant to this round
    
    PauseRound: (self: Round) -> PauseFailReason?, -- Pauses the round. Returns a string reason if the round could not be paused.
    StartRound: (self: Round) -> nil,              -- Starts this round. Usually shouldn't be called externally.
    EndRound: (self: Round, victors: Role) -> nil, -- Ends this round. Usually shouldn't be called externally.
    CheckForVictory: (self: Round) -> boolean?,    -- Checks to see if any role has won yet. Usually shouldn't be called externally.

    IsRoundPreparing: (self: Round) -> boolean,  -- Returns true if the current round phase is Preparing or Waiting
    IsRoundOver: (self: Round) -> boolean,       -- Returns true if the current round phase is Highlights or Intermission
    IsRoundInProgress: (self: Round) -> boolean, -- Returns true if the current round phase is Playing

    GetRoleInfo: (self: Round, name: RoleName) -> Role?,                                            -- Shortcut method to get a Role.
    CompareRoles: (self: Round, role1: Role, role2: Role, comparison: RoleRelationship) -> boolean, -- Compares whether two roles are related.
    GetRoleRelationship: (self: Round, role1: Role, role2: Role) -> RoleRelationship?,              -- Returns the relationship between two roles. Either Ally or Enemy.
    GetLimitedParticipantInfo: (self: Round, viewer: Player, target: Player) -> PartialRole?,       -- Returns a RoleColour and Name if available to the viewer.

    warn: (self: Round, message: string) -> nil,  -- Calls built-in warn, also adding a round identifier.
    error: (self: Round, message: string) -> nil, -- Calls built-in error, also adding a round identifier.

    -- Private members, should not be used from outside the module
    _roundTimerThread: thread?,      -- The current task.delay() thread responsible for ending the round after the timer expires. nil if no timer is active.
    _roundTimerContinueFor: number?, -- Length of time to continue the round timer for when resumed
    _roundTimerResumedAt: number,    -- The time that the round timer was resumed at
    _roundTimerTargetDuration: number -- The target duration the round timer started at
}



-- TODO: This is all very dodgy
-- RoundHighlight can be a list of sub-highlights.
-- i.e, HUGE Kills: {"A huge spread", "used their huge and killed many people", 2 kills needed}
--                 {"A patient para", "@Scelly_Dog's patience was rewarded with 4 kills", 4 kills needed}
-- Or they can be a function that returns a table of highlight Name and Description.
export type RoundHighlightCondition = "HeadshotKills" | "KillsWithWeapon" | "CorrectKills" | "IncorrectKills"
export type RoundHighlight = {
    Condition: RoundHighlightCondition, -- Condition.
    Subcondition: EquipmentName?, -- Only applicable for KillsWithWeapon.
    Levels: { -- Varying levels of this highlight.
        Name: string, -- Title.
        Description: string, -- Description.
        Threshold: Integer, -- Minimum number of condition for this particular highlight to activate.
    }
} | (Round) -> {Name: string, Description: string}


--[[
    Defines the relationship between two (or more) roles.
    Used to identify and group Roles for HighlightRules et al.
]]
export type RoleRelationship = "All" | "Ally" | "Enemy" | RoleName

--[[
    A partial Role which only contains the Name and Colour.
    Returned by Round:GetLimitedParticipantInfo().
]]
export type PartialRole = {
    Name: string,   -- Name of the original Role.
    Colour: Color3, -- Colour of the original Role.
}

--[[
    Represents a Participant Role.
    Contains info such as Allies, Credits, etc.
    Must be defined in a Gamemode.
]]
export type Role = {
    Name: string,        -- Name of this role. Must not be 'Ally', 'Enemy', or 'All'.
    Description: string, -- Description of this role.
    Colour: Color3,      -- Colour of this role. Not color.
    Extras: {[any]: any}?, -- Any extra info about the role, for use in custom functions.

    Allegiance: RoleName,  -- i.e, Detective wins as Innocent. Does not necessarily impact Ally / Enemy status.
    VictoryMusic: {Sound}?, -- Music that plays when this role wins. Must not be nil for the Allegiance roles, no effect on other roles.
    VictoryText: string?,  -- Text shown in event log. Must not be nil for the Allegiance roles, no effect on other roles.
    
    StartingCredits: Integer,           -- Added onto gamemode StartingCredits.
    StartingEquipment: {EquipmentName}, -- Added onto gamemode StartingEquipment.
    EquipmentShop: {EquipmentName},     -- List of equipment available to this role.

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

    OnRoleAssigned: (self: Role, participant: Participant) -> nil, -- Any extra code that should run for AssignRole.
    OnRoleRemoved: (self: Role, participant: Participant) -> nil,  -- Any extra code that should when AssignRole is called on a Participant that previously had this role.
}

--[[
    Represents a Gamemode with a specific set of rules.
    Must be defined manually. Roles form a significant part of Gamemodes.
]]
export type Gamemode = {
    Name: string,        -- Name of the gamemode.
    Description: string, -- Description of the gamemode.
    Extras: {[any]: any}?, -- Any extra info about the gamemode, for use in custom functions.

    EngineVersion: string,   -- Indicates the engine version that this gamemode was designed for.
    GamemodeVersion: string, -- Indicates the version of this gamemode.

    MinimumPlayers: Integer,     -- The gamemode will not start without at least this many players.
    RecommendedPlayers: Integer, -- The gamemode will not appear in voting without at least this many players.
    MaximumPlayers: Integer,     -- The gamemode will not appear in voting if there are more players than this value.

    PyrrhicVictors: RoleName,                       -- Which role wins if everyone is killed simultaneously?
    TimeoutVictors: RoleName | (Round) -> RoleName, -- Which role wins if the round timer expires? Can be a function.
    Highlights: {RoundHighlight},                   -- List of available round highlights.

    FriendlyFire: boolean, -- Whether allies can damage each other. Has no bearing on self-defense.
    SelfDefense: boolean,  -- Whether self-defense is allowed.
    UseKarma: boolean,     -- Whether karma will be affected by this round, and whether it will have an effect in this round.

    StartingCredits: Integer,           -- Amount of credits to start with.
    StartingEquipment: {EquipmentName}, -- Equipment to start with.
    AvailableEquipment: {Equipment},    -- All equipment that is available, including standard weapons.

    Roles: {Role}, -- Defines roles for this gamemode.

    Duration: (self: Gamemode, numParticipants: Integer) -> PositiveNumber, -- Function that determines how long a round will last. Defaults to 120 + (numParticipants * 15)
    OnDeath: (self: Gamemode, victim: Participant) -> nil,                  -- Called when a Participant in this gamemode dies.
    AssignRoles: (self: Gamemode, participants: {Participant}) -> nil,      -- Function that assigns all Participants roles.
    CheckForVictory: (self: Gamemode, round: Round) -> nil,                 -- Function that is called whenever someone dies (yes, it can be fully implemented in OnDeath). Responsible for calling Round:EndRound() with the relevant victorious role.
}


export type RoundHandlerConfiguration = {
    PREPARING_TIME: number,
    HIGHLIGHTS_TIME: number,
    INTERMISSION_TIME: number,
}

export type InventoryManager = {
    GiveEquipment: (plr: Participant, item: Equipment) -> nil,
    RemoveEquipment: (plr: Participant, item: EquipmentName) -> nil,
}

--[[
    Defines all custom types used by Round Handler.
]]
return {}