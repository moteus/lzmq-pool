local zmq   = require "lzmq"
local zpool = require "lzmq.pool.core"

local socket_pool = {} do
socket_pool.__index = socket_pool

function socket_pool:new(id)
  local o = setmetatable({
    _private = {
      id = id - 1;
      sockets = {};
    }
  }, self)

  return o
end

function socket_pool:init(ctx, n, opt)
  local id      = self._private.id
  local sockets = self._private.sockets

  for i = 1, math.min(n, zpool.capacity(id)) do
    local s = zmq.assert(ctx:socket(opt))
    assert(0 == zpool.put(id, s:lightuserdata()))
    table.insert(sockets, s)
  end

  return self
end

local function acquire_return(id, h, ok, ...)
  assert(0 == zpool.put(id, h))
  if not ok then return error(tostring(ret)) end
  return ...
end

local aquire_s
function socket_pool:acquire(timeout, cb)
  if not cb then cb, timeout = timeout, -1 end
  assert(type(timeout) == 'number')
  assert(timeout >= -1)
  assert(cb) -- cb is callable

  local id  = self._private.id
  local h
  if timeout < 0 then
    h = zpool.get(id)
  else
    h = zpool.get_timeout(id, timeout)
  end

  if h == 'timeout' then return nil, zmq.error(zmq.errors.EAGAIN) end

  assert(type(h) == 'userdata')
  
  if aquire_s and (not aquire_s:closed()) then
    zmq.assert(aquire_s:reset_handle(h))
  else
    aquire_s = zmq.assert(zmq.init_socket(h))
  end

  return acquire_return(id, h, pcall(cb, aquire_s))
end

function socket_pool:lock(cb)
  local id  = self._private.id
  local ok = zpool.lock(id)
  if ok ~= 0 then return nil, "can not lock pool: " .. tostring(ok) end

  local ok, ret = pcall(cb, self)

  assert(0 == zpool.unlock(id))

  if not ok then return error(tostring(ret)) end

  return ret
end

function socket_pool:size()
  return zpool.size(self._private.id)
end

function socket_pool:capacity()
  return zpool.capacity(self._private.id)
end

end

return {
  new   = function(...) return socket_pool:new(...) end;
  init  = function(n) return assert(0 == zpool.init(n)) end;
  close = function(n) return assert(0 == zpool.close()) end;
}