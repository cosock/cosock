local lsocket = require "socket"
local internals = require "cosock.cosocket.internals"

local m = {}

local recvmethods = {
  receive = true,
  receivefrom = true,
}

local sendmethods = {
  send = true,
  sendto = true,
}

setmetatable(m, {__call = function()
  local inner_sock, err = lsocket.udp()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, wakers = {}, class = "udp{unconnected}"}, { __index = m})
end})

local passthrough = internals.passthroughbuilder(recvmethods, sendmethods)

m.close = passthrough("close")

m.dirty = passthrough("dirty")

m.getfamily = passthrough("getfamily")

m.getfd = passthrough("getfd")

m.getoption = passthrough("getoption")

m.getpeername = passthrough("getpeername")

m.getsockname = passthrough("getsockname")

m.receive = passthrough("receive")

m.receivefrom = passthrough("receivefrom")

m.send = passthrough("send")

m.sendto = passthrough("sendto")

m.setfd = passthrough("setfd")

m.setoption = passthrough("setoption")

m.setpeername = passthrough("setpeername")

m.setsockname = passthrough("setsockname")

function m:settimeout(timeout)
  self.timeout = timeout
end

function m:setwaker(kind, waker)
  print("udp set waker", self)
  assert(kind == "recvr" or kind == "sendr", "unsupported wake kind: "..tostring(kind))
  assert((not waker) or (not self.wakers[kind]),
    tostring(kind).." waker already set, sockets can only block one thread per waker kind")
  self.wakers[kind] = waker
end

function m:_wake(kind, ...)
  print("wake", self)
  if self.wakers[kind] then
    self.wakers[kind](...)
    return true
  else
    print("warning attempt to wake, but no waker set", self)
    return false
  end
end

return m
