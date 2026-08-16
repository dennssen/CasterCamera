--!strict

local version: string = "2.6.4"

-- Known Issues:
-- Double clicking and hold right click while not moving the mouse makes you unable to rotate the camera. (This is a spectator issue, only happens with UI open)
-- Overtime goals don't have particle affects (think this is fixed)

-- Dependencies
local Profiler = require("profiler")
local Util = require("util")

Util.initializeConfig({
	cameraFOV = 90,
	deadzone = 0,
	followFOV = 100,
	followPositionSmoothing = 0.1,
	followRadius = 20,
	mouseSensitivity = 1,
	invertMouseLookHorizontal = false,
	invertMouseLookVertical = false,
	invertControllerLookHorizontal = false,
	invertControllerLookVertical = false,
	controllerSensitivity = 1,
	positionSmoothing = 0.02,
	lookSmoothness = 0.25,
	ballOutline = true,
	particleSimSpeed = 1,
	vibrance = 1,
	getBallVariant = "PlayerBallDistance",
	sendOverlayInfo = true,
	thirdPersonMode = 2,
	overviewOffsets = {
		_3v3 = {
			{
				position = Vec3.new(1300, -2200, 950),
				rotation = Quat.fromEuler(0, -20, 60),
			},
			{
				position = Vec3.new(1000, 0, 1000),
				rotation = Quat.fromEuler(0, -35, 0),
			},
			{
				position = Vec3.new(1300, 2200, 950),
				rotation = Quat.fromEuler(0, -20, -60),
			},
		},
		_4v4 = {
			{
				position = Vec3.new(680, -2632, 1315),
				rotation = Quat.fromEuler(0, -18, 40),
			},
			{
				position = Vec3.new(2925, 0, 165),
				rotation = Quat.fromEuler(0, 5, 0),
			},
			{
				position = Vec3.new(3565, 2670, 1305),
				rotation = Quat.fromEuler(0, -25, -122),
			},
		},
		_driftblitz = {
			{
				position = Vec3.new(795, -3565, 1140),
				rotation = Quat.fromEuler(0, -20, 60),
			},
			{
				position = Vec3.new(3585, -1670, 40),
				rotation = Quat.fromEuler(0, 0, 50),
			},
			{
				position = Vec3.new(4500, 3135, 620),
				rotation = Quat.fromEuler(0, -15, -90),
			},
		},
		_zdrift = {
			{
				position = Vec3.new(5425, -3355, 1445),
				rotation = Quat.fromEuler(0, -15, 75),
			},
			{
				position = Vec3.new(8845, 0, 630),
				rotation = Quat.fromEuler(0, 5, -180),
			},
			{
				position = Vec3.new(4915, 1560, 1640),
				rotation = Quat.fromEuler(0, -8.5, -170),
			},
		},
		_strike = {
			{
				position = Vec3.new(-660, 0, 500),
				rotation = Quat.fromEuler(0, -35, 0),
			},
			{
				position = Vec3.new(0, -920, 500),
				rotation = Quat.fromEuler(0, -30, 90),
			},
			{
				position = Vec3.new(660, 0, 500),
				rotation = Quat.fromEuler(0, -35, 180),
			},
		},
	},
	keyboardKeybinds = "",
	gamepadKeybinds = "",
	boostPadPositions = {
		_3v3 = "",
		_4v4 = "",
		_driftblitz = "",
		_zdrift = "",
	},
	boostPadPresets = {
		small = Vec3.new(77, 77, 50),
		big = Vec3.new(120, 120, 100),
	},
	postProcessing = {
		bloomIntensity = 0.675,
		bloomThreshold = -1,
		depthOfFieldFstop = 4,
		depthOfFieldFocalDistance = 0,
		depthOfFieldSensorWidth = 24.576,
		chromaticAberrationIntensity = 0,
		motionBlurAmount = 0,
		vignetteIntensity = 0.4,
		exposureBias = 1,
	},
})

local ParticleSystem = require("particlesystem")

local InputSystem = require("inputsystem")
type Keybind = InputSystem.Keybind
type CustomInput = InputSystem.CustomInput
type InputSystem = InputSystem.InputSystem

local BallSim = require("ballsim")
local Possession = require("possession")
local Boost = require("boost")

local Box = require("box")
type BoxType = typeof(Box)

local Arena = require("arena")
local Overlay = require("overlay")

local Gamemodes = require("gamemodes")
Gamemodes.init(Overlay, Profiler, Possession)
type CasterArena = Gamemodes.CasterArena
type Arena3v3 = Gamemodes.Arena3v3
type Arena4v4 = Gamemodes.Arena4v4
type Driftblitz = Gamemodes.Driftblitz
type ZDrift = Gamemodes.ZDrift
type Strike = Gamemodes.Strike
local Arena3v3 = Gamemodes.Arena3v3
local Arena4v4 = Gamemodes.Arena4v4
local Driftblitz = Gamemodes.Driftblitz
local ZDrift = Gamemodes.ZDrift
local Strike = Gamemodes.Strike

export type BoostPadDef = {
	position: Vec3,
	preset: string, -- "small" or "big"
}

local BOOST_PAD_PRESETS = { "small", "big" }
local DEFAULT_BOOST_PAD_PRESET = "small"

function encodeBoostPadDefs(defs: { BoostPadDef }): string
	local parts: { string } = {}
	for _, def in defs do
		table.insert(parts, `{def.preset}:{tostring(def.position)}`)
	end
	return table.concat(parts, "|")
end

function decodeBoostPadDefs(encoded: string): { BoostPadDef }
	local defs: { BoostPadDef } = {}
	for part in encoded:gmatch("[^|]+") do
		local preset, vecPart = part:match("^(%a+):(.+)$")
		if preset and vecPart then
			table.insert(defs, { position = Util.stringToVec3(vecPart), preset = preset })
		end
	end
	return defs
end

local boostPadTypeInfo: { [string]: { classTable: any, configKey: string } } = {
	["3v3"] = { classTable = Arena3v3, configKey = "_3v3" },
	["4v4"] = { classTable = Arena4v4, configKey = "_4v4" },
	["driftblitz"] = { classTable = Driftblitz, configKey = "_driftblitz" },
	["zdrift"] = { classTable = ZDrift, configKey = "_zdrift" },
}

for _, info in boostPadTypeInfo do
	local encoded = config.boostPadPositions[info.configKey]
	if encoded ~= "" then
		info.classTable.boostPadDefs = decodeBoostPadDefs(encoded)
	end
end

type ArenaTeam = Arena.ArenaTeam<Gamemodes.OverviewData>

local HUD = require("hud")
type HUD = HUD.HUD

-- GameData
local readLocation = 0
local gameData: ReplayFrame

local defaultKeybinds = {
	keyboard = {
		lineOfSight = { primary = Input.Key.Q, modifiers = { Input.Key.LeftAlt } },
		previousPlayer = { primary = Input.Key.A, modifiers = {} },
		right = { primary = Input.Key.D, modifiers = {} },
		left = { primary = Input.Key.A, modifiers = {} },
		resetFOV = { primary = Input.Key.MiddleMouseButton, modifiers = {} },
		getClosestArena = { primary = Input.Key.Enter, modifiers = {} },
		thirdPerson = { primary = Input.Key.V, modifiers = {} },
		ballCam = { primary = Input.Key.B, modifiers = {} },
		speedDown = { primary = Input.Key.LeftControl, modifiers = {} },
		lookAround = { primary = Input.Key.RightMouseButton, modifiers = {} },
		up = { primary = Input.Key.E, modifiers = {} },
		forwards = { primary = Input.Key.W, modifiers = {} },
		overview3 = { primary = Input.Key.Seven, modifiers = {} },
		freeCam = { primary = Input.Key.Z, modifiers = {} },
		overview1 = { primary = Input.Key.Five, modifiers = {} },
		backwards = { primary = Input.Key.S, modifiers = {} },
		playerBallDistance = { primary = Input.Key.E, modifiers = { Input.Key.LeftAlt } },
		speedUp = { primary = Input.Key.LeftShift, modifiers = {} },
		overview2 = { primary = Input.Key.Six, modifiers = {} },
		nextPlayer = { primary = Input.Key.D, modifiers = {} },
		down = { primary = Input.Key.Q, modifiers = {} },
		firstPerson = { primary = Input.Key.C, modifiers = {} },
	},
	gamepad = {
		moveY = { primary = Input.Gamepad.LeftY, modifiers = {} },
		previousPlayer = { primary = Input.Gamepad.LeftShoulder, modifiers = {} },
		moveX = { primary = Input.Gamepad.LeftX, modifiers = {} },
		nextPlayer = { primary = Input.Gamepad.RightShoulder, modifiers = {} },
		lookY = { primary = Input.Gamepad.RightY, modifiers = {} },
		resetFOV = { primary = Input.Gamepad.DPad_Right, modifiers = {} },
		getClosestArena = { primary = Input.Gamepad.Special_Right, modifiers = {} },
		thirdPerson = { primary = Input.Gamepad.FaceButton_Top, modifiers = {} },
		ballCam = { primary = Input.Gamepad.FaceButton_Bottom, modifiers = {} },
		speedDown = { primary = Input.Gamepad.LeftShoulder, modifiers = {} },
		up = { primary = Input.Gamepad.RightTrigger, modifiers = {} },
		overview3 = { primary = Input.Gamepad.FaceButton_Right, modifiers = { Input.Gamepad.DPad_Left } },
		overview1 = { primary = Input.Gamepad.FaceButton_Left, modifiers = { Input.Gamepad.DPad_Left } },
		zoomOut = { primary = Input.Gamepad.DPad_Down, modifiers = {} },
		zoomIn = { primary = Input.Gamepad.DPad_Up, modifiers = {} },
		firstPerson = { primary = Input.Gamepad.FaceButton_Right, modifiers = {} },
		freeCam = { primary = Input.Gamepad.FaceButton_Left, modifiers = {} },
		playerBallDistance = { primary = Input.Gamepad.RightThumbstick, modifiers = {} },
		speedUp = { primary = Input.Gamepad.RightShoulder, modifiers = {} },
		overview2 = { primary = Input.Gamepad.FaceButton_Top, modifiers = { Input.Gamepad.DPad_Left } },
		lineOfSight = { primary = Input.Gamepad.LeftThumbstick, modifiers = {} },
		down = { primary = Input.Gamepad.LeftTrigger, modifiers = {} },
		lookX = { primary = Input.Gamepad.RightX, modifiers = {} },
	},
}

InputSystem.setDefaultKeybinds(defaultKeybinds.keyboard, defaultKeybinds.gamepad)

function compareVersion(
	actualRelease: number,
	expectedRelease: number,
	actualMajor: number,
	expectedMajor: number,
	actualMinor: number,
	expectedMinor: number
): number
	if actualRelease ~= expectedRelease then
		return actualRelease - expectedRelease
	end
	if actualMajor ~= expectedMajor then
		return actualMajor - expectedMajor
	end
	return actualMinor - expectedMinor
end

function checkVersion(version: string, versionExpression: string, cameraName: string): { success: boolean, msg: string }
	local msg: string = ""
	local release: string? | number, major: string? | number, minor: string? | number =
		version:match("(%d+)%.(%d+)%.(%d+)")
	local exLogic: string?, exRelease: string? | number, exMajor: string? | number, exMinor: string? | number =
		versionExpression:match("([=<>]+)(%d+)%.(%d+)%.(%d+)")

	if not exRelease or not exMajor or not exMinor then
		return { success = false, msg = `Required version expression is wrong, please contact the dev of this issue` }
	end

	if not release or not major or not minor then
		return {
			success = false,
			msg = `Your version of {cameraName} is outdated, the Suggested version is {exRelease}.{exMajor}.{exMinor}`,
		}
	end

	release = tonumber(release)
	major = tonumber(major)
	minor = tonumber(minor)
	exRelease = tonumber(exRelease)
	exMajor = tonumber(exMajor)
	exMinor = tonumber(exMinor)

	local comparison = compareVersion(
		release :: number,
		exRelease :: number,
		major :: number,
		exMajor :: number,
		minor :: number,
		exMinor :: number
	)

	msg = `Your {cameraName} version is {release}.{major}.{minor}`
	if exLogic == "=" then
		msg ..= `\nSuggested version of {cameraName} is {exRelease}.{exMajor}.{exMinor}`
		if comparison ~= 0 then
			return { success = false, msg = msg }
		end
	elseif exLogic == ">=" then
		msg ..= `\nSuggested version of {cameraName} is {exRelease}.{exMajor}.{exMinor} or higher`

		if comparison < 0 then
			return { success = false, msg = msg }
		end
	elseif exLogic == "<=" then
		msg ..= `\nSuggested version of {cameraName} is {exRelease}.{exMajor}.{exMinor} or lower`

		if comparison > 0 then
			return { success = false, msg = msg }
		end
	elseif exLogic == ">" then
		msg ..= `\nSuggested version of {cameraName} is higher than {exRelease}.{exMajor}.{exMinor}`

		if comparison <= 0 then
			return { success = false, msg = msg }
		end
	elseif exLogic == "<" then
		msg ..= `\nSuggested version of {cameraName} is lower than {exRelease}.{exMajor}.{exMinor}`

		if comparison >= 0 then
			return { success = false, msg = msg }
		end
	else
		return { success = false, msg = "Unsupported comparison operator" }
	end

	return { success = true, msg = "" }
end

function capitalize(s: string): string
	local firstLetter = s:sub(1, 1):upper()
	s = s:sub(2)
	return `{firstLetter}{s}`
end

function setHideHead(hide: boolean)
	camera.hideNearestHead = hide
end

local deltaTime: number = 0

local loadTime: number = 0
local transitionTime: number
local firstTransition: boolean
local isAres: boolean = false
local orionPosition = Vec3.new(0, -3000, -27700)
local orionRotation = Quat.fromEuler(0, 0, 90)
local aresPosition = Vec3.new(2500, -6000, 300)
local aresRotation = Quat.fromEuler(0, 0, 180)

local rotDelta: Vec3 = Vec3.zeroVector

local cameraPosition: Vec3 = orionPosition
local cameraVelocity: Vec3 = Vec3.zeroVector

function isAresGamemode(gamemodeId: string): boolean
	return gamemodeId:find("Beta") ~= nil or gamemodeId:find("Gamma") ~= nil or gamemodeId:find("Alpha") ~= nil
end

function checkIfAres(): boolean
	if isAres then
		return true
	end

	local gamemodes: { string } = SpectatorGamemodes.listGamemodeIds()
	for _, id: string in gamemodes do
		if isAresGamemode(id) then
			isAres = true
			return true
		end
	end

	return false
end

