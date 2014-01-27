[![Build Status](https://travis-ci.org/moteus/lzmq-pool.png?branch=master)](https://travis-ci.org/moteus/lzmq-pool)

This library provide ability to use same sockets from different
Lua states / threads in same process.

###Usage

```Lua
-- Hello World client (http://zguide.zeromq.org/page:all)
-- Use one socket from two os threads.

local zmq      = require "lzmq"
local zthreads = require "lzmq.threads"
local zpool    = require "lzmq.pool"

-- Init library with one queue.
-- You should guarantee thread safe for this call.
-- You could call this function from any thread.
-- Second call of this function just return true 
-- but does not change numbers of pools.
zpool.init(1)

local NUM_SOCKETS = 1
local SOCKETS_OPT = {zmq.REQ, connect = "tcp://127.0.0.1:5556"}

local pool = zpool.new(1)
pool:init(zmq.context(), NUM_SOCKETS, SOCKETS_OPT)

-- Now we should just keep alive `pool` object

-- Worker thread
local worker = string.dump(function(POOL, TID)
  local zpool  = require "lzmq.pool"
  local ztimer = require "lzmq.timer"

  -- We can get this ID for example from config.
  local pool = zpool.new(POOL)

  for i = 1, 5 do
    pool:acquire(function(s)
      print(TID .. ' SEND: ', s:send("hello"))
      print(TID .. ' RECV: ', s:recv())
    end)
    ztimer.sleep(500)
  end
end)

-- We create independent tasks
-- and tell them which pool to use.
local t1 = zthreads.run(nil, worker, 1, 1) t1:start()
local t2 = zthreads.run(nil, worker, 1, 2) t2:start()

t1:join() t2:join()
```


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/moteus/lzmq-pool/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

