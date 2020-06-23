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
        if err == "timeout" then
          local kind = recvmethods[method] and "recvr" or sendmethods[method] and "sendr"

          assert(kind, "about to yield on method that is niether recv nor send")
          local recvr, sendr, rterr = coroutine.yield(recvmethods[method] and {self} or {},
                                                      sendmethods[method] and {self} or {},
                                                      self.timeout)

          -- woken, unset waker
          self.wakers[kind] = nil

          if rterr then return nil --[[ TODO: value? ]], rterr end

          if recvmethods[method] then
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

return m
