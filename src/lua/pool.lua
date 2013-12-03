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
    assert(0 == zpool.put(id, s:handle()))
    table.insert(sockets, s)
  end

  return self
end

function socket_pool:aquire(cb)
  local id  = self._private.id
  local h   = zpool.get(id)

  assert(type(h) == 'userdata')
  s = zmq.assert(zmq.init_socket(h))

  if cb then
    local ok, err = pcall(cb, s)

    assert(0 == zpool.put(id, s:handle()))
    if ok then return err end

    return assert(ok, err)
  end

  s:on_close(function() zpool.put(id, h) end)
  return s
end

end

return {
  new   = function(...) return socket_pool:new(...) end;
  init  = function(n) return assert(0 == zpool.init(n)) end;
  close = function(n) return assert(0 == zpool.close()) end;
}