-- Hello World client (http://zguide.zeromq.org/page:all)
-- Use one socket from two os threads.

local zmq      = require "lzmq"
local zthreads = require "lzmq.threads"
local zpool    = require "lzmq.pool"

-- 
local QUEUE_NAME = "hwclient"

local NUM_SOCKETS = 1
local SOCKETS_OPT = {zmq.REQ, connect = "tcp://127.0.0.1:5556"}

local pool = zpool.new(QUEUE_NAME)
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
local t1 = zthreads.run(nil, worker, QUEUE_NAME, 1) t1:start()
local t2 = zthreads.run(nil, worker, QUEUE_NAME, 2) t2:start()

t1:join() t2:join()