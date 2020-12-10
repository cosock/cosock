local lsocket = require "socket"
local internals = require "cosock.socket.internals"

local m = {}

local recvmethods = {
  receive = "timeout",
  receivefrom = "timeout",
}

local sendmethods = {
  send = "timeout",
  sendto = "timeout",
}

setmetatable(m, {__call = function()
  local inner_sock, err = lsocket.udp()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, class = "udp{unconnected}"}, { __index = m})
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

internals.setuprealsocketwaker(m)


return m
