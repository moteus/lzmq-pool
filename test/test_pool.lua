local HAS_RUNNER = not not lunit 

local lunit      = require "lunit"
local TEST_CASE  = assert(lunit.TEST_CASE)
local skip       = lunit.skip or function() end
local IS_LUA52   = _VERSION >= 'Lua 5.2'

local ECHO_ADDR  = "inproc://echo"

local zmq    = require "lzmq"
local ztimer = require "lzmq.timer"
local zpool  = require "lzmq.pool"

local zmsg   = zmq.msg_init_data("H")

local function return_count(...)
  return select('#', ...), ...
end

print("------------------------------------")
print("Lua version: " .. (_G.jit and _G.jit.version or _G._VERSION))
print("------------------------------------")
print("")

local _ENV = TEST_CASE'user queue'           if true  then

local ctx, pool

local timeout, epselon = 1500, 490

function setup()
  ctx = assert(zmq.context())
end

function teardown()
  if ctx then ctx:destroy() end
  if pool then zpool.close(pool) end
  pool = nil
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

  assert_error_match('some_error', function()
    pool:acquire(function(s)
      error("some_error")
    end)
  end)
  assert_equal(1, pool:size())

  -- we can put new sockets
  pool:init(ctx, 1, {zmq.REQ})
  assert_equal(2, pool:size())
end

function test_multiret()
  pool = assert(zpool.new(1))
  pool:init(ctx, 1, {zmq.REQ})
  assert_equal(1, pool:size())
  local n,a,b,c,d,e = return_count( pool:acquire(function(s)
    assert_equal(0, pool:size())
    return 1, nil, 2, nil, 3
  end))
  assert_equal(5, n)
  assert_equal(1, a)
  assert_nil(b)
  assert_equal(2, c)
  assert_nil(d)
  assert_equal(3, e)

  local n = return_count( pool:acquire(function(s)
    assert_equal(0, pool:size())
  end))
  assert_equal(0, n)
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
