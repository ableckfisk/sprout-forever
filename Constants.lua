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
	--
	-- The heartbeat interval stretches with the size of the roster so total
	-- channel traffic stays roughly flat as a cluster fills up: base interval
	-- times (1 + rosterCount / HEARTBEAT_SCALE_STEP), capped at the maximum.
	-- Every heartbeat carries its sender's interval so receivers expire each
	-- entry on the sender's schedule, not ours.
	HEARTBEAT_INTERVAL = 120,
	HEARTBEAT_INTERVAL_MAX = 600,
	HEARTBEAT_SCALE_STEP = 250,
	MISSED_HEARTBEATS_BEFORE_EXPIRY = 3,
	ROSTER_SWEEP_INTERVAL = 30,

	-- WHO_ONLINE is only useful while our roster is younger than one base
	-- heartbeat interval; after that heartbeats have filled it. Replies are
	-- spread over a wide jitter window and coalesced, so a burst of logins
	-- costs the cluster one reply per player per window, not per request.
	WHO_ONLINE_WINDOW = 120,
	WHO_ONLINE_COOLDOWN = 10,
	HERE_REPLY_MAX_JITTER = 10,
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

-- Time-to-live for a roster entry whose sender heartbeats every `interval`.
-- The interval comes off the wire, so it is clamped to the range a genuine
-- client can produce: a bogus value can neither pin an entry forever nor
-- expire it before the next beat.
function ns.Constants.RosterTtl(interval)
	local C = ns.Constants
	local clamped = math.max(C.HEARTBEAT_INTERVAL, math.min(interval or C.HEARTBEAT_INTERVAL, C.HEARTBEAT_INTERVAL_MAX))

	return clamped * C.MISSED_HEARTBEATS_BEFORE_EXPIRY + C.ROSTER_SWEEP_INTERVAL
end

-- Heartbeat interval to use given how many players we currently see.
function ns.Constants.HeartbeatIntervalFor(rosterCount)
	local C = ns.Constants
	local steps = math.floor((rosterCount or 0) / C.HEARTBEAT_SCALE_STEP)

	return math.min(C.HEARTBEAT_INTERVAL_MAX, C.HEARTBEAT_INTERVAL * (1 + steps))
end
