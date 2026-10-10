-- SparkPoint headless logic tests. Run from the addon root:  lua .tests/run.lua
-- Works on Lua 5.1 (CI) and newer (local). Loads addon files with stubbed WoW globals.

local T = {}
T.NIL = setmetatable({}, {
	__tostring = function()
		return "T.NIL"
	end,
})

local function describe(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function T.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", msg or "values differ", describe(expected), describe(actual)), 2)
	end
end

function T.truthy(value, msg)
	if not value then
		error(msg or "expected a truthy value", 2)
	end
end

function T.errors(fn, pattern)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error", 2)
	end
	if pattern and not tostring(err):find(pattern, 1, true) then
		error(string.format("error %q does not contain %q", tostring(err), pattern), 2)
	end
end

-- Temporarily replace globals (use T.NIL for an explicit nil), run fn, restore.
function T.withGlobals(overrides, fn)
	local saved = {}
	for name, value in pairs(overrides) do
		saved[name] = { value = _G[name] }
		if value == T.NIL then
			_G[name] = nil
		else
			_G[name] = value
		end
	end
	local ok, err = pcall(fn)
	for name, entry in pairs(saved) do
		_G[name] = entry.value
	end
	if not ok then
		error(err, 0)
	end
end

function T.loadAddonFile(path, addon)
	local chunk = assert(loadfile(path))
	chunk("SparkPoint", addon)
	return addon
end

local TEST_FILES = {
	"test_flavor.lua",
}

local passed, failed = 0, 0
for _, file in ipairs(TEST_FILES) do
	local cases = dofile(".tests/" .. file)(T)
	for _, case in ipairs(cases) do
		local ok, err = pcall(case.fn)
		if ok then
			passed = passed + 1
			print("PASS  " .. file .. " :: " .. case.name)
		else
			failed = failed + 1
			print("FAIL  " .. file .. " :: " .. case.name .. "\n      " .. tostring(err))
		end
	end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
