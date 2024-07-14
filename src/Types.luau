-- These types exist for clarity
export type Integer = number
export type PositiveNumber = number
export type PositiveInteger = number
export type Timestamp = number

export type Username = string
export type FormattedUsername = string | "<font color='#{ROLE COLOUR}'>{USERNAME}</font>"
export type EquipmentName = string
export type RoleName = string

export type Asset = "rbxassetid://" | string
export type PauseFailReason = "RoundNotInProgress"

-- The participant that a client can view of themselves
export type GamemodeRoleString = "GAMEMODE__ROLE" | string -- Instead of sending a new table to each client every time they should save the roles in GAMEMODE__ROLE -> Role table
export type ParticipantStatus = "Alive" | "Dead" | "Missing"
export type ClientOwnParticipant = {
    Kind: "ClientOwnParticipant",
    Player: Player,
    FormattedName: FormattedUsername,
    Role: GamemodeRoleString,
    Status: ParticipantStatus,
    Credits: Integer,
    EquipmentPurchases: {[EquipmentName]: Integer},
}

export type ClientParticipant = {
    Kind: "ClientParticipant",
    Player: Player,
    FormattedName: FormattedUsername,
    Role: GamemodeRoleString,
    Status: ParticipantStatus,
}

export type Victor = Participant | Role

export type MessageSeverity = "info" | "warn" | "error"
export type MessageType = "update" | "bodyFound" | "disconnect" | "creditsEarned" | "karma" | "timeToRoundStart"
export type Adapter = {
    PREPARING_TIME: PositiveNumber,
    HIGHLIGHTS_TIME: PositiveNumber,
    INTERMISSION_TIME: PositiveNumber,
    SLAY_VOTES: PositiveInteger,
    LOAD_LIGHTING_SETTINGS: boolean,
    LOAD_TERRAIN_SETTINGS: boolean,
    LOAD_GRAVITY_SETTING: boolean,
    BOUNDS_COLLISION_GROUP: string,
    DEFAULT_GRAVITY: number,

    GetKarma: (plr: Player) -> number,
    SetKarma: (plr: Player, karma: number) -> (),
    CalculateDamageModifier: (karma: number) -> number,

    CalculateUserFacingEvents: (events: RoundEventLog, winners: Victor) -> {UserFacingRoundEvent}, -- Returns a sorted list of UserFacingRoundEvents, to display to players.

    GiveEquipment: (participant: Participant, item: Equipment) -> EquipmentGiveRejectionReason?, -- Returns a string describing the error if any occured, else nil
    ClearAllEquipment: (participant: Participant) -> (),

    SendSlayVote: (to: Participant, target: Participant) -> (), -- Sends a prompt to vote slay an RDMer.
    SendMessage: (message: string, severity: MessageSeverity, messageType: MessageType, recipients: {Participant}) -> () & (message: string, severity: MessageSeverity, messageType: MessageType, isGlobal: true) -> (),
    SendRoleAlert: (recipient: Participant, role: Role) -> (),
    CheckForUpdate: (round: Round, timeDelay: number) -> boolean,
    SendRoundHighlights: (recipients: {Participant}, highlights: {RoundHighlight}, events: {UserFacingRoundEvent}, scores: {[FormattedUsername]: {[ScoreReason]: Integer}}, victors: Victor) -> (),
    
    SetDefaultLighting: () -> (),
    SetDefaultTerrain: () -> (),

    LoadBound: (round: Round, bound: BasePart) -> (),
    LoadWeaponSpawn: (round: Round, weaponSpawn: BasePart) -> (),
    LoadProp: (round: Round, prop: Prop) -> (),

    OnCharacterLoad: (participant: Participant) -> (),
    OnDeath: (victim: Participant) -> (),
    OnCorpseResult: (receiver: Participant, corpse: Participant) -> (),

    DoIntermission: (round: Round) -> boolean, -- Returns true if an intermission should be held, delaying the destruction of the round. Should also run anything that an intermission should handle, like map voting.
}

