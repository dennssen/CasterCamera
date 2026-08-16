--!strict

local Box = require("box")
type BoxType = typeof(Box)

local Util = require("util")
-- Overlay and Possession are not required here because requiring them twice creates two separate instances.
-- Call Gamemodes.init(overlay, profiler, possession) from main after requiring the modules.
local Overlay: typeof(require("overlay")) = nil :: any
local Possession: typeof(require("possession")) = nil :: any
local Arena = require("arena")

local centerBoxSize = Vec3.new(50, 50, 125)
local debuging = {
	bestOfAmount = 0,
}

export type BoostPadDef = {
	position: Vec3,
	preset: string, -- "small" or "big"
}

local DEFAULT_BOOST_PAD_SIZE = {
	["small"] = Vec3.new(77, 77, 50),
	["big"] = Vec3.new(120, 120, 100),
}

local function resolveBoostPadSize(preset: string): Vec3
	local presets = config.boostPadPresets
	if presets and presets[preset] then
		return presets[preset]
	end
	return DEFAULT_BOOST_PAD_SIZE[preset] or Vec3.new(60, 60, 15)
end

export type OverviewData = {
	overview: { { position: Vec3, rotation: Quat } },
}
type ArenaTeam = Arena.ArenaTeam<OverviewData>

export type CasterArena = Arena.Arena<{}, OverviewData, OverviewData> & {
	__index: CasterArena,
	new: (gamemode: ModuleStateSpectatorLuaApi, frameIndex: number) -> CasterArena,
	sendInfoMessage: (self: CasterArena) -> (),
	setupOverviews: (self: CasterArena) -> (),
}

local CasterArena = {} :: CasterArena
CasterArena.__index = CasterArena
setmetatable(CasterArena, { __index = Arena })

function CasterArena.new(gamemode: ModuleStateSpectatorLuaApi, frameIndex: number): CasterArena
	local self = Arena.new(gamemode, frameIndex)
	return setmetatable(self, CasterArena) :: any
end

function CasterArena:onGameStartHook()
	Possession:reset()
	Overlay.clearStats()
	Overlay.clearRounds()
end

function CasterArena:onRoundStartHook() end

function CasterArena:onRoundEndHook(isRestart: boolean, homeScore: number, awayScore: number)
	if not isRestart then
		Overlay.addRound(homeScore, awayScore)
	end
end

function CasterArena:postTickHook()
	(self :: CasterArena):sendInfoMessage()
end

function CasterArena:sendInfoMessage()
	Overlay.setBall(self.ball)

	Overlay.setPlayers(self.home.teamIndex, self.home.players)
	Overlay.setPlayers(self.away.teamIndex, self.away.players)

	Overlay.setIsOvertime(self.isOvertime)
	Overlay.setIsGracePeriod(self.isGracePeriod)
	Overlay.setBestOf(self.bestOfAmount ~= 0 and self.bestOfAmount or debuging.bestOfAmount)
	Overlay.setMatchLengthSeconds(self.matchLengthSeconds)
end

-- Arena3v3 --

export type Arena3v3 = CasterArena & {
	__index: Arena3v3,
	new: (gamemode: ModuleStateSpectatorLuaApi, frameIndex: number) -> Arena3v3,
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
	boostPadDefs: { BoostPadDef },
}

local Arena3v3 = {} :: Arena3v3
Arena3v3.__index = Arena3v3
setmetatable(Arena3v3, { __index = CasterArena })

Arena3v3.homeRotationOffset = Quat.fromEuler(0, 0, 90)
Arena3v3.awayRotationOffset = Quat.fromEuler(0, 0, -90)
Arena3v3.boxSize = Vec3.new(5100, 6750, 1440)
Arena3v3.boxOffset = Vec3.new(0, 0, 650)
Arena3v3.centerBoxOffset = Vec3.new(0, 0, 300)
Arena3v3.goalBoxSize = Vec3.new(150, 500, 225)
Arena3v3.goalPositionOffset = Vec3.new(3250, 0, 175)
Arena3v3.boostPadDefs = {} :: { BoostPadDef }

function Arena3v3.new(gamemode: ModuleStateSpectatorLuaApi, frameIndex: number): Arena3v3
	local self: CasterArena = setmetatable(CasterArena.new(gamemode, frameIndex), Arena3v3) :: any
	self.type = "3v3"
	self.name = self.slotId:gsub("TKB_", "")
	self.home.data = { overview = {} }
	self.away.data = { overview = {} }
	self:setupDimensions()
	self:setupOverviews()
	return self :: Arena3v3