local CameraMode = {
	FirstPerson = 1,
	HeadRotation = 2,
	VelocityRotation = 3,
	FaceTheBall = 4,
	BallCam = 5,
}
local CAMERA_MODE_NAMES = {
	[1] = "First Person",
	[2] = "Head Rotation",
	[3] = "Velocity Rotation",
	[4] = "Face The Ball",
}

local ui = HUD.new("", 1920, 1080, 10)

-- Ball
local ball: ReplayBall
local ballOutline: boolean = config.ballOutline
local GetBallVariant = {
	PlayerBallDistance = "PlayerBallDistance",
	LineOfSight = "LineOfSight",
}
local getBallVariant = config.getBallVariant

-- Overlay
local sendOverlayInfo: boolean = config.sendOverlayInfo
local debugHomeScore: number = 0
local debugAwayScore: number = 0

-- Follow Camera
local followPlussCamera: SpectatorCamera = nil
local followPlussId: string = "dennssen.followpluss"
local requiredFollowPlussVersion: string = ">=1.13.0"
local recommendedFollowPlussVersion: string = ">=1.15.0"
local followPlussVersion: string = ""
local followPlussWarning: string = ""
local followPlussTick: (dt: number, followedBy: SpectatorCamera?) -> ()

local playerFollow = false
local povFollow = false
local currentPlayer: ReplayPlayer? = nil
local currentPlayerIndex: number = 1
local followFOV: number = config.followFOV
local followPositionSmoothing: number = config.followPositionSmoothing
local followRadius: number = config.followRadius
local thirdPersonMode: number = config.thirdPersonMode
local THIRD_PERSON_MODES = {
	HeadRotation = 2,
	VelocityRotation = 3,
	FaceTheBall = 4,
}

function getFollowVersion(version: string)
	followPlussVersion = version
end

function getFollowPlussTick(_followPlussTick: (number, SpectatorCamera?) -> ())
	followPlussTick = _followPlussTick
end

type FollowPlusData = {
	-- Callbacks
	versionCallback: (string) -> ()?,
	getMainProcessCallback: ((number, SpectatorCamera?) -> ()) -> ()?,
	guiCallback: (() -> ()) -> ()?,
	topSettingsCallback: (() -> ()) -> ()?,
	checkboxSettingsCallback: (() -> ()) -> ()?,
	playerSettingsCallback: (() -> ()) -> ()?,
	cameraSettingsCallback: (() -> ()) -> ()?,
	followSettingsCallback: (() -> ()) -> ()?,
	mainSettingsCallback: (() -> ()) -> ()?,
	autoCameraSettingsCallback: (() -> ()) -> ()?,
	savingSettingsCallback: (() -> ()) -> ()?,
	debugSettingsCallback: (() -> ()) -> ()?,
	gestureSettingsCallback: (() -> ()) -> ()?,
	autoShootingSettingsCallback: (() -> ()) -> ()?,
	goalCamSettingsCallback: (() -> ()) -> ()?,
	getTargetPlayerCallback: (() -> ReplayPlayer?) -> ()?,
	getFollowDataCallback: (() -> FollowPlusData) -> ()?,

	-- Data
	readLocation: number?,
	showNameTags: boolean?,
	isLeftHanded: boolean?,
	muteSelf: boolean?,
	isBallOutlineEnabled: boolean?,
	targetPlayer: ReplayPlayer?,
	targetPlayerName: string?,
	positionSmoothing: number?,
	rotationSmoothing: number?,
	cameraFOV: number?,
	cameraMode: number?,
	radius: number?,
	threshold: number?,
	cameraPositionOffset: Vec3?,
	cameraRotationOffset: Quat?,
	gestureControls: boolean?,
	forwardGestureMode: number?,
	upGestureMode: number?,
	backwardsGestureMode: number?,
	autoBall: boolean?,
	simResolutionScale: number?,
	simTimeLength: number?,
	autoGoalCam: boolean?,
	ballGoalMode: number?,
	goalMode: number?,
	hideNearestHead: boolean?,
	showQuests: boolean?,
	autoRecordReplays: boolean?,
	mouseSensitivity: number?,
	controllerSensitivity: number?,
	controllerDeadzone: number?,
}

type Overview = {
	position: Vec3,
	rotation: Quat,
}

type Round = {
	home: {
		score: number,
	},
	away: {
		score: number,
	},
}

local ARENA_TYPES = {
	Arena3v3 = "3v3",
	Arena4v4 = "4v4",
	Driftblitz = "driftblitz",
	ZDrift = "zdrift",
	Strike = "strike",
}
local overviewPredictionSteps: number = 2
local overviewPredictionTime: number = 5

local cachedGamemodesAmount: number = 0

type StrikeFleetArena = {
	name: string,
	transformOffset: Transform,
}

local strikeFleetArenas: { string } = {
	"1200_Full_Weekly_Race",
	"0800_Full_3",
	"1200_Full_2",
	"0800_Full_1",
	"1200_Full_3",
	"0800_Full_2",
	"1200_Full_4",
	"0800_Full_4",
}

local strikeFleetArenasInfo: { [string]: StrikeFleetArena } = {
	["1200_Full_Weekly_Race"] = {
		name = "Strike_Fleet 1v1 1",
		transformOffset = Transform.new(Vec3.new(-2400, 9575, -160), Quat.fromEuler(0, 0, 90), Vec3.oneVector),
	},
	-- global position: (-2400, 16150, 28462.500)
	["0800_Full_3"] = {
		name = "Strike_Fleet 1v1 2",
		transformOffset = Transform.new(Vec3.new(-27189.977, 16150, 42775), Quat.fromEuler(120, 0, 90), Vec3.oneVector),
	},
	["1200_Full_2"] = {
		name = "Strike_Fleet 2v2 1",
		transformOffset = Transform.new(Vec3.new(2400, 9575, -160), Quat.fromEuler(0, 0, 90), Vec3.oneVector),
	},
	-- global position: (2400, 12875, 28462.500)
	["0800_Full_1"] = {
		name = "Strike_Fleet 2v2 2",
		transformOffset = Transform.new(Vec3.new(-22389.977, 12875, 42775), Quat.fromEuler(120, 0, 90), Vec3.oneVector),
	},
	["1200_Full_3"] = {
		name = "Strike_Fleet 2v2 3",
		transformOffset = Transform.new(Vec3.new(2400, 16150, -160), Quat.fromEuler(0, 0, 90), Vec3.oneVector),
	},
	-- global position: (2400, 19450, 28462.500)
	["0800_Full_2"] = {
		name = "Strike_Fleet 2v2 4",
		transformOffset = Transform.new(Vec3.new(-22389.977, 19450, 42775), Quat.fromEuler(120, 0, 90), Vec3.oneVector),
	},
	["1200_Full_4"] = {
		name = "Strike_Fleet 3v3 1",
		transformOffset = Transform.new(Vec3.new(-2400, 12875, -160), Quat.fromEuler(0, 0, 90), Vec3.oneVector),
	},
	-- global position: (-2400, 19450, 28462.500)
	["0800_Full_4"] = {
		name = "Strike_Fleet 3v3 2",
		transformOffset = Transform.new(Vec3.new(-27189.977, 19450, 42775), Quat.fromEuler(120, 0, 90), Vec3.oneVector),
	},
}

function getArenas(): { CasterArena }
	local arenas: { CasterArena } = {}
	local gamemodes = SpectatorGamemodes.listGamemodes()
	for _, gamemode in gamemodes do
		local slotId = gamemode:getSlotId()
		local fieldhouseSplit = slotId:split(" ")

		if not isAres then
			isAres = isAresGamemode(slotId)

			if isAres and os.clock() - loadTime <= 30 then
				setGlobalCameraTransform(aresPosition, aresRotation)
			end
		end

		if
			slotId:find("TKB")
			and not slotId:find("Driftplex")
			and not slotId:find("Full")
			and not slotId:find("Playground")
		then
			local arena: CasterArena = Arena3v3.new(gamemode, readLocation) :: Arena3v3
			table.insert(arenas, arena)
		elseif slotId:find("Soccer") then
			local arena: CasterArena = Driftblitz.new(gamemode, readLocation) :: Driftblitz
			table.insert(arenas, arena)
		elseif
			(slotId:find("Jakeball") or slotId:find("Driftball"))
			or (slotId:find("TKB") and slotId:find("Driftplex") and not slotId:find("Full"))
			or (slotId:find("Beta") or slotId:find("Gamma") or slotId:find("Alpha"))
		then
			local arena: CasterArena = Arena4v4.new(gamemode, readLocation) :: Arena4v4
			table.insert(arenas, arena)
		elseif slotId:lower():find("zdrift") then
			local arena: CasterArena = ZDrift.new(gamemode, readLocation) :: ZDrift
			table.insert(arenas, arena)
		elseif fieldhouseSplit[1] == "FieldHouse" or slotId:find("Club HalfG") then
			local number = tonumber(slotId:split(" ")[2])

			if slotId == "Club HalfG 01" then
				local arena: CasterArena = Strike.new(gamemode, readLocation)
				table.insert(arenas, arena)
				continue
			end

			if typeof(number) ~= "number" then
				continue
			end

			if number >= 3 then
				local arena: CasterArena = Strike.new(gamemode, readLocation)
				table.insert(arenas, arena)
			end
		elseif table.find(strikeFleetArenas, slotId) then
			local strikeInfo = strikeFleetArenasInfo[slotId]
			local arena: CasterArena = Strike.new(gamemode, readLocation, strikeInfo.name, strikeInfo.transformOffset)
			table.insert(arenas, arena)
		end
	end

	return arenas
end

-- arena
local arenas: { CasterArena }?

function updateArenaBoostPads()
	if not arenas then
		return
	end

	for _, arena in arenas do
		arena:setupDimensions()
	end
end

function removeBoostPad(arenaType: string, index: number)
	local info = boostPadTypeInfo[arenaType]
	if not info then
		return
	end

	table.remove(info.classTable.boostPadDefs, index)
	config.boostPadPositions[info.configKey] = encodeBoostPadDefs(info.classTable.boostPadDefs)
	saveConfig()
	updateArenaBoostPads()
end

function saveBoostPads(arenaType: string)
	local info = boostPadTypeInfo[arenaType]
	if not info then
		return
	end

	config.boostPadPositions[info.configKey] = encodeBoostPadDefs(info.classTable.boostPadDefs)
	saveConfig()
end

function updateArenaOverviews()
	if not arenas then
		return
	end

	for _, arena in arenas do
		arena:setupOverviews()
	end
end

local selectedArena: CasterArena = nil

function addBoostPadAtCamera(preset: string): string
	if not selectedArena then
		return "No arena selected"
	end

	local info = boostPadTypeInfo[selectedArena.type]
	if not info then
		return `Boost pads aren't supported for arena type "{selectedArena.type}"`
	end

	local localOffset =
		selectedArena.transform.rotation:inverse():rotateVector(camera.position - selectedArena.transform.position)

	table.insert(info.classTable.boostPadDefs, { position = localOffset, preset = preset })
	saveBoostPads(selectedArena.type)
	updateArenaBoostPads()

	return `Added {preset} boost pad #{#info.classTable.boostPadDefs} to {selectedArena.type}`
end

-- Particles
ParticleSystem.vibrance = config.vibrance
ParticleSystem.speed = config.particleSimSpeed

-- Post Processing

local bloomIntensity = config.postProcessing.bloomIntensity
local bloomThreshold = config.postProcessing.bloomThreshold
local depthOfFieldFstop = config.postProcessing.depthOfFieldFstop
local depthOfFieldFocalDistance = config.postProcessing.depthOfFieldFocalDistance
local depthOfFieldSensorWidth = config.postProcessing.depthOfFieldSensorWidth
local chromaticAberrationIntensity = config.postProcessing.chromaticAberrationIntensity
local motionBlurAmount = config.postProcessing.motionBlurAmount
local vignetteIntensity = config.postProcessing.vignetteIntensity
local exposureBias = config.postProcessing.exposureBias

-- Stats
type BallCollision = {
	home: {
		current: {
			lastContactPlace: Vec3,
			contactTime: number,
			player: ReplayPlayer,
		}?,
		previous: {
			lastContactPlace: Vec3,
			contactTime: number,
			player: ReplayPlayer,
		}?,
	},
	away: {
		current: {
			lastContactPlace: Vec3,
			contactTime: number,
			player: ReplayPlayer,
		}?,
		previous: {
			lastContactPlace: Vec3,
			contactTime: number,
			player: ReplayPlayer,
		}?,
	},
}

local ballCollisionInfo: BallCollision = {
	home = {
		current = nil,
		previous = nil,
	},
	away = {
		current = nil,
		previous = nil,
	},
}

local homeGoalPotentialEnter: boolean = false
local previousHomeGoalPotentialEnter: boolean = false
local awayGoalPotentialEnter: boolean = false
local previousAwayGoalPotentialEnter: boolean = false

local maximumTimeSincePass: number = 5
local shotSeparationDistance: number = 30
local shotDetected: boolean = false
local currentShotPlayer: ReplayPlayer? = nil
local previousContactCheckBallPosition: Vec3? = nil

local goalPlayer: ReplayPlayer? = nil

-- Gravity
local gravityChaser: Quat = gravity.upRotation
local preservedGravityUp: Quat = gravity.upRotation
local doFakeGravity: boolean = false
local fakeGravity: Vec3 = Vec3.zeroVector

function getGravityUp(): Quat
	if doFakeGravity then
		return Util.quatFromVec3(fakeGravity)
	end

	if gravity.strength > 0 then
		preservedGravityUp = gravity.upRotation
		return gravity.upRotation
	else
		return preservedGravityUp
	end
end

-- Caster Camera
local cameraFOV = config.cameraFOV
local cameraMode = nil
-- amount of seconds it takes for the camera to reach it's target
local positionSmoothing = config.positionSmoothing
local cameraPositionSmoothing: number = positionSmoothing
local lookSmoothness = config.lookSmoothness
local dynamicLookSmoothness = lookSmoothness
local targetSpeedIndex: number = 1
local speedGears = {
	7,
	14,
	21,
	28,
	35,
}
local currentSpeedIndex: number = targetSpeedIndex
local gearShiftTime: number = 0
local gearShiftTimeRequired: number = 0.3
local speedLastGearBuffer = false
local turnVelocity: Vec2 = Vec2.zeroVector

-- Input

local Vertical: number = 0
local Horizontal: number = 0
local Up: number = 0
local deadzone: number = config.deadzone
local rotEuler: Vec3 = Vec3.zeroVector

local keyboardKeybindsDeserialized = InputSystem.decodeKeybinds(config.keyboardKeybinds)
local gamepadKeybindsDeserialized = InputSystem.decodeKeybinds(config.gamepadKeybinds)