export type WeaponAttackType = "Blunt" | "Blade" | "Explosion" | "Firearm"
export type EquipmentItem = PVInstance | (self: Equipment, participant: Participant) -> ()
export type Equipment = {
    Name: EquipmentName, -- Name of the equipment.
    Description: string?, -- Description of this equipment.
    Icon: Asset, -- Icon of this equipment.
    Cost: Integer?, -- The number of credits that this equipment costs to buy.
    MaxStock: PositiveInteger?, -- The maximum times a single Participant can purchase this equipment, per round.
    Extras: any, -- Any extra info about the equipment, for use in custom functions.

    AttackType: WeaponAttackType?, -- This determines the event flavour text that will be shown to players.
    NoGuilt: boolean?, -- true if this weapon should not cause the attacker to be a free kill for killing the wrong person.

    Item: EquipmentItem, -- Either a tool added to inventory, or a function that does something.
}

export type RoleRelationship = "__All" | "__Ally" | "__Enemy" | RoleName

export type ScoreReason = "KilledEnemy" | "KilledAlly" | "LeftoverCredits" | "Actions" | string

export type MurderWeapon = Equipment | DeathType

export type SelfDefenseEntry = {
    Against: Participant, -- A reference to the Participant who is able to freely kill this participant until the entry expires.
    Until: Timestamp, -- The timestamp at which this Self Defense entry expires. Always compare this, as opposed to checking the presence of an entry against the Participant, because the entry may not be removed.
}

export type RoundHighlight = {
    Name: string, -- Title of the highlight.
    Description: string, -- Description of the highlight.
}

export type RoundEvent_Death = {
    Attacker: Participant?,
    Victim: Participant,
    Weapon: MurderWeapon,
    CorrectKill: boolean,
    SelfDefense: boolean,
    FreeKill: boolean,
}

export type RoundEvent_CorpseSearched = {
    Participant: Participant,
    Corpse: Participant,
    CreditsFound: PositiveInteger?,
}

export type RoundEvent_MetaEvent = {
    RoundPhase: "Start"?,
    Winners: Victor?,
    NewMap: string?,
}

export type RoundEventData = RoundEvent_MetaEvent | RoundEvent_CorpseSearched | RoundEvent_Death
export type RoundEvent<DataType> = {
    Timestamp: Timestamp,
    Data: DataType,
}

export type RoundEventCategory = "MetaEvent" | "CorpseSearched" | "Death"

export type Icon = "CorrectKill" | "IncorrectKill" | "SelfDefense" | "FreeKill"
export type UserFacingRoundEvent = {
    Timestamp: Timestamp,
    Category: RoundEventCategory,
    Icons: {Asset | Icon},
    Text: string,
}

export type UUID = "{00000000-0000-0000-0000-000000000000}" | string
export type RoundPhase = "Waiting" | "Preparing" | "Playing" | "Highlights" | "Intermission" | "Destroy"
--[[
Round Phases:
    Waiting: Not enough players, waiting indefinitely
    Preparing: Enough players, giving time for others to join
    Playing: Round in progress
    Highlights: Round ended but still loaded
    Intermission: Round unloaded and voting time if applicable
    Destroy: Sent as signal when the round ends
]]

export type PartialRound = {
    Gamemode: Gamemode,
    Map: MapStructure,
    RoundPhase: RoundPhase,
    TimeMilestone: Timestamp,
    Paused: boolean,
    RoundEndInfo: RoundEndInfo?,
}

export type Prop = {
    Kind: "Prop",
    PropInstance: PropInstance,
    Attacker: Participant?,
    IsDead: boolean,
    OnBreak: (self: Prop) -> (),
    TakeDamage: (self: Prop, damage: number, attacker: Participant?) -> (),
    HasHealth: (self: Prop) -> boolean,
    GetHealth: (self: Prop) -> number,
}

