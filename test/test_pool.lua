local HAS_RUNNER = not not lunit 

local lunit      = require "lunit"
local TEST_CASE  = assert(lunit.TEST_CASE)
local skip       = lunit.skip or function() end
local IS_LUA52   = _VERSION >= 'Lua 5.2'

local ECHO_ADDR  = "inproc://echo"

local zmq    = require "lzmq"
local ztimer = require "lzmq.timer"
local zpool  = require "lzmq.pool.core"

local zmsg   = zmq.msg_init_data("H")

print("------------------------------------")
print("Lua version: " .. (_G.jit and _G.jit.version or _G._VERSION))
print("------------------------------------")
print("")

local _ENV = TEST_CASE'core queue'           if true  then

local timeout, epselon = 1500, 490

function setup() end

function teardown() zpool.close() end

function test_interface()
  assert_function(zpool.init)
  assert_function(zpool.get)
  assert_function(zpool.put)
  assert_function(zpool.close)
end

function test_init_close()
  assert_error(function() zpool.size(0) end)

  assert_equal(0, zpool.init(1))
  assert_pass (function() zpool.size(0) end)
  assert_error(function() zpool.size(1) end)
  assert_equal(0, zpool.init(2))
  assert_error(function() zpool.size(1) end)
  assert_equal(0, zpool.close())


  assert_equal(0, zpool.init(2))
  assert_pass (function() zpool.size(0) end)
  assert_pass (function() zpool.size(1) end)
  assert_error(function() zpool.size(2) end)
  assert_equal(0, zpool.close())

  assert_error(function() zpool.size(0) end)
end

function test_timeout()
  assert_equal(0, zpool.init(1))
  assert_equal(0, zpool.size(0))

  timer = ztimer.monotonic():start()
  assert_equal("timeout", zpool.get_timeout(0, timeout))
  local elapsed = timer:stop()
  assert(elapsed > (timeout-epselon), "Expeted " .. timeout .. "(+/-" .. epselon .. ") got: " .. elapsed)
  assert(elapsed < (timeout+epselon), "Expeted " .. timeout .. "(+/-" .. epselon .. ") got: " .. elapsed)

  timer:start()
  assert_equal("timeout", zpool.get_timeout(0, timeout))
  local elapsed = timer:stop()
  assert(elapsed > (timeout-epselon), "Expeted " .. timeout .. "(+/-" .. epselon .. ") got: " .. elapsed)
  assert(elapsed < (timeout+epselon), "Expeted " .. timeout .. "(+/-" .. epselon .. ") got: " .. elapsed)

  assert_equal(0, zpool.put(0, zmsg:pointer()))
  assert_userdata(zpool.get_timeout(0, timeout))

end

end

local _ENV = TEST_CASE'Clone socket'         if true  then

local ctx, rep, s1, s2

function setup()
  zpool.init(1)
  ctx = assert(zmq.context())
  rep = assert(ctx:socket{zmq.REP, bind    = ECHO_ADDR})
  s1  = assert(ctx:socket{zmq.REQ, connect = ECHO_ADDR})
end

function teardown()
  if ctx then ctx:destroy() end
  zpool.close()
end

function test_send_recv()
  assert_equal(0, zpool.put(0, assert(s1:lightuserdata())))
  local h = assert_userdata(zpool.get(0, h))

  s2 =  assert(zmq.init_socket(h))
  assert_true(s1:send("hello"))
  assert_equal("hello", rep:recv())
  assert_true(rep:send("world"))
  assert_equal("world", s2:recv())
end

end

local _ENV = TEST_CASE'user queue'           if true  then

local zpool_core = zpool
local zpool = require"lzmq.pool"

local ctx, pool

local timeout, epselon = 1500, 490

function setup()
  zpool.init(1)
  ctx = assert(zmq.context())
end

function teardown()
  if ctx then ctx:destroy() end
  zpool.close()
end

function test_acquire()
  pool = assert(zpool.new(1))
  pool:init(ctx, 1, {zmq.REQ})
  assert_equal(1, pool:size())
  pool:acquire(function(s)
    assert_equal(0, pool:size())
  end)
  assert_equal(1, pool:size())

  -- only callback mode
  assert_error(function() pool:acquire() end)

  assert_error(function()
    pool:acquire(function(s)
      error("some_error")
    end)
  end)
  assert_equal(1, pool:size())

  -- we can put new sockets
  pool:init(ctx, 1, {zmq.REQ})
  assert_equal(2, pool:size())
end

function test_lock()
  pool = assert(zpool.new(1))
  pool:lock(function(p)
    assert_equal(pool, p)
  end)

  -- only callback mode
  assert_error(function() pool:lock() end)

end

function test_timeout()
  pool = assert(zpool.new(1))

  for i = 1, 3 do
    local timer = ztimer.monotonic():start()
    local ok, err = assert_nil(pool:acquire(timeout, function() end))
    local elapsed = timer:stop()
    assert(err)
    assert_equal("EAGAIN", err:mnemo())
    assert(elapsed > (timeout-epselon), "Expeted " .. timeout .. "(+/-" .. epselon .. ") got: " .. elapsed)
    assert(elapsed < (timeout+epselon), "Expeted " .. timeout .. "(+/-" .. epselon .. ") got: " .. elapsed)
  end

end

end

if not HAS_RUNNER then lunit.run() end
