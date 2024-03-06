-- Returns whether the gamemode is valid, and a list of issues with the gamemode
local Types = require("src/Types")

local module = {}

function module.ValidateGamemode(gamemode: Types.Gamemode, runFunctions: boolean): (boolean, {string})
    local issues = {}
    local i = function(issue: string) table.insert(issues, issue) end

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

        if table.find({"All", "Ally", "Enemy"}, role.Name) then i("Role name "..role.Name.." is reserved.") end
        
        for _, equipmentName in role.StartingEquipment do
            if not table.find(equipmentNames, equipmentName) then
                i("Equipment "..equipmentName.." of "..role.Name..".StartingEquipment ".." is not defined in Gamemode.AvailableEquipment.")
            end
        end
        for _, equipmentName in role.EquipmentShop do
            if not table.find(equipmentNames, equipmentName) then
                i("Equipment "..equipmentName.." of "..role.Name..".EquipmentShop ".." is not defined in Gamemode.EquipmentShop.")
            end
        end
    end

    local function validateRoleRelationship(list: {[Types.RoleRelationship]: any}, info: "Role.Table" | string)
        for relationship, _ in list do
            if not table.find({"All", "Ally", "Enemy"}, relationship) and not table.find(roleNames, relationship) then
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