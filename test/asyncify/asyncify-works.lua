-- disable this test for 5.1 since we can't asyncify
if _VERSION == "Lua 5.1" then os.exit(0) end
local cosock = require "cosock"
-- import the sync versions of one and two for comparison later
local sync_zero = require("socket")
local sync_one = require("test.asyncify.one")
local sync_two = require("test.asyncify.two")

function test_module(async, sync, name)
    print(string.format("Trying %s", name))
    -- Assert we didn't get an error string from cosock.asyncify
    assert(type(async) ~= "string", "Expected table found string for %s: %s", name, tostring(two))
    -- Assert we didn't get the luasocket module
    assert(async ~= sync, "require produced the same result as asyncify for", name)
    -- Confirm that the async module is expecting to run via cosock
    local selected, err = pcall(async.select, {}, {}, 0.1)
    assert(not selected, "selected async w/o error for", name)
    assert(type(err) == "string", "No error for", name)
    assert(err:match("attempt to yield from outside a coroutine"),
        string.format("bad async error for %s: %s", name, err))
    -- Confirm the sync module will timeout on select
    local sync_r, sync_w, sync_err = sync_zero.select({}, {}, 0.1)
    assert(#sync_r == 0, "selected sync read for", name)
    assert(#sync_w == 0, "selected sync write for", name)
    assert(sync_err == "timeout", "bad sync erorr for", name)
end

-- Test wrapping via asyncify
local zero = cosock.asyncify "socket"
test_module(zero, sync_zero, "direct")

-- test wrapping when first module requires socket
local one = cosock.asyncify "test.asyncify.one"
test_module(one, sync_one, "non-nested")

-- test wrapping when first module requires a module that
-- requires socket
local two = cosock.asyncify "test.asyncify.two"
test_module(two, sync_two, "nested")

-- Ensure the "standard library" module names work via asynify
local t = require "table"
local at = cosock.asyncify("table")
assert(at == t, string.format("%s", at))
local nat = cosock.asyncify("test.asyncify.nested.table")
assert(nat == t, string.format("%s", nat))
