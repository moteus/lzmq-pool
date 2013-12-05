[![Build Status](https://travis-ci.org/moteus/lzmq-pool.png?branch=master)](https://travis-ci.org/moteus/lzmq-pool)

This library provide ability to use same sockets from different
Lua states / threads in same process.

###Usage

```Lua
local zmq      = require "lzmq"
local zthreads = require "lzmq.threads"

-- This thread load `lzmq.pool` library initialize 
-- and hold it in process.
local thread, pipe = zthreads.fork(zmq.context(), [[
  local pipe = ...

  local zmq      = require "lzmq"
  local zpool    = require "lzmq.pool"
  local zthreads = require "lzmq.threads"

  -- if `parent` lua state may die and destroy this context
  -- we should use our own context (zmq.context())
  local ctx = zthreads.get_parent_ctx()

  -- init library with one pool
  -- You should guarantee thread safe for this library.
  -- You could call this function from any thread.
  -- Second call of this function just return true 
  -- but does not change numbers of pools.
  zpool.init(1)

  -- Now we need create sockets and put them
  -- in specific pool
  local pool = zpool.new(1)

  -- we create one socket
  pool:init(ctx, 1, {zmq.REQ, connect = "tcp://127.0.0.1:5556"})

  -- tell we are ready
  pipe:send("ready")

  -- keep hold lzmq.pool library
  pipe:recv()
  zpool.close()
]])
thread:start() pipe:recv()

local worker = [[
local zpool  = require "lzmq.pool"
local ztimer = require "lzmq.timer"

-- We get Pool ID and Task ID
local POOL, TID = ...

-- We can get this ID for example from config.
local pool = zpool.new(POOL)

for i = 1, 5 do
  pool:aquire(function(s)
    print(TID, s:send("hello"))
    print(TID, s:recv())
  end)
  ztimer.sleep(500)
end
]]

-- We create independent tasks
-- and tell them which pool to use.
local t1 = zthreads.run(nil, worker, 1, 1) t1:start()
local t2 = zthreads.run(nil, worker, 1, 2) t2:start()

t1:join() t2:join()

pipe:send("finish") thread:join()

```


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/moteus/lzmq-pool/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

