local m = {}

local unpack = table.unpack or unpack
local pack = table.pack or pack or function(a,b,c,d,e)
  -- This is a shim for lua 5.1 which doesn't provide a `pack` operation
  return {
    a,b,c,d,e,
    n = (a and 1 or 0) + (b and 1 or 0) + (c and 1 or 0) + (d and 1 or 0) + (e and 1 or 0)
  }
end

local function maybe_transform_output(ret, transform)
  if transform.output then
    return transform.output(unpack(ret))
  end
  return unpack(ret)
end

function m.passthroughbuilder(recvmethods, sendmethods)
  return function(method, transformsrc)
    return function(self, ...)
      local transform = transformsrc
      if type(transform) == "function" then transform = transform() end
      if transform then
        assert(type(transform) == "table", "transformer must be table or function that returns table")
        assert(not transform.input or type(transform.input) == "function", "input transformer not a function")
        assert(not transform.blocked or type(transform.blocked) == "function", "blocked transformer not a function")
        assert(not transform.output or type(transform.output) == "function", "output transformer not a function")
      else
        transform = {}
      end

      local inputparams = pack(...)

      if transform.input then
        inputparams = pack(transform.input(unpack(inputparams)))
      end

      repeat
        local isock = self.inner_sock
        local ret = pack(isock[method](isock, unpack(inputparams)))
        local status = ret[1]
        local err = ret[2]

        if not status and err and ((recvmethods[method] or {})[err] or (sendmethods[method] or {})[err]) then
          if transform.blocked then
            inputparams = pack(transform.blocked(unpack(ret)))
          end
          local kind = ((recvmethods[method] or {})[err]) and "recvr" or ((sendmethods[method] or {})[err]) and "sendr"

          assert(kind, "about to yield on method that is niether recv nor send")
          local recvr, sendr, rterr = coroutine.yield(kind == "recvr" and {self} or {},
                                                      kind == "sendr" and {self} or {},
                                                      self.timeout)

          -- woken, unset waker
          self.wakers[kind] = nil

          if rterr then
            if rterr == err then
              return maybe_transform_output(ret, transform)
            else
              return maybe_transform_output(pack(nil, rterr), transform)
            end
          end

          if kind == "recvr" then
            assert(recvr and #recvr == 1, "thread resumed without awaited socket or error (or too many sockets)")
            assert(sendr == nil or #sendr == 0, "thread resumed with unexpected socket")
          else
            assert(recvr == nil or #recvr == 0, "thread resumed with unexpected socket")
            assert(sendr and #sendr == 1, "thread resumed without awaited socket or error (or too many sockets)")
          end
        elseif status then
          self.class = self.inner_sock.class
          return maybe_transform_output(ret, transform)
        else
          return maybe_transform_output(ret, transform)
        end
      until nil
    end
  end
end

function m.setuprealsocketwaker(socket, kinds)
  kinds = kinds or {"sendr", "recvr"}
  local kindmap = {}
  for _,kind in ipairs(kinds) do kindmap[kind] = true end

  socket.setwaker = function(self, kind, waker)
    assert(kindmap[kind], "unsupported wake kind: "..tostring(kind))
    self.wakers = self.wakers or {}
    assert((not waker) or (not self.wakers[kind]),
      tostring(kind).." waker already set, sockets can only block one thread per waker kind")
    self.wakers[kind] = waker
  end

  socket._wake = function(self, kind, ...)
    local wakers = self.wakers or {}
    if wakers[kind] then
      wakers[kind](...)
      wakers[kind] = nil
      return true
    else
      print("warning attempt to wake, but no waker set")
      return false
    end
  end
end

return m
