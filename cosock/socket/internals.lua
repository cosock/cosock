local m = {}

local unpack = table.unpack or unpack
local pack = table.pack or pack or function(a,b,c,d,e)
  -- This is a shim for lua 5.1 which doesn't provide a `pack` operation
  return {
    a,b,c,d,e,
    n = 0 and (e and 5) or (d and 4) or (c and 3) or (b and 2) or (a and 1)
  }
end

local function maybe_transform_output(ret, transform)
  if transform.output then
    return transform.output(unpack(ret, 1, ret.n))
  end
  return unpack(ret, 1, ret.n)
end

--- On error to any method in the passthrough builder, if the transform object includes an error
--- transformation this will call that function
---@param sock table the inner socket
---@param ret table The result table where 1: success, 2: error, ...: any additional values
---@param transform table The transform table
local function maybe_transform_error(sock, ret, transform)
  if transform.error then
    -- We are assuming that the `ret` argument includes the "success" value in the first position
    -- just like it is returned from `pack(isock[method](...))`
    return transform.error(sock, unpack(ret, 2, ret.n))
  end
  return unpack(ret, 1, ret.n)
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
        assert(not transform.error or type(transform.error) == "function", "error transformer not a function")
      else
        transform = {}
      end

      local inputparams = pack(...)

      if transform.input then
        inputparams = pack(transform.input(unpack(inputparams, 1, inputparams.n)))
      end

      repeat
        local isock = self.inner_sock
        local ret = pack(isock[method](isock, unpack(inputparams, 1, inputparams.n)))
        local status = ret[1]
        local err = ret[2]
        if status then
          self.class = self.inner_sock.class
          return maybe_transform_output(ret, transform)
        end
        if not err then
          return maybe_transform_output(ret, transform)
        end
        local kind = ((recvmethods[method] or {})[err]) and "recvr" or ((sendmethods[method] or {})[err]) and "sendr"
        if not kind then
          return maybe_transform_error(self, ret, transform)
        end
        if transform.blocked then
          inputparams = pack(transform.blocked(unpack(ret, 1, ret.n)))
        end
        local recvr, sendr, rterr = coroutine.yield(kind == "recvr" and {self} or {},
                                                    kind == "sendr" and {self} or {},
                                                    self.timeout)
        -- woken, unset waker
        self.wakers[kind] = nil
        if rterr then
          if rterr == err then
            return maybe_transform_error(self, ret, transform)
          else
            ret[2] = rterr
            return maybe_transform_error(self, ret, transform)
          end
        end

        if kind == "recvr" then
          assert(recvr and #recvr == 1, "thread resumed without awaited socket or error (or too many sockets)")
          assert(sendr == nil or #sendr == 0, "thread resumed with unexpected socket")
        else
          assert(recvr == nil or #recvr == 0, "thread resumed with unexpected socket")
          assert(sendr and #sendr == 1, "thread resumed without awaited socket or error (or too many sockets)")
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
