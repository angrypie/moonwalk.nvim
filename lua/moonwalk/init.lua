-- Use extmarks to mark scope
-- Figure out scope-scoring algorithm (currently just score / i)
-- While editing score should be higher
-- Figure out frecency algorithm
-- What is best max_scope_depth for scoring scope?
-- node:id() its'not guaranteed to be concrete type, (currently non_printable string)
-- If scores increasing indefinitely, do we need to check for overflow?
local uv = vim.uv
-- local scope = require("moonwalk.tree") uncomment other: TODO tree-sitter version
local utils = require("moonwalk.utils")

-- use vim.fn.has to check for nvim version to be 0.11 or higher, if not exit
if vim.fn.has("nvim-0.11") == 0 then
	vim.notify("Moonwalk requires Neovim 0.11+", vim.log.levels.ERROR)
	return
end


local M = {
	---@type integer
	extmarks_counter     = 0, -- total nuber of extmarks
	---@type integer
	extmark_id_increment = 0, -- incremental id for extmarks to avoid collisions
	---@type table<integer, number>
	scores               = {},
	---@type table<integer, string>
	extmark_to_file      = {}, -- extmark id -> file name
	max_scope_depth      = 5,
	ns_hl                = vim.api.nvim_create_namespace('moonwalk.hl'),
	ns                   = vim.api.nvim_create_namespace('moonwalk.mark'),
	last_walk_time       = 0, -- TODO replace with tracking keypresses
	---@type integer[]
	walking_session      = {}, -- cache walking session to not recalculate while user rapidly invokes walking method
	max_walk_places      = 5, -- how many places to walk back in one session
	current_node         = 0,
	IS_DEBUG             = false,
	hl_enabled           = false,
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
		if M.IS_DEBUG then
			M.debug_show_scores()
		end
	end))
end

function M.next_extmark_id()
	M.extmark_id_increment = M.extmark_id_increment + 1
	return M.extmark_id_increment
end

function M.update_extmark_score(id, line, score)
	if id == nil then -- if mark doesn't exist, create new one
		local next_id = M.next_extmark_id()
		id = vim.api.nvim_buf_set_extmark(0, M.ns, line, -1, {
			right_gravity = false, -- left gravity, stick to start of the node (on new line, and insert)
			id = next_id,
		})
		local file = vim.api.nvim_buf_get_name(0)
		M.extmark_to_file[id] = file -- safve
		print("new extmark", id, file, next_id)
		M.extmarks_counter = M.extmarks_counter + 1
	end

	-- update or add new score
	local new_score = (M.scores[id] or 0) + score
	M.scores[id] = new_score
	return score
end

function M.remove_extmark_score(id)
	print("remove", id)
	table.remove(M.scores, id)
	table.remove(M.extmark_to_file, id)
	M.extmarks_counter = M.extmarks_counter - 1
	vim.api.nvim_buf_del_extmark(0, M.ns, id)
end

function M.score_current_scope()
	local current = utils.get_current_scope()
	-- If working on "chunk" node, do nothing.
	if current == nil then
		return
	end

	M.score_nodes(current, M.max_scope_depth)
	-- scope.score_nodes(current, M.max_scope_depth) uncomment other: TODO tree-sitter version
end

---Get best mark from list of marks, and remove all other marks.
---@param marks any[]
---@return integer | nil
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
			M.remove_extmark_score(id)
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
	return M.update_extmark_score(id, line, score)
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
	-- TODO right now we are double scoring nodes, that are on the same line
	-- because of score consolidation into one extmark,
	for i, n in ipairs(nodes) do
		local new_score = M.score_node(n, score / i) -- figure out better scoring algorithm
		debug_str = debug_str .. n:type() .. string.format(" %.2f", new_score) .. " -> "
	end
	-- print(debug_str)
end

---@class WalkOpts
---@field ignore_file string? File to ignore when walking
---@type WalkOpts
local default_walk_opts = {
	ignore_file = nil,
}

-- TODO implement recency scoring here, make it reusable (jump per file, per project)
-- Returns top k extmarks ids
-- @return integer[]
function M.get_best_places(opts)
	if opts == nil then
		opts = default_walk_opts
	end
	local ignore_file = opts.ignore_file
	print("extmarks_counter", M.extmarks_counter)

	local filtered_scores = M.scores
	local length = M.extmarks_counter
	if ignore_file ~= nil then -- remove from scores all extmarks than are ignore_file
		-- on huge amount of marks it could be redundant to copy all extmarks to new table
		filtered_scores = {}
		length = 0
		for id, score in pairs(M.scores) do
			if M.extmark_to_file[id] ~= ignore_file then
				length = length + 1
				filtered_scores[id] = score
			end
		end
	end
	return utils.topKTable(filtered_scores, length, M.max_walk_places)
end

function M.walk_to_another_file()
	local current_file = vim.api.nvim_buf_get_name(0)
	local opts = { ignore_file = current_file }
	M.walk_to_best_place(opts)
end

--sorts scores and moves cursor to the first node
---@param opts WalkOpts
function M.walk_to_best_place(opts)
	if opts == nil then
		opts = default_walk_opts
	end
	-- get new walking session
	-- TODO for now 'walking session' cashed  if less than 2 seconds passed betweeen calls
	if os.time() - M.last_walk_time > 2 then
		M.walking_session = M.get_best_places(opts)
		M.last_walk_index = 0
	end

	local keys = M.walking_session or {}
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


	local target_file = M.extmark_to_file[nextId]
	local current_file = vim.api.nvim_buf_get_name(0)
	if target_file ~= current_file then
		vim.cmd("e " .. target_file)
	end

	-- convert top to integer id
	-- TODO when extmark deleted it would point to wrong position and cause error for set_cursor
	local mark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, nextId, {})
	if mark == nil then
		print("No marks found")
		return
	end

	vim.api.nvim_win_set_cursor(0, { mark[1] + 1, mark[2] })
	M.last_walk_time = os.time()
end

function M.debug_view_toggle()
	if M.hl_enabled then
		vim.api.nvim_buf_clear_namespace(0, M.ns_hl, 0, -1)
		M.hl_enabled = false
		M.IS_DEBUG = false
		return
	end
	M.hl_enabled = true
	M.IS_DEBUG = true
end

function M.debug_show_scores()
	-- Clear any existing virtual text first
	vim.api.nvim_buf_clear_namespace(0, M.ns_hl, 0, -1)
	-- get extmarks for current file
	local all = vim.api.nvim_buf_get_extmarks(0, M.ns, 0, -1, {})
	for _, mark in pairs(all) do
		-- local mark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, id, {})
		local id = mark[1]
		local row = mark[2]
		local score = M.scores[id]
		-- Format score with 2 decimal places
		local score_text = string.format("%.2f", score)
		-- Add virtual text with score
		vim.api.nvim_buf_set_extmark(0, M.ns_hl, row, 0, {
			id = id,
			virt_text = { { score_text, "Comment" } },
			virt_text_pos = "eol",
		})
	end
end

return M