if Util.getDictSize(keyboardKeybindsDeserialized) ~= Util.getDictSize(InputSystem.defaultKeybinds.keyboard) then
	Util.deepStructureCopy(InputSystem.defaultKeybinds.keyboard, keyboardKeybindsDeserialized)
	Util.deepStructureClean(InputSystem.defaultKeybinds.keyboard, keyboardKeybindsDeserialized)
end

if Util.getDictSize(gamepadKeybindsDeserialized) ~= Util.getDictSize(InputSystem.defaultKeybinds.gamepad) then
	Util.deepStructureCopy(InputSystem.defaultKeybinds.gamepad, gamepadKeybindsDeserialized)
	Util.deepStructureClean(InputSystem.defaultKeybinds.gamepad, gamepadKeybindsDeserialized)
end

InputSystem.inputs = {
	keyboard = {
		forwards = InputSystem.createCustomInput(
			"Move Forwards",
			"Move camera forward",
			keyboardKeybindsDeserialized["forwards"].primary,
			keyboardKeybindsDeserialized["forwards"].modifiers
		),
		right = InputSystem.createCustomInput(
			"Move Right",
			"Move camera right",
			keyboardKeybindsDeserialized["right"].primary,
			keyboardKeybindsDeserialized["right"].modifiers
		),
		left = InputSystem.createCustomInput(
			"Move Left",
			"Move camera left",
			keyboardKeybindsDeserialized["left"].primary,
			keyboardKeybindsDeserialized["left"].modifiers
		),
		backwards = InputSystem.createCustomInput(
			"Move Backwards",
			"Move camera backward",
			keyboardKeybindsDeserialized["backwards"].primary,
			keyboardKeybindsDeserialized["backwards"].modifiers
		),
		up = InputSystem.createCustomInput(
			"Move Up",
			"Move camera up",
			keyboardKeybindsDeserialized["up"].primary,
			keyboardKeybindsDeserialized["up"].modifiers
		),
		down = InputSystem.createCustomInput(
			"Move Down",
			"Move camera down",
			keyboardKeybindsDeserialized["down"].primary,
			keyboardKeybindsDeserialized["down"].modifiers
		),
		nextPlayer = InputSystem.createCustomInput(
			"Next Player",
			"Cycle to next player (POV mode)",
			keyboardKeybindsDeserialized["nextPlayer"].primary,
			keyboardKeybindsDeserialized["nextPlayer"].modifiers
		),
		previousPlayer = InputSystem.createCustomInput(
			"Previous Player",
			"Cycle to previous player (POV mode)",
			keyboardKeybindsDeserialized["previousPlayer"].primary,
			keyboardKeybindsDeserialized["previousPlayer"].modifiers
		),
		lineOfSight = InputSystem.createCustomInput(
			"Line of Sight",
			"Target: Player in line of sight",
			keyboardKeybindsDeserialized["lineOfSight"].primary,
			keyboardKeybindsDeserialized["lineOfSight"].modifiers
		),
		playerBallDistance = InputSystem.createCustomInput(
			"Closest to Ball",
			"Target: Player nearest ball",
			keyboardKeybindsDeserialized["playerBallDistance"].primary,
			keyboardKeybindsDeserialized["playerBallDistance"].modifiers
		),
		speedUp = InputSystem.createCustomInput(
			"Speed Up",
			"Increase camera speed",
			keyboardKeybindsDeserialized["speedUp"].primary,
			keyboardKeybindsDeserialized["speedUp"].modifiers
		),
		speedDown = InputSystem.createCustomInput(
			"Speed Down",
			"Decrease camera speed",
			keyboardKeybindsDeserialized["speedDown"].primary,
			keyboardKeybindsDeserialized["speedDown"].modifiers
		),
		ballCam = InputSystem.createCustomInput(
			"Ball Cam",
			"Toggle ball view",
			keyboardKeybindsDeserialized["ballCam"].primary,
			keyboardKeybindsDeserialized["ballCam"].modifiers
		),
		thirdPerson = InputSystem.createCustomInput(
			"Third Person",
			"Toggle third-person view",
			keyboardKeybindsDeserialized["thirdPerson"].primary,
			keyboardKeybindsDeserialized["thirdPerson"].modifiers
		),
		firstPerson = InputSystem.createCustomInput(
			"First Person",
			"Toggle first-person view",
			keyboardKeybindsDeserialized["firstPerson"].primary,
			keyboardKeybindsDeserialized["firstPerson"].modifiers
		),
		freeCam = InputSystem.createCustomInput(
			"Free Cam",
			"Toggle free-cam view",
			keyboardKeybindsDeserialized["freeCam"].primary,
			keyboardKeybindsDeserialized["freeCam"].modifiers
		),
		overview1 = InputSystem.createCustomInput(
			"Overview 1",
			"Jump to first overview position",
			keyboardKeybindsDeserialized["overview1"].primary,
			keyboardKeybindsDeserialized["overview1"].modifiers
		),
		overview2 = InputSystem.createCustomInput(
			"Overview 2",
			"Jump to second overview position",
			keyboardKeybindsDeserialized["overview2"].primary,
			keyboardKeybindsDeserialized["overview2"].modifiers
		),
		overview3 = InputSystem.createCustomInput(
			"Overview 3",
			"Jump to third overview position",
			keyboardKeybindsDeserialized["overview3"].primary,
			keyboardKeybindsDeserialized["overview3"].modifiers
		),
		getClosestArena = InputSystem.createCustomInput(
			"Select Arena",
			"Select closest arena",
			keyboardKeybindsDeserialized["getClosestArena"].primary,
			keyboardKeybindsDeserialized["getClosestArena"].modifiers
		),
		lookAround = InputSystem.createCustomInput(
			"Look Around",
			"Hold to rotate camera",
			keyboardKeybindsDeserialized["lookAround"].primary,
			keyboardKeybindsDeserialized["lookAround"].modifiers
		),
		resetFOV = InputSystem.createCustomInput(
			"Reset FOV",
			"Reset field of view",
			keyboardKeybindsDeserialized["resetFOV"].primary,
			keyboardKeybindsDeserialized["resetFOV"].modifiers
		),
	},
	gamepad = {
		moveY = InputSystem.createCustomInput(
			"MoveY",
			"Move Camera Forwards/Backwards",
			gamepadKeybindsDeserialized["moveY"].primary,
			gamepadKeybindsDeserialized["moveY"].modifiers,
			false
		),
		moveX = InputSystem.createCustomInput(
			"MoveX",
			"Move Camera Left/Right",
			gamepadKeybindsDeserialized["moveX"].primary,
			gamepadKeybindsDeserialized["moveX"].modifiers,
			false
		),
		up = InputSystem.createCustomInput(
			"Move Up",
			"Move Camera Up",
			gamepadKeybindsDeserialized["up"].primary,
			gamepadKeybindsDeserialized["up"].modifiers
		),
		down = InputSystem.createCustomInput(
			"Move Down",
			"Move Camera Down",
			gamepadKeybindsDeserialized["down"].primary,
			gamepadKeybindsDeserialized["down"].modifiers
		),
		nextPlayer = InputSystem.createCustomInput(
			"Next Player",
			"Cycle to next player (POV mode)",
			gamepadKeybindsDeserialized["nextPlayer"].primary,
			gamepadKeybindsDeserialized["nextPlayer"].modifiers
		),
		previousPlayer = InputSystem.createCustomInput(
			"Previous Player",
			"Cycle to previous player (POV mode)",
			gamepadKeybindsDeserialized["previousPlayer"].primary,
			gamepadKeybindsDeserialized["previousPlayer"].modifiers
		),
		lineOfSight = InputSystem.createCustomInput(
			"Line Of Sight",
			"Target: Player in line of sight",
			gamepadKeybindsDeserialized["lineOfSight"].primary,
			gamepadKeybindsDeserialized["lineOfSight"].modifiers
		),
		playerBallDistance = InputSystem.createCustomInput(
			"Closest to Ball",
			"Target: Player nearest ball",
			gamepadKeybindsDeserialized["playerBallDistance"].primary,
			gamepadKeybindsDeserialized["playerBallDistance"].modifiers
		),
		speedUp = InputSystem.createCustomInput(
			"Speed Up",
			"Increase camera speed",
			gamepadKeybindsDeserialized["speedUp"].primary,
			gamepadKeybindsDeserialized["speedUp"].modifiers
		),
		speedDown = InputSystem.createCustomInput(
			"Speed Down",
			"Decrease camera speed",
			gamepadKeybindsDeserialized["speedDown"].primary,
			gamepadKeybindsDeserialized["speedDown"].modifiers
		),
		lookY = InputSystem.createCustomInput(
			"LookY",
			"Look Up/Down",
			gamepadKeybindsDeserialized["lookY"].primary,
			gamepadKeybindsDeserialized["lookY"].modifiers,
			false
		),
		lookX = InputSystem.createCustomInput(
			"LookX",
			"Look Left/Right",
			gamepadKeybindsDeserialized["lookX"].primary,
			gamepadKeybindsDeserialized["lookX"].modifiers,
			false
		),
		zoomIn = InputSystem.createCustomInput(
			"Zoom In",
			"Increase field of view",
			gamepadKeybindsDeserialized["zoomIn"].primary,
			gamepadKeybindsDeserialized["zoomIn"].modifiers
		),
		zoomOut = InputSystem.createCustomInput(
			"Zoom Out",
			"Decrease field of view",
			gamepadKeybindsDeserialized["zoomOut"].primary,
			gamepadKeybindsDeserialized["zoomOut"].modifiers
		),
		resetFOV = InputSystem.createCustomInput(
			"Reset FOV",
			"Reset field of view",
			gamepadKeybindsDeserialized["resetFOV"].primary,
			gamepadKeybindsDeserialized["resetFOV"].modifiers
		),
		freeCam = InputSystem.createCustomInput(
			"Free Cam",
			"Toggle free-cam view",
			gamepadKeybindsDeserialized["freeCam"].primary,
			gamepadKeybindsDeserialized["freeCam"].modifiers
		),
		firstPerson = InputSystem.createCustomInput(
			"First Person",
			"Toggle first-person view",
			gamepadKeybindsDeserialized["firstPerson"].primary,
			gamepadKeybindsDeserialized["firstPerson"].modifiers
		),
		thirdPerson = InputSystem.createCustomInput(
			"Third Person",
			"Toggle third-person view",
			gamepadKeybindsDeserialized["thirdPerson"].primary,
			gamepadKeybindsDeserialized["thirdPerson"].modifiers
		),
		ballCam = InputSystem.createCustomInput(
			"Ball Cam",
			"Toggle ball view",
			gamepadKeybindsDeserialized["ballCam"].primary,
			gamepadKeybindsDeserialized["ballCam"].modifiers
		),
		overview1 = InputSystem.createCustomInput(
			"Overview 1",
			"Jump to first overview position",
			gamepadKeybindsDeserialized["overview1"].primary,
			gamepadKeybindsDeserialized["overview1"].modifiers
		),
		overview2 = InputSystem.createCustomInput(
			"Overview 2",
			"Jump to second overview position",
			gamepadKeybindsDeserialized["overview2"].primary,
			gamepadKeybindsDeserialized["overview2"].modifiers
		),
		overview3 = InputSystem.createCustomInput(
			"Overview 3",
			"Jump to third overview position",
			gamepadKeybindsDeserialized["overview3"].primary,
			gamepadKeybindsDeserialized["overview3"].modifiers
		),
		getClosestArena = InputSystem.createCustomInput(
			"Select Arena",
			"Select closest arena",
			gamepadKeybindsDeserialized["getClosestArena"].primary,
			gamepadKeybindsDeserialized["getClosestArena"].modifiers
		),
	},
}

local inputOrder = {
	keyboard = {
		"forwards",
		"left",
		"backwards",
		"right",
		"down",
		"up",
		"nextPlayer",
		"previousPlayer",
		"lineOfSight",
		"playerBallDistance",
		"speedUp",
		"speedDown",
		"resetFOV",
		"lookAround",
		"freeCam",
		"firstPerson",
		"thirdPerson",
		"ballCam",
		"overview1",
		"overview2",
		"overview3",
		"getClosestArena",
	},
	gamepad = {
		"moveY",
		"moveX",
		"up",
		"down",
		"nextPlayer",
		"previousPlayer",
		"lineOfSight",
		"playerBallDistance",
		"speedUp",
		"speedDown",
		"lookY",
		"lookX",
		"zoomIn",
		"zoomOut",
		"resetFOV",
		"freeCam",
		"firstPerson",
		"thirdPerson",
		"ballCam",
		"overview1",
		"overview2",
		"overview3",
		"getClosestArena",
	},
}

--  Mouse
local invertMouseLookHorizontal: boolean = config.invertMouseLookHorizontal
local invertMouseLookVertical: boolean = config.invertMouseLookVertical
local mouseSensitivity: number = config.mouseSensitivity
local mouseWheelAxis = Input.Key.MouseWheelAxis

--  Gamepad
local invertControllerLookHorizontal: boolean = config.invertControllerLookHorizontal
local invertControllerLookVertical: boolean = config.invertControllerLookVertical
local controllerSensitivity: number = config.controllerSensitivity

-- Gui
local debugFreecam: boolean = false
local boundingBoxDebug: boolean = false
local showGamemodePositions: boolean = false
local closestDebugGamemodeId: string = ""
local debugBallPrediction: boolean = false

local overviewMessage = {
	overviewNumber = 0,
	message = "",
}
local boostPadMessage: string = ""
local boostPadPresetToAdd: string = DEFAULT_BOOST_PAD_PRESET
local tpGamemodeName: string = ""
local dataGamemodeName: string = ""

function getGamemodeByName(gamemodeName: string): ModuleStateSpectatorLuaApi?
	for _, gamemode in SpectatorGamemodes.listGamemodes() do
		if gamemode:getSlotId() == gamemodeName then
			return gamemode
		end
	end

	return nil
end

function setGlobalCameraRotation(globalRotation)
	camera.rotation = globalRotation

	local upVector: Vec3

	if selectedArena then
		upVector = selectedArena.transform.rotation:getUpVector()
	else
		upVector = Vec3.upVector
	end

	if doFakeGravity then
		fakeGravity = Util.getUpRotation(upVector):euler()
	elseif selectedArena then
		preservedGravityUp = Util.getUpRotation(upVector)
	end
	local localRotation = getGravityUp():inverse() * globalRotation
	rotEuler = localRotation:euler()
end

function setGlobalCameraTransform(position: Vec3, rotation: Quat)
	cameraPosition = position
	setGlobalCameraRotation(rotation)
end

