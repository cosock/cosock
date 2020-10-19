local cosocket = require "cosock.cosocket"
local socket = require "socket"
local channel = require "cosock.channel"

local weaktable = { __mode = "kv" } -- mark table as having weak refs to keys and values
local weakkeys = { __mode = "k" } -- mark table as having weak refs to keys

local threads = {} --TODO: use set instead of list
local threadnames = setmetatable({}, weakkeys)
local threadswaitingfor = {} -- what each thread is waiting for
local readythreads = {} -- like wakethreads, but for next loop (can be modified while looping wakethreads)
local socketwrappermap = setmetatable({}, weaktable) -- from native socket to async socket
local threaderrorhandler = nil -- TODO: allow setting error handler

-- silence print statements in this file
local print = function() end

local m = {}

m.socket = cosocket
m.channel = channel

local timers = {}
do
  local timeouts = {}
  local refs = {}
  -- takes a relative timeout, a callback that is called with no params,
  -- and an optional reference object for cancellation
  timers.set = function(timeout, callback, ref)
    print("timer set: %s,%s", timeout, ref)
    local now = socket.gettime()
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

    local now = socket.gettime()

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
end

function m.spawn(fn, name)
  local thread = coroutine.create(fn)
  print("cosocket spawn", name or thread)
  threadnames[thread] = name
  threads[thread] = thread
  readythreads[thread] = {}
end

local function wake_thread(wakelist, thread, kind, skt)
  print("wake thread", thread, kind, skt)
  wakelist[thread] = wakelist[thread] or {}
  wakelist[thread][kind] = wakelist[thread][kind] or {}
  table.insert(wakelist[thread][kind], skt)
end

local function wake_thread_err(wakelist, thread, err)
  print("wake thread err", thread, err)
  wakelist[thread] = wakelist[thread] or {}
  wakelist[thread].err = err
end