export type Signal<T> = {Event: RBXScriptSignal<T>, Fire: (self: Signal<T>, data: T) -> ()}
export type RoundEventLog = {MetaEvent: {RoundEvent<RoundEvent_MetaEvent>}, CorpseSearched: {RoundEvent<RoundEvent_CorpseSearched>}, Death: {RoundEvent<RoundEvent_Death>}}
export type Round = {
    ID: UUID, -- Unique identifier of the round.
    Gamemode: Gamemode, -- A reference to the current gamemode.
    Map: MapStructure, -- A reference to the loaded map folder.
    MaterialVariantsFolder: MaterialVariantsStructure?,

    RoundEndInfo: RoundEndInfo?,
    Paused: boolean, -- Whether the round is paused or not.
    TimeMilestone: Timestamp, -- The timestamp of the next round phase. Used by the client for a round timer.
    RoundPhase: RoundPhase, -- The current round phase.

    Participants: {Participant}, -- A list of participants in this round.

    LogEvent: (self: Round, category: RoundEventCategory, data: RoundEventData) -> (), -- Adds an event to the round.
    EventLog: RoundEventLog, -- A list of events that have taken place.
    GetProp: (self: Round, propInstance: PropInstance) -> Prop, -- Returns the Prop from a PropInstance. Errors if the prop could not be found.

    RoundPhaseChangeEvent: Signal<RoundPhase>, -- A BindableEvent that fires whenever the round phase changes.

    GetParticipant: (self: Round, name: Username) -> Participant?, -- Returns a Participant from a username.
    JoinRound: (self: Round, plr: Player) -> Participant, -- Adds a Participant to this Round.
    
    GetPartialRound: (self: Round) -> PartialRound, -- Returns a limited view of the round, safe for clients to peak at. Does not include any Participants, see Participant:ViewPartialParticipant for that.
    PauseRound: (self: Round) -> (), -- Pauses the round. Errors if the round is not in progress.
    StartRound: (self: Round) -> (), -- Starts this round. Usually shouldn't be called externally.
    EndRound: (self: Round, victors: Victor, timeout: boolean?) -> (), -- Ends this round.

    IsRoundPreparing: (self: Round) -> boolean, -- Returns true if the current round phase is Preparing or Waiting.
    IsRoundOver: (self: Round) -> boolean, -- Returns true if the current round phase is Highlights or Intermission.
    IsRoundInProgress: (self: Round) -> boolean, -- Returns true if the current round phase is Playing.

    GetEquipment: (self: Round, name: EquipmentName) -> Equipment?, -- Returns the Equipment from Gamemode.
    GetParticipantsWithRole: (self: Round, name: RoleName) -> {Participant}, -- Returns a list of Participants with the specified role.
    GetRoleFromName: (self: Round, name: RoleName) -> Role, -- Returns a Role.
    CompareRoles: (self: Round, role1: Role, role2: Role, comparison: RoleRelationship) -> boolean, -- Tests whether two roles are related by comparison.
    IsRoleAlliedWith: (self: Round, role1: Role, role2: Role) -> boolean, -- Returns true if the roles are allied.

    LoadMap: (self: Round, map: MapStructure) -> (), -- Loads a map.

    -- Private members, should not be used from outside the module
    _roundTimerThread: thread?,
    _roundTimerContinueFor: number?,
    _props: {[PropInstance]: Prop},
}

--[[
    Represents a Gamemode with a specific set of rules.
    Must be defined manually. Roles form a significant part of Gamemodes.
]]
export type RoundEndInfo = {
    Winners: Role | ClientParticipant,
    Music: Sound?,
    Highlights: {RoundHighlight},
    Events: {UserFacingRoundEvent},
    Scores: {[FormattedUsername]: ParticipantScoring},
}
export type Gamemode = {
    Name: string, -- Name of the gamemode.
    Description: string?, -- Description of the gamemode.
    Authors: string?, -- Authors of the gamemode.
    Extras: any, -- Any extra info about the gamemode, for use in custom functions.

    EngineVersion: string, -- Indicates the engine version that this gamemode was designed for.

    MinimumPlayers: PositiveInteger, -- The gamemode will not start without at least this many players.
    RecommendedPlayers: PositiveInteger?, -- The gamemode will not appear in voting without at least this many players.
    MaximumPlayers: PositiveInteger?, -- The gamemode will not appear in voting if there are more players than this value.

    TimeoutVictors: RoleName | (self: Gamemode, round: Round) -> RoleName, -- Which role wins if the round timer expires?
    TimeoutMusic: {Sound}?,
    PhyrricVictors: RoleName, -- Which role wins if everyone dies at the same time? Cannot be a function because this is checked on every mass death event. --todo: So what if it gets checked every time?

    CalculateRoundHighlights: (self: Gamemode, round: Round) -> {RoundHighlight}, -- Returns an ordered list of round highlights.
    CalculateNonDefaultUserFacingEvents: ((self: Gamemode, round: Round) -> {UserFacingRoundEvent})?, -- Calculates the user facing event log for non-default events. Only needed if this Gamemode uses custom events. If any custom event is not converted, it will not be displayed to players.

    FriendlyFire: boolean?, -- Whether allies can damage each other. Has no bearing on self-defense.
    SelfDefense: boolean?, -- Whether self-defense is allowed.
    SelfDefenseDuration: PositiveNumber?, -- Duration of self defense.
    UseKarma: boolean?, -- Whether karma will be affected by this round, and whether it will have an effect in this round.

    StartingCredits: Integer?, -- Amount of credits to start with.
    StartingEquipment: {EquipmentName}?, -- Equipment to start with.
    AvailableEquipment: {Equipment}?, -- All equipment that is available, including standard weapons. Due to type solver weirdness, this must be non-nil for now.

    Roles: {Role}, -- Defines roles for this gamemode.

    Duration: PositiveNumber | (self: Gamemode, numParticipants: PositiveInteger) -> PositiveNumber, -- Function that determines how long a round will last. Defaults to 120 + (numParticipants * 15)
    OnDeath: ((self: Gamemode, victim: Participant) -> ())?, -- Called when a Participant in this gamemode dies.
    OnCharacterLoad: ((self: Gamemode, char: Model) -> ())?, -- Called when CharacterAppearanceLoaded fires.
    AssignRoles: (self: Gamemode, participants: {Participant}) -> (), -- Function that assigns all Participants roles.
}

