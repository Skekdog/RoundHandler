--serverscript
-- A simple implementation of the round system.
-- All players are added to a single round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local RoundHandler = require("src/RoundHandler")
local ThoseYouTrust = require("examples/gamemodes/ThoseYouTrust")
local Murder = require("examples/gamemodes/Murder")

local maps = (ServerStorage:FindFirstChild("Maps") :: Instance):GetChildren() :: {Instance}
local remotes = ReplicatedStorage:FindFirstChild("RoundHandler")

if not remotes then
	error("Missing remotes folder (RoundHandler)")
end

local slayVote = remotes:FindFirstChild("SlayVote") :: RemoteEvent
local getPartialParticipants = remotes:FindFirstChild("GetPartialParticipants") :: RemoteFunction

if not slayVote or not getPartialParticipants then
	error("Missing required remotes")
end

getPartialParticipants.OnServerInvoke = function(plr)
	local roundId = ServerStorage:GetAttribute("RoundID")
	if not roundId then
		return
	end

	local round = RoundHandler.GetRound(roundId)
	local self = round:GetParticipant(plr.Name)

	local participants = {}
	for _, v in round.Participants do
		table.insert(participants, self:ViewPartialParticipant(v))
	end

	return participants
end

slayVote.OnServerEvent:Connect(function(plr, target: Player)
	local roundId = ServerStorage:GetAttribute("RoundID")
	if (not roundId) or (typeof(target) ~= "Instance")  then
		return
	end
	if target.ClassName ~= "Player" then
		return
	end

	local round = RoundHandler.GetRound(roundId)
	local voterParticipant = round:TryGetParticipant(plr.Name)
	local targetParticipant = round:TryGetParticipant(target.Name)
	if voterParticipant and targetParticipant then
		targetParticipant:TryAddSlayVote(voterParticipant)
	end
end)

while true do
	local round = RoundHandler.CreateRound(maps[math.random(1, #maps)] :: any, if math.random(1, 5) >= 2 then ThoseYouTrust else Murder)
	ServerStorage:SetAttribute("RoundID", round.ID)

	local function playerAdded(plr: Player)
		if not round:IsRoundInProgress() then
			round:JoinRound(plr)
		end
	end

	local joinCon = Players.PlayerAdded:Connect(playerAdded)
	for _, v in Players:GetPlayers() do
		playerAdded(v)
	end

	round.RoundStartEvent.Event:Wait()
	joinCon:Disconnect()
	round.RoundEndEvent.Event:Wait()
end