end

function Arena3v3:isPointOnHomeSide(point: Vec3): boolean
	local homeDirection = self:getTeamRotation(Util.TeamIndex.HomeTeam):getForwardVector()
	local ballDirection = Util.getForward(self.transform.position, point)
	return homeDirection:dot(ballDirection) >= 0
end

function Arena3v3:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Arena3v3.boxOffset),
		Arena3v3.boxSize,
		self.transform.rotation
	)

	self.centerBox = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Arena3v3.centerBoxOffset),
		centerBoxSize,
		self.transform.rotation
	)

	self.home.goal = {
		position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
			:rotateVector(Arena3v3.goalPositionOffset),
		rotation = self.transform.rotation * Arena3v3.homeRotationOffset:inverse(),
		box = Box.empty,
	}
	self.home.goal.box = Box.new(self.home.goal.position, Arena3v3.goalBoxSize, self.home.goal.rotation)

	self.away.goal = {
		position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
			:rotateVector(Arena3v3.goalPositionOffset),
		rotation = self.transform.rotation * Arena3v3.awayRotationOffset:inverse(),
		box = Box.empty,
	}
	self.away.goal.box = Box.new(self.away.goal.position, Arena3v3.goalBoxSize, self.away.goal.rotation)

	self.boostPads = {}
	for _, def in Arena3v3.boostPadDefs do
		table.insert(self.boostPads, {
			box = Box.new(
				self.transform.position + self.transform.rotation:rotateVector(def.position),
				resolveBoostPadSize(def.preset),
				self.transform.rotation
			),
			preset = def.preset,
		})
	end
end

function Arena3v3:setupOverviews()
	self.home.data.overview = {}
	self.away.data.overview = {}

	for _, overview in config.overviewOffsets._3v3 do
		table.insert(self.home.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.HomeTeam) * overview.rotation,
		})
		table.insert(self.away.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.AwayTeam) * overview.rotation,
		})
	end
end

function Arena3v3:getTeamRotation(teamIndex: number): Quat
	if teamIndex == Util.TeamIndex.HomeTeam then
		return self.transform.rotation * Arena3v3.homeRotationOffset
	elseif teamIndex == Util.TeamIndex.AwayTeam then
		return self.transform.rotation * Arena3v3.awayRotationOffset
	end
	return Quat.identity
end

