--!strict

-- Possession Tracker
-- Tracks who last touched the ball for the caster's selected arena and reports possession % per round.

local Util = require("util")

local Arena = require("arena")
type Arena = Arena.Arena

export type PlayerPossessionStats = {
	name: string,
	seconds: number,
	dribbleMeters: number,
}

type Possession = {
	arena: Arena?,

	contactDistance: number,
	possessionTimeout: number,
	debug: boolean,

	currentToucher: ReplayPlayer?,
	lastToucher: ReplayPlayer?,
	lastTouchTime: number,
	possessionHolder: ReplayPlayer?,

	-- used to measure distance carried by the current possession holder, cleared whenever possession changes hands or goes loose
	lastPossessionHolderId: number?,
	lastPossessionHolderPosition: Vec3?,

	possessionSeconds: { home: number, away: number, loose: number },
	possessionSecondsByPlayer: { [number]: PlayerPossessionStats },

	reset: (self: Possession) -> (),
	setArena: (self: Possession, arena: Arena) -> (),
	printResults: (self: Possession) -> (),
	tick: (self: Possession, dt: number) -> (),
	gui: (self: Possession) -> (),
}

local Possession: Possession = {} :: Possession

Possession.arena = nil
Possession.debug = false

Possession.contactDistance = 30 -- cm, how close a hand/head needs to be to count as a touch
Possession.possessionTimeout = 3 -- seconds without contact before possession goes loose (covers passes/dribbles)

Possession.currentToucher = nil
Possession.lastToucher = nil
Possession.lastTouchTime = -math.huge
Possession.possessionHolder = nil

Possession.lastPossessionHolderId = nil
Possession.lastPossessionHolderPosition = nil

Possession.possessionSeconds = { home = 0, away = 0, loose = 0 }
Possession.possessionSecondsByPlayer = {}

function Possession:setArena(arena: Arena)
	self.arena = arena
	self:reset()
end

function Possession:reset()
	self.currentToucher = nil
	self.lastToucher = nil
	self.lastTouchTime = -math.huge
	self.possessionHolder = nil
	self.lastPossessionHolderId = nil
	self.lastPossessionHolderPosition = nil
	self.possessionSeconds = { home = 0, away = 0, loose = 0 }
	self.possessionSecondsByPlayer = {}
end

function Possession:printResults()
	local total = self.possessionSeconds.home + self.possessionSeconds.away + self.possessionSeconds.loose
	if total <= 0 then
		return
	end

	local homePct = math.floor((self.possessionSeconds.home / total) * 100 + 0.5)
	local awayPct = math.floor((self.possessionSeconds.away / total) * 100 + 0.5)
	local loosePct = math.floor((self.possessionSeconds.loose / total) * 100 + 0.5)

	print(`[Possession] Home: {homePct}% Loose: {loosePct}% Away: {awayPct}%`)

	local players = {}
	for _, playerStats in self.possessionSecondsByPlayer do
		table.insert(players, playerStats)
	end

	table.sort(players, function(a, b)
		return a.seconds > b.seconds
	end)

	for _, playerStats in players do
		local playerPct = math.floor((playerStats.seconds / total) * 100 + 0.5)
		print(`[Possession] {playerStats.name}: {playerPct}%`)
	end
end

function Possession:tick(dt: number)
	local arena = self.arena
	if not arena then
		return
	end

	local previousPossessionId = self.possessionHolder and self.possessionHolder.playerId or nil

	if arena.ball then
		self.currentToucher = Util.isDriftballHeld(arena.ball, Possession.contactDistance, arena.players)
		if self.currentToucher then
			self.lastToucher = self.currentToucher
			self.lastTouchTime = os.clock()
			self.possessionHolder = self.currentToucher
		end
	else
		self.currentToucher = nil
	end

	-- keep possession with the last toucher through passes/dribbles until the timeout elapses
	if self.possessionHolder and os.clock() - self.lastTouchTime > self.possessionTimeout then
		self.possessionHolder = nil
	end

	if self.debug then
		local newPossessionId = self.possessionHolder and self.possessionHolder.playerId or nil
		if newPossessionId ~= previousPossessionId then
			if self.possessionHolder then
				print(`[Possession] {self.possessionHolder.playerName} has possession`)
			elseif self.lastToucher then
				print(`[Possession] Ball is loose - last touched by {self.lastToucher.playerName}`)
			else
				print(`[Possession] Ball is loose - no one has touched it yet`)
			end
		end
	end

	if arena.isGameActive then
		if self.possessionHolder then
			local playerStats = self.possessionSecondsByPlayer[self.possessionHolder.playerId]
			if not playerStats then
				playerStats = { name = self.possessionHolder.playerName, seconds = 0, dribbleMeters = 0 }
				self.possessionSecondsByPlayer[self.possessionHolder.playerId] = playerStats
			end
			playerStats.seconds += dt

			local holderPosition = self.possessionHolder.root.position
			if self.lastPossessionHolderId == self.possessionHolder.playerId and self.lastPossessionHolderPosition then
				playerStats.dribbleMeters += Util.getDist(self.lastPossessionHolderPosition, holderPosition) / 100
			end
			self.lastPossessionHolderId = self.possessionHolder.playerId
			self.lastPossessionHolderPosition = holderPosition

			if self.possessionHolder.teamIndex == Util.TeamIndex.HomeTeam then
				self.possessionSeconds.home += dt
			elseif self.possessionHolder.teamIndex == Util.TeamIndex.AwayTeam then
				self.possessionSeconds.away += dt
			else
				self.possessionSeconds.loose += dt
			end
		else
			self.possessionSeconds.loose += dt
			self.lastPossessionHolderId = nil
			self.lastPossessionHolderPosition = nil
		end
	end

	if not arena.isGameActive and arena.lastIsGameActive and self.debug then
		self:printResults()
	end
end

function Possession:gui()
	Gui.separatorText("Possession Tracker")
	self.possessionTimeout = Gui.sliderFloat("Possession Timeout (sec)", self.possessionTimeout, 0.5, 15)
end

return Possession
