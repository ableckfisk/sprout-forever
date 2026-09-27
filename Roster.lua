-- In-memory roster of players currently announcing a role.
--
-- Pure Lua, no WoW API. Never persisted: it is rebuilt every session from
-- heartbeat traffic. Keyed by "Name-Realm".
local _, ns = ...

local Roster = {}
Roster.__index = Roster
ns.Roster = Roster

local PRESENCE_FIELDS = { "role", "level", "class", "zone", "note" }

function Roster.New()
	return setmetatable({ entries = {} }, Roster)
end

-- Splits "Name-Realm" into its parts. Realm is nil when absent, which is
-- always the case on WoW Forever where keys are "First Surname".
function Roster.SplitKey(key)
	local name, realm = key:match("^([^%-]+)%-(.+)$")

	if not name then
		return key, nil
	end

	return name, realm
end

-- Inserts or refreshes an entry, keeping it alive for `ttl` seconds. Returns
-- true when something visible changed (new player, or a presence field
-- differs), so callers can skip UI refreshes for routine heartbeats.
function Roster:Upsert(key, presence, now, ttl)
	local entry = self.entries[key]
	local changed = false

	if not entry then
		local name, realm = Roster.SplitKey(key)

		entry = { key = key, name = name, realm = realm }
		self.entries[key] = entry
		changed = true
	end

	for _, field in ipairs(PRESENCE_FIELDS) do
		if entry[field] ~= presence[field] then
			entry[field] = presence[field]
			changed = true
		end
	end

	entry.lastSeen = now
	entry.expiresAt = now + (ttl or 0)

	return changed
end

function Roster:Remove(key)
	if not self.entries[key] then
		return false
	end

	self.entries[key] = nil

	return true
end

function Roster:Get(key)
	return self.entries[key]
end

-- Drops entries whose time-to-live has passed. Returns the number removed.
function Roster:Expire(now)
	local removed = 0

	for key, entry in pairs(self.entries) do
		if entry.expiresAt <= now then
			self.entries[key] = nil
			removed = removed + 1
		end
	end

	return removed
end

function Roster:Count()
	local count = 0

	for _ in pairs(self.entries) do
		count = count + 1
	end

	return count
end

function Roster:Clear()
	self.entries = {}
end

local SORTERS = {
	name = function(a, b)
		return a.key < b.key
	end,
	level = function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end

		return a.key < b.key
	end,
	zone = function(a, b)
		if a.zone ~= b.zone then
			return a.zone < b.zone
		end

		return a.key < b.key
	end,
}

-- Case-insensitive plain-text match against name, zone, class and note.
local function matchesFilter(entry, filter)
	if not filter or filter == "" then
		return true
	end

	local haystack = (entry.key .. " " .. (entry.zone or "") .. " " .. (entry.class or "") .. " " .. (entry.note or "")):lower()

	return haystack:find(filter, 1, true) ~= nil
end

-- Returns an array of entries with the given role, sorted by `sortKey`
-- ("name", "level" or "zone") and optionally narrowed by a filter string.
function Roster:GetByRole(role, sortKey, filter)
	local result = {}
	local normalizedFilter = filter and filter:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""

	for _, entry in pairs(self.entries) do
		if entry.role == role and matchesFilter(entry, normalizedFilter) then
			result[#result + 1] = entry
		end
	end

	table.sort(result, SORTERS[sortKey] or SORTERS.name)

	return result
end
