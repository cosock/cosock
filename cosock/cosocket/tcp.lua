local lsocket = require "socket"
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
  local inner_sock, err = lsocket.tcp()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock}, { __index = m})
end})

local passthrough = internals.passthroughbuilder(recvmethods, sendmethods)

m.accept = passthrough("accept", function(inner_sock)
  assert(inner_sock, "transform called on error from accept")
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock}, { __index = m})
end)

m.bind = passthrough("bind")

m.close = passthrough("close")

m.connect = passthrough("connect")

m.getpeername = passthrough("getpeername")

m.getsockname = passthrough("getsockname")

m.getstats = passthrough("getstats")

m.listen = passthrough("listen")

m.receive = passthrough("receive")

m.send = passthrough("send")

m.setoption = passthrough("setoption")

m.setstats = passthrough("setstats")

function m:settimeout(timeout)
  self.timeout = timeout
end

m.shutdown = passthrough("shutdown")

return m
