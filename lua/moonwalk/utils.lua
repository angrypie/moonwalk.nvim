local ts_utils = require("nvim-treesitter.ts_utils")

local M = {}

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

---Return top k keys of the table. It is fast for small k number.
---@param data table<integer,number>
---@param length integer
---@param k integer
---@return integer[]
function M.topKTable(data, length, k)
	if length < k then
		k = length
	end
	print("topKTable", length, k)
	local topKValues = {}
	local topKKeys = {}

	-- Initialize arrays with default values
	for i = 1, k do
		topKValues[i] = -math.huge
		topKKeys[i] = -1
	end

	-- Iterate through table using pairs instead of ipairs
	for key, value in pairs(data) do
		-- Only process if value is greater than smallest in current top K
		if value > topKValues[k] then
			local j = k
			-- Find correct position to insert while shifting smaller values
			while j > 1 and value > topKValues[j - 1] do
				topKValues[j] = topKValues[j - 1]
				topKKeys[j] = topKKeys[j - 1]
				j = j - 1
			end
			-- Insert new value and key
			topKValues[j] = value
			topKKeys[j] = key
		end
	end

	print("keys", table.concat(topKKeys, ", "))

	return topKKeys
end

return M
