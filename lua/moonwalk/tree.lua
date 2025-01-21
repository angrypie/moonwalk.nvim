---@class Node
---@field id string
---@field parent string
---@field children string[]

local half_block_char = "▄"

local function normalize_whitespace(str)
	return str:gsub("%s+", " ")
end

local function insert_special(ranges, text)
	local special = '•'
	local result = {}

	-- Create lookup tables for starts and ends
	local starts = {}
	local ends = {}
	for _, range in ipairs(ranges) do
		starts[range[1]] = true
		ends[range[2] - 1] = true
	end

	-- Process each character
	for i = 1, #text do
		local char = text:sub(i, i)

		-- Check if we need to insert special char at start
		if starts[i - 1] then
			table.insert(result, special)
		end

		-- Skip whitespace
		if not char:match("%s") then
			-- Add current character
			table.insert(result, char)
		end

		-- Check if we need to insert special char at end
		if ends[i - 1] then
			table.insert(result, special)
		end
	end

	return table.concat(result)
end




local M = {
	nodes = {},
}

local crc32 = require("moonwalk.crc32")

---Score all nodes towards root by specified depth. Chunk node is ignored.
---@param node TSNode
---@param depth integer
function M.score_nodes(node, depth)
	---@type TSNode[]
	local nodes = M.with_ancestors(node)

	-- traverse nodes in reverse order
	local ranges = {}
	local text = vim.treesitter.get_node_text(nodes[#nodes], 0)

	for _, n in ipairs(nodes) do
		local _, _, start_byte, _, _, end_byte = n:range(true)
		ranges[#ranges + 1] = { start_byte, end_byte }
	end

	local inserted_text = insert_special(ranges, text)

	local debug_str = vim.inspect(inserted_text) .. " ++ "
	-- local offset = ranges[#ranges][1]
	-- local prev_light = nil
	-- for i, range in ipairs(ranges) do
	-- 	local first = range[1] - offset + 1
	-- 	local last = range[2] - offset
	-- 	local light = string.sub(text, first, last)
	-- 	if prev_light ~= nil then
	-- 		light = merge_strings(prev_light, light)
	-- 	end
	-- 	prev_light = light
	-- 	-- light = normalize_whitespace(light)
	-- 	debug_str = debug_str .. light .. "->"
	-- end
	-- local debug_st = vim.inspect(ranges[1]) .. " >>"
	-- local offset = ranges[#ranges][1]
	-- --TODO for first use as is others: sub(text, first, prev_first) .. sub(last, prev_last)
	-- for i, range in ipairs(ranges) do
	-- 	local first = range[1] - offset + 1
	-- 	local last = range[2] - offset
	-- 	--TODO spacel will make shadow hash different although it's the same nade
	-- 	-- shadow is a parts of the code that is not belonging to current node and its parents
	-- 	local prefix = half_block_char
	-- 	if i == 1 then
	-- 		prefix = prefix .. string.sub(text, first, last)
	-- 	end
	-- 	-- local shadow = string.sub(text, 0, first - 1) .. prefix .. string.sub(text, last + 1, #text)
	-- 	-- shadow = normalize_whitespace(shadow)
	-- 	-- local hash = crc32(shadow)
	-- 	-- debug_str = debug_str .. shadow .. hash .. "--->"
	-- 	local light = prefix .. string.sub(text, first, last)
	-- 	light = normalize_whitespace(light)
	-- 	local hash = crc32(light)
	-- 	debug_str = debug_str .. light .. hash .. "--->"
	-- end

	debug_str = debug_str
	print(debug_str)
end

-- Score nodes with ast names instead of text
-- function M.score_nodes(node, depth)
-- 	local nodes = M.with_ancestors(node)
-- 	local ast_names = {}
-- 	for _, n in ipairs(nodes) do
-- 		ast_names[#ast_names + 1] = n:sexpr()
-- 	end
-- 	local debug_str = vim.inspect(ast_names[1]) .. " >>"
-- 	for i, name in ipairs(ast_names) do
-- 		local hash = crc32(name)
-- 		-- debug_str = debug_str .. hash .. "--->"
-- 		debug_str = debug_str .. name .. "--->"
-- 	end
-- 	debug_str = debug_str
-- 	print(debug_str)
-- 	print("-------\n")
-- end

---traverse towards root but ignore "chunk" node
---@param node TSNode
---@return TSNode[]
function M.with_ancestors(node)
	local nodes = {}
	local current = node
	local parent = current:parent()
	while parent ~= nil do
		nodes[#nodes + 1] = current
		current = parent
		parent = current:parent()
	end
	return nodes
end

return M