function Arena3v3:GUIChangeDimensions()
	Arena3v3.boxSize = Gui.dragFloat3("Arena3v3 Arena Size", Arena3v3.boxSize, 1, -math.huge, math.huge)
	Arena3v3.boxOffset = Gui.dragFloat3("Arena3v3 Position Offset", Arena3v3.boxOffset, 1, -math.huge, math.huge)
	Arena3v3.centerBoxOffset =
		Gui.dragFloat3("Arena3v3 Place Ball Box Position Offset", Arena3v3.centerBoxOffset, 1, -math.huge, math.huge)
	Arena3v3.goalBoxSize = Gui.dragFloat3("Arena3v3 Goal Size", Arena3v3.goalBoxSize, 1, -math.huge, math.huge)
	Arena3v3.goalPositionOffset =
		Gui.dragFloat3("Arena3v3 Goal Position Offset", Arena3v3.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Arena3v3.boxSize}`)
		print(`boxOffset: {Arena3v3.boxOffset}`)
		print(`centerBoxOffset: {Arena3v3.centerBoxOffset}`)
		print(`goalBoxSize: {Arena3v3.goalBoxSize}`)
		print(`goalPositionOffset: {Arena3v3.goalPositionOffset}`)
		for i, def in Arena3v3.boostPadDefs do
			print(`boostPadDefs[{i}]: {def.preset} at {def.position}`)
		end
	end

	self:setupDimensions()
end

-- Arena4v4 --

export type Arena4v4 = CasterArena & {
	__index: Arena4v4,
	new: (gamemode: ModuleStateSpectatorLuaApi, frameIndex: number) -> Arena4v4,
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
	boostPadDefs: { BoostPadDef },
}

local Arena4v4 = {} :: Arena4v4
Arena4v4.__index = Arena4v4
setmetatable(Arena4v4, { __index = CasterArena })

Arena4v4.homeRotationOffset = Quat.fromEuler(0, 0, 90)
Arena4v4.awayRotationOffset = Quat.fromEuler(0, 0, -90)
Arena4v4.boxSize = Vec3.new(6715, 8400, 1490)
Arena4v4.boxOffset = Vec3.new(0, 0, 685)
Arena4v4.centerBoxOffset = Vec3.new(0, 0, 435)
Arena4v4.goalBoxSize = Vec3.new(165, 450, 225)
Arena4v4.goalPositionOffset = Vec3.new(4085, 0, 270)
Arena4v4.boostPadDefs = {
	{ position = Vec3.new(-1501, -3475, 180), preset = "big" },
	{ position = Vec3.new(0, -3700, 170), preset = "small" },
	{ position = Vec3.new(800, -2975, 139), preset = "small" },
	{ position = Vec3.new(-800, -2975, 139), preset = "small" },
	{ position = Vec3.new(1501, -3475, 180), preset = "big" },
	{ position = Vec3.new(2400, -900, 417), preset = "small" },
	{ position = Vec3.new(2400, 0, 417), preset = "small" },
	{ position = Vec3.new(2400, 900, 417), preset = "small" },
	{ position = Vec3.new(0, 500, 37), preset = "small" },
	{ position = Vec3.new(0, 0, 150), preset = "small" },
	{ position = Vec3.new(-500, 0, 37), preset = "small" },
	{ position = Vec3.new(0, -500, 37), preset = "small" },
	{ position = Vec3.new(500, 0, 37), preset = "small" },
	{ position = Vec3.new(1330, 0, 550), preset = "small" },
	{ position = Vec3.new(705, -660, 425), preset = "small" },
	{ position = Vec3.new(-6, -1170, 698), preset = "small" },
	{ position = Vec3.new(-1360, 0, 555), preset = "small" },
	{ position = Vec3.new(-703, 656, 426), preset = "small" },
	{ position = Vec3.new(-8, 1171, 697), preset = "small" },
	{ position = Vec3.new(-1501, 3475, 180), preset = "big" },
	{ position = Vec3.new(1501, 3475, 180), preset = "big" },
	{ position = Vec3.new(0, 3700, 170), preset = "small" },
	{ position = Vec3.new(800, 2975, 139), preset = "small" },
	{ position = Vec3.new(-800, 2975, 139), preset = "small" },
	{ position = Vec3.new(-2450, 0, 417), preset = "small" },
	{ position = Vec3.new(-2450, 900, 417), preset = "small" },
	{ position = Vec3.new(-2450, -900, 417), preset = "small" },
} :: { BoostPadDef }

function Arena4v4.new(gamemode: ModuleStateSpectatorLuaApi, frameIndex: number): Arena4v4
	local self: Arena4v4 = setmetatable(Arena.new(gamemode, frameIndex), Arena4v4) :: any
	self.type = "4v4"

	local name: string = ""
	if self.slotId:find("TKB_") then
		name = self.slotId:gsub("TKB_", "")
	elseif self.slotId:find("_") then
		local nameEnd = self.slotId:find("_") :: number
		name = `{self.slotId:sub(1, nameEnd - 1)} {self.slotId:sub(self.slotId:len() - 2)}`
	else
		name = self.slotId
	end

	self.name = name
	self.home.data = { overview = {} }
	self.away.data = { overview = {} }
	self:setupDimensions()
	self:setupOverviews()
	return self :: Arena4v4
end

function Arena4v4:isPointOnHomeSide(point: Vec3): boolean
	local homeDirection = self:getTeamRotation(Util.TeamIndex.HomeTeam):getForwardVector()
	local ballDirection = Util.getForward(self.transform.position, point)
	return homeDirection:dot(ballDirection) >= 0
end

function Arena4v4:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Arena4v4.boxOffset),
		Arena4v4.boxSize,
		self.transform.rotation
	)

	self.centerBox = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Arena4v4.centerBoxOffset),
		centerBoxSize,
		self.transform.rotation
	)

	self.home.goal = {
		position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
			:rotateVector(Arena4v4.goalPositionOffset),
		rotation = self.transform.rotation * Arena4v4.homeRotationOffset:inverse(),
		box = Box.empty,
	}
	self.home.goal.box = Box.new(self.home.goal.position, Arena4v4.goalBoxSize, self.home.goal.rotation)

	self.away.goal = {
		position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
			:rotateVector(Arena4v4.goalPositionOffset),
		rotation = self.transform.rotation * Arena4v4.awayRotationOffset:inverse(),
		box = Box.empty,
	}
	self.away.goal.box = Box.new(self.away.goal.position, Arena4v4.goalBoxSize, self.away.goal.rotation)

	self.boostPads = {}
	for _, def in Arena4v4.boostPadDefs do
		table.insert(self.boostPads, {
			box = Box.new(
				self.transform.position + self.transform.rotation:rotateVector(def.position),
				resolveBoostPadSize(def.preset),
				self.transform.rotation
			),
			preset = def.preset,
		})
	end
end

function Arena4v4:setupOverviews()
	self.home.data.overview = {}
	self.away.data.overview = {}

	for _, overview in config.overviewOffsets._4v4 do
		table.insert(self.home.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.HomeTeam) * overview.rotation,
		})
		table.insert(self.away.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.AwayTeam) * overview.rotation,
		})
	end
end

function Arena4v4:getTeamRotation(teamIndex: number?): Quat
	if teamIndex == Util.TeamIndex.HomeTeam then
		return self.transform.rotation * Arena4v4.homeRotationOffset
	elseif teamIndex == Util.TeamIndex.AwayTeam then
		return self.transform.rotation * Arena4v4.awayRotationOffset
	end
	return Quat.identity
end

function Arena4v4:GUIChangeDimensions()
	Arena4v4.boxSize = Gui.dragFloat3("Arena4v4 Arena Size", Arena4v4.boxSize, 1, -math.huge, math.huge)
	Arena4v4.boxOffset = Gui.dragFloat3("Arena4v4 Position Offset", Arena4v4.boxOffset, 1, -math.huge, math.huge)
	Arena4v4.centerBoxOffset =
		Gui.dragFloat3("Arena4v4 Place Ball Box Position Offset", Arena4v4.centerBoxOffset, 1, -math.huge, math.huge)
	Arena4v4.goalBoxSize = Gui.dragFloat3("Arena4v4 Goal Size", Arena4v4.goalBoxSize, 1, -math.huge, math.huge)
	Arena4v4.goalPositionOffset =
		Gui.dragFloat3("Arena4v4 Goal Position Offset", Arena4v4.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Arena4v4.boxSize}`)
		print(`boxOffset: {Arena4v4.boxOffset}`)
		print(`centerBoxOffset: {Arena4v4.centerBoxOffset}`)
		print(`goalBoxSize: {Arena4v4.goalBoxSize}`)
		print(`goalPositionOffset: {Arena4v4.goalPositionOffset}`)
		for i, def in Arena4v4.boostPadDefs do
			print(`boostPadDefs[{i}]: {def.preset} at {def.position}`)
		end
	end

	self:setupDimensions()