--[[
    Represents a Participant Role.
    Contains info such as Allies, Credits, etc.
    Must be defined in a Gamemode.
]]
export type Role = {
    Kind: "Role",
    Name: string, -- Name of this role.
    FormattedName: string?, -- Rich text formatted name, usually with the role colour
    Description: string?, -- Description of this role.
    Colour: Color3, -- Colour of this role. Not color.
    Extras: any, -- Any extra info about the role, for use in custom functions.

    Allegiance: RoleName?, -- i.e, Detective wins as Innocent. Does not necessarily impact Ally / Enemy status.
    VictoryMusic: {Sound}?, -- Music that plays when this role wins. Must not be nil for the Allegiance roles, no effect on other roles.
    VictoryText: string?, -- Text shown in event log. Must not be nil for the Allegiance roles, no effect on other roles.
    
    StartingCredits: Integer?, -- Added onto gamemode StartingCredits.
    StartingEquipment: {EquipmentName}?, -- Added onto gamemode StartingEquipment.
    EquipmentShop: {EquipmentName}?, -- List of equipment available to this role.

    AnnounceDisconnect: boolean?, -- If true, a message is sent to all participants when this player leaves the round.
    CorpseResultsPublicised: boolean?, -- Whether this role will publicise the results from searching a corpse.
    CanStealCredits: boolean?, -- Whether this role can steal credits from corpses.
    CanSeeMissing: boolean?, -- Whether this role can see Missing participants, or if they will be shown as alive instead.
    AwardOnDeath: {[RoleRelationship]: Integer}?, -- How many credits to award to other roles when a member of this role is killed.

    Accessories: {Accessory}?, -- A list of accessories to add to the character.
    Health: number?, -- Sets Health and MaxHealth (of Humanoid).
    Speed: number?,  -- Sets normal WalkSpeed.
    JumpPower: number?, -- Sets JumpPower (of Humanoid).

    Allies: {RoleName}?, -- Allies to this role. Own role is not an ally by default.
    HighlightRoles: {RoleRelationship}?, -- Determines which roles will be highlighted for this role.
    KnowsRoles: {RoleRelationship}?, -- Determines which roles will be revealed to this role.
    TeamChat: boolean?, -- Can this role chat in private to other role members?

    OnRoleAssigned: ((self: Role, participant: Participant) -> ())?, -- Any extra code that should run for AssignRole.
    OnRoleRemoved: ((self: Role, participant: Participant) -> ())?, -- Any extra code that should run when AssignRole is called on a Participant that previously had this role.
}

export type CorpseInfo = {
    Player: Player,
    FormattedName: FormattedUsername,
    Role: Role,
    Headshot: boolean,
    DeathTime: Timestamp,
    MurderWeapon: Equipment | DeathType,
    EquipmentList: {Equipment},
    KillList: {FormattedUsername},
    SelfDefense: boolean,
    FreeKill: boolean,
}

