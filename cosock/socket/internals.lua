local m = {}

local unpack = table.unpack or unpack

function m.passthroughbuilder(recvmethods, sendmethods)
  return function(method, transform)
    return function(self, ...)
      repeat
        local isock = self.inner_sock
        local ret = {isock[method](isock, ...)}
        local status = ret[1]
        local err = ret[2]
        if err and (err == recvmethods[method] or err == sendmethods[method]) then
          local kind = (err == recvmethods[method]) and "recvr" or (err == sendmethods[method]) and "sendr"

          assert(kind, "about to yield on method that is niether recv nor send")
          local recvr, sendr, rterr = coroutine.yield(kind == "recvr" and {self} or {},
                                                      kind == "sendr" and {self} or {},
                                                      self.timeout)

          -- woken, unset waker
          self.wakers[kind] = nil

          if rterr then return nil --[[ TODO: value? ]], rterr end

          if kind == "recvr" then
            assert(recvr and #recvr == 1, "thread resumed without awaited socket or error (or too many sockets)")
            assert(sendr == nil or #sendr == 0, "thread resumed with unexpected socket")
          else
            assert(recvr == nil or #recvr == 0, "thread resumed with unexpected socket")
            assert(sendr and #sendr == 1, "thread resumed without awaited socket or error (or too many sockets)")
          end
        elseif status then
          self.class = self.inner_sock.class
          if transform then
            return transform(unpack(ret))
          else
            return unpack(ret)
          end
        else
          return unpack(ret)
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
