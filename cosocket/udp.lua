local lsocket = require "socket"
local internals = require "cosocket.internals"

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
  return setmetatable({inner_sock = inner_sock}, { __index = m})
end})

local passthrough = internals.passthroughbuilder(recvmethods, sendmethods)

m.close = passthrough("close")

m.getpeername = passthrough("getpeername")

m.getsockname = passthrough("getsockname")

m.receive = passthrough("receive")

m.receivefrom = passthrough("receivefrom")

m.send = passthrough("send")

m.sendto = passthrough("sendto")

m.setpeername = passthrough("setpeername")

m.setsockname = passthrough("setsockname")

m.setoption = passthrough("setoption")

function m:settimeout(timeout)
  self.timeout = timeout
end

return m