--[[
    Represents a Participant in a Round, storing player-related attributes
    such as Role, death info and Credits.
    Independent of Player.
    Created by Round:JoinRound().
]]
export type FreeKillReason = "Teamkill" | string
export type DeathType = "Drown" | "Fall" | "Crush" | "Explosion" | "Suicide" | "Mutation" | "Burn" | WeaponAttackType
export type EquipmentGiveRejectionReason = string -- for use in Adapters.GiveEquipment
export type EquipmentPurchaseRejectionReason = "Dead" | "NotEnoughCredits" | "NotInStock" | EquipmentGiveRejectionReason
export type ParticipantScoring = {[ScoreReason]: Integer}
-- Mutation: DNA mutated by teleporter (in a deadly way)
export type Participant = {
    Kind: "Participant",
    Round: Round, -- A reference to the round.

    Player: Player, -- A reference to the Player object. Will never be nil, but may be parented to nil if the player disconnects. As such it may be useful to check the parent property.
    Character: Model, -- A reference to the Player's character. May be parented to nil if falling into the void, for example, but generally will not be nil. As such it may be useful to check the parent property.
    FormattedName: string, -- Rich text formatted name with the role colour
    
    Role: Role, -- A reference to their role. Uses a blank default role if the round hasn't started yet.
    AssignRole: (self: Participant, role: Role) -> (), -- Assigns Role to this Participant. By default does not override inventory or credits.
    TryViewParticipantRole: (self: Participant, viewer: Participant?) -> Role,
    ViewPartialParticipant: (self: Participant, viewer: Participant?) -> ClientParticipant, -- Returns a limited view of the Participant, for clients.
    ViewPartialSelf: (self: Participant) -> ClientOwnParticipant, -- Returns a limited view of the Participant, for clients.

    LeaveRound: (self: Participant, persistTimer: boolean?) -> (), -- Removes this Participant from the Round.

    IsDamageJustifiedAgainst: (self: Participant, target: Participant) -> boolean,
    SearchedBy: {Participant}, -- A list of Participants who have searched this Corpse.
    KilledAt: Timestamp, -- Timestamp of the Participant's demise. Initially 0.
    KilledByWeapon: MurderWeapon, -- The weapon used to kill a Participant. If a weapon was not directly used, then describes how they died.
    KilledByParticipant: Participant?, -- Who killed this Participant.
    KilledInSelfDefense: boolean, -- Whether this Participant was killed in self defense or not.
    KilledAsFreeKill: boolean, -- Whether this Participant was killed as a free kill or not. Always check this as opposed to FreeKillReasons, as additional reasons may be added after death.
    KilledByHeadshot: boolean, -- True if they were killed by a headshot.

    HasHealth: (self: Participant) -> true, -- Exists to simplify usage alongside props. Will always return true.
    GetHealth: (self: Participant) -> number,
    TakeDamage: (self: Participant, damage: number, attacker: Participant?, weapon: MurderWeapon?, headshot: boolean?, ignoreKarma: boolean?) -> (), -- Sets the Humanoid's Health to 0 and sets relevant properties on the Participant.
    
    GetCredits: (self: Participant) -> Integer,
    SetCredits: (self: Participant, credits: Integer) -> (),

    GetStatus: (self: Participant) -> ParticipantStatus,
    SetStatus: (self: Participant, status: ParticipantStatus) -> (),
    
    Karma: number, -- The Participant's current karma. When the round ends, this is applied using Adapters.SetKarma() if applicable. Initially set by Adapters.GetKarma().
    FreeKill: boolean, -- true if the Participant has done something which now means they can be freely killed by anyone, such as RDM.
    SlayVotes: {Participant}, -- A list of Participants who have voted to slay this person due to RDM.
    TryAddSlayVote: (self: Participant, from: Participant) -> boolean, -- Tries to add a vote to slay this Participant, and executes them if required. Will return false if the vote could not be added, such as due to this Participant already voting to remove them, else returning true if successful.
    
    EquipmentPurchases: {[EquipmentName]: PositiveInteger}, -- The Equipment this Participant purchased, and how many times.
    PurchaseEquipment: (self: Participant, equipment: Equipment) -> EquipmentPurchaseRejectionReason?, -- Deducts credits and stock and gives Equipment. If GiveEquipment rejects, purchase also rejects.

    ViewCorpse: (self: Participant) -> CorpseInfo, -- Returns the target's Corpse info. Errors if self is not dead.
    SearchCorpse: (self: Participant, target: Participant) -> (), -- Errors if target is not dead.
    IsDead: (self: Participant) -> boolean, -- Returns true if Status == "Missing" or "Dead"
    
    KillList: {Participant}, -- A list of Participants this player has killed.
    AddKill: (self: Participant, victim: Participant, ignoreKarma: boolean) -> (), -- Adds a kill to this Participant's kill list. By default, also checks if the kill was correct and sets FreeKill as needed, but this can be disable with ignoreKarma = true.
    
    Score: ParticipantScoring, -- Dictionary of score reason = total score for this reason.
    AddScore: (self: Participant, reason: ScoreReason, amount: Integer) -> (), -- Adds score to this Participant.

    SelfDefenseList: {SelfDefenseEntry}, -- A list of Participants who this participant can freely kill in self-defense.
    AddSelfDefense: (self: Participant, against: Participant, duration: number) -> (), -- Adds a self defense entry against a Participant.
    HasSelfDefenseAgainst: (self: Participant, against: Participant) -> boolean, -- Returns true if this Participant is allowed to hurt the `against` participant in self defense.

    CreditsChanged: Signal<ClientOwnParticipant>,
    StatusChanged: Signal<ClientOwnParticipant>,
    RoleChanged: Signal<ClientOwnParticipant>,

    _credits: Integer,
    _status: ParticipantStatus,
}

