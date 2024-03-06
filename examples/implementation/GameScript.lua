--!strict
--[[
    A simple implementation of the round system.
    All players are added to a single round.
]]

local SS = game:GetService("ServerStorage")

local RoundHandler = require("src/RoundHandler")

local maps = (SS:FindFirstChild("Maps") :: Instance):GetChildren() :: {Instance}
local round = RoundHandler.CreateRound(maps[math.random(1, #maps)] :: Folder)

game:GetService("Players").PlayerAdded:Connect(function(plr)
    if round:IsRoundPreparing() then
        return round:JoinRound(plr.Name)
    end
end)