-- Implementaion Notes:
-- This run loop is where all the magic happens
--
-- Threads' calls to coroutine.yield function exactly like socket.select. They take: a list of
-- receive-test sockets, a list of write-test sockets, and a timeout. Then, that thread is resumed
-- with: a list of recieve-ready sockets, a list of write-ready sockets, and/or a timeout error.
--
-- This function then combines these lists for a single call to the real socket.select. Once that
-- returns it filters the list of ready sockets out each thread that was waiting on each or
-- determines which has a timeout that has ellapsed.
function m.run()
  local runstarttime = socket.gettime()
  while true do
    print(string.format("================= %s ======================", socket.gettime() - runstarttime))
    local wakethreads = {} -- map of thread => named resume params (rdy skts, timeout, etc)
    local sendt, recvt, timeout = {}, {} -- cumulative values across all threads

    -- add threads that have become ready since last loop to threads to be woken
    for thread, reasons in pairs(readythreads) do
      wakethreads[thread] = reasons

      -- drain copied table (note: the `readythreads` table must not be replaced with a new
      -- table, callbacks hold a reference to this specific instance)
      -- also this operation is actually valid, values can be modified or removed, just not added
      readythreads[thread] = nil
    end

    -- run all threads
    for thread, params in pairs(wakethreads) do
      print("waking", threadnames[thread] or thread, params.recvr, params.sendr, params.err)
      if coroutine.status(thread) == "suspended" then
        -- cancel thread timeout (if any)
        timers.cancel(thread)

        -- cancel other timers
        for kind, sockets in pairs(threadswaitingfor[thread] or {}) do
          if kind ~= "timeout" then
            for _, skt in pairs(sockets) do
              assert(skt.setwaker, "non-wakeable socket")
              print("unset waker", kind)
              skt:setwaker(kind, nil)
            end
          end
        end

        -- resume thread
        local status, threadrecvt_or_err, threadsendt, threadtimeout =
          coroutine.resume(thread, params.recvr, params.sendr, params.err)

        if status and coroutine.status(thread) == "suspended" then
          local threadrecvt = threadrecvt_or_err
          print("suspending", threadnames[thread] or thread, threadrecvt, threadsendt, threadtimeout)
          -- note which sockets this thread is now waiting on
          threadswaitingfor[thread] = {recvr = threadrecvt, sendr = threadsendt, timeout = threadtimeout}

          -- setup wakers for all sockets
          for kind, sockets in pairs(threadswaitingfor[thread]) do
            if kind ~= "timeout" then
              for _, skt in pairs(sockets) do
                assert(skt.setwaker, "non-wakeable socket")
                print("set waker", kind)
                skt:setwaker(kind, function()
                  -- unset waker so we can't double wake
                  skt:setwaker(kind, nil)
                  wake_thread(readythreads, thread, kind, skt)
                end)
              end
            end
          end

          -- setup waker for timeout
          if threadtimeout then
            timers.set(threadtimeout, function() wake_thread_err(readythreads, thread, "timeout") end, thread)
          end
        elseif coroutine.status(thread) == "dead" then
          if not status and not threaderrorhandler then
            local err = threadrecvt_or_err
            if debug and debug.traceback then
              error(debug.traceback(thread, err))
            else
              error(err)
            end
            os.exit(-1)
          end
          print("dead", threadnames[thread] or thread, status, threadrecvt_or_err)
          threads[thread] = nil
          threadswaitingfor[thread] = nil
        end
      else
        print("non-suspended thread encountered", coroutine.status(thread))
      end
    end

    -- check if all threads have completed so that the runtime should exit
    local running = false
    for _, thread in pairs(threads) do
      print("thread", threadnames[thread] or thread, coroutine.status(thread))
      if coroutine.status(thread) ~= "dead" then running = true end
    end
    if not running and not next(readythreads) then break end

    -- pull out threads' recieve-test & send-test sockets into each cumulative list
    for thread, params in pairs(threadswaitingfor) do
      if params.recvr then
        for _, skt in pairs(params.recvr) do
          if skt.inner_sock then
            print("thread for recvt:", threadnames[thread] or thread)
            table.insert(recvt, skt.inner_sock)
            socketwrappermap[skt.inner_sock] = skt;
          end
        end
      end
      if params.sendr then
        for _, skt in pairs(params.sendr) do
          if skt.inner_sock then
            print("thread for sendt:", threadnames[thread] or thread)
            table.insert(sendt, skt.inner_sock)
            socketwrappermap[skt.inner_sock] = skt;
          end
        end
      end
    end

    -- run timeouts (will push to `readythreads`)
    timeout = timers.run()

    if next(readythreads) then
      print("thread woken during execution of other threads, no timeout")
      timeout = 0
    end

    if not timeout and #recvt == 0 and #sendt == 0 then
      -- in case of bugs
      error("cosock tried to call socket.select with no sockets and no timeout. "
            .."this is a bug, please report it")
    end

    print("start select", #recvt, #sendt, timeout)
    --for k,v in pairs(recvt) do print("r", k, v) end
    --for k,v in pairs(sendt) do print("s", k, v) end
    local recvr, sendr, err = socket.select(recvt, sendt, timeout)
    print("return select", #(recvr or {}), #(sendr or {}))

    if err and err ~= "timeout" then error(err) end

    -- call waker on recieve-ready sockets
    for _,lskt in ipairs(recvr or {}) do
      local skt = socketwrappermap[lskt]
      assert(skt, "unknown socket")
      assert(skt._wake, "unwakeable socket")
      skt:_wake("recvr")
    end

    -- call waker on send-ready sockets
    for _,lskt in ipairs(sendr or {}) do
      local skt = socketwrappermap[lskt]
      assert(skt, "unknown socket")
      assert(skt._wake, "unwakeable socket")
      skt:_wake("sendr")
    end
  end

  print("run exit")
end

-- reset state for tests, not for external use
function m.reset()
  threads = {}
  threadnames = setmetatable({}, weakkeys)
  threadswaitingfor = {}
  readythreads = {}
  socketwrappermap = setmetatable({}, weaktable)
  threaderrorhandler = nil
end

return m
