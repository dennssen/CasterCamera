--!strict

-- Boost Tracker
-- Owns everything boost related: the pad presets, how arena boost pads are built from their
-- definitions, the per player boost estimate and the debug tools for editing pad placements.

local Util = require("util")

local Box = require("box")

local Arena = require("arena")
type Arena = Arena.Arena
type ArenaBoostPad = Arena.ArenaBoostPad

export type BoostPadPreset = Arena.BoostPadPreset
export type BoostPadDef = Arena.BoostPadDef

-- 4 seconds to use boost
-- small boost gives 22.5% boost, big gives 100%
-- boost cooldowns are 6s for small, 10s for big
-- If you have exact values, use them. These are approximations
local BOOST_DRAIN_SECONDS = 4
local BOOST_DRAIN_PER_SECOND = 100 / BOOST_DRAIN_SECONDS
local MAX_BOOST_PERCENT = 100

local BOOST_PAD_SIZE_PRESETS: { [string]: Vec3 } = {
	small = Vec3.new(77, 77, 50),
	big = Vec3.new(120, 120, 100),
}

local BOOST_PAD_VALUES: { [string]: number } = {
	small = 22.5,
	big = 100,
}

local BOOST_PAD_COOLDOWN_SECONDS: { [string]: number } = {
	small = 6,
	big = 10,
}

local BOOST_PAD_PRESET_NAMES: { BoostPadPreset } = { "small", "big" }
local DEFAULT_BOOST_PAD_PRESET: BoostPadPreset = "small"

type BoostStats = {
	name: string,
	boostPercent: number,
}

export type PlayerBoostStats = { [number]: BoostStats }

type PlayerBoostState = {
	onPad: boolean,
	lastBodyPosition: Vec3?,
	lastHeadPosition: Vec3?,
	lastLeftHandPosition: Vec3?,
	lastRightHandPosition: Vec3?,
}

export type PadContact = {
	pad: ArenaBoostPad,
	padIndex: number,
	part: string,
}

type Boost = {
	arena: Arena?,
	debug: boolean,

	playerStates: { [number]: PlayerBoostState },
	statsByPlayer: PlayerBoostStats,
	padAvailableAt: { [number]: number },

	padEditorPreset: BoostPadPreset,
	padEditorMessage: string,

	resolvePadSize: (preset: string) -> Vec3,
	buildArenaPads: (transform: Transform, defs: { BoostPadDef }) -> { ArenaBoostPad },

	reset: (self: Boost) -> (),
	setArena: (self: Boost, arena: Arena) -> (),
	isTracking: (self: Boost, arena: Arena) -> boolean,
	refillEveryone: (self: Boost) -> (),
	getPlayerState: (self: Boost, player: ReplayPlayer) -> PlayerBoostState,
	getPlayerStats: (self: Boost, player: ReplayPlayer) -> BoostStats,
	isPadAvailable: (self: Boost, padIndex: number) -> boolean,
	getPlayerPadContact: (self: Boost, player: ReplayPlayer, state: PlayerBoostState) -> PadContact?,
	collectPad: (self: Boost, player: ReplayPlayer, contact: PadContact) -> (),
	tick: (self: Boost, dt: number) -> (),
	gui: (self: Boost) -> (),
	addPadAtCamera: (self: Boost, arena: Arena, preset: BoostPadPreset) -> string,
	padEditorGui: (self: Boost, arena: Arena) -> boolean,
}

local Boost: Boost = {} :: Boost

Boost.arena = nil
Boost.debug = false

Boost.playerStates = {}
Boost.statsByPlayer = {}
Boost.padAvailableAt = {}

Boost.padEditorPreset = DEFAULT_BOOST_PAD_PRESET
Boost.padEditorMessage = ""

function Boost.resolvePadSize(preset: string): Vec3
	local size: Vec3? = BOOST_PAD_SIZE_PRESETS[preset]

	if not size then
		error(`Invalid boost pad preset name: {preset}`)
	end

	return size
end

