local luasocket = require "socket"
local internals = require "cosock.cosocket.internals"

local m = {}

local recvmethods = {
  receive = true,
  receivefrom = true,
  accept = true,
}

local sendmethods = {
  send = true,
  sendto = true,
  connect = true, --TODO: right?
}

setmetatable(m, {__call = function()
  local inner_sock, err = luasocket.tcp()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, wakers = {}, class = "tcp{master}"}, { __index = m})
end})

local passthrough = internals.passthroughbuilder(recvmethods, sendmethods)

m.accept = passthrough("accept", function(inner_sock)
  assert(inner_sock, "transform called on error from accept")
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, wakers = {}, class = "tcp{client}"}, { __index = m})
end)

m.bind = passthrough("bind")

m.class = function(self)
  return self.inner_sock.class()
end

m.close = passthrough("close")

m.connect = passthrough("connect")

m.dirty = passthrough("dirty")

m.getfamily = passthrough("getfamily")

m.getfd = passthrough("getfd")

m.getoption = passthrough("getoption")

m.getpeername = passthrough("getpeername")

m.getsockname = passthrough("getsockname")

m.getstats = passthrough("getstats")

m.listen = passthrough("listen")

m.receive = passthrough("receive")

m.send = passthrough("send")

m.setfd = passthrough("setfd")

m.setoption = passthrough("setoption")

m.setstats = passthrough("setstats")

function m:settimeout(timeout)
  self.timeout = timeout
end

function m:setwaker(kind, waker)
  print("tcp set waker", self)
  assert(kind == "recvr" or kind == "sendr", "unsupported wake kind: "..tostring(kind))
  assert((not waker) or (not self.wakers[kind]),
    tostring(kind).." waker already set, sockets can only block one thread per waker kind")
  self.wakers[kind] = waker
end

m.shutdown = passthrough("shutdown")

function m:_wake(kind, ...)
  print("wake", self)
  if self.wakers[kind] then
    self.wakers[kind](...)
    self.wakers[kind] = nil
    return true
  else
    print("warning attempt to wake, but no waker set")
    return false
  end
end

return m
