local cosock = require "cosock"
local channel = cosock.channel

local senders_started = 0
local senders_finished = 0
local messages_sent = 0
local messages_received = 0

local function send10(sender, id, interval)
  senders_started = senders_started + 1
  cosock.spawn(function()
    print("sender spawn", id)
    for _=1,10 do
      sender:send({from = id})
      messages_sent = messages_sent + 1

      cosock.socket.sleep(interval)
    end
    print("sender client exit")
    senders_finished = senders_finished + 1

    -- this is kinda gross, but I don't know if I have any other option than to manually track when
    -- I'm done with this. Thanks garbage collection (which doesn't run while/before the loop gets
    -- blocked in luasocket's select call).
    if senders_finished == senders_started then sender:close() end
  end, "sender "..tostring(id))
end

cosock.spawn(function()
  print("receiver spawn")
  local receiver
  do
    local sender
    sender, receiver = channel.new()

    send10(sender, 1, 0.001)
    send10(sender, 2, 0.005)
  end

  --receiver:settimeout(0.0005)

  while true do
    local msg, err = receiver:receive()
    if err == "closed" then break end
    assert(msg or err, "receiver received no message nor error")
    assert(not err, "receive error: "..tostring(err))
    --assert(msg, "no message, but also no error")
    if msg then messages_received = messages_received + 1 end
  end

  print("server exit")
end, "receiver")

cosock.run()

assert(senders_started > 0, "no senders started")
assert(senders_started == senders_finished, "not all senders finished")
assert(messages_sent > 0, "no messages sent")
assert(messages_sent == messages_received, "all messages not recieved: "..messages_sent..", "..messages_received)

print("--------------- SUCCESS ----------------")
