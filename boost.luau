--!strict

local Util = require("util")

local Arena = require("arena")
type Arena = Arena.Arena

-- 4 seconds to use boost
-- small boost gives 22.5% boost, big gives 100%
-- boost cooldowns are 6s for small, 10s for big
-- If you have exact values, use them. These are approximations
local BOOST_DRAIN_SECONDS = 4
local BOOST_DRAIN_PER_SECOND = 100 / BOOST_DRAIN_SECONDS
local BOOST_PAD_VALUES: { [string]: number } = {
	small = 22.5,
	big = 100,
}

local BOOST_PAD_COOLDOWN_SECONDS: { [string]: number } = {
	small = 6,
	big = 10,
}

export type PlayerBoostStats = {
	name: string,
	boostPercent: number,
}

type PlayerBoostState = {
	onPad: boolean,
	lastBodyPosition: Vec3?,
	lastHeadPosition: Vec3?,
	lastLeftHandPosition: Vec3?,
	lastRightHandPosition: Vec3?,
}

type Boost = {
	arena: Arena?,
	debug: boolean,

	playerStates: { [number]: PlayerBoostState },
	statsByPlayer: { [number]: PlayerBoostStats },
	padAvailableAt: { [number]: number },
	wasOvertime: boolean,

	reset: (self: Boost) -> (),
	setArena: (self: Boost, arena: Arena) -> (),
	getPlayerPadContact: (
		self: Boost,
		player: ReplayPlayer,
		state: PlayerBoostState
	) -> (boolean, string?, string?, number?),
	tick: (self: Boost, dt: number) -> (),
	gui: (self: Boost) -> (),
}

local Boost: Boost = {} :: Boost

Boost.arena = nil
Boost.debug = false

Boost.playerStates = {}
Boost.statsByPlayer = {}
Boost.padAvailableAt = {}
Boost.wasOvertime = false

function Boost:setArena(arena: Arena)
	self.arena = arena
	self:reset()
end

function Boost:reset()
	self.playerStates = {}
	self.statsByPlayer = {}
	self.padAvailableAt = {}
	self.wasOvertime = false
end

function Boost:getPlayerPadContact(player: ReplayPlayer, state: PlayerBoostState): (boolean, string?, string?, number?)
	local arena = self.arena

	local bodyPosition = player.root.position
	local headPosition = player.head.position
	local leftHandPosition = Util.getLeftPlayerHand(player).position
	local rightHandPosition = Util.getRightPlayerHand(player).position

	local points = {
		{ position = bodyPosition, lastPosition = state.lastBodyPosition or bodyPosition, part = "body" },
		{ position = headPosition, lastPosition = state.lastHeadPosition or headPosition, part = "head" },
		{
			position = leftHandPosition,
			lastPosition = state.lastLeftHandPosition or leftHandPosition,
			part = "leftHand",
		},
		{
			position = rightHandPosition,
			lastPosition = state.lastRightHandPosition or rightHandPosition,
			part = "rightHand",
		},
	}

	state.lastBodyPosition = bodyPosition
	state.lastHeadPosition = headPosition
	state.lastLeftHandPosition = leftHandPosition
	state.lastRightHandPosition = rightHandPosition

	if not arena or #arena.boostPads == 0 then
		return false, nil, nil, nil
	end

	for i, pad in arena.boostPads do
		for _, point in points do
			if pad.box:checkSegmentIntersect(point.lastPosition, point.position) then
				return true, point.part, pad.preset, i
			end
		end
	end

	return false, nil, nil, nil
end

function Boost:tick(dt: number)
	local arena = self.arena
	if not arena then
		return
	end

	local isGameStarting = arena.isGameActive and not arena.lastIsGameActive
	if isGameStarting then
		self:reset()
	end

	local isOvertimeStarting = arena.isOvertime and not self.wasOvertime
	self.wasOvertime = arena.isOvertime

	local goalScored = arena.home.scoreIncrease or arena.away.scoreIncrease

	local refillEveryone = isGameStarting or isOvertimeStarting or goalScored

	for _, player: ReplayPlayer in arena.players do
		local state = self.playerStates[player.playerId]
		if not state then
			state = { onPad = false }
			self.playerStates[player.playerId] = state
		end

		local stats = self.statsByPlayer[player.playerId]
		if not stats then
			stats = { name = player.playerName, boostPercent = 0 }
			self.statsByPlayer[player.playerId] = stats
		end
		stats.name = player.playerName

		if refillEveryone then
			stats.boostPercent = 100

			if self.debug then
				local reason = isGameStarting and "game start" or (isOvertimeStarting and "overtime" or "goal scored")
				print(`[Boost] {player.playerName} refilled to 100% ({reason})`)
			end
		end

		local touchingPad, touchingPart, touchedPreset, padIndex = self:getPlayerPadContact(player, state)
		if touchingPad and not state.onPad then
			local now = os.clock()
			local availableAt = (padIndex and self.padAvailableAt[padIndex]) or 0

			if now >= availableAt then
				if stats.boostPercent < 100 then
					local gain = (touchedPreset and BOOST_PAD_VALUES[touchedPreset]) or 0
					stats.boostPercent = math.min(100, stats.boostPercent + gain)

					if padIndex and touchedPreset then
						self.padAvailableAt[padIndex] = now + (BOOST_PAD_COOLDOWN_SECONDS[touchedPreset] or 0)
					end

					if self.debug then
						print(
							`[Boost] {player.playerName} touched a {touchedPreset} boost pad with {touchingPart} (+{gain}%, now {stats.boostPercent}%)`
						)
					end
				elseif self.debug then
					print(
						`[Boost] {player.playerName} touched a {touchedPreset} boost pad already at 100%, pad not used`
					)
				end
			elseif self.debug then
				print(
					`[Boost] {player.playerName} touched a {touchedPreset} boost pad on cooldown ({availableAt - now}s left)`
				)
			end
		end
		state.onPad = touchingPad

		local isBoosting = player.leftThrusterActive or player.rightThrusterActive
		if arena.isGameActive and isBoosting then
			stats.boostPercent = math.max(0, stats.boostPercent - BOOST_DRAIN_PER_SECOND * dt)
		end
	end
end

function Boost:gui()
	Gui.separatorText("Boost Tracker")
	self.debug = Gui.checkbox("Boost Debug", self.debug)

	local players = {}
	for _, stats in self.statsByPlayer do
		table.insert(players, stats)
	end

	table.sort(players, function(a, b)
		return a.boostPercent > b.boostPercent
	end)

	if Gui.beginTable("BoostStats", 2) then
		Gui.tableSetupColumn("Player")
		Gui.tableSetupColumn("Boost %")
		Gui.tableHeadersRow()

		for _, stats in players do
			Gui.tableNextRow()
			Gui.tableNextColumn()
			Gui.text(stats.name)
			Gui.tableNextColumn()
			Gui.text(`{math.floor(stats.boostPercent + 0.5)}%`)
		end
		Gui.endTable()
	end
end

return Boost
