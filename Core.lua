-- Addon object, saved variables and slash commands.
--
-- AceAddon gives us a lifecycle (OnInitialize runs once saved variables are
-- loaded, OnEnable when the player enters the world) and lets the other
-- files register themselves as modules with their own lifecycle hooks.
local ADDON_NAME, ns = ...

local Constants = ns.Constants

local Sprout = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
ns.addon = Sprout

-- Exposed globally for in-game debugging via /run.
_G.Sprout = Sprout

-- AceDB scopes:
--   char   -> stored per character (role, own note)
--   global -> stored once per account (private notes on other players, UI state)
local DB_DEFAULTS = {
	char = {
		role = Constants.ROLES.OFF,
		note = "",
	},
	global = {
		playerNotes = {},
		windowStatus = {},
		sortKey = "name",
		debug = false,
	},
}

function Sprout:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SproutDB", DB_DEFAULTS, true)
	self.roster = ns.Roster.New()

	self:RegisterChatCommand("sprout", "HandleSlashCommand")
end

function Sprout:OnEnable()
	self:Debug("enabled, build %s", select(4, GetBuildInfo()))
end

-- Role and own note --------------------------------------------------------

function Sprout:GetRole()
	return self.db.char.role
end

function Sprout:SetRole(role)
	if not Constants.ROLES[role] then
		return false
	end

	if self.db.char.role == role then
		return true
	end

	self.db.char.role = role
	self:SendMessage(Constants.EVENTS.ROLE_CHANGED, role)
	self:Print("Role set to " .. Constants.ROLE_LABELS[role] .. ".")

	return true
end

function Sprout:IsActive()
	return self.db.char.role ~= Constants.ROLES.OFF
end

function Sprout:GetOwnNote()
	return self.db.char.note or ""
end

function Sprout:SetOwnNote(note)
	local sanitized = ns.Protocol.SanitizeNote(note or "")

	if self.db.char.note == sanitized then
		return
	end

	self.db.char.note = sanitized
	self:SendMessage(Constants.EVENTS.PRESENCE_CHANGED)
end

-- Private notes on other players (account-wide) -----------------------------

function Sprout:GetPlayerNote(playerKey)
	return self.db.global.playerNotes[playerKey]
end

function Sprout:SetPlayerNote(playerKey, note)
	local trimmed = note and note:gsub("^%s+", ""):gsub("%s+$", "") or ""

	if trimmed == "" then
		self.db.global.playerNotes[playerKey] = nil
	else
		self.db.global.playerNotes[playerKey] = trimmed
	end

	self:SendMessage(Constants.EVENTS.PLAYER_NOTE_CHANGED, playerKey)
end

-- Slash commands ------------------------------------------------------------

local ROLE_ALIASES = {
	off = Constants.ROLES.OFF,
	sprout = Constants.ROLES.SPROUT,
	mentor = Constants.ROLES.MENTOR,
}

function Sprout:HandleSlashCommand(input)
	local command, nextPosition = self:GetArgs(input, 1)
	local rest = nextPosition and strtrim(input:sub(nextPosition)) or ""

	command = command and command:lower() or ""

	if command == "" or command == "show" or command == "toggle" then
		self:GetModule("RosterWindow"):Toggle()
	elseif command == "config" or command == "options" then
		self:GetModule("Options"):Open()
	elseif command == "role" then
		self:HandleRoleCommand(rest)
	elseif command == "note" then
		self:SetOwnNote(rest)
		self:Print("Note set to: " .. (self:GetOwnNote() ~= "" and self:GetOwnNote() or "(empty)"))
	elseif command == "status" then
		self:PrintStatus()
	elseif command == "debug" then
		self.db.global.debug = not self.db.global.debug
		self:Print("Debug logging " .. (self.db.global.debug and "enabled" or "disabled") .. ".")
	else
		self:PrintHelp()
	end
end

function Sprout:HandleRoleCommand(roleInput)
	local role = ROLE_ALIASES[(roleInput or ""):lower()]

	if not role then
		self:Print("Usage: /sprout role off | sprout | mentor")
		return
	end

	self:SetRole(role)
end

function Sprout:PrintStatus()
	local channel = self:GetModule("Channel")
	local channelId = channel:GetChannelId()

	self:Print("Role: " .. Constants.ROLE_LABELS[self:GetRole()])
	self:Print("Note: " .. (self:GetOwnNote() ~= "" and self:GetOwnNote() or "(empty)"))
	self:Print("Channel: " .. (channelId and ("joined (#" .. channelId .. ")") or "not joined"))
	self:Print("Roster: " .. self.roster:Count() .. " players online")
end

function Sprout:PrintHelp()
	self:Print("Commands:")
	self:Print("  /sprout - toggle the roster window")
	self:Print("  /sprout role off|sprout|mentor - set your role")
	self:Print("  /sprout note <text> - set the note others see next to your name")
	self:Print("  /sprout config - open settings")
	self:Print("  /sprout status - show connection status")
end

-- Debug logging, enabled with /sprout debug.
function Sprout:Debug(format, ...)
	if not (self.db and self.db.global.debug) then
		return
	end

	self:Printf("|cff888888[debug]|r " .. format, ...)
end
