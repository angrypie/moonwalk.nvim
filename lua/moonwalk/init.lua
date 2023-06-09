-- TODO Figure out scope-scoring algorithm (currently just score / i)
-- TODO While editing score should be higher
-- TODO Figure out frecency algorithm
-- TODO What is best max_scope_depth for scoring scope?
-- TODO node:id() its'not guaranteed to be concerete type, (currently non_printable string)
-- TODO If scores increasing indefinitely, do we need to check for overflow?
local ts_utils = require("nvim-treesitter.ts_utils")
local uv = vim.loop

local M = {
	---@type table<string, integer>
	scores = {},
	---@type table<string, TSNode>
	nodes = {},
	max_scope_depth = 20,
}


-- Create a handle to a uv_timer_t
local timer = uv.new_timer()
local debug_max_timer = 0

-- This will wait 1000ms and then continue inside the callback
timer:start(0, 1000, vim.schedule_wrap(function()
	-- timer here is the value we passed in before from new_timer.

	M.score_current_scope()

	-- You must always close your uv handles or you'll leak memory
	-- We can't depend on the GC since it doesn't know enough about libuv.
	debug_max_timer = debug_max_timer + 1
	if debug_max_timer == 100 then
		timer:close()
	end
end))


--sorts scores and moves cursor to the first node
function M.walk_to_top()
	local top = nil
	local value = 0
	for k, v in pairs(M.scores) do
		if v > value then
			top = k
			value = v
		end
	end
	local node = M.nodes[top]
	ts_utils.goto_node(node, false, true)
end

function M.score_current_scope()
	local current = M.get_current_scope()
	-- If working on "chunk" node, do nothing.
	if current == nil then
		return
	end

	M.score_nodes(current, M.max_scope_depth)
end

---Score all nodes towards root by specified depth. Chunk node is ignored.
---@param node TSNode
---@param depth integer
function M.score_nodes(node, depth)
	local nodes = {}
	local current = node
	local parent = current:parent()

	-- traverse towards root but ignore "chunk" node
	while parent ~= nil do
		table.insert(nodes, current)
		current = parent
		parent = current:parent()
		depth = depth - 1
	end
	local debug_str = ""

	local score = 1
	for i, n in ipairs(nodes) do
		local new_score = M.score_node(n, score / i)
		debug_str = debug_str .. n:type() .. string.format(" %.2f", new_score) .. " -> "
	end
	print(debug_str)
end

---Increase score of the node and returns new score
---@param node TSNode
---@param score integer
---@return integer
function M.score_node(node, score)
	local id = node:id()

	local old_score = M.scores[id] or 0
	if old_score == nil then
		M.scores[id] = 0
	else
		M.scores[id] = old_score + score
	end
	M.nodes[id] = node
	return old_score + score
end

---Get node where user is likely working. Return nil if cursor on "cuhnk" node
---@return TSNode | nil
function M.get_current_scope()
	local current = ts_utils.get_node_at_cursor()
	if current == nil then
		return nil
	end
	-- If working on "chunk" node return nil
	if current:parent() == nil then
		return nil
	end
	return current
end

return M
