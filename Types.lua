--!strict
export type Integer = number
export type PositiveNumber = number
export type Username = string
export type EquipmentName = string
export type Timestamp = number
export type RoleName = string

export type Asset = "rbxassetid://" | string

export type RoundPhase = "Waiting" | "Preparing" | "Playing" | "Highlights" | "Intermission"
--[[
    Waiting: Not enough players, waiting indefinitely
    Preparing: Enough players, giving time for others to join
    Playing: Round in progress
    Highlights: Round ended but still loaded
    Intermission: Round unloaded and voting time if applicable
]]
export type RoundEventType = "Round" | "Death" | "Damage" | "Search" | "Purchase" | "Equipment"
--[[
    Round: Started, paused, ended, etc.
    Death: Participant died
    Damage: Participant took damage
    Search: A corpse was searched, or credits were taken
    Purchase: Something purchased in equipment shop
    Equipment: Something picked up (includes whether it was taken from a corpse or living player)
]]
export type FreeKillReason = "Teamkill" | string
export type DeathType = "Firearm" | "Blunt" | "Blade" | "Drown" | "Fall" | "Crush" | "Explosion" | "Suicide" | "Mutation" | "Other"
-- Mutation: DNA mutated by teleporter (in a deadly way)

export type RoundCategory = "Main" | string
export type UUID = "00000000-0000-0000-0000-000000000000" | string
export type RoundTime = "00:00" | string

export type SelfDefenseEntry = {
    Against: Username,
    Until: Timestamp,
}



--[[
    The Participant class acts similar to an extension of Roblox's Player.
]]

export type Participant = {
    Player: Player?, -- A reference to the Player object. Can be nil.
    Name: string, -- Separates Participant from Player, in case of disconnection.
    Round: Round,

    Role: Role?, -- Role. nil if Round hasn't started.
    Credits: number, -- Credits.
    Score: number,

    Deceased: boolean,
    SearchedBy: {Username},
    KilledBy: DeathType,
    KilledByWeapon: EquipmentName?,
    KilledInSelfDefense: boolean,

    FreeKill: boolean,
    FreeKillReasons: {FreeKillReason},

    SelfDefenseList: {SelfDefenseEntry},
    KillList: {Username},

    SlayVotes: Integer,

    EquipmentPurchases: {[EquipmentName]: Integer?},

    AssignRole: (self: Participant, role: Role, overrideCredits: boolean?, overrideInventory: boolean?) -> nil, -- Assigns Role to this Participant. By default does not override inventory or credits.
    LeaveRound: (self: Participant) -> nil, -- Removes this Participant from the Round.

    GetAllegiance: (self: Participant) -> Role?,
    GiveEquipment: (self: Participant, equipment: Equipment) -> nil,
}

--[[
    The Round class. All Participants belong to a Round.
]]

export type Round = {
    ID: UUID,
    Category: RoundCategory,

    Gamemode: Gamemode,

    TimeMilestone: Timestamp,
    RoundPhase: RoundPhase,

    Participants: {Participant},
    EventLog: {Event},

    GetParticipant: (self: Round, name: Username) -> Participant?,
    JoinRound: (self: Round, name: Username) -> Participant?,
    
    StartRound: (self: Round) -> nil,
    EndRound: (self: Round, victors: Role) -> nil,
    CheckForVictory: (self: Round) -> boolean?,

    GetRoleInfo: (self: Round, name: RoleName) -> Role?, -- Shortcut method to get a Role
    GetRoleRelationship: (self: Round, role1: Role, role2: Role) -> RoleRelationship?,
    GetLimitedParticipantInfo: (self: Round, viewer: Player, target: Player) -> Role?,
}

export type Event = {
    RoundTime: RoundTime,
    Text: string,
    Category: RoundEventType,
    Correct: boolean?, --true if tick should be displayed, false if cross, nil if none
    FreeKill: boolean, --true if free kill icon should be displayed
    SelfDefense: boolean, --as above but self-defense
} -- Removed for public release

export type RoleRelationship = "All" | "Ally" | "Enemy" | RoleName

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