end

-- Driftblitz --

export type Driftblitz = CasterArena & {
	__index: Driftblitz,
	new: (gamemode: ModuleStateSpectatorLuaApi, frameIndex: number) -> Driftblitz,
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
	boostPadDefs: { BoostPadDef },
}

local Driftblitz = {} :: Driftblitz
Driftblitz.__index = Driftblitz
setmetatable(Driftblitz, { __index = CasterArena })

Driftblitz.homeRotationOffset = Quat.fromEuler(0, 0, 90)
Driftblitz.awayRotationOffset = Quat.fromEuler(0, 0, -90)
Driftblitz.boxSize = Vec3.new(7270, 11825, 1440)
Driftblitz.boxOffset = Vec3.new(0, 0, 740)
Driftblitz.centerBoxOffset = Vec3.new(0, 0, 100)
Driftblitz.goalBoxSize = Vec3.new(100, 890, 300)
Driftblitz.goalPositionOffset = Vec3.new(5295, 0, 175)
Driftblitz.boostPadDefs = {} :: { BoostPadDef }

function Driftblitz.new(gamemode: ModuleStateSpectatorLuaApi, frameIndex: number): Driftblitz
	local self: Driftblitz = setmetatable(Arena.new(gamemode, frameIndex), Driftblitz) :: any
	self.name = self.slotId
	self.type = "driftblitz"
	self.home.data = { overview = {} }
	self.away.data = { overview = {} }
	self:setupDimensions()
	self:setupOverviews()
	return self :: Driftblitz
end

function Driftblitz:isPointOnHomeSide(point: Vec3): boolean
	local homeDirection = self:getTeamRotation(Util.TeamIndex.HomeTeam):getForwardVector()
	local ballDirection = Util.getForward(self.transform.position, point)
	return homeDirection:dot(ballDirection) >= 0
