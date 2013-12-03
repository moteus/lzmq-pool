local HAS_RUNNER = not not lunit 

local lunit      = require "lunit"
local TEST_CASE  = assert(lunit.TEST_CASE)
local skip       = lunit.skip or function() end

local IS_LUA52 = _VERSION >= 'Lua 5.2'
local TEST_FFI = ("ffi" == os.getenv("LZMQ"))

local zpool = require("lzmq.pool.core")

print("------------------------------------")
print("Lua version: " .. (_G.jit and _G.jit.version or _G._VERSION))
print("------------------------------------")
print("")

local _ENV = TEST_CASE'interface'            if true then

function setup() end

function teardown() end

function test_interface()
  assert_function(zpool.init)
  assert_function(zpool.get)
  assert_function(zpool.put)
  assert_function(zpool.close)
end

end

if not HAS_RUNNER then lunit.run() end
