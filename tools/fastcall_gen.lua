local MAX_ARGS = 1
local VOID_RET = 'v'
local TYPES = { "c", "i", "s", "l", "q", "C", "I", "S", "L", "Q", "f", "d", "B", "@", "#" }

local TYPE_TRANSLATION = {}
TYPE_TRANSLATION["@"] = "A"
TYPE_TRANSLATION["#"] = "H"

local function generate_function(ret, current_args)
	ret = TYPE_TRANSLATION[ret] or ret

	local arg_str = ""
	for i, v in ipairs(current_args) do
		v = TYPE_TRANSLATION[v] or v
		arg_str = arg_str .. v
	end

	local func_name = "fastcall_" .. ret .. "_" .. arg_str
	
	local output = "static int " .. func_name .. "(lua_State *L) {"
	output = output .. "\n\t// Do something\n\treturn 0;\n}"

	print(output)
	print("")
end

local function create_functions(ret_type, current_args)
	local depth = #current_args + 1
	if depth > MAX_ARGS then return end

	for i, arg_type in ipairs(TYPES) do
		current_args[depth] = arg_type
		
		generate_function(ret_type, current_args)
		create_functions(ret_type, current_args)
	end

	current_args[depth] = nil
end

generate_function("v", {})
create_functions("v", {})
for i, ret_type in ipairs(TYPES) do
	generate_function(ret_type, {})
	create_functions(ret_type, {})
end

