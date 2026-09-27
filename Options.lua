-- Settings panel (Interface > AddOns > Sprout) and the standalone dialog
-- opened by /sprout config. Built with AceConfig, which renders an options
-- table with AceGUI widgets.
local _, ns = ...

local Sprout = ns.addon
local Constants = ns.Constants

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local Options = Sprout:NewModule("Options")

local OPTIONS_NAME = Constants.ADDON_NAME

local function buildOptionsTable()
	return {
		type = "group",
		name = Constants.ADDON_NAME,
		args = {
			intro = {
				type = "description",
				order = 1,
				fontSize = "medium",
				name = "Sprouts are new or returning players looking for help. Mentors are experienced players offering it. Your role is set per character.\n",
			},
			role = {
				type = "select",
				order = 10,
				name = "My role",
				desc = "What this character announces to other Sprout users on your realm cluster.",
				values = {
					[Constants.ROLES.OFF] = "Off (browse only)",
					[Constants.ROLES.SPROUT] = "Sprout - looking for help",
					[Constants.ROLES.MENTOR] = "Mentor - offering help",
				},
				sorting = { Constants.ROLES.OFF, Constants.ROLES.SPROUT, Constants.ROLES.MENTOR },
				get = function()
					return Sprout:GetRole()
				end,
				set = function(_, value)
					Sprout:SetRole(value)
				end,
			},
			note = {
				type = "input",
				order = 20,
				width = "full",
				name = "My note",
				desc = "Shown to other players next to your name, for example \"PvP specialist\" or \"need help with dungeons\". Max "
					.. Constants.MAX_NOTE_LENGTH .. " characters.",
				get = function()
					return Sprout:GetOwnNote()
				end,
				set = function(_, value)
					Sprout:SetOwnNote(value)
				end,
			},
			minimap = {
				type = "toggle",
				order = 25,
				name = "Show minimap button",
				desc = "Left-click the button to open the roster, right-click for settings.",
				get = function()
					return not Sprout.db.global.minimap.hide
				end,
				set = function(_, value)
					Sprout:GetModule("MinimapButton"):SetShown(value)
				end,
			},
			openRoster = {
				type = "execute",
				order = 30,
				name = "Open roster",
				desc = "Show who is online. Also available via /sprout.",
				func = function()
					Sprout:GetModule("RosterWindow"):Open()
				end,
			},
			advanced = {
				type = "group",
				order = 100,
				inline = true,
				name = "Advanced",
				args = {
					debug = {
						type = "toggle",
						order = 1,
						name = "Debug logging",
						desc = "Print protocol traffic and channel events to the chat frame.",
						get = function()
							return Sprout.db.global.debug
						end,
						set = function(_, value)
							Sprout.db.global.debug = value
						end,
					},
				},
			},
		},
	}
end

function Options:OnInitialize()
	AceConfig:RegisterOptionsTable(OPTIONS_NAME, buildOptionsTable())

	local _, categoryId = AceConfigDialog:AddToBlizOptions(OPTIONS_NAME, Constants.ADDON_NAME)
	self.categoryId = categoryId
end

-- Opens the addon's page in the Blizzard settings panel, falling back to a
-- standalone AceConfig window if that API is unavailable.
function Options:Open()
	if Settings and Settings.OpenToCategory and self.categoryId then
		Settings.OpenToCategory(self.categoryId)
		return
	end

	AceConfigDialog:Open(OPTIONS_NAME)
end
