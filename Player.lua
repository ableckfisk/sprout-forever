-- Live information about the player's own character, read from the API when
-- needed rather than stored, so it never goes stale.
local _, ns = ...

local Sprout = ns.addon

local Player = {}
ns.Player = Player

function Player.GetRealm()
	local _, realm = UnitFullName("player")

	if realm and realm ~= "" then
		return realm
	end

	return GetNormalizedRealmName() or ""
end

-- "Name-Realm" for the player's own character; the key format used
-- everywhere in the roster and in private notes.
function Player.GetFullName()
	local name = UnitName("player")

	return name .. "-" .. Player.GetRealm()
end

-- Senders in CHAT_MSG_ADDON normally arrive as "Name-Realm", but same-realm
-- names can be delivered without the realm suffix on some builds.
function Player.NormalizeName(sender)
	if not sender or sender == "" then
		return nil
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

-- Everything another client needs to list us in its roster.
function Player.GetPresence()
	return {
		role = Sprout:GetRole(),
		level = Player.GetLevel(),
		class = Player.GetClassToken(),
		zone = Player.GetZone(),
		note = Sprout:GetOwnNote(),
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
