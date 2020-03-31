local luasocket = require "socket"

local tcp = assert(require "cosocket.tcp")

--- cosocket: a coroutine wrapped luasocket interface
---
--- The goal of cosocket is to provide as close to a pure luasocket interface as
--- possible which can be run within recursive coroutines.
---
--- (It's not there yet.)
local m = {}

-- extraced from luasocket 3.0-rc1
m._VERSION = "cosocket 3.0-rc1"
m._SETSIZE = 1024
m.BLOCKSIZE = 2048


m.connect6 = function()
  error("unimplemented")
end

m.skip = function()
  error("unimplemented")
end

m.sink = function()
  error("unimplemented")
end

m.gettime = luasocket.gettime

m.dns = {}

m.connect = function()
  error("unimplemented")
end

m.select = function(recvt, sendt, timeout)
  return coroutine.yield(recvt, sendt, timeout)
end

m.sleep = function(time)
  m.select(nil, nil, time)
end

m.newtry = function()
  error("unimplemented")
end

m.source = function()
  error("unimplemented")
end

m.protect = function()
  error("unimplemented")
end

m.connect4 = function()
  error("unimplemented")
end

m.udp6 = function()
  error("unimplemented")
end

m.choose = function()
  error("unimplemented")
end

m.try = function()
  error("unimplemented")
end

m.bind = function()
  error("unimplemented")
end

m.tcp6 = function()
  error("unimplemented")
end

m.sourcet = {}

m.tcp = tcp

m.__unload = function()
  error("unimplemented")
end

m.sinkt = {}

m.udp = function()
  error("unimplemented")
end

return m
