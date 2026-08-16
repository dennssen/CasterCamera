--!strict

local Utils = require("util")
local Possession = require("possession")

local Overlay = {}

type OverlayBall = {
	transform: Transform,
	velocity: Vec3,
}

type Stats = {
	goals: number,
	saves: number,
	assists: number,
	shots: number,
	passes: number,
	possession: number,
	possessionsWon: number,
	possessionsLost: number,
	dribbleMeters: number,
}

type OverlayPlayer = {
	stats: Stats,
	velocity: Vec3,
	transform: Transform,
}

function newStats(): Stats
	return {
		goals = 0,
		saves = 0,
		assists = 0,
		shots = 0,
		passes = 0,
		possession = 0,
		possessionsWon = 0,
		possessionsLost = 0,
		dribbleMeters = 0,
	}
end

function newPlayer(velocity: Vec3, transform: Transform): OverlayPlayer
	return {
		stats = newStats(),
		velocity = Vec3.zeroVector,
		transform = Transform.identity,
	}
end

type ShotInfo = {
	shooter: string,
	assister: string,
	team: number,
	shotSpeed: number,
	shotDistanceMeters: number,
}

type Round = {
	home: number,
	away: number,
}

type OverlayTeam = {
	players: { [string]: OverlayPlayer },
	possession: number,
}

export type PossessionData = {
	possessionSeconds: { home: number, away: number, loose: number },
	possessionSecondsByPlayer: { [number]: Possession.PlayerPossessionStats },
}

type APIStructure = {
	gamemodeId: string,

	home: OverlayTeam,
	away: OverlayTeam,
	arenaSize: Vec3,
	ball: OverlayBall,
	rounds: { Round },
	followedPlayer: string,
	lastShotInfo: ShotInfo,
	isGracePeriod: boolean,
	isOvertime: boolean,
	bestOf: number,
	matchLengthSeconds: number,
}

local api: APIStructure = {
	gamemodeId = "",

	home = {
		players = {},
		possession = 0,
	},
	away = {
		players = {},
		possession = 0,
	},
	arenaSize = Vec3.zeroVector,
	rounds = {},
	ball = {
		transform = Transform.identity,
		velocity = Vec3.zeroVector,
	},
	followedPlayer = "",
	lastShotInfo = {
		shooter = "",
		assister = "",
		team = -1,
		shotSpeed = 0,
		shotDistanceMeters = 0,
	},
	isGracePeriod = false,
	isOvertime = false,
	bestOf = 0,
	matchLengthSeconds = 0,
}

function Overlay.setPossession(data: PossessionData)
	local totalPossession = data.possessionSeconds.home + data.possessionSeconds.away + data.possessionSeconds.loose
	if totalPossession > 0 then
		api.home.possession = data.possessionSeconds.home / totalPossession * 100
		api.away.possession = data.possessionSeconds.away / totalPossession * 100

		for playerId: number, playerStats: Possession.PlayerPossessionStats in data.possessionSecondsByPlayer do
			local playerName = playerStats.name
			local playerPossession = playerStats.seconds / totalPossession

			if api.home.players[playerName] then
				api.home.players[playerName].stats.possession = playerPossession * 100
				api.home.players[playerName].stats.dribbleMeters = playerStats.dribbleMeters
			elseif api.away.players[playerName] then
				api.away.players[playerName].stats.possession = playerPossession * 100
				api.away.players[playerName].stats.dribbleMeters = playerStats.dribbleMeters
			end
		end
	else
		api.home.possession = 0
		api.away.possession = 0
	end
end

function Overlay.setGamemodeId(gamemodeId: string)
	api.gamemodeId = gamemodeId
end

function Overlay.setPlayers(teamIndex: number, players: { ReplayPlayer })
	local team: OverlayTeam = nil

	if teamIndex == Utils.TeamIndex.HomeTeam then
		team = api.home
	elseif teamIndex == Utils.TeamIndex.AwayTeam then
		team = api.away
	end

	if team == nil then
		-- Check for teamIndex NoTeam but also check for any number not in TeamIndex
		return
	end

	-- Save current players
	local currentPlayers: { [string]: boolean } = {}
	for playerName: string, _ in team.players do
		currentPlayers[playerName] = true
	end

	-- Add new players
	for _, player: ReplayPlayer in players do
		local overlayPlayer = team.players[player.playerName]
		local playerTransform: Transform = Transform.new(player.head.position, player.head.rotation, Vec3.oneVector)
		if overlayPlayer == nil then
			team.players[player.playerName] = newPlayer(player.velocity, playerTransform)
		else
			-- update player data
			overlayPlayer.transform = playerTransform
			overlayPlayer.velocity = player.velocity
			currentPlayers[player.playerName] = false
		end
	end

	-- Remove old players
	for playerName: string, remove: boolean in currentPlayers do
		if remove then
			team.players[playerName] = nil
		end
	end
end

function Overlay.setArenaSize(size: Vec3)
	api.arenaSize = size
end

function Overlay.setBall(ball: ReplayBall)
	if not ball then
		return
	end

	local ballTransfrom: Transform = Transform.new(ball.transform.position, ball.transform.rotation, Vec3.oneVector)

	api.ball = {
		transform = ballTransfrom,
		velocity = ball.velocity,
	}
end

function Overlay.clearRounds()
	api.rounds = {}
end

function Overlay.addRound(homeScore: number, awayScore: number)
	table.insert(api.rounds, {
		home = homeScore,
		away = awayScore,
	})
end

function Overlay.clearStats()
	for playerName: string, _ in api.home.players do
		api.home.players[playerName].stats = newStats()
	end

	for playerName: string, _ in api.away.players do
		api.away.players[playerName].stats = newStats()
	end
end

function Overlay.increaseStat(teamIndex: number, playerName: string, stat: string)
	local team: OverlayTeam = nil

	if teamIndex == Utils.TeamIndex.HomeTeam then
		team = api.home
	elseif teamIndex == Utils.TeamIndex.AwayTeam then
		team = api.away
	end

	if team == nil then
		-- Check for teamIndex NoTeam but also check for any number not in TeamIndex
		return
	end

	if team.players[playerName] == nil then
		return
	end

	if team.players[playerName].stats[stat] == nil then
		return
	end

	team.players[playerName].stats[stat] += 1
end

function Overlay.setFollowedPlayer(followedPlayer: string)
	api.followedPlayer = followedPlayer
end

function Overlay.setShotInfo(shotInfo: ShotInfo)
	api.lastShotInfo = shotInfo
end

function Overlay.setIsGracePeriod(isGracePeriod: boolean)
	api.isGracePeriod = isGracePeriod
end

function Overlay.setIsOvertime(isOvertime: boolean)
	api.isOvertime = isOvertime
end

function Overlay.setBestOf(bestOf: number)
	api.bestOf = bestOf
end

function Overlay.setMatchLengthSeconds(matchLengthSeconds: number)
	api.matchLengthSeconds = matchLengthSeconds
end

function Overlay.tick()
	config.api = api
	saveConfig()
end

return Overlay