end

function Driftblitz:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Driftblitz.boxOffset),
		Driftblitz.boxSize,
		self.transform.rotation
	)

	self.centerBox = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Driftblitz.centerBoxOffset),
		centerBoxSize,
		self.transform.rotation
	)

	self.home.goal = {
		position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
			:rotateVector(Driftblitz.goalPositionOffset),
		rotation = self.transform.rotation * Driftblitz.homeRotationOffset:inverse(),
		box = Box.empty,
	}
	self.home.goal.box = Box.new(self.home.goal.position, Driftblitz.goalBoxSize, self.home.goal.rotation)

	self.away.goal = {
		position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
			:rotateVector(Driftblitz.goalPositionOffset),
		rotation = self.transform.rotation * Driftblitz.awayRotationOffset:inverse(),
		box = Box.empty,
	}
	self.away.goal.box = Box.new(self.away.goal.position, Driftblitz.goalBoxSize, self.away.goal.rotation)

	self.boostPads = {}
	for _, def in Driftblitz.boostPadDefs do
		table.insert(self.boostPads, {
			box = Box.new(
				self.transform.position + self.transform.rotation:rotateVector(def.position),
				resolveBoostPadSize(def.preset),
				self.transform.rotation
			),
			preset = def.preset,
		})
	end
end

function Driftblitz:setupOverviews()
	self.home.data.overview = {}
	self.away.data.overview = {}

	for _, overview in config.overviewOffsets._driftblitz do
		table.insert(self.home.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.HomeTeam) * overview.rotation,
		})
		table.insert(self.away.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.AwayTeam) * overview.rotation,
		})
	end
end

function Driftblitz:getTeamRotation(teamIndex: number): Quat
	if teamIndex == Util.TeamIndex.HomeTeam then
		return self.transform.rotation * Driftblitz.homeRotationOffset
	elseif teamIndex == Util.TeamIndex.AwayTeam then
		return self.transform.rotation * Driftblitz.awayRotationOffset
	end
	return Quat.identity
end

