local cosock = require "cosock"
-- TODO: cosock
local http = cosock.asyncify "socket.http"
local socket = require "socket"
local csocket = require "cosock.socket"
--local luatrace = require("luatrace")
dbg = require("debugger")
dbg.auto_where = 2

local base = _G

print("start")

--[[
socket.try = nil
socket.newtry = nil
socket.protect = nil

function socket.newtry(finalizer)
  return function(ret1, ...) -- new "try"
    local args = {...}

    if ret1 == nil then
      if finalizer ~= nil and type(finalizer) == "function" then
        finalizer()
      end
      return nil, error(args[1]) -- return ret2 which is optional error message passed in by caller
    else
      return ret1, table.unpack(args)
    end
  end
end

function socket.protect(func)
  return function(...)
    local retvals = {coxpcall.pcall(func, ...)}
    if retvals[1] == true then
      table.remove(retvals, 1)
      return table.unpack(retvals)
    else
      return nil, retvals[2]
    end
  end
end

socket.try = socket.newtry()
--]]

local requests_started = {}
local requests_finished = {}

local metat = { __index = {} }

function metat.__index:sendrequestline(method, uri)
    local reqline = string.format("%s %s HTTP/1.1\r\n", method or "GET", uri)
    return self.try(self.c:send(reqline))
end

function metat.__index:sendheaders(tosend)
    local canonic = headers.canonic
    local h = "\r\n"
    for f, v in base.pairs(tosend) do
        h = (canonic[f] or f) .. ": " .. v .. "\r\n" .. h
    end
    self.try(self.c:send(h))
    return 1
end

function metat.__index:sendbody(headers, source, step)
    source = source or ltn12.source.empty()
    step = step or ltn12.pump.step
    -- if we don't know the size in advance, send chunked and hope for the best
    local mode = "http-chunked"
    if headers["content-length"] then mode = "keep-open" end
    return self.try(ltn12.pump.all(source, socket.sink(mode, self.c), step))
end

function metat.__index:receivestatusline()
    local status,ec = self.try(self.c:receive(5))
    -- identify HTTP/0.9 responses, which do not contain a status line
    -- this is just a heuristic, but is what the RFC recommends
    if status ~= "HTTP/" then
        if ec == "timeout" then
            return 408
        end 
        return nil, status 
    end
    -- otherwise proceed reading a status line
    status = self.try(self.c:receive("*l", status))
    local code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    return self.try(base.tonumber(code), status)
end

function metat.__index:receiveheaders()
    return self.try(receiveheaders(self.c))
end

function metat.__index:receivebody(headers, sink, step)
    sink = sink or ltn12.sink.null()
    step = step or ltn12.pump.step
    local length = base.tonumber(headers["content-length"])
    local t = headers["transfer-encoding"] -- shortcut
    local mode = "default" -- connection close
    if t and t ~= "identity" then mode = "http-chunked"
    elseif base.tonumber(headers["content-length"]) then mode = "by-length" end
    return self.try(ltn12.pump.all(socket.source(mode, self.c, length),
        sink, step))
end

function metat.__index:receive09body(status, sink, step)
    local source = ltn12.source.rewind(socket.source("until-closed", self.c))
    source(status)
    return self.try(ltn12.pump.all(source, sink, step))
end

function metat.__index:close()
    return self.c:close()
end

function slow_request(id)
  return function()
    print("id", id)
  requests_started[id] = true

  local starttime = socket.gettime()
  local body, status = http.request{
    url = "http://52.2.51.61/delay/3",
    create = csocket.tcp
  }
  local endtime = socket.gettime()

  print(string.format("request took %s seconds", endtime - starttime))

  --print("body", body)
  print("status", status)
  --assert(status == 200, "request failed")

  requests_finished[id] = true

  return endtime - starttime
  end
end

function manual()
  -- create socket with user connect function, or with default
  print("create")
  local c = csocket.try(csocket.tcp())
  print("created")
  local h = setmetatable({ c = c }, metat)
  print("mt set")
  -- create finalized try
  h.try = socket.newtry(function() h:close() end)
  -- set timeout before connecting
  print("settimeout")
  c:settimeout(60)
  print("connect")
  h.try(c:connect("52.2.51.61", 80))
  -- here everything worked
  print("worked")
  return h
end

--[[
cosock.spawn(function()
  socket.select(nil, nil, 1)

  print("requests started", #requests_started)
  assert(#requests_started == 3, "not all requests (or too many) started")
  print("requests finished", #requests_finished)
  assert(#requests_finished == 0, "some requests already finished")
end,
"checker")
--]]

---[[
cosock.spawn(slow_request(1), "slow1")
cosock.spawn(slow_request(2), "slow2")
cosock.spawn(slow_request(3), "slow3")
--]]

--[[
cosock.spawn(manual, "man1")
cosock.spawn(manual, "man2")
--]]

--luatrace.tron()
--dbg.call(cosock.run)
cosock.run()
--luatrace.troff()

print("requests finished", #requests_finished)
--assert(#requests_finished == 3, "not all requests (or too many) finished")
