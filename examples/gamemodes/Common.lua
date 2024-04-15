-- Not a Gamemode, but contains some useful functions that are used by multiple Gamemodes.
-- Not a part of the standard implementation, can be removed to your tastes.

local Types = require("src/Types")

local module = {}

function module.TestForOneSurvivingRole(self: Types.Gamemode, round: Types.Round): string?
    local allegiances = {}
    for _, v in self.Roles do
        if not table.find(allegiances, v.Allegiance) then
            table.insert(allegiances, v.Allegiance)
        end
    end

    if #allegiances ~= 2 then
        error("TestForOneSurvivingRole Victory Checker only works if there are 2 teams!")
    end

    local function checkAlive(participant: Types.Participant)
        -- Remember what they took from you: https://github.com/luau-lang/luau/pull/501
        local plr = participant.Player
        if not plr then return false end
        local char = plr.Character
        if not char then return false end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        return hum.Health > 0
    end

    local rolesAlive = {
        [allegiances[1]] = false,
        [allegiances[2]] = false,
    }
    for _, v in round.Participants do
        if checkAlive(v) then
            rolesAlive[v:GetAllegiance().Name] = true
        end
        if rolesAlive[allegiances[1]] and rolesAlive[allegiances[2]] then
            return nil -- Both roles are still alive, nobody wins yet
        end
    end

    if rolesAlive[allegiances[1]] then
        return allegiances[1]
    end
    return allegiances[2]
end

-- returns a table of EquipmentName = {Username, Kills}
-- I don't like this
function module.GetWeaponHighlights(roundEvents: {["Death"]: {Types.RoundEvent_Death}}): {[Types.EquipmentName]: {Types.Username | Types.PositiveInteger}}
    local deathEvents = roundEvents.Death
    
    local counter: {[Types.EquipmentName]: {[Types.Participant]: Types.Integer}} = {} -- yeah i'm not giving this a nice name
    for _, v in deathEvents do
        local attacker = v.Attacker
        local weapon = v.Weapon
        if (not attacker) or (type(weapon) ~= "table") then
            continue
        end

        local weaponName = weapon.Name

        if not counter[weaponName] then
            counter[weaponName] = {}
        end

        if not counter[weaponName][attacker] then
            counter[weaponName][attacker] = 0
        end
        counter[weaponName][attacker] += 1
    end

    local bestPerWeapon: {[Types.EquipmentName]: {Types.Username | Types.PositiveInteger}} = {} -- [1] = username, [2] = amount
    for weapon, v in counter do
        for participant, amount in v do
            if (not bestPerWeapon[weapon]) or (bestPerWeapon[weapon][2] < amount) then
                bestPerWeapon = {participant.Player.Name, amount :: any} :: any
            end
        end
    end

    return bestPerWeapon
end

return module