function Driftblitz:GUIChangeDimensions()
	Driftblitz.boxSize = Gui.dragFloat3("Driftblitz Arena Size", Driftblitz.boxSize, 1, -math.huge, math.huge)
	Driftblitz.boxOffset = Gui.dragFloat3("Driftblitz Position Offset", Driftblitz.boxOffset, 1, -math.huge, math.huge)
	Driftblitz.centerBoxOffset = Gui.dragFloat3(
		"Driftblitz Place Ball Box Position Offset",
		Driftblitz.centerBoxOffset,
		1,
		-math.huge,
		math.huge
	)
	Driftblitz.goalBoxSize = Gui.dragFloat3("Driftblitz Goal Size", Driftblitz.goalBoxSize, 1, -math.huge, math.huge)
	Driftblitz.goalPositionOffset =
		Gui.dragFloat3("Driftblitz Goal Position Offset", Driftblitz.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Driftblitz.boxSize}`)
		print(`boxOffset: {Driftblitz.boxOffset}`)
		print(`centerBoxOffset: {Driftblitz.centerBoxOffset}`)
		print(`goalBoxSize: {Driftblitz.goalBoxSize}`)
		print(`goalPositionOffset: {Driftblitz.goalPositionOffset}`)
		for i, def in Driftblitz.boostPadDefs do
			print(`boostPadDefs[{i}]: {def.preset} at {def.position}`)
		end
	end

	self:setupDimensions()
end

-- ZDrift --

export type ZDrift = CasterArena & {
	__index: ZDrift,
	new: (gamemode: ModuleStateSpectatorLuaApi, frameIndex: number) -> ZDrift,
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
	boostPadDefs: { BoostPadDef },
}

local ZDrift = {} :: ZDrift
ZDrift.__index = ZDrift
setmetatable(ZDrift, { __index = CasterArena })

ZDrift.homeRotationOffset = Quat.fromEuler(0, 0, 90)
ZDrift.awayRotationOffset = Quat.fromEuler(0, 0, -90)
ZDrift.boxSize = Vec3.new(7180, 17800, 1710)
ZDrift.boxOffset = Vec3.new(0, 0, 880)
ZDrift.centerBoxOffset = Vec3.new(0, 0, 500)
ZDrift.goalBoxSize = Vec3.new(600, 600, 600)
ZDrift.goalPositionOffset = Vec3.new(8200, 0, 585)
ZDrift.boostPadDefs = {} :: { BoostPadDef }

function ZDrift.new(gamemode: ModuleStateSpectatorLuaApi, frameIndex: number): ZDrift
	local self: ZDrift = setmetatable(Arena.new(gamemode, frameIndex), ZDrift) :: any
	self.type = "zdrift"
	self.name = self.slotId:gsub("_", " ")
	self.home.data = { overview = {} }
	self.away.data = { overview = {} }
	self:setupDimensions()
	self:setupOverviews()
	return self :: ZDrift
end

function ZDrift:isPointOnHomeSide(point: Vec3): boolean
	local homeDirection = self:getTeamRotation(Util.TeamIndex.HomeTeam):getForwardVector()
	local ballDirection = Util.getForward(self.transform.position, point)
	return homeDirection:dot(ballDirection) >= 0
end

function ZDrift:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(ZDrift.boxOffset),
		ZDrift.boxSize,
		self.transform.rotation
	)

	self.centerBox = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(ZDrift.centerBoxOffset),
		centerBoxSize,
		self.transform.rotation
	)

	self.home.goal = {
		position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
			:rotateVector(ZDrift.goalPositionOffset),
		rotation = self.transform.rotation * ZDrift.homeRotationOffset:inverse(),
		box = Box.empty,
	}
	self.home.goal.box = Box.new(self.home.goal.position, ZDrift.goalBoxSize, self.home.goal.rotation)

	self.away.goal = {
		position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
			:rotateVector(ZDrift.goalPositionOffset),
		rotation = self.transform.rotation * ZDrift.awayRotationOffset:inverse(),
		box = Box.empty,
	}
	self.away.goal.box = Box.new(self.away.goal.position, ZDrift.goalBoxSize, self.away.goal.rotation)

	self.boostPads = {}
	for _, def in ZDrift.boostPadDefs do
		table.insert(self.boostPads, {
			box = Box.new(
				self.transform.position + self.transform.rotation:rotateVector(def.position),
				resolveBoostPadSize(def.preset),
				self.transform.rotation
			),
			preset = def.preset,
		})
	end
end

function ZDrift:setupOverviews()
	self.home.data.overview = {}
	self.away.data.overview = {}

	for _, overview in config.overviewOffsets._zdrift do
		table.insert(self.home.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.HomeTeam) * overview.rotation,
		})
		table.insert(self.away.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.AwayTeam) * overview.rotation,
		})
	end
end

function ZDrift:getTeamRotation(teamIndex: number?): Quat
	if teamIndex == Util.TeamIndex.HomeTeam then
		return self.transform.rotation * ZDrift.homeRotationOffset
	elseif teamIndex == Util.TeamIndex.AwayTeam then
		return self.transform.rotation * ZDrift.awayRotationOffset
	end
	return Quat.identity
end

function ZDrift:GUIChangeDimensions()
	ZDrift.boxSize = Gui.dragFloat3("ZDrift Arena Size", ZDrift.boxSize, 1, -math.huge, math.huge)
	ZDrift.boxOffset = Gui.dragFloat3("ZDrift Position Offset", ZDrift.boxOffset, 1, -math.huge, math.huge)
	ZDrift.centerBoxOffset =
		Gui.dragFloat3("ZDrift Place Ball Box Position Offset", ZDrift.centerBoxOffset, 1, -math.huge, math.huge)
	ZDrift.goalBoxSize = Gui.dragFloat3("ZDrift Goal Size", ZDrift.goalBoxSize, 1, -math.huge, math.huge)
	ZDrift.goalPositionOffset =
		Gui.dragFloat3("ZDrift Goal Position Offset", ZDrift.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {ZDrift.boxSize}`)
		print(`boxOffset: {ZDrift.boxOffset}`)
		print(`centerBoxOffset: {ZDrift.centerBoxOffset}`)
		print(`goalBoxSize: {ZDrift.goalBoxSize}`)
		print(`goalPositionOffset: {ZDrift.goalPositionOffset}`)
		for i, def in ZDrift.boostPadDefs do
			print(`boostPadDefs[{i}]: {def.preset} at {def.position}`)
		end
	end

	self:setupDimensions()
end

-- Strike --

export type Strike = CasterArena & {
	__index: Strike,
	new: (
		gamemode: ModuleStateSpectatorLuaApi,
		frameIndex: number,
		nameOverride: string?,
		transformOffset: Transform?
	) -> Strike,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
}