export type LightingStructure = {GetChildren: (self: Folder) -> {StringValue | NumberValue | Color3Value | BoolValue | Instance}} & Folder
export type MaterialVariantsStructure = {GetChildren: (self: Folder) -> {MaterialVariant}} & Folder
export type WeaponSpawnsStructure = {GetChildren: (self: Folder) -> {BasePart & {Name: EquipmentName}}} & Folder
export type PropsStructure = {GetChildren: (self: Folder) -> {PropInstance}} & Folder
export type TerrainColorsStructure = {GetChildren: (self: Folder) -> {Color3Value}} & Folder
export type WaterSettingsStructure = {GetChildren: (self: Folder) -> {NumberValue | Color3Value}} & Folder
export type WindowsStructure = {GetChildren: (self: Folder) -> {BasePart}} & Folder
export type BoundsStructure = {GetChildren: (self: Folder) -> {BasePart & {Name: "KillBound" | string}}} & Folder

export type MapStructure =  {
    Name: string,
    Clone: (MapStructure) -> MapStructure,
    Destroy: (MapStructure) -> (),

    EngineVersion: StringValue,
    Authors: StringValue,
    Spawns: {Parent: Folder, GetChildren: ({}) -> {BasePart}},
    Map: Folder,

    FindFirstChild:
    ((MapStructure, "Lighting") -> LightingStructure?) &
    ((MapStructure, "Props") -> PropsStructure?) &
    ((MapStructure, "MaterialVariants") -> MaterialVariantsStructure?) &
    ((MapStructure, "WeaponSpawns") -> WeaponSpawnsStructure?) &
    ((MapStructure, "TerrainColors") -> TerrainColorsStructure?) &
    ((MapStructure, "WaterSettings") -> WaterSettingsStructure?) &
    ((MapStructure, "TerrainRegion") -> TerrainRegion?) &
    ((MapStructure, "Windows") -> WindowsStructure?) &
    ((MapStructure, "Bounds") -> BoundsStructure?) &
    ((MapStructure, "Gravity") -> NumberValue?) &
    ((MapStructure, string) -> Instance?),

    GetChildren: (self: MapStructure) -> {Instance}
}

export type MapStructureCast = Instance & MapStructure

export type PropInstance = BasePart & {
    FindFirstChild: (PropInstance, name: "OnBreak") -> ModuleScript?,
    GetAttribute:
    ((PropInstance, attribute: "Health") -> number?) &
    ((PropInstance, attribute: "NoGrab") -> boolean?),
    SetAttribute: (PropInstance, attribute: "Health", value: number) -> (),
    GetAttributeChangedSignal: (PropInstance, attribute: "Health") -> RBXScriptSignal?,
}

return {}