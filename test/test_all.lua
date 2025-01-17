local failures = false

function run_test(path, ...)
  io.write("running ", path, "...")
  local args = table.concat({...}, " ")
  local cmd = string.format("timeout 5 lua %s %s 2>&1", path, args)
  local process = assert(io.popen(cmd, 'r'), "failed to start test")
  local stdout = assert(process:read("*a"))

  local success, _, code = process:close()

  if success then
    print("OK")
    return
  end

  failures = true
  print("ERROR")
  print(stdout)
end

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
run_test("test/http/https-via-http.lua", 8443)
run_test("test/http/https-via-ssl.lua", 9443)
run_test("test/thread-metadata/sleeping.lua")
run_test("test/thread-metadata/sockets.lua")

if failures then
  os.exit(1)
end
