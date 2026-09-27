local T = _G.T

T.suite("Protocol")

T.test("encodes a presence heartbeat deterministically", function(ns)
	local text = ns.Protocol.EncodePresence("HB", {
		role = "MENTOR", level = 42, class = "MAGE", zone = "Elwynn Forest", note = "PvP specialist", interval = 120,
	})

	T.equal(text, "1;HB;c=MAGE;i=120;l=42;n=PvP specialist;r=M;z=Elwynn Forest")
end)

T.test("round-trips presence through decode", function(ns)
	local text = ns.Protocol.EncodePresence("HERE", {
		role = "SPROUT", level = 7, class = "WARRIOR", zone = "Durotar", note = "",
	})
	local message = ns.Protocol.Decode(text)

	T.equal(message.version, 1)
	T.equal(message.type, "HERE")

	local presence = ns.Protocol.PresenceFromFields(message.fields)

	T.equal(presence.role, "SPROUT")
	T.equal(presence.level, 7)
	T.equal(presence.class, "WARRIOR")
	T.equal(presence.zone, "Durotar")
	T.equal(presence.note, "")
	T.falsy(presence.interval, "interval absent when not sent")
end)

T.test("carries the sender's heartbeat interval", function(ns)
	local text = ns.Protocol.EncodePresence("HB", { role = "MENTOR", level = 1, class = "MAGE", zone = "", interval = 360 })
	local presence = ns.Protocol.PresenceFromFields(ns.Protocol.Decode(text).fields)

	T.equal(presence.interval, 360)
end)

T.test("scales heartbeat interval and ttl with roster size", function(ns)
	T.equal(ns.Constants.HeartbeatIntervalFor(0), 120)
	T.equal(ns.Constants.HeartbeatIntervalFor(249), 120)
	T.equal(ns.Constants.HeartbeatIntervalFor(250), 240)
	T.equal(ns.Constants.HeartbeatIntervalFor(5000), ns.Constants.HEARTBEAT_INTERVAL_MAX)
	T.equal(ns.Constants.RosterTtl(nil), 120 * 3 + 30)
	T.equal(ns.Constants.RosterTtl(600), 600 * 3 + 30)
	T.equal(ns.Constants.RosterTtl(5), 120 * 3 + 30, "too-small interval clamped up")
	T.equal(ns.Constants.RosterTtl(999999), 600 * 3 + 30, "too-large interval clamped down")
end)

T.test("encodes bare messages without fields", function(ns)
	T.equal(ns.Protocol.Encode("WHO"), "1;WHO")
	T.equal(ns.Protocol.Encode("BYE"), "1;BYE")
	T.equal(ns.Protocol.Decode("1;WHO").type, "WHO")
end)

T.test("rejects malformed and unknown messages", function(ns)
	T.falsy(ns.Protocol.Decode(""))
	T.falsy(ns.Protocol.Decode(nil))
	T.falsy(ns.Protocol.Decode("hello"))
	T.falsy(ns.Protocol.Decode("1;NOPE;r=M"))
	T.falsy(ns.Protocol.Decode("x;HB;r=M"))
end)

T.test("ignores unknown fields and newer versions (forward compatible)", function(ns)
	local message = ns.Protocol.Decode("2;HB;r=S;l=10;c=ROGUE;z=Orgrimmar;d=1;xyz=whatever")

	T.equal(message.version, 2)
	T.equal(message.fields.d, "1")

	local presence = ns.Protocol.PresenceFromFields(message.fields)

	T.equal(presence.role, "SPROUT")
	T.equal(presence.level, 10)
end)

T.test("returns nil presence when role is missing or unknown", function(ns)
	T.falsy(ns.Protocol.PresenceFromFields({ l = "10" }))
	T.falsy(ns.Protocol.PresenceFromFields({ r = "X" }))
end)

T.test("keeps equals signs inside values", function(ns)
	local message = ns.Protocol.Decode("1;HB;r=M;n=PvP=fun")

	T.equal(message.fields.n, "PvP=fun")
end)

T.test("sanitizes delimiters and control characters out of values", function(ns)
	T.equal(ns.Protocol.SanitizeValue("a;b\nc\td  "), "a,b c d")
	T.equal(ns.Protocol.SanitizeValue(nil), "")
	T.equal(ns.Protocol.SanitizeValue(42), "42")
end)

T.test("truncates notes to the byte limit without splitting UTF-8", function(ns)
	local long = string.rep("a", 100)
	T.equal(#ns.Protocol.SanitizeNote(long), ns.Constants.MAX_NOTE_LENGTH)

	-- 79 ASCII bytes followed by a 2-byte character: the cut must land before it.
	local mixed = string.rep("a", 79) .. "ö" .. "b"
	local truncated = ns.Protocol.SanitizeNote(mixed)
	T.equal(truncated, string.rep("a", 79))
end)

T.test("presence messages never exceed the addon message limit", function(ns)
	local text = ns.Protocol.EncodePresence("HB", {
		role = "MENTOR", level = 80, class = "DEMONHUNTER",
		zone = string.rep("Z", 200), note = string.rep("n", 80),
	})

	T.truthy(#text <= ns.Constants.MAX_ADDON_MESSAGE_LENGTH, "length " .. #text)
	T.truthy(ns.Protocol.Decode(text), "still decodable")
end)

T.test("maps roles to and from wire codes", function(ns)
	T.equal(ns.Protocol.RoleToWire("SPROUT"), "S")
	T.equal(ns.Protocol.RoleToWire("MENTOR"), "M")
	T.falsy(ns.Protocol.RoleToWire("OFF"))
	T.equal(ns.Protocol.RoleFromWire("M"), "MENTOR")
end)