function main()
	loadTime = os.clock()
	if checkIfAres() then
		setGlobalCameraTransform(aresPosition, aresRotation)
	else
		setGlobalCameraTransform(orionPosition, orionRotation)
	end

	camera.rotationSmoothing = 0
	camera.positionSmoothing = 0
	followPlussCamera = getCameraById(followPlussId)
	if followPlussCamera then
		local followSetupMessage: FollowPlusData = {
			getMainProcessCallback = getFollowPlussTick,
			versionCallback = getFollowVersion,
		}

		sendMessage(followPlussCamera, followSetupMessage)
		local recommendedResult = checkVersion(followPlussVersion, recommendedFollowPlussVersion, "Follow Pluss")
		if not recommendedResult.success then
			followPlussWarning =
				`WARNING:\nThis Caster Camera Version is designed for a newer Follow+ version.\nIf you are experiencing issues please install the Follow+ version suggested below.\n{recommendedResult.msg}`
		end

		local requiredResult = checkVersion(followPlussVersion, requiredFollowPlussVersion, "Follow Pluss")
		if not requiredResult.success then
			followPlussWarning =
				`WARNING:\nYour version of Follow+ is outdated.\nPlease install the minimum required version suggested below\n{requiredResult.msg}.`
		end
	else
		followPlussWarning =
			"WARNING:\nFollow+ is not installed. POV mode will not work. \nPlease install Follow+ for POV to work."
	end
end

function updateOverview(overviewKey: number, globalOverviewPosition: Vec3, globalOverviewRotation: Quat): string
	if not selectedArena.box:checkPointIntersect(globalOverviewPosition) then
		return "Overviews cannot be outside an arena!"
	end

	local isOnHomeSide = selectedArena:isPointOnHomeSide(globalOverviewPosition)

	local translatedOverviewPosition
	local translatedOverviewRotation
	local flipQuat
	if isOnHomeSide then
		flipQuat = selectedArena:getTeamRotation(Util.TeamIndex.HomeTeam):inverse()
	else
		flipQuat = selectedArena:getTeamRotation(Util.TeamIndex.AwayTeam):inverse()
	end

	translatedOverviewPosition = flipQuat:rotateVector(globalOverviewPosition - selectedArena.transform.position)
	translatedOverviewRotation = flipQuat * globalOverviewRotation

	config.overviewOffsets[`_{selectedArena.type}`][overviewKey] = {
		position = translatedOverviewPosition,
		rotation = translatedOverviewRotation,
	}
	saveConfig()
	updateArenaOverviews()
	return `Successfully set Overview #{overviewKey} to Camera`
end

function resetPlayersWithBall()
	ballCollisionInfo.home.current = nil
	ballCollisionInfo.home.previous = nil
	ballCollisionInfo.away.current = nil
	ballCollisionInfo.away.previous = nil
	previousContactCheckBallPosition = nil
end

function getClosestArena(targetPosition: Vec3): CasterArena
	local closestArenaDistance = math.huge
	local closestArena = nil

	if not arenas then
		return closestArena
	end

	for _, arena: CasterArena in arenas do
		if arena.box:checkPointIntersect(targetPosition) then
			return arena
		end
	end

	-- if the camera is placed in such a way that it is not leveled with any arena we loop again without limiting height
	for _, arena: CasterArena in arenas do
		local distance = Util.getDist(targetPosition, arena.transform.position)
		if distance < closestArenaDistance then
			closestArenaDistance = distance
			closestArena = arena
		end
	end

	return closestArena
end

function setSelectedArena(arena: CasterArena)
	if (selectedArena and arena.name ~= selectedArena.name) or not selectedArena then -- new arena
		resetPlayersWithBall()
		Overlay.setGamemodeId(arena.slotId)
		Overlay.setArenaSize(arena.box.size)
		Overlay.clearRounds()
		Possession:setArena(arena)
		Boost:setArena(arena)
	end
	arena.instantUpdate = true
	selectedArena = arena
end

function DoGoalExplosion(team: ArenaTeam)
	local goalExplosionPosition: Vec3
	local teamColor: Color = team.color or Color.Black
	local goalExplosionColor: Color = Util.colorNormalized(teamColor)

	local goalExplosionOffset: Vec3 = selectedArena.transform.rotation:rotateVector(Vec3.new(0, 0, -60))

	if
		selectedArena.type == ARENA_TYPES.Driftblitz
		or selectedArena.type == ARENA_TYPES.ZDrift
		or selectedArena.type == ARENA_TYPES.Strike
	then
		goalExplosionPosition = ball.transform.position
	elseif team.teamIndex == Util.TeamIndex.HomeTeam then
		goalExplosionPosition = selectedArena.away.goal.position + goalExplosionOffset
	elseif team.teamIndex == Util.TeamIndex.AwayTeam then
		goalExplosionPosition = selectedArena.home.goal.position + goalExplosionOffset
	end

	GoalExplosionEffect(goalExplosionPosition, team.goal.rotation * Quat.fromEuler(0, 0, 180), goalExplosionColor)
end

--effects start
function GoalExplosionEffect(goalPosition: Vec3, goalRotation: Quat, particleColor: Color)
	for i = 1, 300 do
		local velocityVector = Vec3.new(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100))
		ParticleSystem:createParticle(
			goalPosition,
			Quat.identity,
			0.3,
			velocityVector,
			particleColor,
			ParticleSystem.Variant.Embers,
			math.random(800, 1300)
		)
	end
	ParticleSystem:createParticle(
		goalPosition,
		goalRotation,
		0.9,
		Vec3.zeroVector,
		particleColor,
		ParticleSystem.Variant.Rings,
		150
	)

	--rings
	ParticleSystem:createParticle(
		goalPosition,
		goalRotation,
		1,
		Vec3.zeroVector,
		particleColor,
		ParticleSystem.Variant.Rings,
		200
	)
	ParticleSystem:createParticle(
		goalPosition,
		goalRotation,
		1,
		Vec3.zeroVector,
		particleColor,
		ParticleSystem.Variant.Rings,
		400
	)

	if selectedArena.type == ARENA_TYPES.Driftblitz or selectedArena.type == ARENA_TYPES.ZDrift then
		return
	end

	--goal outline
	local goalSpeed = 20
	for i = 1, 3 do
		ParticleSystem:createParticle(
			goalPosition,
			goalRotation,
			1,
			goalRotation:getForwardVector() * goalSpeed,
			particleColor,
			ParticleSystem.Variant.GoalRing,
			400
		)
		goalSpeed /= 2
	end
end

function GameStartEffect()
	local particlePosition = selectedArena.centerBox.position

	local normalizedHomeColor: Color = Util.colorNormalized(selectedArena.home.color or Color.Black)
	local normalizedAwayColor: Color = Util.colorNormalized(selectedArena.away.color or Color.Black)

	local colorAverage = Color.new(
		(normalizedHomeColor.R + normalizedAwayColor.R) / 2,
		(normalizedHomeColor.G + normalizedAwayColor.G) / 2,
		(normalizedHomeColor.B + normalizedAwayColor.B) / 2,
		1
	)
	ParticleSystem:createParticle(
		particlePosition,
		selectedArena.transform.rotation,
		0.9,
		Vec3.zeroVector,
		colorAverage,
		ParticleSystem.Variant.Rings,
		150
	)
	ParticleSystem:createParticle(
		particlePosition,
		selectedArena.transform.rotation,
		0.7,
		selectedArena.transform.rotation:rotateVector(Vec3.new(0, 0, 10)),
		colorAverage,
		ParticleSystem.Variant.Rings,
		600
	)
	ParticleSystem:createParticle(
		particlePosition,
		selectedArena.transform.rotation,
		0.7,
		selectedArena.transform.rotation:rotateVector(Vec3.new(0, 0, 2)),
		colorAverage,
		ParticleSystem.Variant.Rings,
		400
	)
	local colorPallette = { normalizedHomeColor, normalizedAwayColor }
	for i = 1, 300 do
		local emberVelocity = Vec3.new(math.random(-30, 30), math.random(-30, 30), math.random(20, 80))
		ParticleSystem:createParticle(
			particlePosition,
			selectedArena.transform.rotation,
			0.5,
			selectedArena.transform.rotation:rotateVector(emberVelocity),
			colorPallette[math.random(1, 2)],
			ParticleSystem.Variant.Embers,
			math.random(800, 1300)
		)
	end
end
--effects end

function GUI_CameraInfo()
	if followPlussWarning ~= "" then
		Gui.textColored(
			LinearColor.new(238 / 255, 210 / 255, 2 / 255, 1),
			`{Icon.ExclamationTriangle} {followPlussWarning}`
		)
		Gui.newLine()
	end

	Gui.text("Data Read")
	local readLocationString = ""
	if readLocation > 0 then
		readLocationString = "Replay " .. readLocation
	else
		readLocationString = "Live Game"
	end
	if Gui.beginCombo("Game Data", readLocationString) then
		if Gui.selectable("Live Game", readLocation == 0) then
			readLocation = 0
		end
		for i = 1, #Replay.listLoaded() do
			if Gui.selectable("Replay " .. i, i == readLocation) then
				if i ~= readLocation then
					cachedGamemodesAmount = 0
					selectedArena.instantUpdate = true
				end
				readLocation = i
			end
		end
		Gui.endCombo()
	end
	Gui.setItemTooltip("Start a replay and select it here to practice casting")

	Gui.newLine()
	Gui.separatorText("Camera")
	Gui.indent()

	if Gui.button("Get Closest Arena") then
		setSelectedArena(getClosestArena(camera.position))
	end
	Gui.setItemTooltip("Gets the closest arena | For most accuracy be inside the arena when pressing")

	local arenaName
	if selectedArena then
		arenaName = selectedArena.name
	else
		arenaName = ""
	end
	if Gui.beginCombo("Selected Arena", arenaName) then
		if arenas then
			local _3v3Arenas: { Arena3v3 } = {}
			local _4v4Arenas: { Arena4v4 } = {}
			local DriftblitzArenas: { Driftblitz } = {}
			local ZDriftArenas: { ZDrift } = {}
			local StrikeArenas: { Strike } = {}

			for _, arena: CasterArena in arenas do
				if arena.type == ARENA_TYPES.Arena3v3 then
					table.insert(_3v3Arenas, arena :: Arena3v3)
				elseif arena.type == ARENA_TYPES.Arena4v4 then
					table.insert(_4v4Arenas, arena :: Arena4v4)
				elseif arena.type == ARENA_TYPES.Driftblitz then
					table.insert(DriftblitzArenas, arena :: Driftblitz)
				elseif arena.type == ARENA_TYPES.ZDrift then
					table.insert(ZDriftArenas, arena :: ZDrift)
				elseif arena.type == ARENA_TYPES.Strike then
					table.insert(StrikeArenas, arena :: Strike)
				end
			end

			if #_3v3Arenas > 0 and Gui.beginCombo("##3v3", "3v3 Arenas...") then
				for _, arena: CasterArena in _3v3Arenas do
					if Gui.selectable(arena.name, selectedArena.name == arena.name) then
						setSelectedArena(arena)
					end
				end
				Gui.endCombo()
			end
			if #_4v4Arenas > 0 and Gui.beginCombo("##4v4", "4v4 Arenas...") then
				for _, arena: CasterArena in _4v4Arenas do
					if Gui.selectable(arena.name, selectedArena.name == arena.name) then
						setSelectedArena(arena)
					end
				end
				Gui.endCombo()
			end
			if #DriftblitzArenas > 0 and Gui.beginCombo("##Driftblitz", "Driftblitz Arenas...") then
				for _, arena: CasterArena in DriftblitzArenas do
					if Gui.selectable(arena.name, selectedArena.name == arena.name) then
						setSelectedArena(arena)
					end
				end
				Gui.endCombo()
			end
			if #ZDriftArenas > 0 and Gui.beginCombo("##ZDrift", "ZDrift Arenas...") then
				for _, arena: CasterArena in ZDriftArenas do
					if Gui.selectable(arena.name, selectedArena.name == arena.name) then
						setSelectedArena(arena)
					end
				end
				Gui.endCombo()
			end
			if #StrikeArenas > 0 and Gui.beginCombo("##Strike", "Strike Arenas...") then
				for _, arena: CasterArena in StrikeArenas do
					if Gui.selectable(arena.name, selectedArena.name == arena.name) then
						setSelectedArena(arena)
					end
				end
				Gui.endCombo()
			end
		end
		Gui.endCombo()
	end
	Gui.setItemTooltip("The currently selected arena")

	Gui.newLine()
	cameraFOV = Gui.sliderFloat("Field Of View", cameraFOV, 1, 179)
	cameraFOV = math.clamp(cameraFOV, 1, 179)

	cameraPosition = Gui.dragFloat3("Camera Position", cameraPosition, 1, -math.huge, math.huge)
	local newRot = Gui.dragFloat3("Camera Rotation", rotEuler, 1, -180, 180)
	if Gui.isItemActive() then
		gravityChaser = getGravityUp()
		rotEuler = newRot
		camera.rotation = Quat.fromEuler(rotEuler.x, rotEuler.y, rotEuler.z)
	end

	Gui.text(`Get Player Method: {getBallVariant}`)
	Gui.unindent()
end

