print("----------------------------------------")
local cosock = require "cosock"
assert(cosock, "require something")
assert(type(cosock) == "table", "cosock is table")
local socket = require "cosock.socket"

local unpack = table.unpack or unpack
local pack = table.pack or pack or function(a,b,c,d,e)
  -- This is a shim for lua 5.1 which doesn't provide a `pack` operation
  return {
    a,b,c,d,e,
        n = 0 and (e and 5) or (d and 4) or (c and 3) or (b and 2) or (a and 1)
  }
end

local function run_test(port, send_new_line, tx)
    local server = socket.tcp()
    server:bind("*", port)
    server:setoption("reuseaddr", true)
    server:listen(1)
    local addr = server:getsockname()
    cosock.spawn(function()
        local client = socket.tcp()
        client:settimeout(0.3)
        client:connect(addr, port)
        print("connected to", port)
        local result = pack(client:receive("*l", "prefix"))
        tx:send(result)
    end, "client-task" .. tostring(port))
    
    local client = server:accept()
    for i=1,4 do
        client:send("chunk" .. tostring(i))
        socket.sleep(0.1)
    end
    if send_new_line then
        client:send("\n")
    end
    client:close()
    
end

math.randomseed(socket.gettime())
local port = math.random(3000, 9000)

cosock.spawn(function()
    local tx, rx = cosock.channel.new()
    run_test(port, true, tx)
    local output = assert(unpack(rx:receive()))
    assert(output == "prefixchunk1chunk2chunk3chunk4", "Invalid outout: " .. tostring(output));
end, "send new line")

cosock.spawn(function()
    local tx, rx = cosock.channel.new()
    run_test(port+1, false, tx)
    local output = assert(rx:receive())
    assert(output[3], output[2])
    assert(output[3]:match("prefixchunk1chunk2chunk3"), string.format("Invalid outout: %s", tostring(output)));
end, "don't send new line")

cosock.run()

print("--------------- SUCCESS ----------------")
