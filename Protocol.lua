-- Wire format for messages sent over the hidden channel.
--
-- Pure Lua: no WoW API calls, so it can be unit tested outside the game.
--
-- Layout:  <version>;<type>;<key>=<value>;<key>=<value>...
-- Example: 1;HB;r=M;l=42;c=MAGE;z=Elwynn Forest;n=PvP specialist
--
-- Key/value pairs (rather than fixed positions) mean a future client can add
-- fields, such as a "changed since last heartbeat" flag, without breaking
-- older clients: unknown keys are ignored, missing keys are nil. The sender's
-- name and realm are never part of the payload; the client supplies them
-- with the CHAT_MSG_ADDON event and they cannot be spoofed that way.
local _, ns = ...

local Constants = ns.Constants

local Protocol = {}
ns.Protocol = Protocol

local FIELD_DELIMITER = ";"
local PAIR_DELIMITER = "="

local FIELD_KEYS = {
	role = "r",
	level = "l",
	class = "c",
	zone = "z",
	note = "n",
	interval = "i",
}

local ROLE_TO_WIRE = {
	[Constants.ROLES.SPROUT] = "S",
	[Constants.ROLES.MENTOR] = "M",
}

local ROLE_FROM_WIRE = {
	S = Constants.ROLES.SPROUT,
	M = Constants.ROLES.MENTOR,
}

local VALID_TYPES = {}
for _, messageType in pairs(Constants.MESSAGE_TYPES) do
	VALID_TYPES[messageType] = true
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Strips anything that would break the delimiter-based format or render
-- strangely in the UI: field delimiters, control characters, newlines.
function Protocol.SanitizeValue(value)
	if value == nil then
		return ""
	end

	local text = tostring(value)

	text = text:gsub("[%c]", " ")
	text = text:gsub(FIELD_DELIMITER, ",")

	return trim(text)
end

-- Truncates a UTF-8 string to at most `maxBytes` bytes without splitting a
-- multi-byte character.
function Protocol.TruncateUtf8(text, maxBytes)
	if #text <= maxBytes then
		return text
	end

	local cut = maxBytes

	while cut > 0 do
		local byte = text:byte(cut + 1)
		local isContinuationByte = byte ~= nil and byte >= 0x80 and byte <= 0xBF

		if not isContinuationByte then
			break
		end

		cut = cut - 1
	end

	return text:sub(1, cut)
end

function Protocol.SanitizeNote(note)
	return Protocol.TruncateUtf8(Protocol.SanitizeValue(note), Constants.MAX_NOTE_LENGTH)
end

function Protocol.RoleToWire(role)
	return ROLE_TO_WIRE[role]
end

function Protocol.RoleFromWire(code)
	return ROLE_FROM_WIRE[code]
end

-- Encodes a message. `fields` is an optional table of short key -> value.
-- Keys are emitted in sorted order so output is deterministic.
function Protocol.Encode(messageType, fields)
	assert(VALID_TYPES[messageType], "unknown message type: " .. tostring(messageType))

	local parts = { tostring(Constants.PROTOCOL_VERSION), messageType }
	local keys = {}

	for key in pairs(fields or {}) do
		keys[#keys + 1] = key
	end

	table.sort(keys)

	for _, key in ipairs(keys) do
		local value = Protocol.SanitizeValue(fields[key])

		if value ~= "" then
			parts[#parts + 1] = key .. PAIR_DELIMITER .. value
		end
	end

	return table.concat(parts, FIELD_DELIMITER)
end

-- Encodes a presence announcement (heartbeat or HERE reply) from a presence
-- table { role, level, class, zone, note, interval }. The note is shortened
-- until the whole message fits in a single addon message.
function Protocol.EncodePresence(messageType, presence)
	local note = Protocol.SanitizeNote(presence.note or "")

	local function build(noteText)
		return Protocol.Encode(messageType, {
			[FIELD_KEYS.role] = Protocol.RoleToWire(presence.role),
			[FIELD_KEYS.level] = presence.level,
			[FIELD_KEYS.class] = presence.class,
			[FIELD_KEYS.zone] = presence.zone,
			[FIELD_KEYS.note] = noteText,
			[FIELD_KEYS.interval] = presence.interval,
		})
	end

	local text = build(note)

	while #text > Constants.MAX_ADDON_MESSAGE_LENGTH and note ~= "" do
		note = Protocol.TruncateUtf8(note, #note - 10)
		text = build(note)
	end

	if #text > Constants.MAX_ADDON_MESSAGE_LENGTH then
		-- Zone names are the only remaining variable-length field; drop it
		-- rather than let the client silently truncate the message.
		text = Protocol.Encode(messageType, {
			[FIELD_KEYS.role] = Protocol.RoleToWire(presence.role),
			[FIELD_KEYS.level] = presence.level,
			[FIELD_KEYS.class] = presence.class,
			[FIELD_KEYS.interval] = presence.interval,
		})
	end

	return text
end

-- Decodes a raw message into { version, type, fields } or nil plus a reason.
-- Messages from newer protocol versions are still parsed; only fields we
-- understand are used.
function Protocol.Decode(text)
	if type(text) ~= "string" or text == "" then
		return nil, "empty"
	end

	local version, messageType, rest = text:match("^(%d+)" .. FIELD_DELIMITER .. "([A-Z]+)(.*)$")

	if not version then
		return nil, "malformed"
	end

	if not VALID_TYPES[messageType] then
		return nil, "unknown type"
	end

	local fields = {}

	for pair in rest:gmatch("[^" .. FIELD_DELIMITER .. "]+") do
		local key, value = pair:match("^([^" .. PAIR_DELIMITER .. "]+)" .. PAIR_DELIMITER .. "(.*)$")

		if key then
			fields[key] = value
		end
	end

	return {
		version = tonumber(version),
		type = messageType,
		fields = fields,
	}
end

-- Converts decoded presence fields into the roster's presence shape.
-- Returns nil if the message carries no usable role.
function Protocol.PresenceFromFields(fields)
	local role = Protocol.RoleFromWire(fields[FIELD_KEYS.role])

	if not role then
		return nil
	end

	return {
		role = role,
		level = tonumber(fields[FIELD_KEYS.level]) or 0,
		class = fields[FIELD_KEYS.class] or "",
		zone = fields[FIELD_KEYS.zone] or "",
		note = fields[FIELD_KEYS.note] or "",
		-- nil when the sender predates the field; the receiver falls back
		-- to the base interval.
		interval = tonumber(fields[FIELD_KEYS.interval]),
	}
end
