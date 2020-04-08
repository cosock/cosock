local m = {}

function m.passthroughbuilder(recvmethods, sendmethods)
  return function(method, transform)
    return function(self, ...)
      repeat
        local isock = self.inner_sock
        local ret = table.pack(isock[method](isock, ...))
        local status = ret[1]
        local err = ret[2]
        if err == "timeout" then
          assert(recvmethods[method] or sendmethods[method],
            "about to yield on method that is niether recv nor send")
          local _, _, rterr = coroutine.yield(recvmethods[method] and {self} or {},
                                              sendmethods[method] and {self} or {},
                                              self.timeout)

          if rterr then return nil --[[ TODO: value? ]], rterr end
        elseif status and transform then
          return transform(table.unpack(ret))
        else
          return table.unpack(ret) -- TODO: find way to make this compatiable with 5.1/jit
        end
      until nil
    end
  end
end

return m
