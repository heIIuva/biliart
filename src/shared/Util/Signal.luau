--!strict
-- Minimal signal. Handlers run in their own threads via task.spawn.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} :: { [Connection]: (...any) -> () } }, Signal)
end

export type Signal = typeof(Signal.new())

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	local handlers = self._handlers
	local connection: Connection = {
		Connected = true,
		Disconnect = function(c: Connection)
			c.Connected = false
			handlers[c] = nil
		end,
	}
	handlers[connection] = handler
	return connection
end

function Signal.Once(self: Signal, handler: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal.DisconnectAll(self: Signal)
	for connection in self._handlers do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
