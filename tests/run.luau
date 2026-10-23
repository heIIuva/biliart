--!strict
-- Test runner: `lune run tests/run [filter]`.
-- Every tests/*.spec.luau returns { [testName]: () -> () }; a test fails by erroring.

local fs = require("@lune/fs")
local process = require("@lune/process")

local filter = process.args[1]

local files = {}
for _, file in fs.readDir("tests") do
	if file:match("%.spec%.luau$") and (not filter or file:find(filter, 1, true)) then
		table.insert(files, file)
	end
end
table.sort(files)

local passed, failed = 0, 0
for _, file in files do
	local suite: { [string]: () -> () } = (require :: any)("./" .. file:gsub("%.luau$", ""))
	local names = {}
	for name in suite do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local ok, err = pcall(suite[name])
		if ok then
			passed += 1
		else
			failed += 1
			print(`FAIL {file} :: {name}\n  {err}`)
		end
	end
end

print(`{passed} passed, {failed} failed ({#files} files)`)
process.exit(if failed == 0 and #files > 0 then 0 else 1)
