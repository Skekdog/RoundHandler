--!strict
--[[
    A simple implementation of the round system.
    All players are added to a single round.
]]
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local RoundHandler = require("src/RoundHandler")
local Gamemodes = require("example_implementation/Gamemodes")

local maps = (ServerStorage:FindFirstChild("Maps") :: Instance):GetChildren() :: {Instance}

while true do
	local round = RoundHandler.CreateRound(maps[math.random(1, #maps)] :: Folder, Gamemodes.ThoseYouTrust)

	local function playerAdded(plr: Player)
		round:JoinRound(plr.Name)
	end

	local joinCon = Players.PlayerAdded:Connect(playerAdded)
	for _, v in Players:GetPlayers() do
		playerAdded(v)
	end

	round.RoundStartEvent.Event:Wait()
	joinCon:Disconnect()
	round.RoundEndEvent.Event:Wait()
end