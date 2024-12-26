local luasec = require "ssl"
local internals = require "cosock.socket.internals"

local m = {}

local recvmethods = {
  dohandshake = { wantread = true },
  receive = { wantread = true },
}

local sendmethods = {
  dohandshake = { wantwrite = true },
  send = { wantwrite = true },
}

local passthrough = internals.passthroughbuilder(recvmethods, sendmethods)

m.class = function(self)
  return self.inner_sock.class()
end

m.close = passthrough("close")

m.config = passthrough("config")

m.dirty = passthrough("dirty")

m.dohandshake = passthrough("dohandshake")

m.getalpn = passthrough("getalpn")

m.getfinished = passthrough("getfinished")

m.getpeercertificate = passthrough("getpeercertificate")

m.getpeerchain = passthrough("getpeerchain")

m.getpeerverification = passthrough("getpeerverification")

m.getpeerfinished = passthrough("getpeerfinished")

m.getsniname = passthrough("getsniname")

m.getstats = passthrough("getstats")

m.loadcertificate = passthrough("loadcertificate")

m.newcontext = passthrough("newcontext")

m.receive = passthrough("receive", {
  output = function(bytes)
    return bytes
  end,
  error = function(_sock, err, ...)
    if err == "timeout" then
      err = "wantread"
    end
    return nil, err, ...
  end,
})

m.send = passthrough("send", {
  error = function(_sock, err, ...)
    if err == "timeout" then
      err = "wantwrite"
    end
    return nil, err, ...
  end,
})

m.setdane = passthrough("setdane")

m.setstats = passthrough("setstats")

m.settlsa = passthrough("settlsa")

m.sni = passthrough("sni")

m.want = passthrough("want")

m.wrap = function(tcp_socket, config)
  assert(tcp_socket.inner_sock, "tcp inner_sock is null")
  local inner_sock, err = luasec.wrap(tcp_socket.inner_sock, config)
  if not inner_sock then
    return inner_sock, err
  end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, class = "tls{}"}, {__index = m})
end

function m:settimeout(timeout)
  self.timeout = timeout
end

internals.setuprealsocketwaker(m)

return m
