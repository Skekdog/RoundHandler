-- Builds the src folder into an rbxm file.
-- Requires Lune to be installed (https://github.com/lune-org/lune)

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local Instance = roblox.Instance

local function makeFolder(path: string, parent: Folder?, rootFolder: Folder?)
    local rootString = "script.Parent"
    local foundRoot: any = parent

    if parent then
        rootString ..= ".Parent"
        while (foundRoot ~= rootFolder) and (foundRoot) do
            foundRoot = foundRoot.Parent
            rootString ..= ".Parent"
        end 
    end

    local subFolder = Instance.new("Folder")

    -- Make the folder name Capitalised
    local subFolderName = path:split("/")[#path:split("/")]
    subFolderName = subFolderName:sub(1, 1):upper()..subFolderName:sub(2)
    subFolder.Name = subFolderName

    for _, name in fs.readDir(path) do
        name = path.."/"..name
        if fs.isDir(name) then
            makeFolder(name, subFolder, rootFolder)
            continue
        end

        local source = fs.readFile(name)
        local script
        if source:split("\n")[1] == "--serverscript" then
            script = Instance.new("Script")
        else
            script = Instance.new("ModuleScript")
        end

        script.Source = source:gsub(`require%("{path}/(.-)"%)`, "require(script.Parent.%1)"):gsub('require%("src/(.-)"%)', `require({rootString}.%1)`):gsub("%.gamemodes/", ".Gamemodes.")

        local splitName = name:split("/")
        local extensionSplit = splitName[#splitName]:split(".luau")
        script.Name = extensionSplit[1]

        script.Parent = subFolder
    end

    subFolder.Parent = parent

    return subFolder
end

local mainFolder = makeFolder("src")
local examples = makeFolder("examples", mainFolder, mainFolder)

assert(mainFolder)
mainFolder.Name = "RoundHandler"
examples.Name = "Examples"

fs.writeFile("RoundHandler.rbxm", roblox.serializeModel({mainFolder}))