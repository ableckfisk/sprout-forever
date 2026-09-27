local T = _G.T

T.suite("Roster")

local function presence(overrides)
	local base = { role = "MENTOR", level = 60, class = "MAGE", zone = "Elwynn Forest", note = "" }

	for key, value in pairs(overrides or {}) do
		base[key] = value
	end

	return base
end

T.test("splits Name-Realm keys", function(ns)
	local name, realm = ns.Roster.SplitKey("Frostina-Area52")
	T.equal(name, "Frostina")
	T.equal(realm, "Area52")

	local bareName, noRealm = ns.Roster.SplitKey("Frostina")
	T.equal(bareName, "Frostina")
	T.falsy(noRealm)

	-- WoW Forever keys are "First Surname" with no realm.
	local foreverName, foreverRealm = ns.Roster.SplitKey("Mehrno Onrhem")
	T.equal(foreverName, "Mehrno Onrhem")
	T.falsy(foreverRealm)
end)

T.test("reports changes only when visible fields differ", function(ns)
	local roster = ns.Roster.New()

	T.truthy(roster:Upsert("A-Realm", presence(), 100, 10), "first insert")
	T.falsy(roster:Upsert("A-Realm", presence(), 200, 10), "identical heartbeat")
	T.equal(roster:Get("A-Realm").lastSeen, 200, "lastSeen still refreshed")
	T.truthy(roster:Upsert("A-Realm", presence({ zone = "Westfall" }), 300), "zone change")
	T.truthy(roster:Upsert("A-Realm", presence({ zone = "Westfall", role = "SPROUT" }), 400), "role change")
end)

T.test("removes and counts entries", function(ns)
	local roster = ns.Roster.New()
	roster:Upsert("A-Realm", presence(), 1)
	roster:Upsert("B-Realm", presence(), 1)

	T.equal(roster:Count(), 2)
	T.truthy(roster:Remove("A-Realm"))
	T.falsy(roster:Remove("A-Realm"), "second remove")
	T.equal(roster:Count(), 1)
end)

T.test("expires entries on their own ttl", function(ns)
	local roster = ns.Roster.New()
	roster:Upsert("Short-Realm", presence(), 100, 50)
	roster:Upsert("Long-Realm", presence(), 100, 1000)

	T.equal(roster:Expire(200), 1)
	T.falsy(roster:Get("Short-Realm"))
	T.truthy(roster:Get("Long-Realm"))
	T.equal(roster:Expire(2000), 1)
end)

T.test("filters by name, zone, class and note, case-insensitively", function(ns)
	local roster = ns.Roster.New()
	roster:Upsert("Mehrno Onrhem", presence({ zone = "Elwynn Forest", note = "PvP specialist" }), 1, 10)
	roster:Upsert("Frostina Snow", presence({ class = "MAGE", zone = "Dun Morogh" }), 1, 10)

	T.equal(#roster:GetByRole("MENTOR", "name", ""), 2)
	T.equal(#roster:GetByRole("MENTOR", "name", "  pvp "), 1)
	T.equal(roster:GetByRole("MENTOR", "name", "MOROGH")[1].name, "Frostina Snow")
	T.equal(#roster:GetByRole("MENTOR", "name", "mage"), 2, "class token matches both")
	T.equal(#roster:GetByRole("MENTOR", "name", "nothing"), 0)
end)

T.test("filters by role and sorts", function(ns)
	local roster = ns.Roster.New()
	roster:Upsert("Zed-Realm", presence({ level = 10, zone = "Durotar" }), 1)
	roster:Upsert("Amy-Realm", presence({ level = 30, zone = "Westfall" }), 1)
	roster:Upsert("Bob-Realm", presence({ level = 30, zone = "Durotar" }), 1)
	roster:Upsert("Sprouty-Realm", presence({ role = "SPROUT" }), 1)

	local byName = roster:GetByRole("MENTOR", "name")
	T.equal(#byName, 3)
	T.equal(byName[1].name, "Amy")
	T.equal(byName[3].name, "Zed")

	local byLevel = roster:GetByRole("MENTOR", "level")
	T.equal(byLevel[1].name, "Amy", "highest level first, ties by name")
	T.equal(byLevel[2].name, "Bob")
	T.equal(byLevel[3].name, "Zed")

	local byZone = roster:GetByRole("MENTOR", "zone")
	T.equal(byZone[1].name, "Bob", "Durotar before Westfall, ties by name")
	T.equal(byZone[2].name, "Zed")

	T.equal(#roster:GetByRole("SPROUT"), 1)
	T.equal(#roster:GetByRole("MENTOR", "unknown"), 3, "unknown sort key falls back to name")
end)
