-- The two-box roster window: online Sprouts on the left, Mentors on the
-- right. Each row shows name, level, class and zone. Left-click whispers,
-- right-click opens a context menu with whisper, invite and note actions.
--
-- AceGUI widgets are pooled; ReleaseChildren() returns a container's widgets
-- to the pool, so a refresh is "release everything, rebuild from the roster".
local _, ns = ...

local Sprout = ns.addon
local Constants = ns.Constants
local Player = ns.Player

local AceGUI = LibStub("AceGUI-3.0")

local RosterWindow = Sprout:NewModule("RosterWindow", "AceEvent-3.0", "AceTimer-3.0")

local EVENTS = Constants.EVENTS
local ROLES = Constants.ROLES

local WINDOW_WIDTH = 1040
local WINDOW_HEIGHT = 560
local REFRESH_DEBOUNCE = 0.2

local COLUMN_WIDTHS = {
	name = 190,
	level = 40,
	class = 90,
	zone = 150,
}

local SORT_OPTIONS = {
	name = "Name",
	level = "Level",
	zone = "Zone",
}
local SORT_ORDER = { "name", "level", "zone" }

local ROLE_OPTIONS = {
	[ROLES.OFF] = "Off",
	[ROLES.SPROUT] = "Sprout",
	[ROLES.MENTOR] = "Mentor",
}
local ROLE_ORDER = { ROLES.OFF, ROLES.SPROUT, ROLES.MENTOR }

function RosterWindow:OnInitialize()
	self.frame = nil
	self.lists = {}
	self.refreshTimer = nil
end

function RosterWindow:OnEnable()
	self:RegisterMessage(EVENTS.ROSTER_UPDATED, "QueueRefresh")
	self:RegisterMessage(EVENTS.PLAYER_NOTE_CHANGED, "QueueRefresh")
	self:RegisterMessage(EVENTS.ROLE_CHANGED, "QueueRefresh")
	self:RegisterMessage(EVENTS.CHANNEL_JOINED, "QueueRefresh")
	self:RegisterMessage(EVENTS.CHANNEL_LEFT, "QueueRefresh")
end

-- Window lifecycle -----------------------------------------------------------

function RosterWindow:IsOpen()
	return self.frame ~= nil
end

function RosterWindow:Toggle()
	if self:IsOpen() then
		self:Close()
	else
		self:Open()
	end
end

function RosterWindow:Close()
	if not self.frame then
		return
	end

	self.frame:Hide()
end

function RosterWindow:Open()
	if self.frame then
		self:Refresh()
		return
	end

	local windowStatus = Sprout.db.global.windowStatus

	local frame = AceGUI:Create("Frame")
	frame:SetTitle("Sprout")
	frame:SetLayout("Flow")

	-- The status table persists size and position between sessions; applying
	-- it resets the size, so the defaults go after it and only on first open.
	frame:SetStatusTable(windowStatus)

	if not windowStatus.width then
		frame:SetWidth(WINDOW_WIDTH)
		frame:SetHeight(WINDOW_HEIGHT)
	end
	frame:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		self.frame = nil
		self.lists = {}
	end)

	if frame.frame.SetResizeBounds then
		frame.frame:SetResizeBounds(WINDOW_WIDTH, 320)
	end

	self.frame = frame

	self:BuildHeader(frame)
	self.lists[ROLES.SPROUT] = self:BuildRoleBox(frame, "Sprouts")
	self.lists[ROLES.MENTOR] = self:BuildRoleBox(frame, "Mentors")

	self:Refresh()
	Sprout:GetModule("Comm"):RequestRoster()
end

