-- The two-box roster window: online Sprouts on the left, Mentors on the
-- right. Each row shows name, level, class and zone. Left-click whispers,
-- right-click opens a context menu with whisper, invite and note actions.
--
-- The window chrome (frame, header controls, the two boxes) is AceGUI. The
-- lists inside the boxes are not: AceGUI creates one widget per row, which
-- gets slow with hundreds of players. Instead each box holds a virtualized
-- list built directly with the Frame API. It keeps a small pool of row
-- frames, only as many as fit on screen, and rebinds them to whatever slice
-- of the sorted roster is scrolled into view. Cost is constant no matter how
-- many players are online.
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

-- Roster updates arrive constantly on a busy cluster; the view is redrawn
-- at most this often (seconds) while open. User actions redraw immediately.
local REFRESH_THROTTLE = 1

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 18
local SCROLLBAR_WIDTH = 16
local SCROLLBAR_GAP = 4
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local SCROLLBAR_THUMB = "Interface\\Buttons\\UI-ScrollBar-Knob"

-- Column widths as a share of the list width, so they follow window resizes.
local COLUMNS = {
	{ key = "name", title = "Name", ratio = 0.40 },
	{ key = "level", title = "Lvl", ratio = 0.09 },
	{ key = "class", title = "Class", ratio = 0.18 },
	{ key = "zone", title = "Zone", ratio = 0.33 },
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

local BOX_TITLES = {
	[ROLES.SPROUT] = "Sprouts",
	[ROLES.MENTOR] = "Mentors",
}

local EMPTY_TEXTS = {
	[ROLES.SPROUT] = "No sprouts online right now.",
	[ROLES.MENTOR] = "No mentors online right now.",
}

-- Virtualized list ----------------------------------------------------------

local VirtualList = {}
VirtualList.__index = VirtualList

function VirtualList.New(owner, role)
	local self = setmetatable({
		owner = owner,
		role = role,
		entries = {},
		rows = {},
		offset = 0,
		visibleRows = 0,
		columnWidths = {},
		syncingScrollBar = false,
	}, VirtualList)

	local frame = CreateFrame("Frame", nil, UIParent)
	frame:Hide()
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		self:ScrollBy(-delta * 3)
	end)
	frame:SetScript("OnSizeChanged", function()
		self:OnSizeChanged()
	end)
	self.frame = frame

	self.headerLabels = {}

	for index, column in ipairs(COLUMNS) do
		local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetText(column.title)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		label:SetPoint("TOP", frame, "TOP", 0, 0)
		self.headerLabels[index] = label
	end

	local scrollBar = CreateFrame("Slider", nil, frame)
	scrollBar:SetOrientation("VERTICAL")
	scrollBar:SetWidth(SCROLLBAR_WIDTH)
	scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEADER_HEIGHT)
	scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	scrollBar:SetThumbTexture(SCROLLBAR_THUMB)
	scrollBar:GetThumbTexture():SetSize(SCROLLBAR_WIDTH, 24)
	scrollBar:SetMinMaxValues(0, 0)
	scrollBar:SetValueStep(1)
	scrollBar:SetObeyStepOnDrag(true)
	scrollBar:SetValue(0)
	scrollBar:SetScript("OnValueChanged", function(_, value)
		if self.syncingScrollBar then
			return
		end

		self:SetOffset(math.floor(value + 0.5))
	end)

	local track = scrollBar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.35)

	self.scrollBar = scrollBar

	local rowsFrame = CreateFrame("Frame", nil, frame)
	rowsFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_HEIGHT)
	rowsFrame:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -SCROLLBAR_GAP, 0)
	self.rowsFrame = rowsFrame

	local emptyText = rowsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	emptyText:SetPoint("TOP", rowsFrame, "TOP", 0, -12)
	emptyText:SetText(EMPTY_TEXTS[role])
	self.emptyText = emptyText

	return self
end

