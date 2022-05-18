print("----------------------------------------")
local cosock = require "cosock"
assert(cosock, "require something")
assert(type(cosock) == "table", "cosock is table")
local socket = require "cosock.socket"

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
        local result = table.pack(client:receive("*l", "prefix"))
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
    local output = assert(table.unpack(rx:receive()))
    assert(output == "prefixchunk1chunk2chunk3chunk4", "Invalid outout: " .. tostring(output));
end, "send new line")

cosock.spawn(function()
    local tx, rx = cosock.channel.new()
    run_test(port+1, false, tx)
    local output = assert(rx:receive())
    assert(output[3], output[2])
    assert(output[3]:match("prefixchunk1chunk2chunk3"), string.format("Invalid outout: %s", output));
end, "don't send new line")

cosock.run()

print("--------------- SUCCESS ----------------")