function GUI_CameraSettings()
	Gui.beginTabBar("SettingsBar")

	if Gui.beginTabItem("Controls") then
		Gui.indent()
		positionSmoothing = Gui.sliderFloat("Position Smoothing", positionSmoothing, 0, 1)
		positionSmoothing = math.clamp(positionSmoothing, 0, 1)
		lookSmoothness = Gui.sliderFloat("Rotation Smoothing", lookSmoothness, 0, 1)
		lookSmoothness = math.clamp(lookSmoothness, 0, 1)
		Gui.newLine()
		invertControllerLookHorizontal = Gui.checkbox("Invert Controller Horizontal", invertControllerLookHorizontal)
		invertControllerLookVertical = Gui.checkbox("Invert Controller Vertical", invertControllerLookVertical)
		controllerSensitivity = Gui.sliderFloat("Controller Sensitivity", controllerSensitivity, 0.001, 2)
		controllerSensitivity = math.clamp(controllerSensitivity, 0.001, 2)
		deadzone = Gui.sliderFloat("Controller Deadzone", deadzone, 0, 0.999)
		deadzone = math.clamp(deadzone, 0, 0.999)
		Gui.newLine()
		invertMouseLookHorizontal = Gui.checkbox("Invert Mouse Horizontal", invertMouseLookHorizontal)
		invertMouseLookVertical = Gui.checkbox("Invert Mouse Vertical", invertMouseLookVertical)
		mouseSensitivity = Gui.sliderFloat("Mouse Sensitivity", mouseSensitivity, 0.001, 2)
		mouseSensitivity = math.clamp(mouseSensitivity, 0.001, 2)
		Gui.unindent()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("HUD") then
		Gui.indent()
		ballOutline = Gui.checkbox("Ball Outline", ballOutline)
		Gui.setItemTooltip("Toggles an outline around the arena ball that shows it's position through walls.")
		Gui.unindent()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Particles") then
		Gui.indent()
		ParticleSystem.speed = Gui.sliderFloat("Particle Speed", ParticleSystem.speed, 0.001, 1)
		ParticleSystem.speed = math.clamp(ParticleSystem.speed, 0.001, 1)
		Gui.newLine()
		ParticleSystem.vibrance = Gui.sliderInt("Color Vibrance", ParticleSystem.vibrance, 1, 20)
		ParticleSystem.vibrance = math.clamp(ParticleSystem.vibrance, 1, 20)
		Gui.unindent()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Post Processing") then
		Gui.indent()
		if Gui.button("Apply Preset") then
			postProcessSettings.bloomIntensity = bloomIntensity
			postProcessSettings.bloomThreshold = bloomThreshold
			postProcessSettings.depthOfFieldFstop = depthOfFieldFstop
			postProcessSettings.depthOfFieldFocalDistance = depthOfFieldFocalDistance
			postProcessSettings.depthOfFieldSensorWidth = depthOfFieldSensorWidth
			postProcessSettings.chromaticAberrationIntensity = chromaticAberrationIntensity
			postProcessSettings.motionBlurAmount = motionBlurAmount
			postProcessSettings.vignetteIntensity = vignetteIntensity
			postProcessSettings.autoExposureBias = exposureBias
		end

		Gui.sameLine()

		if Gui.button("Apply Post Processing to Preset") then
			bloomIntensity = postProcessSettings.bloomIntensity
			bloomThreshold = postProcessSettings.bloomThreshold
			depthOfFieldFstop = postProcessSettings.depthOfFieldFstop
			depthOfFieldFocalDistance = postProcessSettings.depthOfFieldFocalDistance
			depthOfFieldSensorWidth = postProcessSettings.depthOfFieldSensorWidth
			chromaticAberrationIntensity = postProcessSettings.chromaticAberrationIntensity
			motionBlurAmount = postProcessSettings.motionBlurAmount
			vignetteIntensity = postProcessSettings.vignetteIntensity
			exposureBias = postProcessSettings.autoExposureBias
		end

		Gui.newLine()
		Gui.text("Preset")
		Gui.separator()

		bloomIntensity = Gui.sliderFloat("Bloom Intensity", bloomIntensity, 0, 10)
		bloomThreshold = Gui.sliderFloat("Bloom Threshold", bloomThreshold, -1, 10)
		depthOfFieldFstop = Gui.sliderFloat("Depth of Field Fstop", depthOfFieldFstop, 0, 22)
		depthOfFieldFocalDistance =
			Gui.dragFloat("Depth of Field Focal Distance", depthOfFieldFocalDistance, 1, 0, math.huge)
		depthOfFieldSensorWidth = Gui.sliderFloat("Depth of Field Sensor Width", depthOfFieldSensorWidth, 0, 200)
		chromaticAberrationIntensity =
			Gui.sliderFloat("Chromatic Aberration Intensity", chromaticAberrationIntensity, 0, 2)
		motionBlurAmount = Gui.sliderFloat("Motion Blur Amount", motionBlurAmount, 0, 1)
		vignetteIntensity = Gui.sliderFloat("Vignette Intensity", vignetteIntensity, 0, 1)
		exposureBias = Gui.sliderFloat("Exposure Bias", exposureBias, -6, 6)
		Gui.unindent()
		Gui.endTabItem()
	end

	if followPlussCamera and Gui.beginTabItem("POV") then
		Gui.indent()
		Gui.text(`Follow Pluss version: {followPlussVersion}`)

		followFOV = Gui.sliderInt("Field of View", followFOV, 1, 179)
		Gui.setItemTooltip("Sets the FOV for when the camera is in POV mode")
		followFOV = math.clamp(followFOV, 1, 179)

		followPositionSmoothing = Gui.sliderFloat("Position Smoothing##2", followPositionSmoothing, 0, 1)
		Gui.setItemTooltip("Sets the smoothing for when the camera is in POV mode")
		followPositionSmoothing = math.clamp(followPositionSmoothing, 0, 1)

		Gui.newLine()

		if Gui.beginCombo("Third Person Mode", CAMERA_MODE_NAMES[thirdPersonMode]) then
			for key, value: number in THIRD_PERSON_MODES :: { number } do
				if Gui.selectable(CAMERA_MODE_NAMES[value], thirdPersonMode == value) then
					thirdPersonMode = value
				end
			end
			Gui.endCombo()
		end
		Gui.setItemTooltip("Sets the Camera Mode to be used in 3rd Person POV mode")
		thirdPersonMode = math.clamp(thirdPersonMode, 2, #CAMERA_MODE_NAMES)

		followRadius = Gui.sliderFloat("3rd Person Radius", followRadius, 5, 100)
		Gui.setItemTooltip("The distance from the player when the camera is in 3rd Person POV mode")
		followRadius = math.clamp(followRadius, 5, 100)

		Gui.unindent()
		Gui.endTabItem()
	end

	if selectedArena and Gui.beginTabItem("Overviews") then
		Gui.indent()
		Gui.separatorText(`{capitalize(selectedArena.type)} Overviews`)

		for i, overview in config.overviewOffsets[`_{selectedArena.type}`] do
			if i ~= 1 then
				Gui.separator()
			end
			Gui.text(`Overview #{i}`)
			Gui.dragFloat3(`Position##{i}`, overview.position, 0, -math.huge, math.huge)
			Gui.dragFloat3(`Rotation##{i}`, overview.rotation:euler(), 0, -math.huge, math.huge)

			if Gui.button(`Set Overview To Camera##{i}`) then
				overviewMessage.overviewNumber = i
				overviewMessage.message = updateOverview(i, camera.position, camera.rotation)
			end
			Gui.setItemTooltip(
				"This will overwrite the current overview with your current position and rotation and save it to your settings"
			)

			if overviewMessage.overviewNumber == i then
				Gui.text(overviewMessage.message)
			end
		end

		Gui.unindent()
		Gui.endTabItem()
	end

	if selectedArena and Gui.beginTabItem("Boost Pads") then
		Gui.indent()

		Gui.separatorText("Boost Pad Size Presets")
		Gui.text("Editing a preset resizes every pad using it, in every arena, live.")

		config.boostPadPresets.small = Gui.dragFloat3("Small Size", config.boostPadPresets.small, 1, 1, math.huge)
		if Gui.isItemActive() then
			updateArenaBoostPads()
			saveConfig()
		end

		config.boostPadPresets.big = Gui.dragFloat3("Big Size", config.boostPadPresets.big, 1, 1, math.huge)
		if Gui.isItemActive() then
			updateArenaBoostPads()
			saveConfig()
		end

		Gui.newLine()
		Gui.separatorText(`{capitalize(selectedArena.type)} Boost Pads`)

		local info = boostPadTypeInfo[selectedArena.type]

		if not info then
			Gui.text("Boost pads aren't supported for this arena type")
		else
			if Gui.beginCombo("Preset To Add", boostPadPresetToAdd) then
				for _, preset in BOOST_PAD_PRESETS do
					if Gui.selectable(preset, boostPadPresetToAdd == preset) then
						boostPadPresetToAdd = preset
					end
				end
				Gui.endCombo()
			end

			if Gui.button("Add Boost Pad At Camera") then
				boostPadMessage = addBoostPadAtCamera(boostPadPresetToAdd)
			end
			Gui.setItemTooltip(
				"Adds a boost pad at your current camera position for this arena type and saves it to your settings"
			)

			if boostPadMessage ~= "" then
				Gui.text(boostPadMessage)
			end

			Gui.newLine()

			local removeIndex: number? = nil
			local changed = false

			for i, def: BoostPadDef in info.classTable.boostPadDefs do
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
					for _, preset in BOOST_PAD_PRESETS do
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

			if changed then
				updateArenaBoostPads()
				saveBoostPads(selectedArena.type)
			end

			if removeIndex then
				removeBoostPad(selectedArena.type, removeIndex)
				boostPadMessage = `Removed boost pad #{removeIndex}`
			end
		end

		Gui.unindent()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Overlay") then
		Gui.indent()
		sendOverlayInfo = Gui.checkbox("Send Overlay Info", sendOverlayInfo)
		Gui.setItemTooltip("Toggle this off to stop the camera from sending info to the overlay")
		Gui.unindent()
		Gui.endTabItem()
	end

	Gui.endTabBar()
end

function GUI_CameraControls()
	Gui.beginTabBar("ControlsBar")

	if Gui.beginTabItem("Keyboard") then
		InputSystem.guiKeyboardInputs(inputOrder.keyboard)
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Controller") then
		InputSystem.guiGamepadInputs(inputOrder.gamepad)
		Gui.endTabItem()
	end

	Gui.endTabBar()
end

function GUI_CameraDebug()
	Gui.beginTabBar("DebugBar")

	if Gui.beginTabItem("Profiler") then
		Gui.indent()

		Profiler:controls()
		Gui.text(`Frames: {#Profiler.frames}`)
		Profiler:graph()

		Gui.unindent()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Camera") then
		Gui.indent()
		Gui.text(`Camera position smoothing: {camera.positionSmoothing}`)
		Gui.text(`Camera rotation smoothing: {camera.rotationSmoothing}`)
		Gui.text("Camera Rotation: " .. tostring(camera:getSmoothedRotation():euler()))
		Gui.text(`Camera Position: {tostring(camera.position)}`)
		Gui.text("Target Speed Gear: " .. tostring(targetSpeedIndex))
		Gui.text("Current Speed Gear: " .. tostring(currentSpeedIndex))
		Gui.text("Gear Shift Time: " .. tostring(gearShiftTime))
		Gui.text(`Hide nearest head: {camera.hideNearestHead}`)

		Gui.newLine()

		if Gui.treeNode("Gravity") then
			Gui.text(`Gravity Direction: {gravity.upDirection}`)
			Gui.text(`Gravity Rotation: {gravity.upRotation:euler()}`)
			Gui.text(`Gravity Strength: {gravity.strength}`)

			Gui.newLine()

			doFakeGravity = Gui.checkbox("Fake Gravity", doFakeGravity)
			if doFakeGravity then
				if Gui.button("Driftball") then
					fakeGravity = Vec3.new(0, 0, 0)
				end

				if Gui.button("Club") then
					fakeGravity = Vec3.new(0, 120, 0)
				end

				if Gui.button("Parkour") then
					fakeGravity = Vec3.new(0, 240, 0)
				end

				fakeGravity = Gui.dragFloat3("Fake Gravity Up", fakeGravity, 1, 0, 360)
			end
			Gui.treePop()
		end

		if Gui.treeNode("Freecam") then
			if Gui.button("Follow Freecam") then
				debugFreecam = true
				ui:setCamera("anotheraxiom.freecam")
				camera:followCamera(getCameraById("anotheraxiom.freecam"))
			end
			Gui.treePop()
		end

		Gui.unindent()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Arena") then
		Gui.indent()
		local gamemodes = SpectatorGamemodes.listGamemodes()
		Gui.text(`Number of Gamemodes: {#gamemodes}`)
		if Gui.button("Print Gamemode Ids") then
			for _, gamemode in gamemodes do
				print(gamemode:getSlotId())
			end
		end

		tpGamemodeName = Gui.inputText("##gamemodeName", tpGamemodeName)
		Gui.sameLine()
		if Gui.button("TP to Gamemode") then
			local gamemode = getGamemodeByName(tpGamemodeName)
			if gamemode then
				local transform = gamemode.transform
				setGlobalCameraTransform(transform.position, transform.rotation)
			end
		end

		Gui.newLine()

		showGamemodePositions = Gui.checkbox("Show gamemode positions", showGamemodePositions)
		if showGamemodePositions and Gui.button("Print Closest Gamemode") then
			print(closestDebugGamemodeId)
		end

		Gui.newLine()

		if arenas and Gui.button("Print Arenas") then
			for _, arena in arenas do
				print(arena.slotId)
			end
		end

		dataGamemodeName = Gui.inputText("##GamemodeData", dataGamemodeName)
		Gui.sameLine()
		if Gui.button("Print gamemode data") then
			print(Util.tableToString(SpectatorGamemodes.getGamemodeData(dataGamemodeName).teams))
		end

		if selectedArena and Gui.button("Set Orientation to Arena") then
			Gui.sameLine()
			cameraPosition = selectedArena.transform.position
			camera.rotation = selectedArena.transform.rotation
			rotEuler = (selectedArena.transform.rotation * gravity.upRotation:inverse()):euler()
		end

		if selectedArena and Gui.button("Print Relative Orientation") then
			local RelativeLocation =
				selectedArena.transform.rotation:rotateVector(camera.position - selectedArena.transform.position)
			local RelativeRotation = camera.rotation * selectedArena.transform.rotation:inverse()
			print(`Relative Position ({selectedArena.name}):`)
			print(RelativeLocation)
			print(`Relative Rotation ({selectedArena.name}):`)
			print(RelativeRotation:euler())
			Gui.sameLine()
		end

		if selectedArena and Gui.button("Print Team Colors Array") then
			Gui.sameLine()
			for i, value in selectedArena.gamemode:getTeamColorsArray() do
				print(i)
				print(tostring(value))
			end
		end

		if selectedArena then
			if ball and selectedArena.home.goal then
				Gui.text(
					`Home goal ball intersect: {selectedArena.home.goal.box:checkPointIntersect(ball.transform.position)}`
				)
				Gui.text(
					`Away goal ball intersect: {selectedArena.away.goal.box:checkPointIntersect(ball.transform.position)}`
				)
			end
			if Gui.button("Print Selected Arena") then
				print(selectedArena)
			end
			Gui.sameLine()
			if Gui.button("Print Selected String Arena") then
				print(`Selected Arena: {Util.tableToString(selectedArena)}`)
			end
			if Gui.treeNode("Selected Arena Dimensions") then
				selectedArena:GUIChangeDimensions()
				Gui.treePop()
			end

			Gui.text("Home Team: ")
			Gui.indent()
			for i, player in selectedArena.home.players do
				Gui.text(i .. " " .. player.playerName)
			end
			Gui.unindent()
			Gui.text("Away Team: ")
			Gui.indent()
			for i, player in selectedArena.away.players do
				Gui.text(i .. " " .. player.playerName)
			end
			Gui.unindent()

			Gui.text("All Players: ")
			Gui.indent()
			for i, player in selectedArena.players do
				Gui.text(i .. " " .. player.playerName)
			end
			Gui.unindent()
		end

		Gui.newLine()

		if Gui.treeNode("Ball") then
			if ball and Gui.button("Print arena ball json") then
				print(ball:toJson())
			end

			if selectedArena and Gui.button("Print closest ball json") then
				local closestBall = Util.getClosestBall(selectedArena.transform.position, gameData)
				print(closestBall:toJson())
			end

			debugBallPrediction = Gui.checkbox("show ball prediction", debugBallPrediction)

			Possession.debug = Gui.checkbox("Possession Debug", Possession.debug)

			if Gui.treeNode("Print ball collision info") then
				if Gui.treeNode("Home") then
					if Gui.treeNode("Current##Home") then
						if ballCollisionInfo.home.current then
							Gui.text(`PlayerName: {ballCollisionInfo.home.current.player.playerName}`)
							Gui.text(`Caught Ball Time: {ballCollisionInfo.home.current.contactTime}`)
							Gui.text(`Last Held Position: {ballCollisionInfo.home.current.lastContactPlace}`)
						end
						Gui.treePop()
					end
					if Gui.treeNode("Previous##Home") then
						if ballCollisionInfo.home.previous then
							Gui.text(`PlayerName: {ballCollisionInfo.home.previous.player.playerName}`)
							Gui.text(`Caught Ball Time: {ballCollisionInfo.home.previous.contactTime}`)
							Gui.text(`Last Held Position: {ballCollisionInfo.home.previous.lastContactPlace}`)
						end
						Gui.treePop()
					end
					Gui.treePop()
				end
				if Gui.treeNode("Away") then
					if Gui.treeNode("Current##Away") then
						if ballCollisionInfo.away.current then
							Gui.text(`PlayerName: {ballCollisionInfo.away.current.player.playerName}`)
							Gui.text(`Caught Ball Time: {ballCollisionInfo.away.current.contactTime}`)
							Gui.text(`Last Held Position: {ballCollisionInfo.away.current.lastContactPlace}`)
						end
						Gui.treePop()
					end
					if Gui.treeNode("Previous##Away") then
						if ballCollisionInfo.away.previous then
							Gui.text(`PlayerName: {ballCollisionInfo.away.previous.player.playerName}`)
							Gui.text(`Caught Ball Time: {ballCollisionInfo.away.previous.contactTime}`)
							Gui.text(`Last Held Position: {ballCollisionInfo.away.previous.lastContactPlace}`)
						end
						Gui.treePop()
					end
					Gui.treePop()
				end
				Gui.treePop()
			end
			Gui.treePop()
		end

		Gui.unindent()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Match") then
		Gui.indent()
		if Gui.treeNode("Score Overlay") then
			Gamemodes.debuging.bestOfAmount = Gui.dragInt("Best Of", Gamemodes.debuging.bestOfAmount, 1, 0, 99)
			debugHomeScore = Gui.dragInt("Home Score", debugHomeScore, 1, 0, 99)
			debugAwayScore = Gui.dragInt("Away Score", debugAwayScore, 1, 0, 99)
			if Gui.button("Add Round") then
				Overlay.addRound(debugHomeScore, debugAwayScore)
			end

			if Gui.button("Clear Rounds") then
				Overlay.clearRounds()
			end
			Gui.treePop()
		end

		if Gui.treeNode("Particle Effects") then
			if Gui.button("Home Scores") then
				DoGoalExplosion(selectedArena.home)
			end

			if Gui.button("Away Scores") then
				DoGoalExplosion(selectedArena.away)
			end

			if Gui.button("Round Starts") then
				GameStartEffect()
			end
			Gui.treePop()
		end

		Gui.unindent()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Settings") then
		Gui.indent()
		if Gui.treeNode("Inputs") then
			if Gui.button("Print Pressed Keys") then
				print(InputSystem.pressedInputKeys)
			end
			Gui.text(tostring("Vertical:" .. Vertical))
			Gui.text(tostring("Horizontal: " .. Horizontal))
			Gui.treePop()
		end

		if Gui.treeNode("Performance") then
			Gui.text(`Luau Memory Usage: {gcinfo() / 1000}MB`)
			Gui.treePop()
		end

		if Gui.treeNode("Debug Overrides") then
			speedGears[#speedGears] = Gui.dragInt("Last Speed Override", speedGears[#speedGears], 1, 0, 5000)
			camera.nearClippingPlane = Gui.dragFloat("Near Clipping Plane", camera.nearClippingPlane, 1, 0, 999999)
			boundingBoxDebug = Gui.checkbox("show boxes", boundingBoxDebug)
			Gui.treePop()
		end

		Gui.unindent()
		Gui.endTabItem()
	end

	Gui.endTabBar()
end

function onGui()
	Gui.text(`Version: {version}`)

	Gui.beginTabBar("MainBar")
	if Gui.beginTabItem("Info") then
		GUI_CameraInfo()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Settings") then
		GUI_CameraSettings()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Controls##TabItem") then
		GUI_CameraControls()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Debug") then
		GUI_CameraDebug()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Possession") then
		Possession:gui()
		Gui.endTabItem()
	end

	if Gui.beginTabItem("Boost") then
		Boost:gui()
		Gui.endTabItem()
	end
	Gui.endTabBar()

	Gui.newLine()

	if Gui.button(Icon.Save .. " Save Config") then
		config.cameraFOV = cameraFOV
		config.deadzone = deadzone
		config.followFOV = followFOV
		config.followPositionSmoothing = followPositionSmoothing
		config.followRadius = followRadius
		config.invertMouseLookHorizontal = invertMouseLookHorizontal
		config.invertMouseLookVertical = invertMouseLookVertical
		config.mouseSensitivity = mouseSensitivity
		config.invertControllerLookHorizontal = invertControllerLookHorizontal
		config.invertControllerLookVertical = invertControllerLookVertical
		config.controllerSensitivity = controllerSensitivity
		config.positionSmoothing = positionSmoothing
		config.lookSmoothness = lookSmoothness
		config.particleSimSpeed = ParticleSystem.speed
		config.ballOutline = ballOutline
		config.vibrance = ParticleSystem.vibrance
		config.getBallVariant = getBallVariant
		config.sendOverlayInfo = sendOverlayInfo
		config.thirdPersonMode = thirdPersonMode
		config.postProcessing = {
			bloomIntensity = bloomIntensity,
			bloomThreshold = bloomThreshold,
			depthOfFieldFstop = depthOfFieldFstop,
			depthOfFieldFocalDistance = depthOfFieldFocalDistance,
			depthOfFieldSensorWidth = depthOfFieldSensorWidth,
			chromaticAberrationIntensity = chromaticAberrationIntensity,
			motionBlurAmount = motionBlurAmount,
			vignetteIntensity = vignetteIntensity,
			exposureBias = exposureBias,
		}
		saveConfig()
	end
	Gui.setItemTooltip("Saves your settings!")
end

function debugGamemodePositions()
	if showGamemodePositions then
		local gamemodes = SpectatorGamemodes.listGamemodes()

		local closestGamemode = {
			distance = math.huge,
		}

		local cameraPos = camera.position
		for _, gamemode: ModuleStateSpectatorLuaApi in gamemodes do
			local position = gamemode.transform.position
			local distance = cameraPos:distance(position)

			WorldDraw.drawPoint(position, 1, 0, 0, 50, 0)

			if distance < closestGamemode.distance then
				closestGamemode.distance = distance
				closestGamemode.gamemode = gamemode
			end
		end

		closestDebugGamemodeId = closestGamemode.gamemode:getSlotId()
		WorldDraw.drawPoint(closestGamemode.gamemode.transform.position, 0, 1, 0, 50, 0)
	else
		closestDebugGamemodeId = ""
	end
end

function toggleSmoothing(position: boolean, rotation: boolean)
	if position then
		cameraPositionSmoothing = positionSmoothing
	else
		cameraPositionSmoothing = 0
	end
	if rotation then
		dynamicLookSmoothness = lookSmoothness
	else
		dynamicLookSmoothness = 0
	end
end

function onTransitionBegin(transitionInfo: Transition)
	transitionTime = os.clock()
	firstTransition = transitionTime <= loadTime + 1 -- Margin of 1 second

	if firstTransition then
		if checkIfAres() then
			cameraPosition = aresPosition
			camera.rotation = aresRotation
			rotEuler = aresRotation:euler()
			rotEuler.x = 0
		else
			cameraPosition = orionPosition
			camera.rotation = orionRotation
			rotEuler = orionRotation:euler()
			rotEuler.x = 0
		end
	else
		cameraPosition = transitionInfo.startPosition
		camera.rotation = transitionInfo.startRotation
		rotEuler = transitionInfo.startRotation:euler()
		rotEuler.x = 0
	end

	alwaysTick = true
	camera.rotationSmoothing = 0
	setHideHead(false)
	camera.showNameTags = true
end

-- Remember: ball radius is 17.5, use an extra 10 for player contact
function getClosestPlayerToBall(maximumDistance: number?): ReplayPlayer?
	local players = selectedArena.players
	local closestPlayerDistance = maximumDistance or math.huge
	local closestPlayer: ReplayPlayer = nil

	for _, player in players do
		local root = player.root
		local headPosition = player.head.position
		local leftHandPosition = root.rotation:rotateVector(player.leftHand.position) + root.position
		local rightHandPosition = root.rotation:rotateVector(player.rightHand.position) + root.position

		local headDistance = Util.getDist(ball.transform.position, headPosition)
		local leftHandDistance = Util.getDist(ball.transform.position, leftHandPosition)
		local rightHandDistance = Util.getDist(ball.transform.position, rightHandPosition)

		local minimumDistance = math.min(headDistance, leftHandDistance, rightHandDistance)

		if minimumDistance < closestPlayerDistance then
			closestPlayerDistance = minimumDistance
			closestPlayer = player
		end
	end

	return closestPlayer
end

-- instead of just the ball pos, check the path in the last frame so it is less likely to skip touches
function getClosestPlayerToBallSegment(segmentStart: Vec3, segmentEnd: Vec3, maximumDistance: number?): ReplayPlayer?
	local players = selectedArena.players
	local closestPlayerDistance = maximumDistance or math.huge
	local closestPlayer: ReplayPlayer = nil

	for _, player in players do
		local root = player.root
		local headPosition = player.head.position
		local leftHandPosition = root.rotation:rotateVector(player.leftHand.position) + root.position
		local rightHandPosition = root.rotation:rotateVector(player.rightHand.position) + root.position

		local headDistance = Util.getPointToSegmentDist(headPosition, segmentStart, segmentEnd)
		local leftHandDistance = Util.getPointToSegmentDist(leftHandPosition, segmentStart, segmentEnd)
		local rightHandDistance = Util.getPointToSegmentDist(rightHandPosition, segmentStart, segmentEnd)

		local minimumDistance = math.min(headDistance, leftHandDistance, rightHandDistance)

		if minimumDistance < closestPlayerDistance then
			closestPlayerDistance = minimumDistance
			closestPlayer = player
		end
	end

	return closestPlayer
end

function getClosestPlayerToLineOfSight(): ReplayPlayer?
	local players = selectedArena.players
	local cameraForward = camera.rotation:getForwardVector()

	local closestPlayerDistance = math.huge
	local closestPlayer: ReplayPlayer = nil

	for _, player: ReplayPlayer in players do
		local playerRelativePostion = player.root.position - camera.position
		if cameraForward:dot(playerRelativePostion) < 0 then -- continue because player is behind camera
			continue
		end

		local playerDistance = Util.getDist(camera.position, player.root.position)
		local calculatedScreenPosition = camera.position + (cameraForward * playerDistance)
		local lineOfSightDistance = Util.getDist(calculatedScreenPosition, player.root.position)

		if lineOfSightDistance < closestPlayerDistance then
			closestPlayerDistance = lineOfSightDistance
			closestPlayer = player
		end
	end

	return closestPlayer
end

function followPov(type: "player" | "ball")
	povFollow = true
	if type == "player" then
		playerFollow = true
	elseif type == "ball" then
		playerFollow = false
	end

	local message: FollowPlusData = {
		readLocation = readLocation,
		showNameTags = true,
		muteSelf = false,
		isBallOutlineEnabled = ballOutline,
		targetPlayer = currentPlayer,
		cameraFOV = followFOV,
		cameraMode = cameraMode,
		radius = followRadius,
		threshold = 5,
		positionSmoothing = followPositionSmoothing,
		cameraPositionOffset = Vec3.zeroVector,
		cameraRotationOffset = Quat.identity,
		gestureControls = false,
		autoBall = false,
		autoGoalCam = false,
		showQuests = false,
		autoRecordReplays = false,
		mouseSensitivity = mouseSensitivity,
		controllerSensitivity = controllerSensitivity,
		controllerDeadzone = deadzone,
	}
	toggleSmoothing(false, false)
	sendMessage(followPlussCamera, message)
	ui:setCamera(followPlussId)
end

function getPlayer(type: "player" | "ball")
	if not followPlussCamera then
		return
	end

	local tryGetPlayer: ReplayPlayer?

	if getBallVariant == GetBallVariant.PlayerBallDistance then
		tryGetPlayer = getClosestPlayerToBall()
	else
		tryGetPlayer = getClosestPlayerToLineOfSight()
	end

	if tryGetPlayer then
		currentPlayer = tryGetPlayer
		Overlay.setFollowedPlayer(type == "player" and tryGetPlayer.playerName or "")
	else
		return
	end
	local playerIndex = Util.findPlayerInTable(selectedArena.players, tryGetPlayer)
	if playerIndex == nil then
		return
	end
	currentPlayerIndex = playerIndex
	followPov(type)
end

function stopFollow()
	toggleSmoothing(true, true)
	ui:setCamera("")
	povFollow = false
	playerFollow = false
	cameraPosition = followPlussCamera:getSmoothedPosition()
	setGlobalCameraRotation(followPlussCamera:getSmoothedRotation())
	rotEuler.x = 0
	currentPlayer = nil
	Overlay.setFollowedPlayer("")
	camera.fieldOfView = cameraFOV
	setHideHead(false)
	followPlussTick(deltaTime, nil)
end

function setOverview(overviewNumber: number)
	if povFollow then
		stopFollow()
	end
	toggleSmoothing(false, false)

	BallSim:simBallPath(ball, overviewPredictionSteps, overviewPredictionTime / overviewPredictionSteps)
	local futureBallPosition: Vec3 = BallSim.simPath[#BallSim.simPath].position

	if selectedArena:isPointOnHomeSide(futureBallPosition) then
		cameraPosition = selectedArena.home.data.overview[overviewNumber].position
		setGlobalCameraRotation(selectedArena.home.data.overview[overviewNumber].rotation)
	else
		cameraPosition = selectedArena.away.data.overview[overviewNumber].position
		setGlobalCameraRotation(selectedArena.away.data.overview[overviewNumber].rotation)
	end
end

function readInput()
	readOtherInputs()
	readMoveInput()
	readUpInput()
end

function readOtherInputs()
	if InputSystem.keyToBeRebinded.key ~= "" then
		-- don't read inputs on rebind
		return
	end

	cameraFOV -= Input.getAnalog(mouseWheelAxis) * 10

	if
		InputSystem.getCustomKey(InputSystem.inputs.gamepad.zoomIn).held
		and InputSystem.getCustomKey(InputSystem.inputs.gamepad.zoomOut).held
	then
		cameraFOV += 0
	elseif InputSystem.getCustomKey(InputSystem.inputs.gamepad.zoomIn).held then
		cameraFOV -= 50 * deltaTime
	elseif InputSystem.getCustomKey(InputSystem.inputs.gamepad.zoomOut).held then
		cameraFOV += 50 * deltaTime
	end

	cameraFOV = math.clamp(cameraFOV, 1, 179)

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.resetFOV).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.resetFOV).down
	then
		cameraFOV = config.cameraFOV
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.speedUp).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.speedUp).down
	then
		if targetSpeedIndex == #speedGears - 2 then
			speedLastGearBuffer = true
		end
		targetSpeedIndex = math.min(targetSpeedIndex + 1, #speedGears - 1)
	end
	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.speedDown).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.speedDown).down
	then
		targetSpeedIndex = math.max(targetSpeedIndex - 1, 1)
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.speedUp).up
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.speedUp).up
	then
		if speedLastGearBuffer then
			speedLastGearBuffer = false
		end

		if targetSpeedIndex == #speedGears then
			targetSpeedIndex -= 1
		end
	end

	if
		(
			InputSystem.getCustomKey(InputSystem.inputs.keyboard.speedUp).held
			or InputSystem.getCustomKey(InputSystem.inputs.gamepad.speedUp).held
		)
		and targetSpeedIndex >= #speedGears - 1
		and not speedLastGearBuffer
	then
		targetSpeedIndex = #speedGears
	end

	if selectedArena == nil then
		return
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.getClosestArena).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.getClosestArena).down
	then
		setSelectedArena(getClosestArena(camera.position))
	end

	if
		ball
		and (
			InputSystem.getCustomKey(InputSystem.inputs.keyboard.overview1).down
			or InputSystem.getCustomKey(InputSystem.inputs.gamepad.overview1).down
		)
	then
		setOverview(1)
	end
	if
		ball
		and (
			InputSystem.getCustomKey(InputSystem.inputs.keyboard.overview2).down
			or InputSystem.getCustomKey(InputSystem.inputs.gamepad.overview2).down
		)
	then
		setOverview(2)
	end
	if
		ball
		and (
			InputSystem.getCustomKey(InputSystem.inputs.keyboard.overview3).down
			or InputSystem.getCustomKey(InputSystem.inputs.gamepad.overview3).down
		)
	then
		setOverview(3)
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.lineOfSight).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.lineOfSight).down
	then
		getBallVariant = GetBallVariant.LineOfSight
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.playerBallDistance).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.playerBallDistance).down
	then
		getBallVariant = GetBallVariant.PlayerBallDistance
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.thirdPerson).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.thirdPerson).down
	then
		-- Get player if already in third person or in ball cam
		-- Otherwise just switch camera mode
		if currentPlayer == nil or cameraMode == thirdPersonMode or cameraMode == CameraMode.BallCam then
			cameraMode = thirdPersonMode
			getPlayer("player")
		else
			cameraMode = thirdPersonMode
			followPov("player")
		end
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.firstPerson).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.firstPerson).down
	then
		-- Get player if already in third person or in ball cam
		-- Otherwise just switch camera mode
		if currentPlayer == nil or cameraMode == CameraMode.FirstPerson or cameraMode == CameraMode.BallCam then
			cameraMode = CameraMode.FirstPerson
			getPlayer("player")
		else
			cameraMode = CameraMode.FirstPerson
			followPov("player")
		end
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.ballCam).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.ballCam).down
	then
		cameraMode = CameraMode.BallCam
		getPlayer("ball")
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.freeCam).down
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.freeCam).down
	then
		if povFollow then
			stopFollow()
		end
	end

	if
		playerFollow
		and (
			InputSystem.getCustomKey(InputSystem.inputs.gamepad.previousPlayer).down
			or InputSystem.getCustomKey(InputSystem.inputs.keyboard.previousPlayer).down
		)
	then
		currentPlayerIndex -= 1
		if currentPlayerIndex < 1 then
			currentPlayerIndex = #selectedArena.players
		end
		currentPlayer = selectedArena.players[currentPlayerIndex]
		followPov("player")
	end
	if
		playerFollow
		and (
			InputSystem.getCustomKey(InputSystem.inputs.gamepad.nextPlayer).down
			or InputSystem.getCustomKey(InputSystem.inputs.keyboard.nextPlayer).down
		)
	then
		currentPlayerIndex += 1
		if currentPlayerIndex > #selectedArena.players then
			currentPlayerIndex = 1
		end
		currentPlayer = selectedArena.players[currentPlayerIndex]
		followPov("player")
	end