export type Equipment = {
    Name: EquipmentName,
    Description: string,
    Icon: Asset,
    Item: Model | (participant: Participant, equipmentName: EquipmentName) -> nil,
    Cost: Integer,
}

export type Role = {
    Name: string,
    Description: string,

    Allegiance: RoleName, -- i.e, Detective wins as Innocent. Previously known as WinsAs.
    VictoryMusic: {Sound}, -- Music that plays when this role wins.
    VictoryText: string?, -- Text shown in event log. Defaults to "The {role}s have won!".

    AssignmentPriority: Integer?, -- Lower value will be assigned first. Used for default AssignRoles().
    AssignmentProportion: number?, -- Proportion of total players that will have this role. Rounds down. Used for default AssignRoles().
    
    StartingCredits: Integer, -- Added onto gamemode StartingCredits
    StartingEquipment: {EquipmentName}, -- Added onto gamemode StartingEquipment
    EquipmentShop: {EquipmentName}, -- List of equipment available to this role

    CorpseResultsPublicised: boolean, -- Whether this role will publicise the results from searching a corpse.
    CanStealCredits: boolean, -- Whether this role can steal credits from corpses.
    AwardOnDeath: {[RoleRelationship]: Integer}, -- How many credits to award to other roles when this role is killed.

    Accessories: {Asset},
    Health: number, -- Health and MaxHealth
    Speed: number, -- WalkSpeed
    JumpPower: number, -- JumpPower

    Allies: {RoleName}, -- Allies to this role. Own role is not an ally by default.
    HighlightRules: {[RoleRelationship]: boolean}, -- Determines which roles will be highlighted for this role.
    KnowsRoles: {[RoleRelationship]: boolean}, -- Determines which roles will be revealed to this role.
    TeamChat: boolean, -- Can this role chat in private to other role members?

    OnRoleAssigned: (self: Role, participant: Participant) -> nil, -- Any extra code that should run for AssignRole.
    OnRoleRemoved: (self: Role, participant: Participant) -> nil, -- Any extra code that should when AssignRole is called on a Participant that previously had this role.

    --[[
        For the sake of interest, the following can be implemented manually:
         - PyrrhicVictor, VictoryMusic, AwardOnDeath (OnDeath)
         - StartingCredits, StartingEquipment, Health, Speed, JumpPower, Accessories (OnRoleAssigned)
    ]]
}

export type Gamemode = {
    Name: string,
    Description: string,

    MinimumPlayers: Integer, -- The gamemode will not start without at least this many players.
    RecommendedPlayers: Integer?, -- The gamemode will not appear in voting without at least this many players.
    MaximumPlayers: Integer?, -- The gamemode will not appear in voting if there are more players than this value.

    PyrrhicVictors: RoleName, -- Which role wins if everyone is killed simultaneously?
    TimeoutVictors: RoleName | (Round) -> nil, -- Which role wins if the round timer expires? Can be a function.
    Highlights: {RoundHighlight}, -- List of available round highlights.

    FriendlyFire: boolean, -- Whether allies can damage each other. Has no bearing on self-defense.
    SelfDefense: boolean, -- Whether self-defense is allowed.
    UseKarma: boolean, -- Whether karma will be affected by this round, and whether it will have an effect in this round.

    StartingCredits: Integer, -- Amount of credits to start with.
    StartingEquipment: {EquipmentName}, -- Equipment to start with.
    AvailableEquipment: {Equipment}, -- All equipment that is available, including standard weapons.

    Roles: {Role}, -- Defines roles for this gamemode.

    Duration: (numParticipants: Integer) -> PositiveNumber, -- Function that determines how long a round will last. Defaults to 120 + (numParticipants * 15)
    OnDeath: (Participant) -> nil, -- Called when a Participant in this gamemode dies. A default system is in place.
    AssignRoles: ({Participant}) -> nil, -- Function that assigns all Participants roles. A default system is in place.
    CheckForVictory: (Round) -> nil, -- Function that is called whenever someone dies (yes, it can be fully implemented in OnDeath). Responsible for calling Round:EndRound() with the relevant victorious role. A default system is in place.
}

--[[
    Defines all custom types used by Round Handler.
]]
return {}