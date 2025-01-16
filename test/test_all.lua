local failures = false

function run_test(path, ...)
  if os.getenv("GITHUB_ACTION") then
    io.write("::group::")
  end

  io.write("running ", path, "...")
  local args = table.concat({...}, " ")
  local cmd = string.format("timeout 5 lua %s %s 2>&1", path, args)
  local process = assert(io.popen(cmd, 'r'), "failed to start test")
  local stdout = assert(process:read("*a"))

  local success, _, code = process:close()

  if success then
    print("OK")
  else
    print("ERROR")
  end

  if not success or os.getenv("GITHUB_ACTION") then
    print(stdout)
  end

  if os.getenv("GITHUB_ACTION") then
    print("::endgroup::")
  end
end

-- setup test HTTP(S) server
local p = assert(io.popen("lua scripts/http-test-server.lua &\necho $!"))
local serverpid = assert(p:read("*l"))
os.execute("sleep 1") -- wait for test server to start

run_test("test/channel/via-select.lua")
run_test("test/channel/recv-timesout.lua")
run_test("test/error-handling/try-protect.lua")
run_test("test/ssl/client-multi.lua")
run_test("test/ssl/client-timeout.lua")
run_test("test/ssl/client-server-large-payload.lua")
run_test("test/tcp/client-multi.lua")
run_test("test/tcp/client-server-large-payload.lua")
run_test("test/tcp/client-timeout.lua")
run_test("test/tcp/prefix.lua")
run_test("test/threads/spawn-child-and-die.lua")
run_test("test/threads/handle-aliveness-works.lua")
run_test("test/threads/handle-to-string.lua")
run_test("test/threads/handles-can-cancel.lua")
run_test("test/threads/handles-cannot-cancel-self.lua")
run_test("test/udp/client-timeout.lua")
run_test("test/asyncify/asyncify-works.lua")
run_test("test/asyncify/nested/module.lua")
run_test("test/asyncify/nested/table.lua")
run_test("test/asyncify/one.lua")
run_test("test/asyncify/two.lua")
run_test("test/http/http.lua", 8080)
run_test("test/http/https-via-http.lua", 8080)
run_test("test/http/https-via-ssl.lua", 8080)
run_test("test/thread-metadata/sleeping.lua")
run_test("test/thread-metadata/sockets.lua")

-- stop test server
os.execute("kill "..serverpid)

if failures then
  os.exit(1)
end
