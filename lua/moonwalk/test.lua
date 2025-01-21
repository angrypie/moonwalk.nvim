local half_block_char = "▄"


local function merge_strings(x, y)
	print("x " .. x)
	y = y:gsub("%s+", "")
	-- preserve spaces around node
	y = y:gsub(x, half_block_char .. x .. half_block_char)
	-- remove all other spaces
	y = y:gsub(half_block_char, " ")

	return y
end

local x1 = "3"
local x2 = "3;"
local x = "return 3;"
local y = "{return 3;}"
local expected = "{ return 3 ; }"

local first = merge_strings(x1, x2)
local second = merge_strings(first, x)
local third = merge_strings(second, y)

print(first)
print(second)
print(third)
