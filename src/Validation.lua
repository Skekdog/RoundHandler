-- Returns whether the gamemode is valid, and a list of issues with the gamemode
local Types = require("src/Types")

local module = {}

function module.ValidateGamemode(gamemode: Types.Gamemode, runFunctions: boolean): (boolean, {string})
    local issues = {}
    local i = function(issue: string)
        table.insert(issues, issue)
    end

    -- Dunders are reserved
    local function checkString(str: string, issue: string)
        if str:sub(1, 2) == "__" then
            i(issue.." must not start with 2 underscores.")
        end
    end

    -- Test with some functions
    if gamemode:Duration(gamemode.MinimumPlayers) <= 0 then i("Gamemode duration is negative with MinimumPlayers.") end
    if gamemode:Duration(gamemode.MaximumPlayers) <= 0 then i("Gamemode duration is negative with "..tostring(gamemode.MaximumPlayers).." players") end

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
                i(("Equipment %s of %s.StartingEquipment is not defined in Gamemode.AvailableEquipment."):format(equipmentName, role.Name))
            end
        end
        for _, equipmentName in role.EquipmentShop do
            checkString(equipmentName, "Equipment Name")
            if not table.find(equipmentNames, equipmentName) then
                i(("Equipment %s of %s.EquipmentShop is not defined in Gamemode.AvailableEquipment."):format(equipmentName, role.Name))
            end
        end
    end

    local function validateRoleRelationship(list: {[Types.RoleRelationship]: any}, info: "Role.Table" | string)
        for relationship, _ in list do
            if not table.find(Types.RoleRelationships, relationship) and not table.find(roleNames, relationship) then
                i(relationship.." is not a valid RoleRelationship in "..info..".")
            end
        end
    end

    for _, role in gamemode.Roles do
        for _, ally in role.Allies do
            if not table.find(roleNames, ally) then i("Role "..role.Name.." has an undefined Ally: "..ally) end
        end
        if not table.find(roleNames, role.Allegiance) then
            i("Role "..role.Name.." has an undefined Allegiance: "..role.Allegiance)
        end

        if table.find(allegianceNames, role.Name) then
            if not role.VictoryMusic then
                i("Role "..role.Name.." is an allegiance and therefore must have VictoryMusic.")
            end
            if not role.VictoryText then
                i("Role "..role.Name.." is an allegiance and therefore must have VictoryText.")
            end
        end

        validateRoleRelationship(role.KnowsRoles, role.Name..".KnowsRoles")
        validateRoleRelationship(role.HighlightRules, role.Name..".HighlightRules")
        validateRoleRelationship(role.AwardOnDeath, role.Name..".AwardOnDeath")
    end

    return #issues<1, issues
end

return module