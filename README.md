<div align="center">

<img width="626" height="139" alt="Zignal" src="https://github.com/user-attachments/assets/8e7b7c8b-c58d-4aa1-9f80-d3c985f29a88" />

Ridiculously fast, production‑ready signals for Luau — with generic types, zero dependencies, and comprehensive docs.

---

<details>
<summary><strong>Basic Usage</strong></summary>
## Creating a Signal

Create a new signal using `Signal.new`.
```lua
local Signal = require(path.to.Zignal)

local MySignal = Signal.new("MySignal")
```

## Connecting a Listener

Attach a function using Connect.
```lua
local connection = MySignal:Connect(function(a, b)
  print("Received:", a, b)
end)
```

## Firing the Signal

Trigger all connected listeners with Fire.
```lua
MySignal:Fire(10, 20)
```
Output
```
Received: 10 20
```

## Disconnecting
Remove a listener using Disconnect.
```lua
connection:Disconnect()
```
After disconnecting, the callback will no longer run.

## Reconnecting
Reconnect a previously disconnected listener.
```lua
connection:Reconnect()
```
Returns `true` if successfu

## One-Time Listener
Use Once to run a callback only once.
```lua
MySignal:Once(function(message)
	print(message)
end)

MySignal:Fire("Hello")
MySignal:Fire("World")
```
Output
```
Hello
```

## Waiting for a Signal
Wait for the next fire inside a coroutine.
```lua
task.spawn(function()
	local a, b = MySignal:Wait()
	print("Waited:", a, b)
end)

MySignal:Fire(5, 6)
```
Output
```
Waited: 5 6
```

## Using Priorities
Listeners with higher priority run first.
```lua
MySignal:Connect(function()
	print("Low Priority")
end, 0)

MySignal:Connect(function()
	print("High Priority")
end, 100)

MySignal:Fire()
```
Output
```
High Priority
Low Priority
```

## Using Priorities
Listeners with higher priority run first.
```lua
MySignal:Connect(function()
	print("Low Priority")
end, 0)

MySignal:Connect(function()
	print("High Priority")
end, 100)

MySignal:Fire()
```
Output
```
High Priority
Low Priority
```

## Pausing and Resuming
Temporarily disable firing.
```lua
MySignal:Pause()
MySignal:Fire() -- Ignored

MySignal:Resume()
MySignal:Fire() -- Works
```

## Wrapping Roblox Signals
Wrap a native Roblox signal.
```lua
local wrapped = Signal.Wrap(workspace.ChildAdded, "ChildAdded")

wrapped:Connect(function(child)
	print("Added:", child.Name)
end)
```


## Destroying a Signal
Clean up the signal and all connections.
```lua
MySignal:Destroy()
```

</details>

---

<details>
<summary><strong>Documentation</strong></summary>

---

## Overview

Zignal.luau is a custom signal implementation that provides:

- Priority-based connections
- Coroutine waiting
- Safe disconnection during firing
- Connection pooling
- Native signal wrapping

Each signal maintains an ordered list of connections that are executed when fired.

---

## Signal

A `Signal` represents an event that can be listened to and fired.

Signals are created using `Signal.new`.

---

### Signal.new(name?)

Creates a new signal.

**Parameters**

- `name` (string | nil)  
  Optional name for debugging.

**Returns**

- `Signal`

---

### Signal:Connect(fn, priority?)

Connects a callback to the signal.

**Parameters**

- `fn` (function)  
  Function to call when fired.

- `priority` (number | nil)  
  Execution priority. Default: `0`.

**Returns**

- `Connection`

**Errors**

- If `fn` is not a function
- If the signal is destroyed

**Notes**

- Higher priority runs first.
- Connections are inserted in sorted order.

---

### Signal:Once(fn, priority?)

Connects a callback that runs once.

**Parameters**

- `fn` (function)
- `priority` (number | nil)

**Returns**

- `Connection`

**Behavior**

- The connection disconnects before invoking `fn`.

---

### Signal:Fire(...)

Fires the signal.

**Parameters**

- `...` (any)  
  Arguments passed to listeners.

**Behavior**

- Executes callbacks in priority order
- Safe during disconnects
- Does nothing if paused or destroyed

---

### Signal:Wait()

Yields until the signal fires.

**Returns**

- `...` (any)

**Requirements**

- Must be called inside a coroutine

**Errors**

- Signal is destroyed
- Not in coroutine
- Too many waiters

---

### Signal:Pause()

Pauses the signal.

While paused, `Fire()` does nothing.

---

### Signal:Resume()

Resumes a paused signal.

---

### Signal:IsDestroyed()

