--!strict
--[[
    A simple implementation of the round system.
    All players are added to a single round.
]]

local SS = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local RoundHandler = require("src/RoundHandler")
local Gamemodes = require("example_implementation/Gamemodes")

local maps = (SS:FindFirstChild("Maps") :: Instance):GetChildren() :: {Instance}

Players.PlayerAdded:Wait()
while true do
	local round = RoundHandler.CreateRound(maps[math.random(1, #maps)] :: Folder, Gamemodes.ThoseYouTrust)
	local con = Players.PlayerAdded:Connect(function(plr)
		round:JoinRound(plr.Name)
	end)
	for _, v in Players:GetPlayers() do
		round:JoinRound(v.Name)
	end
	round.RoundStartEvent.Event:Wait()
	con:Disconnect()
	round.RoundEndEvent.Event:Wait()
end