function VirtualList:AttachTo(parent)
	self.frame:SetParent(parent)
	self.frame:ClearAllPoints()
	self.frame:SetAllPoints(parent)
	self.frame:Show()
	self:OnSizeChanged()
end

function VirtualList:Detach()
	self.frame:Hide()
	self.frame:ClearAllPoints()
	self.frame:SetParent(UIParent)
end

function VirtualList:CreateRow(index)
	local row = CreateFrame("Button", nil, self.rowsFrame)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", self.rowsFrame, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", self.rowsFrame, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetHighlightTexture(ROW_HIGHLIGHT, "ADD")

	row.cells = {}

	for columnIndex in ipairs(COLUMNS) do
		local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell:SetJustifyH("LEFT")
		cell:SetWordWrap(false)
		cell:SetPoint("TOP", row, "TOP", 0, 0)
		cell:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
		row.cells[columnIndex] = cell
	end

	row:SetScript("OnClick", function(_, button)
		if row.entry then
			self.owner:OnRowClick(row, row.entry, button)
		end
	end)
	row:SetScript("OnEnter", function()
		if row.entry then
			self.owner:ShowTooltip(row, row.entry)
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return row
end

-- Recomputes how many rows fit and where the columns sit. Called on resize
-- and on every refresh (cheap, and it makes the first layout reliable).
function VirtualList:OnSizeChanged()
	local width = self.frame:GetWidth() or 0
	local height = self.frame:GetHeight() or 0
	local listWidth = math.max(0, width - SCROLLBAR_WIDTH - SCROLLBAR_GAP)

	self.visibleRows = math.max(0, math.floor((height - HEADER_HEIGHT) / ROW_HEIGHT))

	for index = #self.rows + 1, self.visibleRows do
		self.rows[index] = self:CreateRow(index)
	end

	local x = 0

	for index, column in ipairs(COLUMNS) do
		local columnWidth = math.floor(listWidth * column.ratio)
		self.columnWidths[index] = columnWidth

		local label = self.headerLabels[index]
		label:ClearAllPoints()
		label:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x + 2, 0)
		label:SetWidth(math.max(1, columnWidth - 4))

		for _, row in ipairs(self.rows) do
			local cell = row.cells[index]
			cell:ClearAllPoints()
			cell:SetPoint("LEFT", row, "LEFT", x + 2, 0)
			cell:SetWidth(math.max(1, columnWidth - 4))
		end

		x = x + columnWidth
	end

	self:Redraw()
end

function VirtualList:SetEntries(entries)
	self.entries = entries
	self:Redraw()
end