Returns whether the signal is destroyed.

**Returns**

- `boolean`

---

### Signal:IsPaused()

Returns whether the signal is paused.

**Returns**

- `boolean`

---

### Signal:GetConnectionCount()

Returns number of active connections.

**Returns**

- `number`

---

### Signal:Destroy()

Destroys the signal.

**Behavior**

- Disconnects wrapped native signals
- Clears all connections
- Resumes waiters
- Prevents reuse

---

## Connection

A `Connection` represents a bound listener.

Returned from `Connect` and `Once`.

---

### Properties

#### Connection.Connected

Whether the connection is active.

Type: `boolean`

---

### Methods

---

#### Connection:Disconnect()

Disconnects the listener.

**Behavior**

- Safe during `Fire`
- Deferred if firing
- Returned to pool

---

#### Connection:Reconnect()

Reconnects a disconnected listener.

**Returns**

- `boolean`

**Fails If**

- Already connected
- Signal destroyed
- Callback missing

---

## Execution Model

- Connections stored in doubly-linked list
- Sorted by descending priority
- Linear traversal during `Fire`
- Structural changes deferred

This guarantees stable execution order.

---

## Waiting System

- Waiters stored as coroutines
- Resumed with `task.spawn`
- Receive fire arguments
- Cleared after firing

Maximum waiters: `512`

---

## Pause / Resume

- Pause disables firing
- Resume enables firing
- Does not affect connections

---

## Wrapping RBXScriptSignal

`Signal.Wrap(rbxSignal, name?)`

Creates a signal that forwards a Roblox event.

**Behavior**

- Connects to native signal
- Forwards arguments
- Disconnects on destroy

---

## Destruction

After `Destroy()`:

- All connections removed
- Native connections closed
- Waiters resumed
- Signal unusable

Subsequent calls:

- `Connect` → error
- `Wait` → error
- `Fire` → no-op

---

## Limits

| Item | Limit |
|------|--------|
| Connection Pool | 512 |
| Waiters | 512 |

---

## Error Conditions

Errors are thrown when:

- Connecting with non-function
- Connecting to destroyed signal
- Waiting on destroyed signal
- Waiting outside coroutine
- Exceeding waiter limit

---

</details>

---

<details>
<summary><strong>Benchmarks</strong></summary>

---

Benchmark Code:
```lua
--!strict
--!optimize 2

local Signal = require(game.ReplicatedStorage.Packages.Zignal)

local function measureTime(fn: () -> ()): number
	local start = os.clock()
	fn()
	return (os.clock() - start) * 1000
end

local function benchmark(name: string, iterations: number, fn: () -> ())
	local total = 0.0
	for _ = 1, iterations do
		total += measureTime(fn)
	end
	local avgMs = total / iterations
	local perFrame = (1000 / 60) / avgMs
	print(string.format("%s: avg %.10f ms, ~%.1f ops/frame", name, avgMs, perFrame))
end

local function freshSignal()
	return Signal.new()
end

print("=== Benchmark ===")
print("Frame budget: 16.67 ms (60 FPS)\n")

benchmark("Connect (250)", 1000, function()
	local sig = freshSignal()
	local conns = {}
	for i = 1, 250 do
		conns[i] = sig:Connect(function() end)
	end
	for i = 1, 250 do
		conns[i]:Disconnect()
	end
end)

benchmark("Once (250)", 1000, function()
	local sig = freshSignal()
	local conns = {}
	for i = 1, 250 do
		conns[i] = sig:Once(function() end)
	end
	for i = 1, 250 do
		conns[i]:Disconnect()
	end
end)

local fireSignal = freshSignal()
local permConns = {}
for i = 1, 250 do
	permConns[i] = fireSignal:Connect(function() end)
end

benchmark("Fire (250 conn)", 10000, function()
	fireSignal:Fire()
end)

for i = 1, 250 do
	permConns[i]:Disconnect()
end

print("\nBenchmark complete.")
```

Results:
```
  00:21:16.646  === Benchmark ===  -  Server - Script:26
  00:21:16.646  Frame budget: 16.67 ms (60 FPS)
  -  Server - Script:27
  00:21:16.704  Connect (250): avg 0.0582144000 ms, ~286.3 ops/frame  -  Server - Script:19
  00:21:16.777  Once (250): avg 0.0729567000 ms, ~228.4 ops/frame  -  Server - Script:19
  00:21:16.836  Fire (250 conn): avg 0.0058294500 ms, ~2859.0 ops/frame  -  Server - Script:19
  00:21:16.836  
Benchmark complete.  -  Server - Script:65
```

Code can be made faster but by doing that reliability goes down.

</details>
