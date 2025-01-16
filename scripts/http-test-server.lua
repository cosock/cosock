local port = arg[1] or 8080

local cqueues = require "cqueues"
local http_server = require "http.server"
local http_headers = require "http.headers"

local myserver = assert(http_server.listen {
	host = "localhost";
	port = port;
	onstream = function(myserver, stream) -- luacheck: ignore 212
		-- Read in headers
		local req_headers = assert(stream:get_headers())
		local req_method = req_headers:get ":method"
		local req_path = req_headers:get ":path"

		-- print("path", req_path)

		-- Build response headers
		local res_headers = http_headers.new()
		if req_method ~= "GET" then
			res_headers:upsert(":status", "405")
			assert(stream:write_headers(res_headers, true))
			return
		end
		if req_path == "/" then
			res_headers:append(":status", "200")
			res_headers:append("content-type", "text/html")
			-- Send headers to client; end the stream immediately if this was a HEAD request
			assert(stream:write_headers(res_headers, false))
			assert(stream:write_chunk([[<!DOCTYPE html><p>Try /delay[/:seconds:]</p>]], true))
		elseif string.match(req_path, "^/delay") then
      local seconds = string.match(req_path, "^/delay/(%d+)")
      seconds = tonumber(seconds) or 3

		  -- delay response
			cqueues.sleep(seconds) -- yield the current thread for a second.

			-- respond
			res_headers:append(":status", "200")
			assert(stream:write_headers(res_headers, false))
			assert(stream:write_chunk("OK", true))
		else
			res_headers:append(":status", "404")
			assert(stream:write_headers(res_headers, true))
		end
	end;
	onerror = function(myserver, context, op, err, errno) -- luacheck: ignore 212
		local msg = op .. " on " .. tostring(context) .. " failed"
		if err then
			msg = msg .. ": " .. tostring(err)
		end
		assert(io.stderr:write(msg, "\n"))
	end;
})

-- Manually call :listen() so that we are bound before calling :localname()
assert(myserver:listen())
do
	local bound_port = select(3, myserver:localname())
	assert(io.stderr:write(string.format("Now listening on port %d\nOpen http://localhost:%d/ in your browser\n", bound_port, bound_port)))
end
-- Start the main server loop
assert(myserver:loop())

