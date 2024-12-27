local nativesocket = require "socket"
local print = function(...) end
local timers = {}

local timeouts = {}
local refs = {}
-- takes a relative timeout, a callback that is called with no params,
-- and an optional reference object for cancellation
timers.set = function(timeout, callback, ref)
  print("timer set: %s,%s", timeout, ref)
  local now = nativesocket.gettime()
  local timeoutat = timeout + now
  print(timeoutat, timeout, now)
  local timeoutinfo = {timeoutat = timeoutat, callback = callback, ref = ref}
  table.insert(timeouts, timeoutinfo)
  if ref then refs[ref] = timeoutinfo end
end

timers.cancel = function(ref)
  local timeoutinfo = refs[ref]
  if timeoutinfo then
    -- mark as canceled, actual object will fall out at originally scheduled time
    timeoutinfo.callback = nil
    timeoutinfo.ref = nil
  end
  refs[ref] = nil
end

-- run expired timers, returns time to next timeout expiration
timers.run = function()
  -- this seems exceptionally inefficient, but it works
  -- TODO: I dunno, maybe use a timerwheel, after benchmarks
  table.sort(
    timeouts,
    function(a,b)
      -- bubble nil timeouts to the top to be dropped
      return
        not a.timeoutat or
        (a.timeoutat and b.timeoutat and a.timeoutat < b.timeoutat)
    end
  )

  local now = nativesocket.gettime()

  -- process timeout callback and remove
  while timeouts[1] and (timeouts[1].timeoutat == nil or timeouts[1].timeoutat < now) do
    local timeoutinfo = table.remove(timeouts, 1)
    if timeoutinfo.callback then timeoutinfo.callback() end
    if timeoutinfo.ref then refs[timeoutinfo.ref] = nil end
  end

  local timeoutat = (timeouts[1] or {}).timeoutat
  print("timeout time", timeoutat)
  if timeoutat then
    local timeout = timeoutat - now
    print("earliest timeout", timeout)
    return timeout
  else
    return nil
  end
end

return timers