end

function readMoveInput()
	if InputSystem.keyToBeRebinded.key ~= "" then
		-- don't read inputs on rebind
		return
	end

	local input = math.abs(InputSystem.getCustomAnalog(InputSystem.inputs.gamepad.moveY))
		+ math.abs(InputSystem.getCustomAnalog(InputSystem.inputs.gamepad.moveX))
	if input > deadzone then
		Vertical = InputSystem.getCustomAnalog(InputSystem.inputs.gamepad.moveY)
		Horizontal = InputSystem.getCustomAnalog(InputSystem.inputs.gamepad.moveX)
		return
	else
		if
			InputSystem.getCustomKey(InputSystem.inputs.keyboard.forwards).held
			and InputSystem.getCustomKey(InputSystem.inputs.keyboard.backwards).held
		then
			Vertical = 0
		elseif InputSystem.getCustomKey(InputSystem.inputs.keyboard.forwards).held then
			Vertical = 1
		elseif InputSystem.getCustomKey(InputSystem.inputs.keyboard.backwards).held then
			Vertical = -1
		else
			Vertical = 0
		end

		if
			InputSystem.getCustomKey(InputSystem.inputs.keyboard.right).held
			and InputSystem.getCustomKey(InputSystem.inputs.keyboard.left).held
		then
			Horizontal = 0
		elseif InputSystem.getCustomKey(InputSystem.inputs.keyboard.right).held then
			Horizontal = 1
		elseif InputSystem.getCustomKey(InputSystem.inputs.keyboard.left).held then
			Horizontal = -1
		else
			Horizontal = 0
		end
	end
