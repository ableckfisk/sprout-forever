-- Live information about the player's own character, read from the API when
-- needed rather than stored, so it never goes stale.
local _, ns = ...

local Sprout = ns.addon

local Player = {}
ns.Player = Player

-- WoW Forever uses "regional unique names": every character has a first
-- name and a surname ("Mehrno Onrhem") that is unique across the region, and
-- there is no realm. Classic/retail instead identify characters as
-- "Name-Realm". Both formats are supported so the same key logic works
-- wherever the addon runs, but on Forever the key is simply "First Surname".
function Player.UsesRegionalUniqueNames()
	return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end

function Player.GetRealm()
	if Player.UsesRegionalUniqueNames() then
		return nil
	end

	local _, realm = UnitFullName("player")

	if realm and realm ~= "" then
		return realm
	end

	return GetNormalizedRealmName() or ""
end

-- The player's own identity key, as used in the roster and private notes:
-- "First Surname" on Forever, "Name-Realm" elsewhere.
function Player.GetFullName()
	if Player.UsesRegionalUniqueNames() then
		local name, surname = UnitNameUnmodified("player")

		if surname and surname ~= "" then
			return name .. " " .. surname
		end

		return name
	end

	return UnitName("player") .. "-" .. Player.GetRealm()
end

-- Turns the sender string from CHAT_MSG_ADDON into a roster key.
-- On Forever anything after a dash is a leftover of the realm format and is
-- dropped; elsewhere a missing realm suffix is filled in from our own realm.
function Player.NormalizeName(sender)
	if not sender or sender == "" then
		return nil
	end

	if Player.UsesRegionalUniqueNames() then
		return (sender:gsub("%-.*$", ""))
	end

	if sender:find("-", 1, true) then
		return sender
	end

	return sender .. "-" .. Player.GetRealm()
end

function Player.GetLevel()
	return UnitLevel("player") or 0
end

-- Locale-independent class token such as "MAGE".
function Player.GetClassToken()
	local _, classToken = UnitClass("player")

	return classToken or ""
end

function Player.GetZone()
	local zone = GetRealZoneText()

	if zone and zone ~= "" then
		return zone
	end

	local mapId = C_Map and C_Map.GetBestMapForUnit("player")
	local mapInfo = mapId and C_Map.GetMapInfo(mapId)

	return mapInfo and mapInfo.name or ""
end

-- Everything another client needs to list us in its roster. `interval` is
-- how often we currently heartbeat, so receivers know when to expire us.
function Player.GetPresence(interval)
	return {
		role = Sprout:GetRole(),
		level = Player.GetLevel(),
		class = Player.GetClassToken(),
		zone = Player.GetZone(),
		note = Sprout:GetOwnNote(),
		interval = interval,
	}
end

-- Display helpers ------------------------------------------------------------

function Player.GetClassColor(classToken)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]

	if color then
		return color.r, color.g, color.b
	end

	return 1, 1, 1
end

function Player.GetClassName(classToken)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken]) or classToken or ""
end

function Player.ColorizeByClass(text, classToken)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]

	if color and color.colorStr then
		return "|c" .. color.colorStr .. text .. "|r"
	end

	local r, g, b = Player.GetClassColor(classToken)

	return string.format("|cff%02x%02x%02x%s|r",
		math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end
