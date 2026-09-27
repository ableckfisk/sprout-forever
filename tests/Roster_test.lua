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
end)

T.test("reports changes only when visible fields differ", function(ns)
	local roster = ns.Roster.New()

	T.truthy(roster:Upsert("A-Realm", presence(), 100), "first insert")
	T.falsy(roster:Upsert("A-Realm", presence(), 200), "identical heartbeat")
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

T.test("expires entries older than the cutoff", function(ns)
	local roster = ns.Roster.New()
	roster:Upsert("Old-Realm", presence(), 100)
	roster:Upsert("Fresh-Realm", presence(), 500)

	T.equal(roster:ExpireOlderThan(300), 1)
	T.falsy(roster:Get("Old-Realm"))
	T.truthy(roster:Get("Fresh-Realm"))
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