end

function readUpInput()
	if InputSystem.keyToBeRebinded.key ~= "" then
		-- don't read inputs on rebind
		return
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.gamepad.down).held
		or InputSystem.getCustomKey(InputSystem.inputs.gamepad.up).held
	then
		if
			InputSystem.getCustomKey(InputSystem.inputs.gamepad.down).held
			and InputSystem.getCustomKey(InputSystem.inputs.gamepad.up).held
		then
			Up = 0
		elseif InputSystem.getCustomKey(InputSystem.inputs.gamepad.up).held then
			Up = 1
		elseif InputSystem.getCustomKey(InputSystem.inputs.gamepad.down).held then
			Up = -1
		else
			Up = 0
		end
		return
	end

	if
		InputSystem.getCustomKey(InputSystem.inputs.keyboard.down).held
		and InputSystem.getCustomKey(InputSystem.inputs.keyboard.up).held
	then
		Up = 0
	elseif InputSystem.getCustomKey(InputSystem.inputs.keyboard.up).held then
		Up = 1
	elseif InputSystem.getCustomKey(InputSystem.inputs.keyboard.down).held then
		Up = -1
	else
		Up = 0
	end
end

function moveCamera()
	local forwardDirection = camera.rotation:getForwardVector()
	local rightDirection = camera.rotation:getRightVector()
	local upDirection = camera.rotation:getUpVector()

	if currentSpeedIndex <= targetSpeedIndex then
		gearShiftTime = math.min(gearShiftTime + deltaTime, gearShiftTimeRequired)
		if gearShiftTime >= gearShiftTimeRequired and currentSpeedIndex < targetSpeedIndex then
			currentSpeedIndex += 1
			gearShiftTime = 0
		end
	elseif currentSpeedIndex > targetSpeedIndex then
		gearShiftTime = math.max(gearShiftTime - deltaTime, 0)
		if gearShiftTime <= 0 then
			currentSpeedIndex -= 1
			gearShiftTime = gearShiftTimeRequired
		end
	end

	local speedMultiplier = Util.lerp(
		speedGears[math.max(currentSpeedIndex - 1, 1)],
		speedGears[currentSpeedIndex],
		gearShiftTime / gearShiftTimeRequired
	)

	local forwardMovement = forwardDirection * Vertical * speedMultiplier * 100 * deltaTime
	local sidewaysMovement = rightDirection * Horizontal * speedMultiplier * 100 * deltaTime
	local upwardsMovement = upDirection * Up * speedMultiplier * 50 * deltaTime

	cameraVelocity = (forwardMovement + sidewaysMovement + upwardsMovement)

	cameraPosition += cameraVelocity

	camera.position = Vec3.lerp(camera.position, cameraPosition, deltaTime / (cameraPositionSmoothing + deltaTime))
end

function rotateCamera()
	if InputSystem.keyToBeRebinded.key ~= "" then
		-- don't read input on rebind
		return
	end

	local mouse = Input.getMouseDelta()
	local adjustedLookSmoothness = 1 - (1 - dynamicLookSmoothness) ^ 3

	if invertMouseLookHorizontal then
		mouse.x = -mouse.x
	end

	if invertMouseLookVertical then
		mouse.y = -mouse.y
	end

	-- Keyboard
	if InputSystem.getCustomKey(InputSystem.inputs.keyboard.lookAround).held then
		turnVelocity = Vec2.new(mouse.x, mouse.y) * 10
		rotDelta += Vec3.new(0, turnVelocity.y, turnVelocity.x) * mouseSensitivity
	end

	-- Gamepad
	turnVelocity = Vec2.new(
		InputSystem.getCustomAnalog(InputSystem.inputs.gamepad.lookX),
		InputSystem.getCustomAnalog(InputSystem.inputs.gamepad.lookY)
	) * controllerSensitivity * 2

	if invertControllerLookHorizontal then
		turnVelocity.x = -turnVelocity.x
	end

	if invertControllerLookVertical then
		turnVelocity.y = -turnVelocity.y
	end

	rotDelta += Vec3.new(0, turnVelocity.y, turnVelocity.x)

	local nextLookDiff = rotDelta * math.min((1 - adjustedLookSmoothness) * deltaTime * 60, 1)

	local upRotation = getGravityUp()
	gravityChaser = Quat.slerp(gravityChaser, upRotation, math.min((1 - adjustedLookSmoothness) * deltaTime * 60, 1))

	rotEuler += nextLookDiff
	rotDelta -= nextLookDiff

	rotEuler.y = math.clamp(rotEuler.y, -89.99, 89.99)
	camera.rotation = gravityChaser * Quat.fromEuler(rotEuler.x, rotEuler.y, rotEuler.z)
end

function checkForPossessionChange(newTeam: string, newTeamIndex: number, newPlayer: ReplayPlayer)
	if not selectedArena.isGameActive then
		return
	end

	local previousTeam = getPossessionTeam()
	if previousTeam == nil then
		return
	end

	local previousTeamInfo = ballCollisionInfo[previousTeam]
	if previousTeamInfo.current == nil then
		return
	end

	local previousPlayer = previousTeamInfo.current.player

	if previousTeam == newTeam then
		Overlay.increaseStat(newTeamIndex, previousPlayer.playerName, "passes")
		return
	end

	local losingTeamIndex = previousTeam == "home" and Util.TeamIndex.HomeTeam or Util.TeamIndex.AwayTeam

	Overlay.increaseStat(newTeamIndex, newPlayer.playerName, "possessionsWon")
	Overlay.increaseStat(losingTeamIndex, previousPlayer.playerName, "possessionsLost")
end

function checkBallContact()
	local segmentStart = previousContactCheckBallPosition or ball.transform.position
	local segmentEnd = ball.transform.position
	previousContactCheckBallPosition = segmentEnd

	local contactPlayer: ReplayPlayer? = getClosestPlayerToBallSegment(segmentStart, segmentEnd, 30)
	if contactPlayer == nil then
		return
	end

	local contactTime = os.clock()

	if contactPlayer.teamIndex == Util.TeamIndex.HomeTeam then
		if
			ballCollisionInfo.home.current
			and contactPlayer.playerId == ballCollisionInfo.home.current.player.playerId
		then
			ballCollisionInfo.home.current.lastContactPlace = ball.transform.position
			return
		end
		checkForPossessionChange("home", Util.TeamIndex.HomeTeam, contactPlayer)
		ballCollisionInfo.home.previous = ballCollisionInfo.home.current
		ballCollisionInfo.home.current = {
			lastContactPlace = ball.transform.position,
			contactTime = contactTime,
			player = contactPlayer,
		}
	elseif contactPlayer.teamIndex == Util.TeamIndex.AwayTeam then
		if
			ballCollisionInfo.away.current
			and contactPlayer.playerId == ballCollisionInfo.away.current.player.playerId
		then
			ballCollisionInfo.away.current.lastContactPlace = ball.transform.position
			return
		end
		checkForPossessionChange("away", Util.TeamIndex.AwayTeam, contactPlayer)
		ballCollisionInfo.away.previous = ballCollisionInfo.away.current
		ballCollisionInfo.away.current = {
			lastContactPlace = ball.transform.position,
			contactTime = contactTime,
			player = contactPlayer,
		}
	end
end

function getLastPlayerWithBall(): { contactTime: number, player: ReplayPlayer }?
	local homePlayer: { contactTime: number, player: ReplayPlayer }
	local awayPlayer: { contactTime: number, player: ReplayPlayer }
	if ballCollisionInfo.home.current then
		homePlayer = ballCollisionInfo.home.current
	else
		return
	end

	if ballCollisionInfo.away.current then
		awayPlayer = ballCollisionInfo.away.current
	else
		return
	end

	if homePlayer.contactTime > awayPlayer.contactTime then
		return homePlayer
	elseif awayPlayer.contactTime > homePlayer.contactTime then
		return awayPlayer
	else
		return nil
	end
end

function getPossessionTeam(): string?
	if ballCollisionInfo.home.current == nil and ballCollisionInfo.away.current == nil then
		return nil
	end

	if ballCollisionInfo.home.current == nil then
		return "away"
	end

	if ballCollisionInfo.away.current == nil then
		return "home"
	end

	if ballCollisionInfo.home.current.contactTime > ballCollisionInfo.away.current.contactTime then
		return "home"
	else
		return "away"
	end
