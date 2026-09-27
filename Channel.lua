-- Joins and maintains the hidden discovery channel.
--
-- WoW concepts:
--   * Custom chat channels are scoped to the connected-realm cluster and
--     faction. Anyone can join one by name (and password).
--   * JoinTemporaryChannel joins without saving the channel to the
--     character's channel list. Passing no chat frame keeps it out of every
--     chat window, so the player never sees channel chatter.
--   * The channel list is slow to populate after login, so a join right at
--     PLAYER_ENTERING_WORLD can silently do nothing. We retry until
--     GetChannelName reports a channel number.
local _, ns = ...

local Sprout = ns.addon
local Constants = ns.Constants

local Channel = Sprout:NewModule("Channel", "AceEvent-3.0", "AceTimer-3.0")

local function stripChannelNumber(channelName)
	return (channelName or ""):gsub("^%d+%.%s*", "")
end

-- CHAT_MSG_CHANNEL_NOTICE carries both "5. Name" and, on newer clients, the
-- bare base name. Prefer the base name when present.
local function resolveChannelName(channelName, channelBaseName)
	if channelBaseName and channelBaseName ~= "" then
		return channelBaseName
	end

	return channelName
end

local function isOurChannel(channelName)
	return stripChannelNumber(channelName):lower() == Constants.CHANNEL_NAME:lower()
end

-- Chat message filters run before a message reaches a chat window; returning
-- true hides it. This hides "Joined Channel: [5. SproutFvrMentor7]" etc.
local function suppressOurChannelNotices(_, _, _, _, _, channelName, _, _, _, _, channelBaseName)
	return isOurChannel(resolveChannelName(channelName, channelBaseName))
end

function Channel:OnInitialize()
	self.joinAttempts = 0
	self.joinTimer = nil
	self.wasJoined = false
end

function Channel:OnEnable()
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", suppressOurChannelNotices)

	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
	self:ScheduleRepeatingTimer("CheckHealth", Constants.CHANNEL_HEALTH_CHECK_INTERVAL)
end

function Channel:PLAYER_ENTERING_WORLD()
	self.joinAttempts = 0
	self:ScheduleJoin(Constants.CHANNEL_JOIN_INITIAL_DELAY)
end

-- Returns the channel's current number (1-10) or nil when not joined.
-- Numbers shift when the player leaves other channels, so always resolve
-- at send time instead of caching.
function Channel:GetChannelId()
	local id = GetChannelName(Constants.CHANNEL_NAME)

	if id and id > 0 then
		return id
	end

	return nil
end

function Channel:IsJoined()
	return self:GetChannelId() ~= nil
end

function Channel:ScheduleJoin(delay)
	if self.joinTimer then
		return
	end

	self.joinTimer = self:ScheduleTimer("AttemptJoin", delay)
end

function Channel:AttemptJoin()
	self.joinTimer = nil

	if self:IsJoined() then
		self:OnJoined()
		return
	end

	if self.joinAttempts >= Constants.CHANNEL_JOIN_MAX_ATTEMPTS then
		Sprout:Debug("channel join gave up after %d attempts; health check will retry", self.joinAttempts)
		return
	end

	self.joinAttempts = self.joinAttempts + 1
	Sprout:Debug("joining channel (attempt %d)", self.joinAttempts)

	JoinTemporaryChannel(Constants.CHANNEL_NAME, Constants.CHANNEL_PASSWORD)

	-- Verify after a delay; the notice event usually confirms sooner.
	self:ScheduleJoin(Constants.CHANNEL_JOIN_RETRY_DELAY)
end

function Channel:CHAT_MSG_CHANNEL_NOTICE(_, noticeType, _, _, channelName, _, _, _, _, channelBaseName)
	if not isOurChannel(resolveChannelName(channelName, channelBaseName)) then
		return
	end

	Sprout:Debug("channel notice %s", tostring(noticeType))

	if noticeType == "YOU_JOINED" or noticeType == "YOU_CHANGED" then
		self:OnJoined()
	elseif noticeType == "YOU_LEFT" or noticeType == "YOU_KICKED" or noticeType == "YOU_BANNED" then
		self:OnLeft()
	elseif noticeType == "WRONG_PASSWORD" then
		Sprout:Print("Could not join the discovery channel: another channel with the same name exists with a different password.")
	end
end

function Channel:OnJoined()
	if self.joinTimer then
		self:CancelTimer(self.joinTimer)
		self.joinTimer = nil
	end

	self.joinAttempts = 0

	-- Defensive: make sure no chat window picked the channel up.
	if ChatFrame_RemoveChannel and DEFAULT_CHAT_FRAME then
		ChatFrame_RemoveChannel(DEFAULT_CHAT_FRAME, Constants.CHANNEL_NAME)
	end

	if self.wasJoined then
		return
	end

	self.wasJoined = true
	Sprout:Debug("channel joined as #%d", self:GetChannelId() or 0)
	self:SendMessage(Constants.EVENTS.CHANNEL_JOINED, self:GetChannelId())
end

function Channel:OnLeft()
	if not self.wasJoined then
		return
	end

	self.wasJoined = false
	Sprout:Debug("channel dropped, rejoining")
	self:SendMessage(Constants.EVENTS.CHANNEL_LEFT)
	self:ScheduleJoin(Constants.CHANNEL_JOIN_RETRY_DELAY)
end

-- Periodic safety net: rejoin if the channel silently disappeared, and keep
-- retrying (at this slower cadence) after the fast retries gave up.
function Channel:CheckHealth()
	if self:IsJoined() then
		if not self.wasJoined then
			self:OnJoined()
		end

		return
	end

	if self.wasJoined then
		self:OnLeft()
		return
	end

	self.joinAttempts = 0
	self:ScheduleJoin(0.1)
end
