--!native
--!optimize 2

--[[
                                                                  ,--,    
         ,----,                             ,--.               ,---.'|    
       .'   .`|   ,---,  ,----..          ,--.'|   ,---,       |   | :    
    .'   .'   ;,`--.' | /   /   \     ,--,:  : |  '  .' \      :   : |    
  ,---, '    .'|   :  :|   :     : ,`--.'`|  ' : /  ;    '.    |   ' :    
  |   :     ./ :   |  '.   |  ;. / |   :  :  | |:  :       \   ;   ; '    
  ;   | .'  /  |   :  |.   ; /--`  :   |   \ | ::  |   /\   \  '   | |__  
  `---' /  ;   '   '  ;;   | ;  __ |   : '  '; ||  :  ' ;.   : |   | :.'| 
    /  ;  /    |   |  ||   : |.' .''   ' ;.    ;|  |  ;/  \   \'   :    ; 
   ;  /  /--,  '   :  ;.   | '_.' :|   | | \   |'  :  | \  \ ,'|   |  ./  
  /  /  / .`|  |   |  ''   ; : \  |'   : |  ; .'|  |  '  '--'  ;   : ;    
./__;       :  '   :  |'   | '/  .'|   | '`--'  |  :  :        |   ,/     
|   :     .'   ;   |.' |   :    /  '   : |      |  | ,'        '---'      
;   |  .'      '---'    \   \ .'   ;   |.'      `--''                     
`---'                    `---`     '---'                                  
                                                                            // SmugNugg ( Trikaes )
--]]

--[[
    MIT License

    Copyright (c) 2025 SmugNugg

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

-- Zignal.lua

----------------------------------------------------------------
-- TYPES
----------------------------------------------------------------

export type Connection<T...> = {
	Connected: boolean,
	Disconnect: (self: Connection<T...>) -> (),
	Reconnect: (self: Connection<T...>) -> boolean,

	_signal: Signal<T...>?,
	_fn: ((T...) -> ())?,
	_priority: number,

	_next: Connection<T...>?,
	_prev: Connection<T...>?,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> (), priority: number?) -> Connection<T...>,
	Once: (self: Signal<T...>, fn: (T...) -> (), priority: number?) -> Connection<T...>,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	Destroy: (self: Signal<T...>) -> (),

	Pause: (self: Signal<T...>) -> (),
	Resume: (self: Signal<T...>) -> (),

	IsDestroyed: (self: Signal<T...>) -> boolean,
	IsPaused: (self: Signal<T...>) -> boolean,
	GetConnectionCount: (self: Signal<T...>) -> number,

	__index: Signal<T...>,
	__tostring: (self: Signal<T...>) -> string,

	_head: Connection<T...>?,
	_tail: Connection<T...>?,
	_count: number,
	_destroyed: boolean,
	_paused: boolean,
	_firing: boolean,
	_deferred: { Connection<T...> }?,
	_waiters: { thread }?,
	_name: string?,
	_nativeConn: RBXScriptConnection?,
}

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------

local DEFAULT_PRIORITY = 0
local POOL_LIMIT = 512
local MAX_WAITERS = 512

----------------------------------------------------------------
-- CONNECTION POOL
----------------------------------------------------------------

local ConnectionPool: { Connection<any> } = {}

local function resetConnection(conn: Connection<any>)
	conn.Connected = false
	conn._signal = nil
	conn._fn = nil
	conn._priority = 0
	conn._next = nil
	conn._prev = nil
end

----------------------------------------------------------------
-- SHARED CONNECTION METHODS
----------------------------------------------------------------

local function connectionDisconnect<T...>(self: Connection<T...>)
	if not self.Connected then return end
	self.Connected = false

	local sig = self._signal
	if not sig then return end

	if sig._firing then
		local d = sig._deferred
		if not d then
			d = {}
			sig._deferred = d
		end
		table.insert(d, self)
		return
	end

	local prev = self._prev
	local next = self._next
	if prev then
		prev._next = next
	else
		sig._head = next
	end
	if next then
		next._prev = prev
	else
		sig._tail = prev
	end
	sig._count -= 1

	self._signal = nil
	self._fn = nil
	resetConnection(self)
	if #ConnectionPool < POOL_LIMIT then
		table.insert(ConnectionPool, self)
	end
end

local function connectionReconnect<T...>(self: Connection<T...>): boolean
	if self.Connected or not self._fn then return false end

	local sig = self._signal
	if not sig or sig._destroyed then return false end

	self.Connected = true

	local prio = self._priority
	local head = sig._head
	local tail = sig._tail

	if not head then
		sig._head = self
		sig._tail = self
		sig._count += 1
		return true
	end

	if tail and prio <= tail._priority then
		self._prev = tail
		tail._next = self
		sig._tail = self
		sig._count += 1
		return true
	end

	if prio > head._priority then
		self._next = head
		head._prev = self
		sig._head = self
		sig._count += 1
		return true
	end

	local cur = head
	while cur and cur._priority > prio do
		cur = cur._next
	end
	if cur then
		self._next = cur
		self._prev = cur._prev
		if cur._prev then
			cur._prev._next = self
		else
			sig._head = self
		end
		cur._prev = self
	else
		self._prev = tail
		tail._next = self
		sig._tail = self
	end
	sig._count += 1
	return true
end

----------------------------------------------------------------
-- CONNECTION ACQUISITION
----------------------------------------------------------------

local function acquireConnection<T...>(
	signal: Signal<T...>,
	fn: (T...) -> (),
	priority: number
): Connection<T...>
	local conn: Connection<T...> = table.remove(ConnectionPool)
	if not conn then
		conn = {} :: any
	end

	conn.Connected = true
	conn._signal = signal
	conn._fn = fn
	conn._priority = priority
	conn._next = nil
	conn._prev = nil

	conn.Disconnect = connectionDisconnect :: any
	conn.Reconnect = connectionReconnect :: any

	return conn
end

----------------------------------------------------------------
-- SIGNAL CLASS
----------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.__tostring(self)
	if self._destroyed then return "Signal<destroyed>" end
	return `Signal<{self._name or "unnamed"} count={self._count}>`
end

----------------------------------------------------------------
-- CONSTRUCTOR
----------------------------------------------------------------

function Signal.new<T...>(name: string?): Signal<T...>
	local self: Signal<T...> = setmetatable({}, Signal) :: Signal<T...>
	self._head = nil
	self._tail = nil
	self._count = 0
	self._destroyed = false
	self._paused = false
	self._firing = false
	self._deferred = nil
	self._waiters = nil
	self._name = name
	self._nativeConn = nil
	return self
end

----------------------------------------------------------------
-- WRAP CONSTRUCTOR
----------------------------------------------------------------

function Signal.Wrap<T...>(rbxScriptSignal: RBXScriptSignal, name: string?): Signal<T...>
	local self = Signal.new(name) :: Signal<T...>
	local function forwarder(...: T...)
		self:Fire(...)
	end
	self._nativeConn = rbxScriptSignal:Connect(forwarder)
	return self
end

----------------------------------------------------------------
-- CONNECT
----------------------------------------------------------------

function Signal:Connect<T...>(fn: (T...) -> (), priority: number?): Connection<T...>
	if typeof(fn) ~= "function" then
		error("Signal:Connect expects function", 2)
	end
	if self._destroyed then
		error("Signal:Connect on destroyed signal", 2)
	end

	local prio = priority or DEFAULT_PRIORITY
	local conn = acquireConnection(self, fn, prio)

	local head = self._head
	local tail = self._tail

	if not head then
		self._head = conn
		self._tail = conn
		self._count += 1
		return conn
	end

	if prio == DEFAULT_PRIORITY then
		conn._next = head
		head._prev = conn
		self._head = conn
		self._count += 1
		return conn
	end

	if tail and prio <= tail._priority then
		conn._prev = tail
		tail._next = conn
		self._tail = conn
		self._count += 1
		return conn
	end

	if prio > head._priority then
		conn._next = head
		head._prev = conn
		self._head = conn
		self._count += 1
		return conn
	end

	local cur = head
	while cur and cur._priority > prio do
		cur = cur._next
	end
	if cur then
		conn._next = cur
		conn._prev = cur._prev
		if cur._prev then
			cur._prev._next = conn
		else
			self._head = conn
		end
		cur._prev = conn
	else
		conn._prev = tail
		tail._next = conn
		self._tail = conn
	end
	self._count += 1

	return conn
end

----------------------------------------------------------------
-- ONCE
----------------------------------------------------------------

function Signal:Once<T...>(fn: (T...) -> (), priority: number?): Connection<T...>
	local function dummy() end
	local conn = self:Connect(dummy, priority)
	local wrapper = function(...: T...)
		conn:Disconnect()
		fn(...)
	end
	conn._fn = wrapper
	return conn
end

----------------------------------------------------------------
-- FIRE
----------------------------------------------------------------

function Signal:Fire<T...>(...: T...)
	if self._destroyed or self._paused or self._count == 0 then return end

	self._firing = true

	local deferred = self._deferred
	self._deferred = nil
	if deferred then
		table.clear(deferred)
	end

	local cur = self._head
	while cur do
		if cur.Connected then
			local fn = cur._fn
			if fn then
				fn(...)
			end
		end
		cur = cur._next
	end

	self._firing = false

	if deferred then
		for _, c in ipairs(deferred) do
			if c.Connected then
				c:Disconnect()
			end
		end
	end

	if self._waiters then
		local waiters = self._waiters
		self._waiters = nil
		for i = 1, #waiters do
			task.spawn(waiters[i], ...)
		end
	end
end

----------------------------------------------------------------
-- WAIT
----------------------------------------------------------------

function Signal:Wait<T...>(): T...
	if self._destroyed then
		error("Signal:Wait on destroyed signal", 2)
	end

	local thread = coroutine.running()
	if not thread then
		error("Wait must be in coroutine", 2)
	end

	self._waiters = self._waiters or {}
	if #self._waiters >= MAX_WAITERS then
		error("Too many waiters", 2)
	end
	table.insert(self._waiters, thread)

	return coroutine.yield()
end

----------------------------------------------------------------
-- PAUSE / RESUME
----------------------------------------------------------------

function Signal:Pause()
	if not self._destroyed then self._paused = true end
end

function Signal:Resume()
	if not self._destroyed then self._paused = false end
end

----------------------------------------------------------------
-- STATUS QUERIES
----------------------------------------------------------------

function Signal:IsDestroyed(): boolean
	return self._destroyed or false
end

function Signal:IsPaused(): boolean
	return (not self._destroyed) and self._paused or false
end

function Signal:GetConnectionCount(): number
	return (not self._destroyed) and self._count or 0
end

----------------------------------------------------------------
-- DESTROY
----------------------------------------------------------------

function Signal:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	if self._nativeConn then
		self._nativeConn:Disconnect()
		self._nativeConn = nil
	end

	local cur = self._head
	while cur do
		local next = cur._next
		resetConnection(cur)
		if #ConnectionPool < POOL_LIMIT then
			table.insert(ConnectionPool, cur)
		end
		cur = next
	end

	if self._waiters then
		for _, t in ipairs(self._waiters) do
			task.spawn(t)
		end
	end

	self._head = nil
	self._tail = nil
	self._count = 0
	self._paused = false
	self._firing = false
	self._deferred = nil
	self._waiters = nil
	self._name = nil
	self._nativeConn = nil
end

----------------------------------------------------------------

return Signal
