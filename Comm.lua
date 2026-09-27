-- Presence protocol over the hidden channel: heartbeats, on-demand roster
-- pulls (WHO_ONLINE / HERE) and goodbyes.
--
-- Sending goes through AceComm, which wraps C_ChatInfo.SendAddonMessage in
-- ChatThrottleLib. ChatThrottleLib paces output and, when the client reports
-- the per-prefix throttle (10 messages, refilling 1/s), parks the queue and
-- retries instead of dropping.
--
-- Scaling rules (see Constants for the numbers):
--   * Heartbeat interval grows with roster size, so per-client traffic stays
--     roughly flat however many players share the channel.
--   * WHO_ONLINE is only sent while our roster is young; afterwards it adds
--     nothing that heartbeats do not already deliver.
--   * HERE replies are jittered over a wide window and coalesced, so any
--     number of WHO_ONLINE requests inside that window cost one reply.
local _, ns = ...

local Sprout = ns.addon
local Constants = ns.Constants
local Protocol = ns.Protocol
local Player = ns.Player

local MESSAGE_TYPES = Constants.MESSAGE_TYPES
local EVENTS = Constants.EVENTS

local Comm = Sprout:NewModule("Comm", "AceComm-3.0", "AceEvent-3.0", "AceTimer-3.0")

local SEND_RESULT_SUCCESS = (Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success) or 0

function Comm:OnInitialize()
	self.heartbeatTimer = nil
	self.pendingHereReply = nil
	self.pendingPresenceChange = nil
	self.lastWhoOnlineAt = 0
	self.channelJoinedAt = nil
end

function Comm:OnEnable()
	self:RegisterComm(Constants.COMM_PREFIX, "OnCommReceived")

	self:RegisterMessage(EVENTS.CHANNEL_JOINED, "OnChannelJoined")
	self:RegisterMessage(EVENTS.CHANNEL_LEFT, "OnChannelLeft")
	self:RegisterMessage(EVENTS.ROLE_CHANGED, "OnPresenceChanged")
	self:RegisterMessage(EVENTS.PRESENCE_CHANGED, "OnPresenceChanged")

	self:RegisterEvent("PLAYER_LOGOUT")

	self:ScheduleRepeatingTimer("SweepRoster", Constants.ROSTER_SWEEP_INTERVAL)
end

-- Lifecycle ------------------------------------------------------------------

function Comm:OnChannelJoined()
	self.channelJoinedAt = GetTime()
	self:ScheduleNextHeartbeat()
	self:RequestRoster(true)
	self:SendHeartbeat()
end

function Comm:OnChannelLeft()
	self.channelJoinedAt = nil
	self:StopHeartbeat()
end

-- Current interval, derived from how many players we see right now.
function Comm:GetHeartbeatInterval()
	return Constants.HeartbeatIntervalFor(Sprout.roster:Count())
end

-- One-shot timer that reschedules itself, so the interval can change between
-- beats as the roster grows or shrinks.
function Comm:ScheduleNextHeartbeat()
	self:StopHeartbeat()
	self.heartbeatTimer = self:ScheduleTimer("OnHeartbeatTick", self:GetHeartbeatInterval())
end

function Comm:OnHeartbeatTick()
	self.heartbeatTimer = nil
	self:SendHeartbeat()
	self:ScheduleNextHeartbeat()
end

function Comm:StopHeartbeat()
	if not self.heartbeatTimer then
		return
	end

	self:CancelTimer(self.heartbeatTimer)
	self.heartbeatTimer = nil
end

-- Role or note changed. Debounced so rapid toggling sends one message.
function Comm:OnPresenceChanged()
	if self.pendingPresenceChange then
		return
	end

	self.pendingPresenceChange = self:ScheduleTimer("FlushPresenceChange", Constants.PRESENCE_CHANGE_DEBOUNCE)
end

function Comm:FlushPresenceChange()
	self.pendingPresenceChange = nil

	if Sprout:IsActive() then
		self:SendHeartbeat()
	else
		self:SendGoodbye()
	end
end

-- Best effort: after PLAYER_LOGOUT no more frames run, so ChatThrottleLib's
-- queue would never flush. Send directly instead; one message cannot trip
-- the throttle on its own.
function Comm:PLAYER_LOGOUT()
	if not Sprout:IsActive() then
		return
	end

	local channelId = self:GetChannelId()

	if not channelId then
		return
	end

	C_ChatInfo.SendAddonMessage(Constants.COMM_PREFIX, Protocol.Encode(MESSAGE_TYPES.GOODBYE), "CHANNEL", channelId)
end

-- Outbound -------------------------------------------------------------------

function Comm:GetChannelId()
	return Sprout:GetModule("Channel"):GetChannelId()
end

