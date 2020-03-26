local cosocket = require "cosocket"
local socket = require "socket"

local threads = {} --TODO: use set instead of list
local newthreads = {} -- threads to be added before next iteration of run
local threadnames = {}
local threadswaitingfor = {} -- what each thread is waiting for
local threadsocketmap = {} -- maps threads from which socket is being waiting
local socketwrappermap = {} -- from native socket to async socket TODO: weak ref

local m = {}

m.socket = cosocket

function m.spawn(fn, name)
  local thread = coroutine.create(fn)
  print("cosocket spawn", name or thread)
  threadnames[thread] = name
  table.insert(newthreads, thread)
end

function m.run()
  local recvr, sendr = {}, {} -- ready to send/recv sockets from luasocket.select
  local threadt = {} -- recvt & sendt by thread
  while true do
    print("====================================================")
    local deadthreads = {}
    local wakethreads = {}
    local sendt, recvt, timeout = {}, {}, nil

    -- threads can't be added while iterating through the main list
    for _, thread in pairs(newthreads) do
      table.insert(threads, thread)
      wakethreads[thread] = {} -- empty no ready sockets or errors
    end
    newthreads = {}

    for i,lskt in ipairs(recvr) do
      print("**** recvr ****")
      local skt = socketwrappermap[lskt]
      assert(skt)
      local srcthreads = threadsocketmap[skt]
      assert(srcthreads, "no thread waiting on socket")
      assert(srcthreads.recv, "no thread waiting on recv ready")
      wakethreads[srcthreads.recv] = wakethreads[srcthreads.recv] or {}
      wakethreads[srcthreads.recv].recvr = wakethreads[srcthreads.recv].recvr or {}
      table.insert(wakethreads[srcthreads.recv].recvr, skt)
    end

    for i,lskt in ipairs(sendr) do
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
    end

    -- run all threads
    for thread, params in pairs(wakethreads) do
      print("+++++++++++++ waking", threadnames[thread] or thread)
      if coroutine.status(thread) == "suspended" then
        local status, threadrecvt_or_err, threadsendt, threadtimeout =
          coroutine.resume(thread, params.recvr, params.sendr, params.err)

        assert(not threadtimeout, "timeout not supported")
        if status and coroutine.status(thread) == "suspended" then
          local threadrecvt = threadrecvt_or_err
          -- note which sockets this thread is waiting on
          threadswaitingfor[thread] = {recvt = threadrecvt, sendt = threadsendt, timeout = threadtimeout}
        elseif coroutine.status(thread) == "dead" then
          if not status and not thread_error_handler then
            local err = threadrecvt_or_err
            if debug and debug.traceback then
              print(debug.traceback(thread, err))
            else
              print(err)
            end
            os.exit(-1)
          end
          print("dead", threadnames[thread] or thread, status, recvt_or_err)
          table.insert(deadthreads, index)
        end
      else
        print("warning: non-suspended thread encountered", coroutine.status(thread))
      end
    end

    -- threads can't be removed while iterating through the main list
    -- reverse sort, must pop larger indicies before smaller
    table.sort(deadthreads, function(a, b) return a > b end)
    for _, threadindex in ipairs(deadthreads) do
      table.remove(threads, threadindex)
    end

    local running = false
    for _, thread in pairs(threads) do
      print("thread", threadnames[thread] or thread, coroutine.status(thread))
      if coroutine.status(thread) ~= "dead" then running = true end
    end
    if not running then break end

    if #newthreads > 0 then timeout = 0 end

    for thread, test in pairs(threadswaitingfor) do
      if test.recvt then
        for _, skt in pairs(test.recvt) do
          print("thread for recvt:", threadnames[thread] or thread)
          threadsocketmap[skt] = {recv = thread}
          table.insert(recvt, skt.inner_sock)
          socketwrappermap[skt.inner_sock] = skt;
        end
      end
      if test.sendt then
        for _, skt in pairs(test.sendt) do
          print("thread for sendt:", threadnames[thread] or thread)
          threadsocketmap[skt] = {send = thread}
          table.insert(sendt, skt.inner_sock)
          socketwrappermap[skt.inner_sock] = skt;
        end
      end
      -- TODO: probably something with timers/outs
    end

    if not timeout and #recvt == 0 and #sendt == 0 then
      -- in case of bugs
      timeout = 1
      print("WARNING: cosock tried to call socket select with no sockets and no timeout"
        --[[ TODO: for when things actuall work: .." this is a bug, please report it"]])
    end

    print("start select", #recvt, #sendt, timeout)
    --for k,v in pairs(recvt) do print("r", k, v) end
    --for k,v in pairs(sendt) do print("s", k, v) end
    local err
    recvr, sendr, err = socket.select(recvt, sendt, timeout)
    print("return select", #recvr, #sendr)

    if err and err ~= "timeout" then error(err) end
  end

  print("run exit")
end

return m