local Strike = {} :: Strike
Strike.__index = Strike
setmetatable(Strike, { __index = CasterArena })

Strike.boxSize = Vec3.new(2250, 2250, 1150)
Strike.boxOffset = Vec3.new(0, 0, 415)
Strike.centerBoxOffset = Vec3.new(0, 0, -40)

function Strike.new(
	gamemode: ModuleStateSpectatorLuaApi,
	frameIndex: number,
	nameOverride: string?,
	transformOffset: Transform?
): Strike
	local self: CasterArena = setmetatable(CasterArena.new(gamemode, frameIndex), Strike) :: any
	self.type = "strike"

	if nameOverride then
		self.name = nameOverride
	else
		if self.slotId:find("FieldHouse") then
			local split = self.slotId:split(" ")
			local _, number = split[1], tonumber(split[2])
			local patchedNumber = typeof(number) == "number" and tostring(number - 2) or split[2]

			self.name = `Strike {patchedNumber}`
		elseif self.slotId:find("HalfG") then
			self.name = `Strike HalfG`
		else
			self.name = self.slotId
		end
	end

	if transformOffset then
		self.transformOffset = transformOffset
		self.transform = Util.addTransforms(self.gamemode.transform, self.transformOffset)
	end

	self.home.data = { overview = {} }
	self.away.data = { overview = {} }
	self:setupDimensions()
	self:setupOverviews()
	return self :: Strike
end

function Strike:isPointOnHomeSide(point: Vec3): boolean
	-- There is no Home or Away
	return true
end

function Strike:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Strike.boxOffset),
		Strike.boxSize,
		self.transform.rotation
	)

	self.centerBox = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Strike.centerBoxOffset),
		centerBoxSize,
		self.transform.rotation
	)
end

function Strike:setupOverviews()
	self.home.data.overview = {}
	self.away.data.overview = {}

	for _, overview in config.overviewOffsets._strike do
		table.insert(self.home.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.HomeTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.HomeTeam) * overview.rotation,
		})
		table.insert(self.away.data.overview, {
			position = self.transform.position + self:getTeamRotation(Util.TeamIndex.AwayTeam)
				:rotateVector(overview.position),
			rotation = self:getTeamRotation(Util.TeamIndex.AwayTeam) * overview.rotation,
		})
	end
end

function Strike:getTeamRotation(teamIndex: number): Quat
	return self.transform.rotation
end

function Strike:GUIChangeDimensions()
	Strike.boxSize = Gui.dragFloat3("Strike Arena Size", Strike.boxSize, 1, -math.huge, math.huge)
	Strike.boxOffset = Gui.dragFloat3("Strike Box Position Offset", Strike.boxOffset, 1, -math.huge, math.huge)
	Strike.centerBoxOffset =
		Gui.dragFloat3("Strike Place Ball Box Position Offset", Strike.centerBoxOffset, 1, -math.huge, math.huge)
	local transformEdit: boolean = false
	self.transformOffset.position =
		Gui.dragFloat3("Strike Gamemode Position Offset", self.transformOffset.position, 1, -math.huge, math.huge)
	if Gui.isItemActive() then
		transformEdit = true
	end
	self.transformOffset.rotation = Util.quatFromVec3(
		Gui.dragFloat3(
			"Strike Gamemode Rotation Offset",
			self.transformOffset.rotation:euler(),
			1,
			-math.huge,
			math.huge
		)
	)
	if Gui.isItemActive() then
		transformEdit = true
	end
	if transformEdit then
		self.transform.rotation = self.gamemode.transform.rotation * self.transformOffset.rotation
		self.transform.position = self.gamemode.transform.position + self.transformOffset.position
	end

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Strike.boxSize}`)
		print(`boxOffset: {Strike.boxOffset}`)
		print(`centerBoxOffset: {Strike.centerBoxOffset}`)
	end

	self:setupDimensions()
end

local function init(
	overlay: typeof(require("overlay")),
	profiler: typeof(require("profiler")),
	possession: typeof(require("possession"))
)
	Overlay = overlay
	Possession = possession
	Arena.profile(profiler)
end

return {
	init = init,
	CasterArena = CasterArena,
	Arena3v3 = Arena3v3,
	Arena4v4 = Arena4v4,
	Driftblitz = Driftblitz,
	ZDrift = ZDrift,
	Strike = Strike,
	debuging = debuging,
}