-- AceComm reports the outcome as ChatThrottleLib's `didSend` boolean; the
-- enum comparison is kept in case a future AceComm forwards the raw result.
local function onSendResult(messageType, _, _, sendResult)
	if sendResult == true or sendResult == SEND_RESULT_SUCCESS then
		return
	end

	Sprout:Debug("send of %s did not go out (result %s)", messageType, tostring(sendResult))
end

function Comm:Send(messageType, text, priority)
	local channelId = self:GetChannelId()

	if not channelId then
		Sprout:Debug("cannot send %s: channel not joined", messageType)
		return false
	end

	Sprout:Debug("-> %s", text)
	self:SendCommMessage(Constants.COMM_PREFIX, text, "CHANNEL", channelId, priority or "NORMAL", onSendResult, messageType)

	return true
end

function Comm:SendHeartbeat()
	if not Sprout:IsActive() then
		return
	end

	local presence = Player.GetPresence(self:GetHeartbeatInterval())

	self:Send(MESSAGE_TYPES.HEARTBEAT, Protocol.EncodePresence(MESSAGE_TYPES.HEARTBEAT, presence), "BULK")
end

function Comm:SendHere()
	self.pendingHereReply = nil

	if not Sprout:IsActive() then
		return
	end

	local presence = Player.GetPresence(self:GetHeartbeatInterval())

	self:Send(MESSAGE_TYPES.HERE, Protocol.EncodePresence(MESSAGE_TYPES.HERE, presence))
end

function Comm:SendGoodbye()
	self:Send(MESSAGE_TYPES.GOODBYE, Protocol.Encode(MESSAGE_TYPES.GOODBYE), "ALERT")
end

-- True while our roster is too young for heartbeats to have filled it.
function Comm:IsRosterYoung()
	if not self.channelJoinedAt then
		return false
	end

	return GetTime() - self.channelJoinedAt < Constants.WHO_ONLINE_WINDOW
end

-- True while HERE replies to our last request may still be arriving.
function Comm:IsCollectingReplies()
	return GetTime() - self.lastWhoOnlineAt < Constants.HERE_REPLY_MAX_JITTER
end

-- Asks everyone to announce themselves. Only sent while the roster is young
-- (or when forced right after joining) and never more than once per
-- cooldown, so window opens on a mature client cost the cluster nothing.
function Comm:RequestRoster(force)
	local now = GetTime()

	if not force and not self:IsRosterYoung() then
		return false
	end

	if not force and now - self.lastWhoOnlineAt < Constants.WHO_ONLINE_COOLDOWN then
		return false
	end

	self.lastWhoOnlineAt = now

	return self:Send(MESSAGE_TYPES.WHO_ONLINE, Protocol.Encode(MESSAGE_TYPES.WHO_ONLINE))
end

-- Inbound --------------------------------------------------------------------

function Comm:OnCommReceived(_, text, distribution, sender)
	if distribution ~= "CHANNEL" then
		return
	end

	local senderKey = Player.NormalizeName(sender)

	if not senderKey or senderKey == Player.GetFullName() then
		return
	end

	local message, reason = Protocol.Decode(text)

	if not message then
		Sprout:Debug("ignored message from %s (%s): %s", senderKey, reason, text)
		return
	end

	Sprout:Debug("<- %s from %s", text, senderKey)

	local handler = self.handlers[message.type]

	if handler then
		handler(self, senderKey, message)
	end
end

Comm.handlers = {}

local function handlePresence(self, senderKey, message)
	local presence = Protocol.PresenceFromFields(message.fields)

	if not presence then
		return
	end

	local ttl = Constants.RosterTtl(presence.interval)
	local changed = Sprout.roster:Upsert(senderKey, presence, GetTime(), ttl)

	if changed then
		self:SendMessage(EVENTS.ROSTER_UPDATED)
	end
end

Comm.handlers[MESSAGE_TYPES.HEARTBEAT] = handlePresence
Comm.handlers[MESSAGE_TYPES.HERE] = handlePresence

Comm.handlers[MESSAGE_TYPES.WHO_ONLINE] = function(self)
	if not Sprout:IsActive() then
		return
	end

	-- Coalesce: one reply covers every request that arrives while it is pending.
	if self.pendingHereReply then
		return
	end

	local jitter = math.random() * Constants.HERE_REPLY_MAX_JITTER
	self.pendingHereReply = self:ScheduleTimer("SendHere", jitter)
end

Comm.handlers[MESSAGE_TYPES.GOODBYE] = function(self, senderKey)
	if Sprout.roster:Remove(senderKey) then
		self:SendMessage(EVENTS.ROSTER_UPDATED)
	end
end

-- Expiry ---------------------------------------------------------------------

function Comm:SweepRoster()
	local removed = Sprout.roster:Expire(GetTime())

	if removed > 0 then
		Sprout:Debug("expired %d roster entries", removed)
		self:SendMessage(EVENTS.ROSTER_UPDATED)
	end
end
