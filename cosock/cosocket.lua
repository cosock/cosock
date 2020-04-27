local luasocket = require "socket"

local tcp = assert(require "cosock.cosocket.tcp")
local udp = assert(require "cosock.cosocket.udp")

--- cosocket: a coroutine wrapped luasocket interface
---
--- The goal of cosocket is to provide as close to a pure luasocket interface as
--- possible which can be run within recursive coroutines.
---
--- (It's not 100% there yet.)
local m = {}

-- extraced from luasocket 3.0-rc1
m._VERSION = "cosocket 3.0-rc1"
m._SETSIZE = 1024
m.BLOCKSIZE = 2048

m.bind = function(host, port, backlog)
  local ret
  local skt, err = m.tcp()
  if not skt then return nil, err end

  ret, err = skt:bind(host, port)
  if not ret then return nil, err end

  ret, err = skt:listen(backlog)
  if not ret then return nil, err end

  -- I don't know why, but this is what the docs say
  ret, err = skt:setoption("reuseaddr", true)
  if not ret then return nil, err end

  return skt
end

m.choose = luasocket.choose

m.connect = function(address, port, locaddr, locport)
  local skt, createerr = m.tcp()
  if not skt then return nil, createerr end

  if locaddr then
    locport = locport or 0
    local status, err = skt:bind(locaddr, locport)
    if not status then return nil, err end
  end

  local status, err = skt:connect(address, port)
  if not status then return nil, err end

  return skt
end

m.connect4 = m.connect

m.connect6 = function(address, port, locaddr, locport)
  local skt, createerr = m.tcp6()
  if not skt then return nil, createerr end

  if locaddr then
    locport = locport or 0
    local status, err = skt:bind(locaddr, locport)
    if not status then return nil, err end
  end

  local status, err = skt:connect(address, port)
  if not status then return nil, err end

  return skt
end

-- these block the runtime, TODO: do something about that, somehow
m.dns = luasocket.dns

m.gettime = luasocket.gettime

m.newtry = luasocket.newtry

m.protect = luasocket.protect

m.select = function(recvt, sendt, timeout)
  return coroutine.yield(recvt, sendt, timeout)
end

m.sink = luasocket.sink

m.sinkt = luasocket.sinkt

m.skip = luasocket.skip

m.sleep = function(time)
  m.select(nil, nil, time)
end

m.source = luasocket.source

m.sourcet = luasocket.sourcet

m.tcp = tcp

m.tcp6 = function()
  local inner_sock, err = luasocket.tcp6()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, class = "tcp{master}"}, { __index = tcp})
end

m.try = luasocket.try

m.udp = udp

m.udp6 = function()
  local inner_sock, err = luasocket.udp6()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, class = "udp{unconnected}"}, { __index = udp})
end

return m
