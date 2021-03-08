local cosock = require "cosock"
local socket = cosock.socket

local funcsran = 0
local finalizersran = 0

------------------
-- mock functions
------------------

local function happy()
  funcsran = funcsran + 1
  if 1+1 == 2 then
    return "all good"
  else
    return nil,  "your computer is super broke"
  end
end

local function callserror()
  funcsran = funcsran + 1
  error("I meant to do that")
end

local function returnserror()
  funcsran = funcsran + 1
  return nil, "is this really my purpose in life?"
end

---------------------------------------------
-- try each mock function with default `try`
---------------------------------------------

local pth = socket.protect(function()
  return socket.try(happy())
end)

assert(pth() == "all good", "not all good")

local ptce = socket.protect(function()
  socket.try(callserror())
end)

assert(not pcall(ptce), "internal error didn't error")

local ptre = socket.protect(function()
  socket.try(returnserror())
end)

ptre()

---------------------------------------------------
-- try each mock function with custom try function
---------------------------------------------------

local custtry = socket.newtry(function()
  finalizersran = finalizersran + 1
end)

local pcth = socket.protect(function()
  return custtry(happy())
end)

assert(pcth() == "all good", "not all good")

local pctce = socket.protect(function()
  custtry(callserror())
end)

assert(not pcall(pctce), "internal error didn't error")

local pctre = socket.protect(function()
  custtry(returnserror())
end)

pctre()

---------------------------------
-- check that stuff actually ran
---------------------------------

assert(funcsran == 6, "functions didn't run")
assert(finalizersran == 1, "finalizers didn't run")

print("--------------- SUCCESS ----------------")

