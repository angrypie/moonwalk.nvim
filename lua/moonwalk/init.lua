-- Use extmarks to mark scope
-- Figure out scope-scoring algorithm (currently just score / i)
-- While editing score should be higher
-- Figure out frecency algorithm
-- What is best max_scope_depth for scoring scope?
-- node:id() its'not guaranteed to be concerete type, (currently non_printable string)
-- If scores increasing indefinitely, do we need to check for overflow?
local ts_utils = require("nvim-treesitter.ts_utils")
local uv = vim.loop

local M = {
	---@type table<string, integer>
	scores          = {},
	---@type table<string, integer>
	marks           = {},
	max_scope_depth = 1,
	ns              = vim.api.nvim_create_namespace('my-plugin')
}


-- Create a handle to a uv_timer_t
local timer = uv.new_timer()
local debug_max_timer = 0

-- This will wait 1000ms and then continue inside the callback
if timer == nil then
	-- throw error
	vim.notify("moonwalk: luv timer is nil", vim.log.levels.ERROR)
else
	timer:start(0, 1000, vim.schedule_wrap(function()
		-- timer here is the value we passed in before from new_timer.
		M.score_current_scope()
		-- You must always close your uv handles or you'll leak memory
		-- We can't depend on the GC since it doesn't know enough about libuv.
		debug_max_timer = debug_max_timer + 1
		if debug_max_timer == 1000 then
			timer:close()
		end
	end))
end

function M.score_current_scope()
	local current = M.get_current_scope()
	-- If working on "chunk" node, do nothing.
	if current == nil then
		return
	end

	M.score_nodes(current, M.max_scope_depth)
end

---TODO score_node is the most important part now, we have to figure out how to properly score each node.
---Time of the visits should be taken into account. Possible look into exponential decay.
---Also score_node sets extmarks and updatets them, sohuld be a lot of bugs while editing text.
---=====
---Increase score of the node, create extmark on the start of the node and returns new score.
---If mark already exists on same line, it will be updated.
---@param node TSNode
---@param score integer
---@return integer
function M.score_node(node, score)
	local line = node:range() -- node start position

	-- get mark for line where ts node starts, or create new one
	local mark = vim.api.nvim_buf_get_extmarks(0, M.ns, { line, 0 }, { line, -1 }, {})[1]
	local id = -1
	if mark == nil then
		id = vim.api.nvim_buf_set_extmark(0, M.ns, line, -1, {})
	else -- if mark exists, get id
		id = mark[1]
	end

	-- update score of the mark
	local old_score = M.scores[id] or 0
	M.scores[id] = old_score + score

	return M.scores[id]
end

---Score all nodes towards root by specified depth. Chunk node is ignored.
---@param node TSNode
---@param depth integer
function M.score_nodes(node, depth)
	local nodes = {}
	local current = node
	local parent = current:parent()

	-- traverse towards root but ignore "chunk" node
	while parent ~= nil and depth ~= 0 do
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
	-- print(debug_str)
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

--sorts scores and moves cursor to the first node
function M.walk_to_best_mark()
	local top = 0
	local value = 0
	for k, v in ipairs(M.scores) do
		if v > value then
			top = k
			value = v
		end
	end
	if top == 0 then
		vim.notify("moonwalk: no history available", vim.log.levels.ERROR)
		return
	end
	-- convert top to integer id
	local mark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, top, {})

	if mark == nil then
		print("No marks found")
		return
	end
	print("mark", mark[1], mark[2], value, top)
	vim.api.nvim_win_set_cursor(0, { mark[1] + 1, mark[2] })
end

return M
