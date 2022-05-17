local m = {}

local unpack = table.unpack or unpack

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

      local inputparams = {...}

      if transform.input then
        inputparams = {transform.input(unpack(inputparams))}
      end

      repeat
        local isock = self.inner_sock
        local ret = {isock[method](isock, unpack(inputparams))}
        local status = ret[1]
        local err = ret[2]

        if not status and err and ((recvmethods[method] or {})[err] or (sendmethods[method] or {})[err]) then
          if transform.blocked then
            inputparams = {transform.blocked(unpack(ret))}
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
              return unpack(ret)
            else
              return nil --[[ TODO: value? ]], rterr
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
          if transform.output then
            return transform.output(unpack(ret))
          else
            return unpack(ret)
          end
        else
          -- for reasons I can't figure out `unpack(ret)` returns nothing when nil precedes other values
          if transform.output then
            return transform.output(ret[1], ret[2], ret[3], ret[4], ret[5])
          else
            return ret[1], ret[2], ret[3], ret[4], ret[5]
          end
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