function Boost.buildArenaPads(transform: Transform, defs: { BoostPadDef }): { ArenaBoostPad }
	local pads: { ArenaBoostPad } = {}

	for _, def in defs do
		table.insert(pads, {
			box = Box.new(
				transform.position + transform.rotation:rotateVector(def.position),
				Boost.resolvePadSize(def.preset),
				transform.rotation
			),
			preset = def.preset,
		})
	end

	return pads
end

function Boost:setArena(arena: Arena)
	self.arena = arena
	self:reset()
end

-- Only the caster's selected arena is tracked, so arena events from any other arena are ignored
function Boost:isTracking(arena: Arena): boolean
	return self.arena == arena
end

function Boost:reset()
	self.playerStates = {}
	self.statsByPlayer = {}
	self.padAvailableAt = {}
end

function Boost:getPlayerState(player: ReplayPlayer): PlayerBoostState
	local state = self.playerStates[player.playerId]

	if not state then
		state = { onPad = false }
		self.playerStates[player.playerId] = state
	end

	return state
end

function Boost:getPlayerStats(player: ReplayPlayer): BoostStats
	local playerStats = self.statsByPlayer[player.playerId]

	if not playerStats then
		-- players spawn with full boost, so anyone we have not seen before starts topped up
		playerStats = { name = player.playerName, boostPercent = MAX_BOOST_PERCENT }
		self.statsByPlayer[player.playerId] = playerStats
	end

	playerStats.name = player.playerName

	return playerStats
end

function Boost:refillEveryone()
	local arena = self.arena
	if not arena then
		return
	end

	for _, player: ReplayPlayer in arena.players do
		local playerStats = self:getPlayerStats(player)
		playerStats.boostPercent = MAX_BOOST_PERCENT

		if self.debug then
			print(`[Boost] {player.playerName} refilled to {MAX_BOOST_PERCENT}%`)
		end
	end
end

function Boost:isPadAvailable(padIndex: number): boolean
	return os.clock() >= (self.padAvailableAt[padIndex] or 0)
end

function Boost:getPlayerPadContact(player: ReplayPlayer, state: PlayerBoostState): PadContact?
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

	if not arena then
		return nil
	end

	for padIndex, pad in arena.boostPads do
		for _, point in points do
			if pad.box:checkSegmentIntersect(point.lastPosition, point.position) then
				return { pad = pad, padIndex = padIndex, part = point.part }
			end
		end
	end

	return nil
end

function Boost:collectPad(player: ReplayPlayer, contact: PadContact)
	local preset = contact.pad.preset
	local playerStats = self:getPlayerStats(player)

	if not self:isPadAvailable(contact.padIndex) then
		if self.debug then
			local secondsLeft = self.padAvailableAt[contact.padIndex] - os.clock()
			print(`[Boost] {player.playerName} touched a {preset} boost pad on cooldown ({secondsLeft}s left)`)
		end
		return
	end

	if playerStats.boostPercent >= MAX_BOOST_PERCENT then
		if self.debug then
			print(
				`[Boost] {player.playerName} touched a {preset} boost pad already at {MAX_BOOST_PERCENT}%, pad not used`
			)
		end
		return
	end

	local gain = BOOST_PAD_VALUES[preset] or 0
	playerStats.boostPercent = math.min(MAX_BOOST_PERCENT, playerStats.boostPercent + gain)
	self.padAvailableAt[contact.padIndex] = os.clock() + (BOOST_PAD_COOLDOWN_SECONDS[preset] or 0)

	if self.debug then
		print(
			`[Boost] {player.playerName} touched a {preset} boost pad with {contact.part} (+{gain}%, now {playerStats.boostPercent}%)`
		)
	end
end

function Boost:tick(dt: number)
	local arena = self.arena
	if not arena then
		return
	end

	for _, player: ReplayPlayer in arena.players do
		local state = self:getPlayerState(player)
		local playerStats = self:getPlayerStats(player)

		local contact = self:getPlayerPadContact(player, state)
		if contact and not state.onPad then
			self:collectPad(player, contact)
		end
		state.onPad = contact ~= nil

		local isBoosting = player.leftThrusterActive or player.rightThrusterActive
		if arena.isGameActive and isBoosting then
			playerStats.boostPercent = math.max(0, playerStats.boostPercent - BOOST_DRAIN_PER_SECOND * dt)
		end
	end
