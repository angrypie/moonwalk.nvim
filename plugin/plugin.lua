local ffi = require("ffi")

ffi.cdef([[
	void init_plugin();
	int get_number();
	int apply_patch();
	int setup_shadow(const char *config_json);
	int process_array(const uint32_t *arr, size_t len);
]])

local lib = ffi.load("./libmain.dylib")

local M = {}
local setup_done = false

lib.init_plugin()

function M.setup(opts)
	if setup_done then
		return false, "moonwalk: setup already called"
	end

	local payload = "{}"
	if opts ~= nil then
		local ok, encoded = pcall(vim.json.encode, opts)
		if not ok then
			return false, "moonwalk: failed to encode setup options"
		end
		payload = encoded
	end

	local code = lib.setup_shadow(payload)
	if code == 0 then
		setup_done = true
		return true
	end

	if code == 1 then
		return false, "moonwalk: invalid setup json"
	end
	if code == 2 then
		return false, "moonwalk: invalid setup values"
	end
	if code == 3 then
		return false, "moonwalk: setup already initialized"
	end

	return false, string.format("moonwalk: setup failed (%d)", code)
end

function M.process_array(numbers)
	if #numbers == 0 then
		return 0
	end
	local arr = ffi.new("uint32_t[?]", #numbers)
	for i = 1, #numbers do
		arr[i - 1] = numbers[i]
	end
	return lib.process_array(arr, #numbers)
end

vim.keymap.set("n", "<c-x>", function()
	local api_time_ms = lib.get_number()
	if api_time_ms > 0 then
		print(string.format("LLM suggestion completed in %d ms", api_time_ms))
	end
end, {})

vim.keymap.set("n", "<c-m>", function()
	local api_time_ms = lib.apply_patch()
	if api_time_ms > 0 then
		print(string.format("Apply patch completed in %d ms", api_time_ms))
	end
end, {})

return M
