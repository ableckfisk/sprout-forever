-- Minimal test runner for the pure-Lua modules (no WoW API needed).
--
--   lua tests/run.lua
--
-- WoW loads every addon file with (addonName, namespaceTable) as varargs;
-- we do the same here so the modules run unmodified.
local ADDON_NAME = "Sprout"

local function loadAddonFile(path, ns)
	local chunk, err = loadfile(path)
	assert(chunk, err)
	chunk(ADDON_NAME, ns)
end

local function newNamespace()
	local ns = {}
	loadAddonFile("Constants.lua", ns)
	loadAddonFile("Protocol.lua", ns)
	loadAddonFile("Roster.lua", ns)
	return ns
end

local passed, failed = 0, 0
local currentSuite = ""

local T = {}

function T.suite(name)
	currentSuite = name
end

function T.test(name, fn)
	local ok, err = pcall(fn, newNamespace())

	if ok then
		passed = passed + 1
		return
	end

	failed = failed + 1
	print(string.format("FAIL [%s] %s\n  %s", currentSuite, name, tostring(err)))
end

function T.equal(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

function T.truthy(value, label)
	if not value then
		error((label or "value") .. ": expected truthy, got " .. tostring(value), 2)
	end
end

function T.falsy(value, label)
	if value then
		error((label or "value") .. ": expected falsy, got " .. tostring(value), 2)
	end
end

_G.T = T

dofile("tests/Protocol_test.lua")
dofile("tests/Roster_test.lua")

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
