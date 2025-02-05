-- Partition function for QuickSelect
local function partition(arr, left, right, pivotIndex)
	local pivotValue = arr[pivotIndex]
	-- Move pivot to end
	arr[pivotIndex], arr[right] = arr[right], arr[pivotIndex]

	local storeIndex = left
	for i = left, right - 1 do
		if arr[i] > pivotValue then
			arr[storeIndex], arr[i] = arr[i], arr[storeIndex]
			storeIndex = storeIndex + 1
		end
	end

	arr[right], arr[storeIndex] = arr[storeIndex], arr[right]
	return storeIndex
end

-- QuickSelect function to find the kth largest element
local function quickSelect(arr, left, right, k)
	if left == right then
		return arr[left]
	end

	-- Choose random pivot
	local pivotIndex = left + math.floor(math.random() * (right - left + 1))
	pivotIndex = partition(arr, left, right, pivotIndex)

	if k == pivotIndex + 1 then
		return arr[pivotIndex]
	elseif k < pivotIndex + 1 then
		return quickSelect(arr, left, pivotIndex - 1, k)
	else
		return quickSelect(arr, pivotIndex + 1, right, k)
	end
end

-- Main topK function with O(n) complexity
local function topKTest(tbl, k)
	-- Convert input table to array
	local arr = {}
	for _, v in pairs(tbl) do
		table.insert(arr, v)
	end

	-- Handle edge cases
	local n = #arr
	if n == 0 then return {} end
	k = math.min(k, n)

	-- Use QuickSelect to partition around kth element
	math.randomseed(os.time()) -- Initialize random seed
	quickSelect(arr, 1, n, k)

	-- Create result table with top k elements
	local result = {}
	for i = 1, k do
		result[i] = arr[i]
	end

	-- Sort the top k elements (optional, only if ordered output is needed)
	table.sort(result, function(a, b) return a > b end)

	return result
end

local function topKTable(data, k)
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

	-- return topKKeys
	return topKValues
end


local function get_keys_sorted_by_value(tbl, limit)
	local keys = {}
	local total = 0
	for key in pairs(tbl) do
		table.insert(keys, key)
		total = total + 1
	end

	table.sort(keys, function(a, b)
		return tbl[a] > tbl[b]
	end)


	if limit > total then
		limit = total
	end
	local values_result = {}
	-- local keys_result = {}
	for i = 1, limit do
		values_result[i] = tbl[keys[i]]
	end

	return values_result
	-- return keys_result
end

-- Test helper function
local function printTable(t)
	local result = {}
	for i, v in ipairs(t) do
		table.insert(result, tostring(v))
	end
	return table.concat(result, ", ")
end

-- Test cases
local tests = {
	{
		name = "Numeric keys test",
		input = { [1] = 5, [2] = 2, [3] = 8, [4] = 1, [5] = 9, [6] = 3 },
		k = 3,
		expected = { 5, 3, 1 } -- keys of values 9, 8, 5
	},
	{
		name = "Large dataset test",
		input = {},
		k = 10,
		-- Will be filled with 10000 entries
	}
}

-- Fill large dataset
for i = 1, 100000 do
	local randKey = math.random(1, 100000)
	tests[2].input[randKey] = math.random(1, 100000000)
end


local function testFunction(fn)
	-- Run tests and measure performance
	print("Running tests...\n")

	for _, test in ipairs(tests) do
		print("Test:", test.name)

		-- Measure execution time
		local start_time = os.clock()
		local result = fn(test.input, test.k)
		local end_time = os.clock()
		local execution_time = end_time - start_time

		-- Print results
		print(#test.input)
		-- print("Input size:", #test.input > 0 and #test.input or table.maxn(test.input))
		print("K:", test.k)
		print("Result:", printTable(result))
		if test.expected then
			local success = true
			for i = 1, test.k do
				local found = false
				for j = 1, test.k do
					if result[i] == test.expected[j] then
						found = true
						break
					end
				end
				if not found then
					success = false
					break
				end
			end
			print("Test passed:", success)
		end
		print(string.format("Execution time: %.6f seconds", execution_time))
		print()
	end
end



testFunction(get_keys_sorted_by_value)
testFunction(topKTable)
testFunction(topKTest)