function RosterWindow:BuildHeader(frame)
	local header = AceGUI:Create("SimpleGroup")
	header:SetFullWidth(true)
	header:SetLayout("Flow")
	frame:AddChild(header)

	local roleDropdown = AceGUI:Create("Dropdown")
	roleDropdown:SetLabel("My role")
	roleDropdown:SetWidth(160)
	roleDropdown:SetList(ROLE_OPTIONS, ROLE_ORDER)
	roleDropdown:SetValue(Sprout:GetRole())
	roleDropdown:SetCallback("OnValueChanged", function(_, _, value)
		Sprout:SetRole(value)
	end)
	header:AddChild(roleDropdown)
	self.roleDropdown = roleDropdown

	local sortDropdown = AceGUI:Create("Dropdown")
	sortDropdown:SetLabel("Sort by")
	sortDropdown:SetWidth(140)
	sortDropdown:SetList(SORT_OPTIONS, SORT_ORDER)
	sortDropdown:SetValue(Sprout.db.global.sortKey)
	sortDropdown:SetCallback("OnValueChanged", function(_, _, value)
		Sprout.db.global.sortKey = value
		self:Refresh()
	end)
	header:AddChild(sortDropdown)

	local refreshButton = AceGUI:Create("Button")
	refreshButton:SetText("Refresh")
	refreshButton:SetWidth(100)
	refreshButton:SetCallback("OnClick", function()
		local sent = Sprout:GetModule("Comm"):RequestRoster()

		if not sent then
			Sprout:Print("Roster was refreshed recently, please wait a moment.")
		end

		self:Refresh()
	end)
	header:AddChild(refreshButton)

	local optionsButton = AceGUI:Create("Button")
	optionsButton:SetText("Options")
	optionsButton:SetWidth(100)
	optionsButton:SetCallback("OnClick", function()
		Sprout:GetModule("Options"):Open()
	end)
	header:AddChild(optionsButton)
end

function RosterWindow:BuildRoleBox(frame, title)
	local box = AceGUI:Create("InlineGroup")
	box:SetTitle(title)
	box:SetRelativeWidth(0.5)
	box:SetFullHeight(true)
	box:SetLayout("Fill")
	frame:AddChild(box)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	box:AddChild(scroll)

	return { box = box, scroll = scroll }
end

-- Refresh --------------------------------------------------------------------

function RosterWindow:QueueRefresh()
	if not self.frame or self.refreshTimer then
		return
	end

	self.refreshTimer = self:ScheduleTimer("Refresh", REFRESH_DEBOUNCE)
end

