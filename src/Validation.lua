-- Returns whether the gamemode is valid, and a list of issues with the gamemode
local Types = require("src/Types")
local EngineVersion = "0.0.1"
print("test")

local module = {}

function module.ValidateGamemode(gamemode: Types.Gamemode, runFunctions: boolean, checkVersion: boolean): (boolean, {string})
    local issues = {}
    local i = function(issue: string)
        table.insert(issues, issue)
    end

    -- Dunders are reserved
    local function checkString(str: string, name: string)
        if str:sub(1, 2) == "__" then
            i(`{name} must not start with 2 underscores.`)
        end
    end

    if gamemode.MinimumPlayers <= 0 then
        i("MinimumPlayers must be greater than 0.")
    end
    if gamemode.MaximumPlayers <= 0 then
        i("MaximumPlayers must be greater than 0.")
    end
    if gamemode.RecommendedPlayers <= 0 then
        i("RecommendedPlayers must be greater than 0.")
    end
    if (gamemode.RecommendedPlayers < gamemode.MinimumPlayers) or (gamemode.RecommendedPlayers > gamemode.MaximumPlayers) then
        i("RecommendedPlayers must be between MinimumPlayers and MaximumPlayers.")
    end
    if gamemode.MinimumPlayers > gamemode.MaximumPlayers then
        i("MinimumPlayers must not be greater than MaximumPlayers.")
    end

    -- Good enough
    if gamemode:Duration(gamemode.MinimumPlayers) <= 0 then
        i("Gamemode duration is negative with MinimumPlayers.")
    end
    if gamemode:Duration(gamemode.MaximumPlayers) <= 0 then
        i(`Gamemode duration is negative with {tostring(gamemode.MaximumPlayers)} players`)
    end

    local equipmentNames = {}
    for _, equipment in gamemode.AvailableEquipment do table.insert(equipmentNames, equipment.Name) end

    local roleNames = {}
    local allegianceNames = {}
    for _, role in gamemode.Roles do
        table.insert(roleNames, role.Name)
        
        if not table.find(allegianceNames, role.Allegiance) then
            table.insert(allegianceNames, role.Allegiance)
        end

        checkString(role.Name, "Role Name")
        
        for _, equipmentName in role.StartingEquipment do
            checkString(equipmentName, "Equipment Name")
            if not table.find(equipmentNames, equipmentName) then
                i((`Equipment {equipmentName} of {role.Name}.StartingEquipment is not defined in Gamemode.AvailableEquipment.`))
            end
        end
        for _, equipmentName in role.EquipmentShop do
            checkString(equipmentName, "Equipment Name")
            if not table.find(equipmentNames, equipmentName) then
                i((`Equipment {equipmentName} of {role.Name}.EquipmentShop is not defined in Gamemode.AvailableEquipment.`))
            end
        end
    end

    local function validateRoleRelationship(list: {[Types.RoleRelationship]: any}, info: "Role.Table" | string)
        for relationship, _ in list do
            if not table.find(Types.RoleRelationships, relationship) and not table.find(roleNames, relationship) then
                i(`{relationship} is not a valid RoleRelationship in {info}.`)
            end
        end
    end

    for _, role in gamemode.Roles do
        for _, ally in role.Allies do
            if not table.find(roleNames, ally) then i(`Role {role.Name}.Ally is undefined: {ally}`) end
        end
        if not table.find(roleNames, role.Allegiance) then
            i(`Role {role.Name} has an undefined Allegiance: {role.Allegiance}`)
        end

        if table.find(allegianceNames, role.Name) then
            if not role.VictoryMusic then
                i(`Role {role.Name} is an allegiance and therefore must have VictoryMusic.`)
            end
            if not role.VictoryText then
                i(`Role {role.Name} is an allegiance and therefore must have VictoryText.`)
            end
        end

        if role.Health <= 0 then
            i(`Role {role.Name}.Health must be greater than 0.`)
        end

        validateRoleRelationship(role.KnowsRoles, `{role.Name}.KnowsRoles`)
        validateRoleRelationship(role.HighlightRules, `{role.Name}.HighlightRules`)
        validateRoleRelationship(role.AwardOnDeath, `{role.Name}.AwardOnDeath`)
    end

    local function doCheckVersion()
        local version = EngineVersion
        local major = tonumber(version:split(".")[1])
        local minor = tonumber(version:split(".")[2])

        local gmVersion = gamemode.EngineVersion
        local gmMajor = tonumber(gmVersion:split(".")[1])
        local gmMinor = tonumber(gmVersion:split(".")[2])

        if gmMajor ~= major then
            if gmMajor < major then
                i(`This gamemode was designed for an older version of RoundHandler ({gmVersion} < {version}) and is very likely to not work.`)
            else
                i(`This gamemode was designed for a newer version of RoundHandler ({gmVersion} > {version}) and is very likely to not work.`)
            end
        elseif gmMinor ~= minor then
            if gmMinor < minor then
                i(`This gamemode was designed for an older version of RoundHandler ({gmVersion} < {version}) and may not work.`)
            else
                i(`This gamemode was designed for a newer version of RoundHandler ({gmVersion} > {version}) and may not work.`)
            end
        end
    end

    if checkVersion then
        doCheckVersion()
    end

    return #issues<1, issues
end

return module