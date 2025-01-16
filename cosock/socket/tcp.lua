local luasocket = require "socket"
local internals = require "cosock.socket.internals"
local system = require "cosock.system"

local unpack = table.unpack or unpack

local m = {}

local recvmethods = {
  receive = {timeout = true},
  receivefrom = {timeout = true},
  accept = {timeout = true},
}

local sendmethods = {
  send = {timeout = true},
  sendto = {timeout = true},
  connect = {timeout = true, ["Operation already in progress"] = true}, --TODO: right?
}

setmetatable(m, {__call = function()
  local inner_sock, err = luasocket.tcp()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, class = "tcp{master}"}, { __index = m})
end})

--- Build the receive transformer for the TCP sockets so it can be shared between this
--- module and the `ssl` module
---@param error_transformer any
function m.__build_tcp_receive_transform(error_transformer)
  return function()
    error_transformer = error_transformer or function(err) return err end
    local pattern
    -- save partial results on timeout
    local parts = {}
    local bytes_remaining
    local function new_part(part)
      if type(part) == "string" and #part > 0 then
        table.insert(parts, part)
        if bytes_remaining then
          bytes_remaining = bytes_remaining - #part
        end
      end
    end
    return {
      -- transform input parameters
      input = function(ipattern, iprefix)
        assert(#parts == 0, "input transformer called more than once")
        -- save these for later
        pattern = ipattern
        if type(pattern) == "number" then bytes_remaining = pattern end
        new_part(iprefix)

        return pattern
      end,
      -- receives results of luasocket call when we need to block, provides parameters to pass when next ready
      blocked = function(_, _, partial)
        new_part(partial)
        if bytes_remaining then
          assert(bytes_remaining > 0, "somehow about to block despite being done")
          return bytes_remaining
        else
          return pattern
        end
      end,
      error = function(_sock, err, partial)
        err = error_transformer(err)
        new_part(partial)
        if pattern == "*a" and err == "closed" then
          new_part(partial)
          return table.concat(parts)
        end
        return nil, err, table.concat(parts)
      end,
      -- transform output after final success
      output = function(recv)
        assert(recv, "socket receive returned nil data")
        if #parts == 0 then
          return recv
        end
        new_part(recv)
        return table.concat(parts)
      end,
    }
  end
end

local passthrough = internals.passthroughbuilder(recvmethods, sendmethods)

m.accept = passthrough("accept", {
  output = function(inner_sock)
    assert(inner_sock, "transform called on error from accept")
    inner_sock:settimeout(0)
    return setmetatable({inner_sock = inner_sock, class = "tcp{client}"}, { __index = m})
  end
})

m.bind = passthrough("bind")

m.class = function(self)
  return self.inner_sock.class()
end

m.close = passthrough("close")

local function connect_transform()
  if system.info().kernel == "Darwin" then
    -- workaround: macOS returns an "already connected" error once the socket connects
    return function()
      local input
      local connecting = false
      return {
        input = function(...)
          input = {...}
          return ...
        end,
        blocked = function()
          connecting = true
          return unpack(input)
        end,
        error = function(_sock, error)
          if connecting and error == "already connected" then
            connecting = false
            return 1.0
          end

          connecting = false
          input = nil
          return nil, error
        end,
        output = function(...)
          connecting = false
          input = nil

          return ...
        end
      }
    end
  else
    -- no workarounds needed
    return nil
  end
end

m.connect = passthrough("connect", connect_transform())

m.dirty = passthrough("dirty")

m.getfamily = passthrough("getfamily")

m.getfd = passthrough("getfd")

m.getoption = passthrough("getoption")

m.getpeername = passthrough("getpeername")

m.getsockname = passthrough("getsockname")

m.getstats = passthrough("getstats")

m.listen = passthrough("listen")

m.receive = passthrough("receive", m.__build_tcp_receive_transform())

m.send = passthrough("send")

m.setfd = passthrough("setfd")

m.setoption = passthrough("setoption")

m.setstats = passthrough("setstats")

function m:settimeout(timeout)
  self.timeout = timeout

  return 1.0
end


internals.setuprealsocketwaker(m)

return m