function VirtualList:MaxOffset()
	return math.max(0, #self.entries - self.visibleRows)
end

function VirtualList:SetOffset(offset)
	local clamped = math.max(0, math.min(offset, self:MaxOffset()))

	if clamped == self.offset then
		return
	end

	self.offset = clamped
	self:Redraw()
end

function VirtualList:ScrollBy(rows)
	self:SetOffset(self.offset + rows)
end

function VirtualList:SyncScrollBar()
	self.syncingScrollBar = true
	self.scrollBar:SetMinMaxValues(0, self:MaxOffset())
	self.scrollBar:SetValue(self.offset)
	self.syncingScrollBar = false
end

function VirtualList:Redraw()
	self.offset = math.min(self.offset, self:MaxOffset())
	self:SyncScrollBar()

	for index, row in ipairs(self.rows) do
		local entry = index <= self.visibleRows and self.entries[self.offset + index] or nil

		row.entry = entry

		if entry then
			self:BindRow(row, entry)
			row:Show()
		else
			row:Hide()
		end
	end

	self.emptyText:SetShown(#self.entries == 0)
end

function VirtualList:BindRow(row, entry)
	local displayName = Player.ColorizeByClass(entry.name, entry.class)

	if Sprout:GetPlayerNote(entry.key) then
		displayName = displayName .. " |cffffd100*|r"
	end

	row.cells[1]:SetText(displayName)
	row.cells[2]:SetText(tostring(entry.level))
	row.cells[3]:SetText(Player.ColorizeByClass(Player.GetClassName(entry.class), entry.class))
	row.cells[4]:SetText(entry.zone or "")
end

-- Module ---------------------------------------------------------------------

function RosterWindow:OnInitialize()
	self.frame = nil
	self.boxes = {}
	self.lists = {}
	self.filterText = ""
	self.refreshTimer = nil
	self.replyRefreshTimer = nil
end

function RosterWindow:OnEnable()
	self:RegisterMessage(EVENTS.ROSTER_UPDATED, "QueueRefresh")
	self:RegisterMessage(EVENTS.PLAYER_NOTE_CHANGED, "QueueRefresh")
	self:RegisterMessage(EVENTS.ROLE_CHANGED, "QueueRefresh")
	self:RegisterMessage(EVENTS.CHANNEL_JOINED, "QueueRefresh")
	self:RegisterMessage(EVENTS.CHANNEL_LEFT, "QueueRefresh")
end

function RosterWindow:GetList(role)
	if not self.lists[role] then
		self.lists[role] = VirtualList.New(self, role)
	end

	return self.lists[role]
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
		self:OnWindowClosed(widget)
	end)

	if frame.frame.SetResizeBounds then
		frame.frame:SetResizeBounds(720, 320)
	end

	self.frame = frame

	self:BuildHeader(frame)
	self.boxes[ROLES.SPROUT] = self:BuildRoleBox(frame, ROLES.SPROUT)
	self.boxes[ROLES.MENTOR] = self:BuildRoleBox(frame, ROLES.MENTOR)

	self:Refresh()
	self:RequestRoster()
end

function RosterWindow:OnWindowClosed(widget)
	for _, list in pairs(self.lists) do
		list:Detach()
	end

	self.boxes = {}
	self.frame = nil
	AceGUI:Release(widget)
end

function RosterWindow:BuildHeader(frame)
	local header = AceGUI:Create("SimpleGroup")
	header:SetFullWidth(true)
	header:SetLayout("Flow")
	frame:AddChild(header)

	local roleDropdown = AceGUI:Create("Dropdown")
	roleDropdown:SetLabel("My role")
	roleDropdown:SetWidth(150)
	roleDropdown:SetList(ROLE_OPTIONS, ROLE_ORDER)
	roleDropdown:SetValue(Sprout:GetRole())
	roleDropdown:SetCallback("OnValueChanged", function(_, _, value)
		Sprout:SetRole(value)
	end)
	header:AddChild(roleDropdown)
	self.roleDropdown = roleDropdown

	local sortDropdown = AceGUI:Create("Dropdown")
	sortDropdown:SetLabel("Sort by")
	sortDropdown:SetWidth(130)
	sortDropdown:SetList(SORT_OPTIONS, SORT_ORDER)
	sortDropdown:SetValue(Sprout.db.global.sortKey)
	sortDropdown:SetCallback("OnValueChanged", function(_, _, value)
		Sprout.db.global.sortKey = value
		self:Refresh()
	end)
	header:AddChild(sortDropdown)

	local filterBox = AceGUI:Create("EditBox")
	filterBox:SetLabel("Filter (name, zone, class, note)")
	filterBox:SetWidth(260)
	filterBox:SetText(self.filterText)
	filterBox:DisableButton(true)
	filterBox:SetCallback("OnTextChanged", function(_, _, text)
		self.filterText = text or ""
		self:Refresh()
	end)
	header:AddChild(filterBox)

	local refreshButton = AceGUI:Create("Button")
	refreshButton:SetText("Refresh")
	refreshButton:SetWidth(100)
	refreshButton:SetCallback("OnClick", function()
		self:RequestRoster()
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

function RosterWindow:BuildRoleBox(frame, role)
	local box = AceGUI:Create("InlineGroup")
	box:SetTitle(BOX_TITLES[role])
	box:SetRelativeWidth(0.5)
	box:SetFullHeight(true)
	box:SetLayout("Fill")
	frame:AddChild(box)

	-- The list lives inside the box's content frame rather than as an
	-- AceGUI child; see the note at the top of the file.
	self:GetList(role):AttachTo(box.content)

	return box
end

-- Asks the cluster for a roster only while ours is young (Comm decides), and
-- redraws once the reply window has passed so late replies show up.
function RosterWindow:RequestRoster()
	local sent = Sprout:GetModule("Comm"):RequestRoster()

	if not sent then
		return
	end

	if self.replyRefreshTimer then
		self:CancelTimer(self.replyRefreshTimer)
	end

	self.replyRefreshTimer = self:ScheduleTimer("OnReplyWindowClosed", Constants.HERE_REPLY_MAX_JITTER + 1)
end

function RosterWindow:OnReplyWindowClosed()
	self.replyRefreshTimer = nil
	self:Refresh()
end

-- Refresh --------------------------------------------------------------------

function RosterWindow:QueueRefresh()
	if not self.frame or self.refreshTimer then
		return
	end

	self.refreshTimer = self:ScheduleTimer("OnRefreshTimer", REFRESH_THROTTLE)
end

function RosterWindow:OnRefreshTimer()
	self.refreshTimer = nil
	self:Refresh()
end

function RosterWindow:Refresh()
	if not self.frame then
		return
	end

	if self.roleDropdown then
		self.roleDropdown:SetValue(Sprout:GetRole())
	end

	local sortKey = Sprout.db.global.sortKey
	local counts = {}

	for role, box in pairs(self.boxes) do
		local entries = Sprout.roster:GetByRole(role, sortKey, self.filterText)
		local list = self:GetList(role)

		counts[role] = #entries
		box:SetTitle(string.format("%s (%d)", BOX_TITLES[role], #entries))

		list.emptyText:SetText(self.filterText ~= "" and "No matches for the filter." or EMPTY_TEXTS[role])
		list:OnSizeChanged()
		list:SetEntries(entries)
	end

	self.frame:SetStatusText(self:BuildStatusText(counts))
end

function RosterWindow:BuildStatusText(counts)
	local channel = Sprout:GetModule("Channel")
	local comm = Sprout:GetModule("Comm")

	if not channel:IsJoined() then
		return "Connecting to the discovery channel..."
	end

	if comm:IsCollectingReplies() then
		return "Collecting replies from players on your cluster..."
	end

	local roleText = "You are " .. Constants.ROLE_LABELS[Sprout:GetRole()]

	if not Sprout:IsActive() then
		roleText = roleText .. " (browsing only, others cannot see you)"
	end

	return string.format("%s. %d sprouts and %d mentors shown. Left-click a row to whisper, right-click for options.",
		roleText, counts[ROLES.SPROUT] or 0, counts[ROLES.MENTOR] or 0)
end

-- Row interaction ------------------------------------------------------------

function RosterWindow:OnRowClick(row, entry, button)
	if button == "RightButton" then
		self:OpenContextMenu(row, entry)
		return
	end

	self:Whisper(entry)
end

function RosterWindow:ShowTooltip(anchor, entry)
	local privateNote = Sprout:GetPlayerNote(entry.key)

	GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(Player.ColorizeByClass(entry.name, entry.class))

	if entry.realm then
		GameTooltip:AddLine(entry.realm, 0.8, 0.8, 0.8)
	end

	GameTooltip:AddLine(string.format("Level %d %s", entry.level, Player.GetClassName(entry.class)), 1, 1, 1)
	GameTooltip:AddLine(entry.zone or "", 1, 1, 1)

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

-- Context menu built with the client's MenuUtil API (the same system the
-- unit frame right-click menu uses on 11.0+ clients).
function RosterWindow:OpenContextMenu(anchor, entry)
	GameTooltip:Hide()

	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		Sprout:Print("Context menus are not available on this client. Left-click to whisper.")
		return
	end

	local privateNote = Sprout:GetPlayerNote(entry.key)

	MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
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
