local zmq    = require "lzmq"
local luq    = require "luq"
local table  = require "table"
local string = require "string"
local math   = require "math"

local LUQ_QUEUE_PREFIX = "lzmq/pool/"

local socket_pool = {} do
socket_pool.__index = socket_pool

function socket_pool:new(id)
  assert(id)
  id = LUQ_QUEUE_PREFIX .. id
  local q, err  = luq.queue(id)
  if not q then return nil, err end

  local o = setmetatable({
    _private = {
      id = id;
      q  = q;
      sockets = {};
    }
  }, self)

  return o
end

function socket_pool:init(ctx, n, opt)
  local q       = self._private.q
  local sockets = self._private.sockets

  for i = 1, math.min(n, q:capacity()) do
    local s = zmq.assert(ctx:socket(opt))
    local errno = q:put(s:lightuserdata())
    assert(0 == errno, errno .. "/" .. q:size() .. "/" .. q:capacity() .. tostring(s:lightuserdata()))
    table.insert(sockets, s)
  end

  return self
end

local function acquire_return(q, h, ok, ...)
  assert(0 == q:put(h))
  if not ok then return error(tostring((...))) end
  return ...
end

function socket_pool:acquire(timeout, cb)
  if not cb then cb, timeout = timeout, -1 end
  assert(type(timeout) == 'number')
  assert(timeout >= -1)
  assert(cb) -- cb is callable

  local q  = self._private.q
  local h
  if timeout < 0 then
    h = q:get()
  else
    h = q:get_timeout(timeout)
  end

  if h == 'timeout' then return nil, zmq.error(zmq.errors.EAGAIN) end

  assert(type(h) == 'userdata')

  local aquire_s = self._private.aquire_s
  if aquire_s and (not aquire_s:closed()) then
    zmq.assert(aquire_s:reset_handle(h))
  else
    aquire_s = zmq.assert(zmq.init_socket(h))
  end
  self._private.aquire_s = aquire_s

  return acquire_return(q, h, pcall(cb, aquire_s))
end

function socket_pool:lock(cb)
  local q  = self._private.q
  local ok = q:lock()
  if ok ~= 0 then return nil, "can not lock pool: " .. tostring(ok) end

  local ok, ret = pcall(cb, self)

  assert(0 == q:unlock())

  if not ok then return error(tostring(ret)) end

  return ret
end

function socket_pool:size()
  return self._private.q:size()
end

function socket_pool:capacity()
  return self._private.q:capacity()
end

end

return {
  new   = function(...) return socket_pool:new(...) end;
  close = function(q) luq.close(q._private.q) end;
}