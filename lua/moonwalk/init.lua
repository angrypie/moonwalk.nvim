-- Use extmarks to mark scope
-- Figure out scope-scoring algorithm (currently just score / i)
-- While editing score should be higher
-- Figure out frecency algorithm
-- What is best max_scope_depth for scoring scope?
-- node:id() its'not guaranteed to be concerete type, (currently non_printable string)
-- If scores increasing indefinitely, do we need to check for overflow?
local ts_utils = require("nvim-treesitter.ts_utils")
local uv = vim.loop

---@param tbl table<integer,number>
---@param sortFunction fun(a: any, b: any):boolean
---@param limit integer
---@return integer[]
local function get_keys_sorted_by_value(tbl, sortFunction, limit)
	local keys = {}
	local total = 0
	for key in pairs(tbl) do
		table.insert(keys, key)
		total = total + 1
	end

	table.sort(keys, function(a, b)
		return sortFunction(tbl[a], tbl[b])
	end)

	if limit > total then
		limit = total
	end

	return { unpack(keys, 1, total) }
end



local M = {
	---@type table<integer, number>
	scores          = {},
	max_scope_depth = 10,
	ns              = vim.api.nvim_create_namespace('my-plugin'),
	last_walk_time  = 0,
	---@type integer[]
	walking_session = {}, --
	max_walk_places = 5, -- how many places to walk back in one session
	current_node    = 0,
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

---Get best mark from list of marks, and remove all other marks.
---@param marks any[]
---@return integer
function M.best_extmark_clear_rest(marks)
	local best = nil
	local best_score = 0
	for _, mark in pairs(marks) do
		local id = mark[1]
		local score = M.scores[id] or 0
		if score >= best_score then
			best = id
			best_score = score
		end

		if best ~= nil and best ~= id then -- remove previous best mark
			print("removing", id)
			vim.api.nvim_buf_del_extmark(0, M.ns, id)
			table.remove(M.scores, id)
		end
	end
	-- print("best", best)
	return best
end

---TODO score_node is the most important part now, we have to figure out how to properly score each node.
---Time of the visits should be taken into account. Possible look into exponential decay.
---Also score_node sets extmarks and updatets them, sohuld be a lot of bugs while editing text.
---NOTE if multiple extmarks on the same line, best one would be chosen and others would be deleted.
---=====
---Increase score of the node, create extmark on the start of the node and returns new score.
---If mark already exists on same line, it will be updated.
---@param node TSNode
---@param score integer
---@return integer
function M.score_node(node, score)
	local line = node:range() -- node start position

	-- get mark for line where ts node starts, or create new one
	local marks = vim.api.nvim_buf_get_extmarks(0, M.ns, { line, 0 }, { line, -1 }, {})
	local id = M.best_extmark_clear_rest(marks)
	if id == nil then       -- if mark doesn't exist, create new one
		id = vim.api.nvim_buf_set_extmark(0, M.ns, line, -1, {
			right_gravity = false, -- left gravity, stick to start of the node (on new line, and insert)
		})
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
	-- get new walking session
	if os.time() - M.last_walk_time > 3 then
		M.walking_session = get_keys_sorted_by_value(M.scores, function(a, b)
			return a > b
		end, M.max_walk_places)
		M.last_walk_index = 0
	end

	local keys = M.walking_session
	if keys[1] == nil then
		vim.notify("moonwalk: no history available", vim.log.levels.ERROR)
		return
	end

	-- Track jump history and dont jump to same position twice during 'jump session'
	M.last_walk_index = M.last_walk_index + 1
	if M.last_walk_index > #keys then
		M.last_walk_index = 1
	end
	local nextId = keys[M.last_walk_index]
	local score = M.scores[nextId]

	-- convert top to integer id
	-- TODO when extmark deleted it would point to wrong position and cause error for set_cursor
	local mark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, nextId, {})
	if mark == nil then
		print("No marks found")
		return
	end

	-- print("mark", score, nextId, "since_last")
	vim.api.nvim_win_set_cursor(0, { mark[1] + 1, mark[2] })
	M.last_walk_time = os.time()
end

return M
