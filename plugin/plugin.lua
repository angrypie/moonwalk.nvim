-- local m = require('moonwalk')

-- vim.keymap.set('n', '\\', m.walk_to_top, { noremap = true, silent = true })
-- vim.keymap.set('n', '<C-s>', m.walk_to_top, { noremap = true, silent = true })


local ffi = require 'ffi'

ffi.cdef [[
	int get_magenta()
]]

local lib = ffi.load('./libmain.dylib')

vim.keymap.set('n', '<C-s>', function()
	local result = lib.get_magenta()
	print(result)
end, {})

-- print(lib.get_magenta())
