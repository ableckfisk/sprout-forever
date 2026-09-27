-- Every file in a WoW addon is loaded with two varargs: the addon folder name
-- and a private table shared by all files of this addon. We use that table
-- (`ns`) as the namespace for internal modules instead of polluting globals.
local _, ns = ...

ns.Constants = {
	ADDON_NAME = "Sprout",

	-- Addon message prefix (max 16 characters). Registered with the client so
	-- CHAT_MSG_ADDON events for it are delivered to us.
	COMM_PREFIX = "SproutFvr",

	-- Bump when the wire format changes in a way old clients cannot parse.
	PROTOCOL_VERSION = 1,

	-- Hidden custom chat channel used for discovery. Deliberately obscure so it
	-- does not collide with player-created channels. The password only guards
	-- against accidental collisions; it is public in the source.
	CHANNEL_NAME = "SproutFvrMentor7",
	CHANNEL_PASSWORD = "sproutfvr2026",

	-- Presence timings (seconds).
	HEARTBEAT_INTERVAL = 120,
	MISSED_HEARTBEATS_BEFORE_EXPIRY = 3,
	ROSTER_SWEEP_INTERVAL = 30,
	HERE_REPLY_MAX_JITTER = 2,
	WHO_ONLINE_COOLDOWN = 10,
	PRESENCE_CHANGE_DEBOUNCE = 1,

	-- Channel join behaviour (seconds / attempts).
	CHANNEL_JOIN_INITIAL_DELAY = 3,
	CHANNEL_JOIN_RETRY_DELAY = 5,
	CHANNEL_JOIN_MAX_ATTEMPTS = 12,
	CHANNEL_HEALTH_CHECK_INTERVAL = 60,

	-- Own note is broadcast, so it is capped to keep messages under 255 bytes.
	MAX_NOTE_LENGTH = 80,
	MAX_ADDON_MESSAGE_LENGTH = 255,

	ROLES = {
		OFF = "OFF",
		SPROUT = "SPROUT",
		MENTOR = "MENTOR",
	},

	ROLE_LABELS = {
		OFF = "Off",
		SPROUT = "Sprout",
		MENTOR = "Mentor",
	},

	MESSAGE_TYPES = {
		HEARTBEAT = "HB",
		WHO_ONLINE = "WHO",
		HERE = "HERE",
		GOODBYE = "BYE",
	},

	-- AceEvent messages used for in-addon decoupling between modules.
	EVENTS = {
		CHANNEL_JOINED = "SPROUT_CHANNEL_JOINED",
		CHANNEL_LEFT = "SPROUT_CHANNEL_LEFT",
		ROLE_CHANGED = "SPROUT_ROLE_CHANGED",
		PRESENCE_CHANGED = "SPROUT_PRESENCE_CHANGED",
		ROSTER_UPDATED = "SPROUT_ROSTER_UPDATED",
		PLAYER_NOTE_CHANGED = "SPROUT_PLAYER_NOTE_CHANGED",
	},
}

ns.Constants.ROSTER_EXPIRY = ns.Constants.HEARTBEAT_INTERVAL * ns.Constants.MISSED_HEARTBEATS_BEFORE_EXPIRY
	+ ns.Constants.ROSTER_SWEEP_INTERVAL
