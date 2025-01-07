local cosock = require "cosock"

local control_tx, control_rx = cosock.channel.new()

local sleep_handle = cosock.spawn(function()
  control_tx:send({})
  cosock.socket.sleep(math.maxinteger)
end, "sleep")

local _, handle_rx = cosock.channel.new()
local rx_handle = cosock.spawn(function()
  control_tx:send({})
  handle_rx:receive()
end, "rx")

local socket_handle = cosock.spawn(function()
  control_tx:send({})
  local udp = assert(cosock.socket.udp())
  udp:setsockname("*", 0)
  assert(udp:receivefrom())
end, "socket")

local handles = {sleep_handle, rx_handle, socket_handle}

local killer = cosock.spawn(function()
  -- wait for all to be yielding
  for i=1, #handles do
    assert(control_rx:receive())
  end
  for _,handle in ipairs(handles) do
    print("checking", handle.name)
    assert(handle:is_alive(), string.format("expected %q to be alive", handle.name))
    print("canceling", handle.name)
    handle:cancel()
    print("confirming", handle.name)
    assert(not handle:is_alive(), string.format("expected %q to be dead", handle.name))
    print("successfully canceled", handle.name)
  end
end)

cosock.run()
