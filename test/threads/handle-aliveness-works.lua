local cosock = require "cosock"

local tx, rx = cosock.channel.new()

local handle = cosock.spawn(function()
  rx:receive()
end)

cosock.spawn(function()
  assert(handle:is_alive())
  tx:send({})
  -- yield to allow the `handle` task to complete
  cosock.socket.sleep(0)
  assert(not handle:is_alive())
end)

cosock.run()
