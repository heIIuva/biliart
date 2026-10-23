--!strict
-- Requires every ModuleScript in a folder, calls all Init() first, then all Start().
-- Start() runs in its own thread so a yielding module does not block the others.

export type Module = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

local Loader = {}

function Loader.load(folder: Instance?): { [string]: Module }
	local modules: { [string]: Module } = {}
	if not folder then
		return modules
	end

	local names = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			modules[child.Name] = (require :: any)(child)
			table.insert(names, child.Name)
		end
	end
	table.sort(names)

	for _, name in names do
		local module = modules[name]
		local init = module.Init
		if init then
			init(module)
		end
	end
	for _, name in names do
		local module = modules[name]
		local start = module.Start
		if start then
			task.spawn(start, module)
		end
	end
	return modules
end

return Loader
