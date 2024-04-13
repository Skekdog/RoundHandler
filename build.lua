-- Builds the src folder into an rbxm file.
-- Requires Lune to be installed (https://github.com/lune-org/lune)

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local Instance = roblox.Instance

local buildExample = table.find(process.args, "example")

local function makeFolder(path: string, parent: Folder?)
    local subFolder = Instance.new("Folder")
    subFolder.Name = path:split("/")[#path:split("/")]
    
    for _, name in fs.readDir(path) do
        name = path.."/"..name
        if fs.isDir(name) then
            makeFolder(name, subFolder)
            continue
        end
        local script = Instance.new("ModuleScript")

        if not buildExample then
            -- There's no way to know where RoundHandler will be stored so we shouldn't replace anything in examples
            script.Source = fs.readFile(name):gsub('require%("src/(.-)"%)', 'require(script.Parent.%1)')
        end

        local splitName = name:split("/")
        local extensionSplit = splitName[#splitName]:split(".lua")
        script.Name = extensionSplit[1]

        script.Parent = subFolder
    end

    subFolder.Parent = parent

    return subFolder
end

local folder = makeFolder(if buildExample then "examples" else "src")

assert(folder)
folder.Name = if buildExample then "RoundHandlerExamples" else "RoundHandler"

fs.writeFile(if buildExample then "RoundHandlerExamples.rbxm" else "RoundHandler.rbxm", roblox.serializeModel({folder}))