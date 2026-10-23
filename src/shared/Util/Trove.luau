--!strict
-- Collects cleanup items; Clean() releases them in reverse order.
-- Supports functions, RBXScriptConnections, Instances and objects with Destroy/Disconnect.

local Trove = {}
Trove.__index = Trove

function Trove.new()
	return setmetatable({ _items = {} :: { any } }, Trove)
end

export type Trove = typeof(Trove.new())

function Trove.Add<T>(self: Trove, item: T): T
	table.insert(self._items, item)
	return item
end

local function release(item: any)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "table" then
		if item.Destroy then
			item:Destroy()
		elseif item.Disconnect then
			item:Disconnect()
		end
	end
end

function Trove.Clean(self: Trove)
	local items = self._items
	for i = #items, 1, -1 do
		local item = items[i]
		items[i] = nil
		release(item)
	end
end

Trove.Destroy = Trove.Clean

return Trove