end

function getAssistPlayer(team: string): ReplayPlayer?
	local possessionTeam = ballCollisionInfo[team]

	if possessionTeam.current == nil or possessionTeam.previous == nil then
		return nil
	end

	if os.clock() - possessionTeam.current.contactTime < maximumTimeSincePass then
		return possessionTeam.previous.player
	else
		return nil
	end
end

function checkForShot()
	local possesionTeamString: string? = getPossessionTeam()

	if not possesionTeamString then
		return
	end

	local possessionTeam = ballCollisionInfo[possesionTeamString]

	if possessionTeam.current == nil then
		return
	end

	if possessionTeam.current.player ~= currentShotPlayer then
		currentShotPlayer = possessionTeam.current.player
		shotDetected = false
	end

	local separationDistance = Util.getDist(ball.transform.position, possessionTeam.current.lastContactPlace)
	local isSeparated = separationDistance >= shotSeparationDistance

	if not isSeparated or shotDetected then
		return
	end

	if homeGoalPotentialEnter and possessionTeam.current.player.teamIndex == Util.TeamIndex.AwayTeam then
		shotDetected = true
		Overlay.increaseStat(Util.TeamIndex.AwayTeam, possessionTeam.current.player.playerName, "shots")
	elseif awayGoalPotentialEnter and possessionTeam.current.player.teamIndex == Util.TeamIndex.HomeTeam then
		shotDetected = true
		Overlay.increaseStat(Util.TeamIndex.HomeTeam, possessionTeam.current.player.playerName, "shots")
	end
end

function checkForGoalPotential(): boolean
	local successfulPotential = false
	local possesionTeamString: string? = getPossessionTeam()

	if not possesionTeamString then
		return successfulPotential
	end

	local possessionTeam = ballCollisionInfo[possesionTeamString]

	if possessionTeam.current == nil then
		return successfulPotential
	end

	if homeGoalPotentialEnter and not previousHomeGoalPotentialEnter then
		if possessionTeam.current.player.teamIndex == Util.TeamIndex.AwayTeam then
			goalPlayer = possessionTeam.current.player
			successfulPotential = true
		end
	end

	if awayGoalPotentialEnter and not previousAwayGoalPotentialEnter then
		if possessionTeam.current.player.teamIndex == Util.TeamIndex.HomeTeam then
			goalPlayer = possessionTeam.current.player
			successfulPotential = true
		end
	end

	return successfulPotential
end

function checkForSave(goal: { team: string, dist: number }): boolean
	local goalie = getClosestPlayerToBall(60)
	local lastPlayerWithBall = getLastPlayerWithBall()

	local successfulSave = false

	if not lastPlayerWithBall then
		return false
	end

	local isHomeGoal = goal.team == "home"
	local isAwayGoal = goal.team == "away"

	if not isHomeGoal and not isAwayGoal then
		return false
	end

	local goalPotentialEnter = isHomeGoal and homeGoalPotentialEnter or awayGoalPotentialEnter
	local previousGoalPotentialEnter = isHomeGoal and previousHomeGoalPotentialEnter or previousAwayGoalPotentialEnter
	local teamIndex = isHomeGoal and Util.TeamIndex.HomeTeam or Util.TeamIndex.AwayTeam

	if goalPotentialEnter then
		return false
	end
	if not previousGoalPotentialEnter then
		return false
	end
	if goal.dist > 600 then
		return false
	end
	if not goalie or goalie.teamIndex ~= teamIndex then
		return false
	end

	if lastPlayerWithBall.player.teamIndex == teamIndex then
		-- The player who last touched the ball could be the goalie saving it
		if os.clock() - lastPlayerWithBall.contactTime > 0.25 then
			-- The player touched the ball way too long ago for it to be the goalie
			return false
		end
	end

	successfulSave = true
	resetPlayersWithBall()
	Overlay.increaseStat(teamIndex, goalie.playerName, "saves")

	return successfulSave
end

function earlyStatChangeReturn(ballExit: boolean)
	if ballExit then
		homeGoalPotentialEnter = false
		awayGoalPotentialEnter = false
	end

	previousHomeGoalPotentialEnter = homeGoalPotentialEnter
	previousAwayGoalPotentialEnter = awayGoalPotentialEnter
end

function checkPotentialStatChange(homeGoalBox: BoxType, awayGoalBox: BoxType)
	if selectedArena.isGracePeriod then
		earlyStatChangeReturn(true)
		return
	end

	local ballToHomeGoalDist = Util.getDist(ball.transform.position, homeGoalBox.position)
	local ballToAwayGoalDist = Util.getDist(ball.transform.position, awayGoalBox.position)
	local closestGoal = {}

	if ballToHomeGoalDist < ballToAwayGoalDist then
		closestGoal.team = "home"
		closestGoal.dist = ballToHomeGoalDist
	else
		closestGoal.team = "away"
		closestGoal.dist = ballToAwayGoalDist
	end

	if closestGoal.team == "home" then
		local ballHomePotentialPosition = ball.transform.position + (ball.velocity:normalize() * ballToHomeGoalDist)
		local homeHit = camera:castRay(ball.transform.position, ballHomePotentialPosition)

		if homeHit.successful then
			local velocityDotNormal = ball.velocity:dot(homeHit.normal)
			local reflectedVelocityNormalized = (ball.velocity - (homeHit.normal * (2 * velocityDotNormal))):normalize()
			local distanceLeft = Util.getDist(homeHit.position, homeGoalBox.position)

			ballHomePotentialPosition = homeHit.position + (reflectedVelocityNormalized * distanceLeft)
		end

		if
			homeGoalBox:checkPointIntersect(ballHomePotentialPosition)
			or homeGoalBox:checkPointIntersect(homeHit.position)
		then
			homeGoalPotentialEnter = true
		else
			homeGoalPotentialEnter = false
		end
		awayGoalPotentialEnter = false
	else
		local ballAwayPotentialPosition = ball.transform.position + (ball.velocity:normalize() * ballToAwayGoalDist)

		local awayHit = camera:castRay(ball.transform.position, ballAwayPotentialPosition)

		if awayHit.successful then
			local velocityDotNormal = ball.velocity:dot(awayHit.normal)
			local reflectedVelocityNormalized = (ball.velocity - (awayHit.normal * (2 * velocityDotNormal))):normalize()
			local distanceLeft = Util.getDist(awayHit.position, awayGoalBox.position)

			ballAwayPotentialPosition = awayHit.position + (reflectedVelocityNormalized * distanceLeft)
		end

		if
			awayGoalBox:checkPointIntersect(ballAwayPotentialPosition)
			or awayGoalBox:checkPointIntersect(awayHit.position)
		then
			awayGoalPotentialEnter = true
		else
			awayGoalPotentialEnter = false
		end
		homeGoalPotentialEnter = false
	end

	checkBallContact()

	checkForShot()

	if checkForGoalPotential() then
		earlyStatChangeReturn(false)
		return
	end

	if checkForSave(closestGoal) then
		earlyStatChangeReturn(false)
		return
	end

	previousHomeGoalPotentialEnter = homeGoalPotentialEnter
	previousAwayGoalPotentialEnter = awayGoalPotentialEnter
end

function goalScoreCheck()
	if selectedArena.home.goal then
		local homeGoalBox: BoxType = selectedArena.home.goal.box
		local awayGoalBox: BoxType = selectedArena.away.goal.box

		checkPotentialStatChange(homeGoalBox, awayGoalBox)
	end

	-- the ball has newely scored
	if selectedArena.away.scoreIncrease then
		DoGoalExplosion(selectedArena.away)

		local shooterName = ""
		local assistName = ""
		local shotFrom: Vec3

		if ballCollisionInfo.away.current then
			shooterName = ballCollisionInfo.away.current.player.playerName
			shotFrom = ballCollisionInfo.away.current.lastContactPlace
		end

		local shotDistance: number = 0
		if shotFrom then
			shotDistance = Util.getDist(shotFrom, ball.transform.position) / 100
		end

		local assistPlayer = getAssistPlayer("away")

		if assistPlayer then
			assistName = assistPlayer.playerName
		end

		Overlay.setShotInfo({
			shooter = shooterName,
			assister = assistName,
			team = Util.TeamIndex.AwayTeam,
			shotSpeed = ball.velocity:length() / 100,
			shotDistanceMeters = shotDistance,
		})

		if goalPlayer then
			resetPlayersWithBall()

			Overlay.increaseStat(Util.TeamIndex.AwayTeam, goalPlayer.playerName, "goals")

			if assistPlayer then
				Overlay.increaseStat(Util.TeamIndex.AwayTeam, assistPlayer.playerName, "assists")

				assistPlayer = nil
			end
		end
	end

	if selectedArena.home.scoreIncrease then
		DoGoalExplosion(selectedArena.home)

		local shooterName = ""
		local assistName = ""
		local shotFrom: Vec3

		if ballCollisionInfo.home.current then
			shooterName = ballCollisionInfo.home.current.player.playerName
			shotFrom = ballCollisionInfo.home.current.lastContactPlace
		end

		local shotDistance: number = 0
		if shotFrom then
			shotDistance = Util.getDist(shotFrom, ball.transform.position) / 100
		end

		local assistPlayer = getAssistPlayer("home")

		if assistPlayer then
			assistName = assistPlayer.playerName
		end

		Overlay.setShotInfo({
			shooter = shooterName,
			assister = assistName,
			team = Util.TeamIndex.HomeTeam,
			shotSpeed = ball.velocity:length() / 100,
			shotDistanceMeters = shotDistance,
		})

		if goalPlayer then
			resetPlayersWithBall()

			Overlay.increaseStat(Util.TeamIndex.HomeTeam, goalPlayer.playerName, "goals")
			if assistPlayer then
				Overlay.increaseStat(Util.TeamIndex.HomeTeam, assistPlayer.playerName, "assists")

				assistPlayer = nil
			end
		end
	end
end

function ballInCenterCheck()
	local isKickoff = selectedArena.isKickoff
	if isKickoff and selectedArena.actionTimerSeconds == 0 then
		resetPlayersWithBall()
		GameStartEffect()
		selectedArena.isKickoff = false
	end
end

function drawBallOutline()
	if not ballOutline or not ball then
		return
	end

	ui:tick()

	local ballPosition: Vec3 = ball.transform.position
	local ballDistance: number = Util.getDist(camera.position, ballPosition)
	local ballRadius = 17.5

	local minimumRenderDistance: number = ballRadius + 10

	-- only disable render on live data. Replays are smooth as butter.
	if readLocation == 0 and ballDistance <= minimumRenderDistance then
		return
	end

	local ballHUDPosition: Vec2 = ui:worldToHUD(ballPosition)

	if ballHUDPosition == Vec2.zeroVector then
		return
	end

	local segments = 20
	local angleStep = (2 * math.pi) / segments
	local thickness = (ui.depth / 50) / (ballDistance / 100)

	local camToBall = (ballPosition - camera.position):getSafeNormal()

	-- Create perpendicular vectors for the circle plane
	local right = camToBall:cross(camera.rotation:getUpVector()):getSafeNormal()
	local up = right:cross(camToBall):getSafeNormal()

	local points = {}
	for i = 0, segments do
		local angle = i * angleStep
		local x = ballRadius * math.cos(angle)
		local y = ballRadius * math.sin(angle)

		-- Calculate 3D world position on the sphere
		local worldPoint = ballPosition + (right * x) + (up * y)

		-- Project to HUD space
		local point: Vec2 = ui:worldToHUD(worldPoint)

		if point == Vec2.zeroVector then
			points = {} -- reset so none are drawn
			break
		end

		table.insert(points, point)
	end

	if #points == 0 then
		return
	end

	for i, point in points do
		if i == 1 then
			continue -- skip the first
		end

		local lastPoint = points[i - 1]
		ui:drawLine(lastPoint, point, Vec3.oneVector, thickness, 0)
	end
end

function debugCode()
	if showGamemodePositions then
		debugGamemodePositions()
	end

	if arenas and boundingBoxDebug then
		for _, arena in arenas do
			arena.box:renderFaces(LinearColor.new(1, 0, 1, 0.5))
			arena.centerBox:render(0, 1, 0)
			arena.home.goal.box:render(1, 0, 0)
			arena.away.goal.box:render(0, 0, 1)
			for _, boostPad in arena.boostPads do
				boostPad.box:render(1, 1, 0)
			end
		end
	end

	if ball and debugBallPrediction then
		BallSim:simBallPath(ball, overviewPredictionSteps, overviewPredictionTime / overviewPredictionSteps)
		BallSim:renderBallPath()
	end
end

function onExit()
	if povFollow then
		stopFollow()
	end
end

function tick(dt)
	Profiler:tick(dt)
	if not camera.isActive and not camera.isFollowed then
		alwaysTick = nil
		onExit()
		return
	end

	WorldDraw.clear()

	if cachedGamemodesAmount ~= #SpectatorGamemodes.listGamemodeIds() then
		arenas = getArenas()
		if arenas and #arenas > 0 then
			setSelectedArena(arenas[1])
		end
		cachedGamemodesAmount = #SpectatorGamemodes.listGamemodeIds()
	end

	InputSystem.readInputStart()

	deltaTime = dt
	camera.fieldOfView = cameraFOV

	gameData = Util.getReplayFrameFromIndex(readLocation)

	if selectedArena == nil then
		toggleSmoothing(true, true)
		readInput()

		moveCamera()
		rotateCamera()
		InputSystem.readInputEnd()
		return
	end

	selectedArena:tick()
	ball = selectedArena.ball

	Possession:tick(dt)
	Boost:tick(dt)

	if #gameData.players < 1 and povFollow then
		stopFollow()
	end

	if ball and debugFreecam then
		drawBallOutline()
		return
	end

	if povFollow then
		followPlussTick(dt, camera)
		Util.followCamera(followPlussId)
		readOtherInputs()
	else
		toggleSmoothing(true, true)
		readInput()

		moveCamera()
		rotateCamera()
		drawBallOutline()
	end

	if readLocation > 0 then
		ParticleSystem.replay = Replay.getByIndex(readLocation)
	else
		ParticleSystem.replay = nil
	end
	ParticleSystem:particleAffect()
	ballInCenterCheck()
	if ball then
		goalScoreCheck()
	end

	if sendOverlayInfo then
		Overlay.setPossession({
			possessionSeconds = Possession.possessionSeconds,
			possessionSecondsByPlayer = Possession.possessionSecondsByPlayer,
		})
		Overlay.setBoost(Boost.statsByPlayer)
		Overlay.tick()
	end

	InputSystem.readInputEnd()

	debugCode()
end

tick = Profiler:wrapScriptTick(tick)
