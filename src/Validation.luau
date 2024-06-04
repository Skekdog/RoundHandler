-- Functions to check if gamemodes / maps are correctly defined, when the type-checker is unable to do so.
local Types = require(script.Parent.Types)
local EngineVersion = "0.0.1"

local Lighting = game:GetService("Lighting")

local module = {}

local function validateVersion(targetVersion: string, objectName: string): string?
    local major = tonumber(EngineVersion:split(".")[1])
    local minor = tonumber(EngineVersion:split(".")[2])

    local targetMajor = tonumber(targetVersion:split(".")[1])
    local targetMinor = tonumber(targetVersion:split(".")[2])

    if targetMajor ~= major then
        if targetMajor < major then
            return `This {objectName} was designed for an older version of RoundHandler ({targetVersion} < {version}) and is very likely to not work.`
        else
            return `This {objectName} was designed for a newer version of RoundHandler ({targetVersion} > {version}) and is very likely to not work.`
        end
    elseif targetMinor ~= minor then
        if targetMinor < minor then
            return `This {objectName} was designed for an older version of RoundHandler ({targetVersion} < {version}) and may not work.`
        else
            return `This {objectName} was designed for a newer version of RoundHandler ({targetVersion} > {version}) and may not work.`
        end
    end
    return
end

function module.ValidateGamemode(gamemode: Types.Gamemode): (boolean, {string?})
    local issues = {}
    local i = function(issue: string?)
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
    if gamemode.MaximumPlayers and gamemode.MinimumPlayers > gamemode.MaximumPlayers then
        i("MinimumPlayers must not be greater than MaximumPlayers.")
    end

    -- Good enough
    if type(gamemode.Duration) == "number" then
        if gamemode.Duration <= 0 then 
            i("Gamemode duration is negative.")
        end
    else
        if gamemode.Duration(gamemode, gamemode.MinimumPlayers) <= 0 then
            i("Gamemode duration is negative with MinimumPlayers.")
        end
        if gamemode.Duration(gamemode, gamemode.MaximumPlayers or 700) <= 0 then
            i(`Gamemode duration is negative with {tostring(gamemode.MaximumPlayers or 700)} players`)
        end
    end

    local equipmentNames = {}
    if gamemode.AvailableEquipment then
        for _, equipment in gamemode.AvailableEquipment do
            table.insert(equipmentNames, equipment.Name)
        end
    end

    local roleNames = {}
    local allegianceNames = {}
    for _, role in gamemode.Roles do
        table.insert(roleNames, role.Name)
        
        if not table.find(allegianceNames, role.Allegiance) then
            table.insert(allegianceNames, role.Allegiance)
        end

        checkString(role.Name, "Role Name")
        
        if role.StartingEquipment then
            for _, equipmentName in role.StartingEquipment do
                checkString(equipmentName, "Equipment Name")
                if not table.find(equipmentNames, equipmentName) then
                    i((`Equipment {equipmentName} of {role.Name}.StartingEquipment is not defined in Gamemode.AvailableEquipment.`))
                end
            end
        end
        if role.EquipmentShop then
            for _, equipmentName in role.EquipmentShop do
                checkString(equipmentName, "Equipment Name")
                if not table.find(equipmentNames, equipmentName) then
                    i((`Equipment {equipmentName} of {role.Name}.EquipmentShop is not defined in Gamemode.AvailableEquipment.`))
                end
            end
        end
    end

    local function validateRoleRelationship(list: {[Types.RoleRelationship]: boolean | number}, info: "Role.Table" | string)
        for relationship, _ in list do
            if not table.find({"__Ally", "__Enemy", "__All"}, relationship) and not table.find(roleNames, relationship) then
                i(`{relationship} is not a valid RoleRelationship in {info}.`)
            end
        end
    end

    for _, role in gamemode.Roles do
        if role.Allies then
            for _, ally in role.Allies do
                if not table.find(roleNames, ally) then i(`Role {role.Name}.Ally is undefined: {ally}`) end
            end
        end
        if not table.find(roleNames, role.Allegiance or role.Name) then
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

        if role.KnowsRoles then
            validateRoleRelationship(role.KnowsRoles, `{role.Name}.KnowsRoles`)
        end
        if role.HighlightRules then
            validateRoleRelationship(role.HighlightRules, `{role.Name}.HighlightRules`)
        end
        if role.AwardOnDeath then
            validateRoleRelationship(role.AwardOnDeath, `{role.Name}.AwardOnDeath`)
        end
    end

    i(validateVersion(gamemode.EngineVersion, "gamemode"))

    return #issues<1, issues
end

function module.ValidateMap(map: Types.MapStructure): (boolean, {string?})
    local issues = {}
    local i = function(issue: string?)
        table.insert(issues, issue)
    end

    local lighting = map:FindFirstChild("Lighting") :: Types.LightingStructure?
    if lighting then
        for _, v in lighting:GetChildren() do
            local success, _ = pcall(function()
                if v:IsA("Color3Value") or v:IsA("BoolValue") or v:IsA("NumberValue") or v:IsA("StringValue") then
                    (Lighting :: any)[v.Name] = v.Value
                end
            end)
            if not success then
                i(`Failed to set property {v.Name} of Lighting, check that it is the correct type and that it exists.`)
            end
        end
    end

    local mats = map:FindFirstChild("MaterialVariants") :: Types.MaterialVariantsStructure?
    if mats then
        for _, v in mats:GetChildren() do
            if v.ClassName ~= "MaterialService" then
                i("MaterialVariants must only contain MaterialVariants.")
                break
            end
        end
    end

    if not map:FindFirstChild("Map") then
        i("Map must have a Folder named Map.")
    end

    if not map:FindFirstChild("EngineVersion") or map.EngineVersion.ClassName ~= "StringValue" then
        i("Map must have a StringValue named EngineVersion.")
    end

    -- We don't actually care if it is a folder or not, just that it exists
    if not map:FindFirstChild("Props") then
        i("Map must have a Folder named Props.")
    else
        for _, prop in map.Props:GetChildren() do
            if not prop:IsA("BasePart") then
                i("Props must only contain BaseParts.")
                break
            end
        end
    end

    if not map:FindFirstChild("WeaponSpawns") then
        i("Map must have a Folder named WeaponSpawns.")
    else
        for _, spawn in map.WeaponSpawns:GetChildren() do
            if not spawn:IsA("BasePart") then
                i("Spawns must only contain BaseParts.")
                break
            end
        end
    end

    if not map:FindFirstChild("Spawns") then
        i("Map must have a Folder named Spawns.")
    else
        local didIterate = false
        for _, spawn in map.Spawns:GetChildren() do
            if not spawn:IsA("BasePart") then
                i("Spawns must only contain BaseParts.")
                break
            end
            didIterate = true
        end

        if not didIterate then
            i("Map must have at least 1 spawn.")
        end
    end

    i(validateVersion(map.EngineVersion.Value, "map"))

    return #issues<1, issues
end

return module