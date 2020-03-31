local lsocket = require "socket"

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


local function pass_through_async(method, transform)
  return function(self, ...)
    repeat
      local isock = self.inner_sock
      local ret = table.pack(isock[method](isock, ...))
      local status = ret[1]
      local err = ret[2]
      if err == "timeout" then
        print("yield: "..method.." (".."".."")
        local _, _, rterr = coroutine.yield(recvmethods[method] and {self} or {},
                                            sendmethods[method] and {self} or {})

        if rterr then return nil --[[ TODO: value? ]], rterr end
      elseif status and transform then
        return transform(table.unpack(ret))
      else
        return table.unpack(ret)
      end
    until nil
  end
end


m.accept = pass_through_async("accept", function(inner_sock)
  assert(inner_sock, "transform called on error from accept")
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock}, { __index = m})
end)

m.bind = pass_through_async("bind")

m.close = pass_through_async("close")

m.connect = pass_through_async("connect")

m.getpeername = pass_through_async("getpeername")

m.getsockname = pass_through_async("getsockname")

m.getstats = pass_through_async("getstats")

m.listen = pass_through_async("listen")

m.receive = pass_through_async("receive")

m.send = pass_through_async("send")

m.setoption = pass_through_async("setoption")

m.setstats = pass_through_async("setstats")

function m:settimeout()
  error("async timeouts not yet supported")
end

m.shutdown = pass_through_async("shutdown")

return m
