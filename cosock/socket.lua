local luasocket = require "socket"

local tcp = assert(require "cosock.socket.tcp")
local udp = assert(require "cosock.socket.udp")

--- socket: a coroutine wrapped luasocket interface
---
--- The goal of socket is to provide as close to a pure luasocket interface as
--- possible which can be run within recursive coroutines.
---
--- (It's not 100% there yet.)
local m = {}

m._VERSION = luasocket._VERSION
m._SETSIZE = luasocket._SETSIZE
m.BLOCKSIZE = luasocket.BLOCKSIZE

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

-- a unique marker for errors that come from try
local tryerror = {}

-- reimpl'ing here in lua, luasocket impls in C preventing yielding across this call
m.newtry = function(finalizer)
  return function(...)
    local ret = {...}
    if ret[1] == nil then
      if type(finalizer) == "function" then finalizer() end
      local err = {ret[2]}
      setmetatable(err, tryerror)
      error(err)
    end
    return ...
  end
end

local function filtertryerror(status, firstorerr, ...)
  if status then
    return firstorerr, ...
  elseif type(firstorerr) == "table" and getmetatable(firstorerr) == tryerror then
    return nil
  else
    error(firstorerr, 3) -- 3 meaning, not here and not in protect, but where protect was called
  end
end

-- reimpl'ing here in lua, luasocket impls in C preventing yielding across this call
m.protect = function(func)
  return function(...)
    return filtertryerror(pcall(func, ...))
  end
end

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

-- using our local lua impl, luasocket impls in C preventing yielding across this call
m.try = m.newtry()

m.udp = udp

m.udp6 = function()
  local inner_sock, err = luasocket.udp6()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, class = "udp{unconnected}"}, { __index = udp})
end

return m
