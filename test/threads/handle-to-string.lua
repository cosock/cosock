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

local function assert_name_starts_with(handle, prefix)
  local s = tostring(handle)
  if string.sub(s, 1, 6) ~= prefix then
    error("expected prefix `" .. prefix .. "` found `" .. s .. "`", 2)
  end 
end

local function assert_name_equals(handle, expected)
  local s = tostring(handle)
  if s ~= expected then
    error("expected `" .. expected .. "` found `" .. s .. "`", 2)
  end
end

cosock.spawn(function()
  assert_name_starts_with(nameless, "thread")
  nameless:cancel()
  assert_name_equals(nameless, "dead-thread")
  assert_name_equals(named, "named")
  named:cancel()
  assert_name_equals(number_name, "1")
  number_name:cancel()
  assert_name_equals(table_name, tostring(t))
  table_name:cancel()
end)

cosock.run()
