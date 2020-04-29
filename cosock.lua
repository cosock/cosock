local cosocket = require "cosock.cosocket"
local socket = require "socket"
local channel = require "cosock.channel"

local threads = {} --TODO: use set instead of list
local newthreads = {} -- threads to be added before next iteration of run
local threadnames = {}
local threadswaitingfor = {} -- what each thread is waiting for
local threadsocketmap = {} -- maps threads from which socket is being waiting
local socketwrappermap = {} -- from native socket to async socket TODO: weak ref
local threaderrorhandler = nil
local threadtimeouts = {} -- map of thread => timeout info map
local threadtimeoutlist = {} -- ordered list of timeout info maps

-- silence print statements in this file
local print = function() end

local m = {}

m.socket = cosocket
m.channel = channel

function m.spawn(fn, name)
  local thread = coroutine.create(fn)
  print("cosocket spawn", name or thread)
  threadnames[thread] = name
  table.insert(newthreads, thread)
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
  local recvr, sendr = {}, {} -- ready to send/recv sockets from luasocket.select
  local nextwakethreads = nil -- set to table like wakethreads if a thread is woken by other thread
  while true do
    print(string.format("================= %s ======================", socket.gettime() - runstarttime))
    local deadthreads = {} -- list of threads that are finished executing
    local wakethreads = nextwakethreads or {} -- map of thread => named resume params (rdy skts, timeout, etc)
    nextwakethreads = nil
    local sendt, recvt, timeout = {}, {}, nil -- cumulative values across all threads

    -- threads can't be added while iterating through the main list
    for _, thread in pairs(newthreads) do
      threads[thread] = thread
      wakethreads[thread] = {} -- empty no ready sockets or errors
    end
    newthreads = {}

    -- map recieve-ready sockets to threads to be woken & note which socket(s) were the cause
    for _,lskt in ipairs(recvr) do
      print("**** recvr ****")
      local skt = socketwrappermap[lskt]
      assert(skt)
      local srcthreads = threadsocketmap[skt]
      assert(srcthreads, "no thread waiting on socket")
      assert(srcthreads.recv, "no thread waiting on recv ready")
      wakethreads[srcthreads.recv] = wakethreads[srcthreads.recv] or {}
      wakethreads[srcthreads.recv].recvr = wakethreads[srcthreads.recv].recvr or {}
      table.insert(wakethreads[srcthreads.recv].recvr, skt)
      local threadtimeoutinfo = threadtimeouts[srcthreads.recv]
      if threadtimeoutinfo then threadtimeoutinfo.timeouttime = nil end -- mark timeout canceled
    end

    -- map send-ready sockets to threads to be woken & note which socket(s) were the cause
    for _,lskt in ipairs(sendr) do
      local skt = socketwrappermap[lskt]
      print("**** sendr ****", skt)
      assert(skt)
      local srcthreads = threadsocketmap[skt]
      for k,thread in pairs(srcthreads) do print(k,threadnames[thread] or thread) end
      assert(srcthreads, "no thread waiting on socket")
      assert(srcthreads.send, "no thread waiting on send ready")
      wakethreads[srcthreads.send] = wakethreads[srcthreads.send] or {}
      wakethreads[srcthreads.send].sendr = wakethreads[srcthreads.send].sendr or {}
      table.insert(wakethreads[srcthreads.send].sendr, skt)
      local threadtimeoutinfo = threadtimeouts[srcthreads.send]
      if threadtimeoutinfo then threadtimeoutinfo.timeouttime = nil end -- mark timeout canceled
    end

    -- map hit timeouts to threads to be woken & note that timeout was the cause
    local now = socket.gettime()
    for _,toinfo in ipairs(threadtimeoutlist) do
      if toinfo.timeouttime then -- skip canceled timeouts
        if now < toinfo.timeouttime then break end -- only process expired timeouts
        print(toinfo.timeouttime, now, toinfo.timeouttime - now)

        wakethreads[toinfo.thread] = {err = "timeout" }
        toinfo.timeouttime = nil -- mark timeout handled
      end
    end

    -- run all threads
    for thread, params in pairs(wakethreads) do
      print("+++++++++++++ waking", threadnames[thread] or thread, params.recvr, params.sendr, params.err)
      if coroutine.status(thread) == "suspended" then
        local status, threadrecvt_or_err, threadsendt, threadtimeout =
          coroutine.resume(thread, params.recvr, params.sendr, params.err)

        if status and coroutine.status(thread) == "suspended" then
          local threadrecvt = threadrecvt_or_err
          print("--------------- suspending", threadnames[thread] or thread, threadrecvt, threadsendt, threadtimeout)
          -- note which sockets this thread is now waiting on
          threadswaitingfor[thread] = {recvt = threadrecvt, sendt = threadsendt, timeout = threadtimeout}

	  if threadrecvt then
            for _,skt in pairs(threadrecvt) do
              -- waker-style virtual sockets only, luasocket sockets handled outside wakethread loop
              if skt.setwaker then
                skt:setwaker("recvr", function()
                  nextwakethreads = nextwakethreads or {}
                  nextwakethreads[thread] = nextwakethreads[thread] or {}
                  nextwakethreads[thread].recvr = nextwakethreads[thread].recvr or {}
                  table.insert(nextwakethreads[thread].recvr, skt)
                end)
              end
            end
	  end
          if threadsendt then
            for _,skt in pairs(threadsendt) do
              -- waker-style virtual sockets only, luasocket sockets handled outside wakethread loop
              if skt.setwaker then
                skt:setwaker("sendr", function()
                  nextwakethreads = nextwakethreads or {}
                  nextwakethreads[thread] = nextwakethreads[thread] or {}
                  nextwakethreads[thread].sendr = nextwakethreads[thread].sendr or {}
                  table.insert(nextwakethreads[thread].sendr, skt)
                end)
              end
            end
          end
          if threadtimeout then
            local timeoutinfo = {
              thread = thread,
              timeouttime = threadtimeout + socket.gettime()
            }
            threadtimeouts[thread] = timeoutinfo
            table.insert(threadtimeoutlist, timeoutinfo)
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
          table.insert(deadthreads, thread)
        end
      else
        print("warning: non-suspended thread encountered", coroutine.status(thread))
      end
    end

    -- threads can't be removed while iterating through the main list
    for _, thread in ipairs(deadthreads) do
      threads[thread] = nil
    end

    -- cull dead timeouts
    local listlen = #threadtimeoutlist -- list will shrink during iteration
    for i = 1, #threadtimeoutlist do
      local ri = listlen - i + 1
      print("idx", i, ri, listlen)
      print(threadtimeoutlist[ri])
      if not threadtimeoutlist[ri] then
        print(string.format("internal error: empty element in timeout list at %s/%s", ri, listlen))
        table.remove(threadtimeoutlist, ri)
      elseif not threadtimeoutlist[ri].timeouttime then
        local toinfo = table.remove(threadtimeoutlist, ri)
        threadtimeouts[toinfo.thread] = nil
      end
    end

    -- check if all threads have completed so that the runtime should exit
    local running = false
    for _, thread in pairs(threads) do
      print("thread", threadnames[thread] or thread, coroutine.status(thread))
      if coroutine.status(thread) ~= "dead" then running = true end
    end
    if not running and #newthreads == 0 then break end

    -- pull out threads' recieve-test & send-test sockets into each cumulative list
    for thread, params in pairs(threadswaitingfor) do
      if params.recvt then
        for _, skt in pairs(params.recvt) do
          if skt.inner_sock then
            print("thread for recvt:", threadnames[thread] or thread)
            threadsocketmap[skt] = {recv = thread}
            table.insert(recvt, skt.inner_sock)
            socketwrappermap[skt.inner_sock] = skt;
          end
        end
      end
      if params.sendt then
        for _, skt in pairs(params.sendt) do
          if skt.inner_sock then
            print("thread for sendt:", threadnames[thread] or thread)
            threadsocketmap[skt] = {send = thread}
            table.insert(sendt, skt.inner_sock)
            socketwrappermap[skt.inner_sock] = skt;
          end
        end
      end
    end

    if #newthreads > 0 then
      print("new thread waiting, no timeout")
      timeout = 0
    elseif nextwakethreads then
      print("thread woken during execution of other threads, no timeout")
      timeout = 0
    else
      -- this is exceptionally inefficient, but it works, TODO: I dunno, timerwheel, after benchmarks
      table.sort(
        threadtimeoutlist,
        function(a,b) return a.timeouttime and b.timeouttime and a.timeouttime < b.timeouttime end
      )
      local timeouttime = (threadtimeoutlist[1] or {}).timeouttime
      if timeouttime then
        timeout = math.max(timeouttime - socket.gettime(), 0) -- negative timeouts mean infinity
        print("earliest timeout", timeout)
        now = socket.gettime()
        for k,v in ipairs(threadtimeoutlist) do print(k,v,v.timeouttime - now) end
      end
    end

    --if not timeout and #recvt == 0 and #sendt == 0 then
    --  -- in case of bugs
    --  timeout = 1
    --  print("WARNING: cosock tried to call socket select with no sockets and no timeout"
    --    --[[ TODO: for when things actually work: .." this is a bug, please report it"]])
    --end

    print("start select", #recvt, #sendt, timeout)
    --for k,v in pairs(recvt) do print("r", k, v) end
    --for k,v in pairs(sendt) do print("s", k, v) end
    local err
    recvr, sendr, err = socket.select(recvt, sendt, timeout)
    print("return select", #recvr, #sendr)

    if err and err ~= "timeout" then error(err) end
  end

  print("run exit")
  --for k,v in ipairs(threadtimeoutlist) do print(k,v); print(threadnames[v.thread] or v.thread, v.timeouttime) end
  assert(#threadtimeoutlist == 0, "thread timeoutlist")

end

return m
