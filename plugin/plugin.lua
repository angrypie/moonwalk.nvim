-- local m = require('moonwalk')
--
-- vim.keymap.set('n', '<C-m>', m.walk_to_best_place, { noremap = true, silent = true })
-- vim.keymap.set('n', '<C-s>', m.walk_to_another_file, { noremap = true, silent = true })
-- vim.keymap.set('n', '<C-h>', m.debug_view_toggle, { noremap = true, silent = true })
--

local ffi = require("ffi")

-- function M.process_array(numbers)
-- 	if #numbers == 0 then
-- 		return 0
-- 	end
-- 	local arr = ffi.new("uint32_t[?]", #numbers)
-- 	for i = 1, #numbers do
-- 		arr[i - 1] = numbers[i]
-- 	end
-- 	return lib.process_array(arr, #numbers)
-- end

ffi.cdef([[
	void init_plugin();
	int get_number();
	int process_array(const uint32_t *arr, size_t len);
]])
-- --
--
--
--
--
local lib = ffi.load("./libmain.dylib")
--
local M = {}
lib.init_plugin()
--
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

vim.keymap.set("n", "<c-s>", function()
	local api_time_ms = lib.get_number()
	if api_time_ms > 0 then
		print(string.format("LLM suggestion completed in %d ms", api_time_ms))
	end
end, {})

vim.keymap.set("n", "<c-m>", function()
	local result = M.process_array({ 1, 2, 10 })
	-- print(result)
end, {})

return M