function RosterWindow:Refresh()
	self.refreshTimer = nil

	if not self.frame then
		return
	end

	if self.roleDropdown then
		self.roleDropdown:SetValue(Sprout:GetRole())
	end

	local sortKey = Sprout.db.global.sortKey
	local counts = {}

	for role, list in pairs(self.lists) do
		local entries = Sprout.roster:GetByRole(role, sortKey)
		counts[role] = #entries

		list.box:SetTitle(string.format("%s (%d)", role == ROLES.SPROUT and "Sprouts" or "Mentors", #entries))
		self:FillList(list.scroll, entries, role)
	end

	self.frame:SetStatusText(self:BuildStatusText(counts))
end

function RosterWindow:BuildStatusText(counts)
	local channel = Sprout:GetModule("Channel")

	if not channel:IsJoined() then
		return "Connecting to the discovery channel..."
	end

	local roleText = "You are " .. Constants.ROLE_LABELS[Sprout:GetRole()]

	if not Sprout:IsActive() then
		roleText = roleText .. " (browsing only, others cannot see you)"
	end

	return string.format("%s. %d sprouts and %d mentors online. Left-click a row to whisper, right-click for options.",
		roleText, counts[ROLES.SPROUT] or 0, counts[ROLES.MENTOR] or 0)
end

function RosterWindow:FillList(scroll, entries, role)
	scroll:ReleaseChildren()

	if #entries == 0 then
		local empty = AceGUI:Create("Label")
		empty:SetFullWidth(true)
		empty:SetText(role == ROLES.SPROUT
			and "No sprouts online right now."
			or "No mentors online right now.")
		scroll:AddChild(empty)
	end

	for _, entry in ipairs(entries) do
		scroll:AddChild(self:BuildRow(entry))
	end

	scroll:DoLayout()
end

-- Rows -----------------------------------------------------------------------

local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

-- Every cell is an InteractiveLabel wired to the same handlers, so the whole
-- row reacts to hover and clicks even though AceGUI has no row widget.
local function addCell(row, text, width, handlers)
	local cell = AceGUI:Create("InteractiveLabel")
	cell:SetText(text)
	cell:SetWidth(width)
	cell:SetHighlight(ROW_HIGHLIGHT)
	cell:SetCallback("OnEnter", handlers.onEnter)
	cell:SetCallback("OnLeave", handlers.onLeave)
	cell:SetCallback("OnClick", handlers.onClick)
	row:AddChild(cell)

	return cell
end

function RosterWindow:BuildRow(entry)
	local row = AceGUI:Create("SimpleGroup")
	row:SetFullWidth(true)
	row:SetLayout("Flow")

	local privateNote = Sprout:GetPlayerNote(entry.key)
	local displayName = Player.ColorizeByClass(entry.name, entry.class)

	if privateNote then
		displayName = displayName .. " |cffffd100*|r"
	end

	local handlers = {
		onEnter = function(widget)
			self:ShowTooltip(widget, entry, privateNote)
		end,
		onLeave = function()
			GameTooltip:Hide()
		end,
		onClick = function(widget, _, button)
			if button == "RightButton" then
				self:OpenContextMenu(widget, entry, privateNote)
			else
				self:Whisper(entry)
			end
		end,
	}

	addCell(row, displayName, COLUMN_WIDTHS.name, handlers)
	addCell(row, tostring(entry.level), COLUMN_WIDTHS.level, handlers)
	addCell(row, Player.ColorizeByClass(Player.GetClassName(entry.class), entry.class), COLUMN_WIDTHS.class, handlers)
	addCell(row, entry.zone, COLUMN_WIDTHS.zone, handlers)

	return row
end

-- Context menu built with the client's MenuUtil API (the same system the
-- unit frame right-click menu uses on 11.0+ clients).
function RosterWindow:OpenContextMenu(widget, entry, privateNote)
	GameTooltip:Hide()

	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		Sprout:Print("Context menus are not available on this client. Left-click to whisper.")
		return
	end

	MenuUtil.CreateContextMenu(widget.frame, function(_, rootDescription)
		rootDescription:CreateTitle(entry.key)
		rootDescription:CreateButton("Whisper", function()
			self:Whisper(entry)
		end)
		rootDescription:CreateButton("Invite to party", function()
			self:Invite(entry)
		end)
		rootDescription:CreateDivider()
		rootDescription:CreateButton(privateNote and "Edit private note" or "Add private note", function()
			Sprout:GetModule("NoteDialog"):Open(entry.key)
		end)
	end)
end

function RosterWindow:ShowTooltip(widget, entry, privateNote)
	GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(Player.ColorizeByClass(entry.name, entry.class))

	if entry.realm then
		GameTooltip:AddLine(entry.realm, 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine(string.format("Level %d %s", entry.level, Player.GetClassName(entry.class)), 1, 1, 1)
	GameTooltip:AddLine(entry.zone, 1, 1, 1)

	if entry.note and entry.note ~= "" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Their note:", 1, 0.82, 0)
		GameTooltip:AddLine(entry.note, 1, 1, 1, true)
	end

	if privateNote then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Your private note:", 1, 0.82, 0)
		GameTooltip:AddLine(privateNote, 1, 1, 1, true)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click to whisper, right-click for options", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- Actions --------------------------------------------------------------------

-- Opens the chat edit box in whisper mode for the player, the same thing
-- clicking a name in chat does. ChatFrame_SendTell knows how to format
-- names with spaces (Forever surnames) or realm suffixes.
function RosterWindow:Whisper(entry)
	if ChatFrame_SendTell then
		ChatFrame_SendTell(entry.key)
		return
	end

	ChatFrame_OpenChat("/w " .. entry.key .. " ")
end

function RosterWindow:Invite(entry)
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(entry.key)
		return
	end

	InviteUnit(entry.key)
end
