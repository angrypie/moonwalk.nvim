---@class Node
---@field id string
---@field parent string
---@field children string[]

local M = {
	nodes = {},
}

local locals = require("nvim-treesitter.locals")

---Score all nodes towards root by specified depth. Chunk node is ignored.
---@param node TSNode
---@param depth integer
function M.score_nodes(node, depth)
	---@type TSNode[]
	local nodes = {}
	local current = node
	local parent = current:parent()
	-- traverse towards root but ignore "chunk" node
	while parent ~= nil do
		nodes[#nodes + 1] = current
		depth = depth - 1
		current = parent
		parent = current:parent()
	end

	-- traverse nodes in reverse order
	-- l
	local ranges = {}
	local text = vim.treesitter.get_node_text(nodes[#nodes], 0)

	for i = #nodes, 1, -1 do
		local n = nodes[i]
		local _, _, start_byte, _, _, end_byte = n:range(true)
		ranges[#ranges + 1] = { start_byte, end_byte }
		-- print(vim.inspect(ranges))
	end

	local debug_str = vim.inspect(ranges[1]) .. " >> "
	local base_start = ranges[1][1]
	-- local base_end = ranges[#ranges][2]
	for _, range in ipairs(ranges) do
		local sub = string.sub(text, range[1] - base_start, range[2] - base_start)
		debug_str = debug_str .. sub .. " -> "
	end

	-- for _, n in ipairs(M.nodes) do
	-- 	local changed = n:missing()
	-- 	-- if changed then
	-- 	local text = changed and "missing" or "not-missing"
	-- 	debug_str = debug_str .. text .. " -> "
	-- 	-- end
	-- end
	print(debug_str)
end

return M
