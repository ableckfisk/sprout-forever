-- Minimap button via LibDataBroker + LibDBIcon.
--
-- LibDataBroker is a tiny pub/sub registry: an addon publishes a "data
-- object" (icon, text, click and tooltip handlers) and any display addon
-- can render it. LibDBIcon is the simplest such display: a draggable button
-- on the minimap edge that also appears in the addon compartment menu.
-- Position and visibility are stored in db.global.minimap by LibDBIcon.
local _, ns = ...

local Sprout = ns.addon
local Constants = ns.Constants

local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")

local MinimapButton = Sprout:NewModule("MinimapButton")

local ROLES = Constants.ROLES

local function countByRole(role)
	return #Sprout.roster:GetByRole(role)
end

function MinimapButton:OnInitialize()
	self.dataObject = LibDataBroker:NewDataObject(Constants.ADDON_NAME, {
		type = "launcher",
		text = Constants.ADDON_NAME,
		icon = Constants.MINIMAP_ICON,
		OnClick = function(_, button)
			self:OnClick(button)
		end,
		OnTooltipShow = function(tooltip)
			self:FillTooltip(tooltip)
		end,
	})

	LibDBIcon:Register(Constants.ADDON_NAME, self.dataObject, Sprout.db.global.minimap)
end

function MinimapButton:OnClick(button)
	if button == "RightButton" then
		Sprout:GetModule("Options"):Open()
		return
	end

	Sprout:GetModule("RosterWindow"):Toggle()
end

function MinimapButton:FillTooltip(tooltip)
	tooltip:AddLine(Constants.ADDON_NAME)
	tooltip:AddLine("You are " .. Constants.ROLE_LABELS[Sprout:GetRole()], 1, 1, 1)

	if Sprout:GetModule("Channel"):IsJoined() then
		tooltip:AddLine(string.format("%d sprouts, %d mentors online", countByRole(ROLES.SPROUT), countByRole(ROLES.MENTOR)), 1, 1, 1)
	else
		tooltip:AddLine("Connecting to the discovery channel...", 0.7, 0.7, 0.7)
	end

	tooltip:AddLine(" ")
	tooltip:AddLine("Left-click: roster", 0.6, 0.6, 0.6)
	tooltip:AddLine("Right-click: settings", 0.6, 0.6, 0.6)
end

function MinimapButton:SetShown(shown)
	Sprout.db.global.minimap.hide = not shown

	if shown then
		LibDBIcon:Show(Constants.ADDON_NAME)
	else
		LibDBIcon:Hide(Constants.ADDON_NAME)
	end
end
