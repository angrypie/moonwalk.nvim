---@class Node
---@field id string
---@field parent string
---@field children string[]

local half_block_char = "▄"

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

	local debug_str = vim.inspect(ranges[1]) .. " >>"
	local offset = ranges[#ranges][1]
	--TODO for first use as is others: sub(text, first, prev_first) .. sub(last, prev_last)
	for i, range in ipairs(ranges) do
		local first = range[1] - offset + 1
		local last = range[2] - offset
		--TODO spacel will make shadow hash different although it's the same nade
		-- shadow is a parts of the code that is not belonging to current node and its parents
		local prefix = half_block_char
		if i == 1 then
			prefix = prefix .. string.sub(text, first, last)
		end
		local shadow = string.sub(text, 0, first - 1) .. prefix .. string.sub(text, last + 1, #text)
		local hash = crc32(shadow)
		debug_str = debug_str .. shadow .. hash .. "--->"
	end

	debug_str = debug_str
	print(debug_str)
end

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
