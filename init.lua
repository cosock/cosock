local cosocket = require "cosocket"

local threads = {} --TODO: use set instead of list
local newthreads = {} -- threads to be added before next iteration of run

local m = {}

m.socket = cosocket

function m.spawn(fn)
  local thread = coroutine.create(fn)
  table.insert(threads, thread)
end

function m.run()
  local running = true
  while running do

    local deadthreads = {}

    -- this can't happen while iterating through list
    for _, thread in pairs(newthreads) do table.insert(threads, thread) end

    running = false
    for index, thread in pairs(threads) do
      if coroutine.status(thread) == "suspended" then
        local status, socket_or_err = coroutine.resume(thread, nil) -- no error
        if status and coroutine.status(thread) == "suspended" then
          running = true
        elseif coroutine.status(thread) == "dead" then
          print("dead", thread, status, socket_or_err)
          table.insert(deadthreads, index)
        end
      else
        print("warning: non-suspended thread encountered", coroutine.status(thread))
      end
    end

    -- reverse sort, must pop larger indicies before smaller
    table.sort(deadthreads, function(a, b) return a > b end)
    for _, threadindex in ipairs(deadthreads) do
      table.remove(threads, threadindex)
    end
  end

  print("run exit")
end

return m
