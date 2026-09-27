-- Small dialog for editing the account-wide private note on another player
-- ("avoid", "great with dungeons", ...). Only the local player ever sees it.
local _, ns = ...

local Sprout = ns.addon

local AceGUI = LibStub("AceGUI-3.0")

local NoteDialog = Sprout:NewModule("NoteDialog")

function NoteDialog:OnInitialize()
	self.frame = nil
end

function NoteDialog:Open(playerKey)
	self:Close()

	local frame = AceGUI:Create("Frame")
	frame:SetTitle("Private note")
	frame:SetStatusText(playerKey)
	frame:SetLayout("Flow")
	frame:SetWidth(420)
	frame:SetHeight(260)
	frame:EnableResize(false)
	frame:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		self.frame = nil
	end)

	local description = AceGUI:Create("Label")
	description:SetFullWidth(true)
	description:SetText("Only you can see this note. It is shared across all your characters.")
	frame:AddChild(description)

	local editBox = AceGUI:Create("MultiLineEditBox")
	editBox:SetFullWidth(true)
	editBox:SetNumLines(5)
	editBox:SetLabel("")
	editBox:SetText(Sprout:GetPlayerNote(playerKey) or "")
	editBox:SetMaxLetters(500)
	editBox:DisableButton(true)
	frame:AddChild(editBox)

	local saveButton = AceGUI:Create("Button")
	saveButton:SetText("Save")
	saveButton:SetWidth(100)
	saveButton:SetCallback("OnClick", function()
		Sprout:SetPlayerNote(playerKey, editBox:GetText())
		self:Close()
	end)
	frame:AddChild(saveButton)

	local clearButton = AceGUI:Create("Button")
	clearButton:SetText("Clear")
	clearButton:SetWidth(100)
	clearButton:SetCallback("OnClick", function()
		Sprout:SetPlayerNote(playerKey, nil)
		self:Close()
	end)
	frame:AddChild(clearButton)

	editBox:SetFocus()

	self.frame = frame
end

function NoteDialog:Close()
	if not self.frame then
		return
	end

	self.frame:Hide()
end
