local cosock = require "cosock"

local named_tx, named_rx = cosock.channel.new()
local unnamed_tx, unnamed_rx = cosock.channel.new()

local nameless = cosock.spawn(function()
  cosock.socket.sleep(65535)
end)

local named = cosock.spawn(function()
  cosock.socket.sleep(65535)
end, "named")

local number_name = cosock.spawn(function()
  cosock.socket.sleep(65535)
end, 1)
local t = {}
local table_name = cosock.spawn(function()
  cosock.socket.sleep(65535)
end, t)

cosock.spawn(function()
  assert(string.sub(tostring(nameless), 1, 6) == "thread", string.format("expected `thread <pointer>` found `%s`", nameless))
  nameless:cancel()
  assert(tostring(nameless) == "dead-thread")
  assert(tostring(named) == "named", string.format("expected `named` found `%s`", named))
  named:cancel()  
  assert(tostring(number_name) == "1", string.format("expected `1` found `%s`", number_name))
  number_name:cancel()
  assert(tostring(table_name) == tostring(t), string.format("expected `%s` found `%s`", t, table_name))
  table_name:cancel()
end)

cosock.run()