end

function Boost:gui()
	Gui.separatorText("Boost Tracker")
	self.debug = Gui.checkbox("Boost Debug", self.debug)

	local players = {}
	for _, playerStats in self.statsByPlayer do
		table.insert(players, playerStats)
	end

	table.sort(players, function(a, b)
		return a.boostPercent > b.boostPercent
	end)

	if Gui.beginTable("BoostStats", 2) then
		Gui.tableSetupColumn("Player")
		Gui.tableSetupColumn("Boost %")
		Gui.tableHeadersRow()

		for _, playerStats in players do
			Gui.tableNextRow()
			Gui.tableNextColumn()
			Gui.text(playerStats.name)
			Gui.tableNextColumn()
			Gui.text(`{math.floor(playerStats.boostPercent + 0.5)}%`)
		end
		Gui.endTable()
	end
end

function Boost:addPadAtCamera(arena: Arena, preset: BoostPadPreset): string
	local localOffset = arena.transform.rotation:inverse():rotateVector(camera.position - arena.transform.position)

	table.insert(arena.boostPadDefs, { position = localOffset, preset = preset })

	return `Added {preset} boost pad #{#arena.boostPadDefs} to {arena.type}`
end

-- Debug only editor for placing boost pads, returns true when the pads of the arena type changed
function Boost:padEditorGui(arena: Arena): boolean
	local defs = arena.boostPadDefs
	local changed = false

	Gui.text("Positions are arena relative and shared by every arena of this type")

	if Gui.beginCombo("Preset To Add", self.padEditorPreset) then
		for _, preset in BOOST_PAD_PRESET_NAMES do
			if Gui.selectable(preset, self.padEditorPreset == preset) then
				self.padEditorPreset = preset
			end
		end
		Gui.endCombo()
	end

	if Gui.button("Add Boost Pad At Camera") then
		self.padEditorMessage = self:addPadAtCamera(arena, self.padEditorPreset)
		changed = true
	end
	Gui.setItemTooltip("Adds a boost pad at your current camera position for this arena type")

	if Gui.button("Print Boost Pads") then
		for i, def in defs do
			print(`boostPadDefs[{i}]: {def.preset} at {def.position}`)
		end
	end

	if self.padEditorMessage ~= "" then
		Gui.text(self.padEditorMessage)
	end

	Gui.newLine()

	local removeIndex: number? = nil

	for i, def in defs do
		if i ~= 1 then
			Gui.separator()
		end
		Gui.text(`Boost Pad #{i}`)

		def.position = Gui.dragFloat3(`Position##boostPad{i}`, def.position, 1, -math.huge, math.huge)
		if Gui.isItemActive() then
			changed = true
		end
		Gui.setItemTooltip("Drag to move this boost pad")

		if Gui.beginCombo(`Preset##boostPad{i}`, def.preset) then
			for _, preset in BOOST_PAD_PRESET_NAMES do
				if Gui.selectable(`{preset}##boostPad{i}`, def.preset == preset) then
					def.preset = preset
					changed = true
				end
			end
			Gui.endCombo()
		end

		if Gui.button(`Remove##boostPad{i}`) then
			removeIndex = i
		end
	end

	if removeIndex then
		table.remove(defs, removeIndex)
		self.padEditorMessage = `Removed boost pad #{removeIndex}`
		changed = true
	end

	return changed
end

return {
	Boost = Boost,
	padSizes = BOOST_PAD_SIZE_PRESETS,
	padValues = BOOST_PAD_VALUES,
	padCooldownSeconds = BOOST_PAD_COOLDOWN_SECONDS,
	padPresetNames = BOOST_PAD_PRESET_NAMES,
	defaultPadPreset = DEFAULT_BOOST_PAD_PRESET,
}
