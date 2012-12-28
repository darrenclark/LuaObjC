local MAX_ARGS = 2
local VOID_RET = 'v'
local TYPES = { "c", "i", "s", "l", "q", "C", "I", "S", "L", "Q", "f", "d", "B", "@", "#" }

local TYPE_TRANSLATION = {}
TYPE_TRANSLATION["@"] = "A"
TYPE_TRANSLATION["#"] = "H"

local TYPE_CTYPES = {}
TYPE_CTYPES["c"] = "char"
TYPE_CTYPES["i"] = "int"
TYPE_CTYPES["s"] = "short"
TYPE_CTYPES["l"] = "long"
TYPE_CTYPES["q"] = "long long"
TYPE_CTYPES["C"] = "unsigned char"
TYPE_CTYPES["I"] = "unsigned int"
TYPE_CTYPES["S"] = "unsigned short"
TYPE_CTYPES["L"] = "unsigned long"
TYPE_CTYPES["Q"] = "unsigned long long"
TYPE_CTYPES["f"] = "float"
TYPE_CTYPES["d"] = "double"
TYPE_CTYPES["B"] = "_Bool"
TYPE_CTYPES["@"] = "id"
TYPE_CTYPES["#"] = "id"


local lua_to_c_char_base = [[
	char arg_ARG_INDEX_;
	if (lua_isboolean(L, _ARG_INDEX_)) {
		arg_ARG_INDEX_ = lua_toboolean(L, _ARG_INDEX_);
	} else {
		arg_ARG_INDEX_ = luaL_checknumber(L, _ARG_INDEX_);
	}
]]
local function lua_to_c_char(arg_index, arg_type)
	return lua_to_c_char_base:gsub("_ARG_INDEX_", tostring(arg_index))
end

local function lua_to_c_numbers(arg_index, arg_type)
	return "\t" .. TYPE_CTYPES[arg_type] .. " arg" .. arg_index .. " = (" .. TYPE_CTYPES[arg_type] .. ")luaL_checknumber(L, " .. arg_index .. ");"
end

local lua_to_c_bool_base = [[
	luaL_argcheck(L, lua_isboolean(L, _ARG_INDEX_), _ARG_INDEX_, "`boolean' expected");
	_Bool arg_ARG_INDEX_ = lua_toboolean(L, _ARG_INDEX_);
]]
local function lua_to_c_bool(arg_index, arg_type)
	return lua_to_c_bool_base:gsub("_ARG_INDEX_", tostring(arg_index))
end

local lua_to_c_objects_base = [[
	id arg_ARG_INDEX_ = nil;
	if (lua_isnumber(L, _ARG_INDEX_)) {
		double val = lua_tonumber(L, _ARG_INDEX_);
		arg_ARG_INDEX_ = (NSNumber *)CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &val);
		[arg_ARG_INDEX_ autorelease];
	} else if (lua_isboolean(L, _ARG_INDEX_)) {
		int val = lua_toboolean(L, _ARG_INDEX_);
		arg_ARG_INDEX_ = (NSNumber *)CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &val);
		[arg_ARG_INDEX_ autorelease];
	} else if (lua_isstring(L, _ARG_INDEX_)) {
		const char *str = lua_tolstring(L, _ARG_INDEX_, NULL);
		arg_ARG_INDEX_ = [NSString stringWithUTF8String:str];
	} else {
		arg_ARG_INDEX_ = luaobjc_object_check_or_nil(L, _ARG_INDEX_);
	}
]]
local function lua_to_c_objects(arg_index, arg_type)
	return lua_to_c_objects_base:gsub("_ARG_INDEX_", tostring(arg_index))
end

local TYPE_LUA_TO_C = {}
TYPE_LUA_TO_C["c"] = lua_to_c_char
TYPE_LUA_TO_C["i"] = lua_to_c_numbers
TYPE_LUA_TO_C["s"] = lua_to_c_numbers
TYPE_LUA_TO_C["l"] = lua_to_c_numbers
TYPE_LUA_TO_C["q"] = lua_to_c_numbers
TYPE_LUA_TO_C["C"] = lua_to_c_numbers
TYPE_LUA_TO_C["I"] = lua_to_c_numbers
TYPE_LUA_TO_C["S"] = lua_to_c_numbers
TYPE_LUA_TO_C["L"] = lua_to_c_numbers
TYPE_LUA_TO_C["Q"] = lua_to_c_numbers
TYPE_LUA_TO_C["f"] = lua_to_c_numbers
TYPE_LUA_TO_C["d"] = lua_to_c_numbers
TYPE_LUA_TO_C["B"] = lua_to_c_bool
TYPE_LUA_TO_C["@"] = lua_to_c_objects
TYPE_LUA_TO_C["#"] = lua_to_c_objects


local c_to_lua_char = [[	if (ret == NO || ret == YES) {
		lua_pushboolean(L, ret);
	} else {
		lua_pushnumber(L, ret);
	}
]]
local c_to_lua_number = "\tlua_pushnumber(L, ret);"
local c_to_lua_bool = "\tlua_pushboolean(L, ret);"
local c_to_lua_object = "\tluaobjc_object_push(L, ret);"

local TYPE_C_TO_LUA = {}
TYPE_C_TO_LUA["c"] = c_to_lua_char
TYPE_C_TO_LUA["i"] = c_to_lua_number
TYPE_C_TO_LUA["s"] = c_to_lua_number
TYPE_C_TO_LUA["l"] = c_to_lua_number
TYPE_C_TO_LUA["q"] = c_to_lua_number
TYPE_C_TO_LUA["C"] = c_to_lua_number
TYPE_C_TO_LUA["I"] = c_to_lua_number
TYPE_C_TO_LUA["S"] = c_to_lua_number
TYPE_C_TO_LUA["L"] = c_to_lua_number
TYPE_C_TO_LUA["Q"] = c_to_lua_number
TYPE_C_TO_LUA["f"] = c_to_lua_number
TYPE_C_TO_LUA["d"] = c_to_lua_number
TYPE_C_TO_LUA["B"] = c_to_lua_bool
TYPE_C_TO_LUA["@"] = c_to_lua_object
TYPE_C_TO_LUA["#"] = c_to_lua_object

local function get_func_name(ret, current_args)
	local arg_str = ""
	for i, v in ipairs(current_args) do
		v = TYPE_TRANSLATION[v] or v
		arg_str = arg_str .. v
	end

	return "fc_" .. (TYPE_TRANSLATION[ret] or ret) .. "_" .. arg_str
end

local function msgsend_cast(ret, current_args)
	local ret_type = TYPE_CTYPES[ret] or "void"
	local ret_val = "((" .. ret_type .. "(*)(id, SEL"
	for i, v in ipairs(current_args) do
		ret_val = ret_val .. ", " .. TYPE_CTYPES[v]
	end
	ret_val = ret_val .. "))objc_msgSend)"
	return ret_val
end

local function generate_msgsend(ret, current_args)
	local ret_val = "\t"
	if ret ~= VOID_RET then
		ret_val = "\t" .. TYPE_CTYPES[ret] .. " ret = "
	end
	ret_val = ret_val .. msgsend_cast(ret, current_args) .. "(m_info->target, m_info->selector"

	for i, v in ipairs(current_args) do
		ret_val = ret_val .. ", arg" .. tostring(i + 1)
	end
	ret_val = ret_val .. ");"
	return ret_val
end

local function generate_function(ret, current_args)
	local arg_str = ""
	for i, v in ipairs(current_args) do
		v = TYPE_TRANSLATION[v] or v
		arg_str = arg_str .. v
	end

	local func_name = get_func_name(ret, current_args)
	
	local output = "static int " .. func_name .. "(lua_State *L) {\n"
	output = output .. "\tluaobjc_method_info *m_info = (luaobjc_method_info *)lua_touserdata(L, lua_upvalueindex(1));\n"

	for i, v in ipairs(current_args) do
		-- i + 1 b/c first arg is self
		output = output .. TYPE_LUA_TO_C[v](i + 1, v) .. "\n"
	end

	output = output .. "\n" .. generate_msgsend(ret, current_args) .. "\n"
	if ret == VOID_RET then
		output = output .. "\treturn 0;\n}"
	else
		output = output .. TYPE_C_TO_LUA[ret] .. "\n"
		output = output .. "\treturn 1;\n}"
	end

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

print("// Autogenerated via tools/fastcall_gen.lua")
print("")
print("#import \"luaobjc_fastcall.h\"")
print("#import \"luaobjc_object.h\"")
print("")
print("")

generate_function("v", {})
create_functions("v", {})
for i, ret_type in ipairs(TYPES) do
	generate_function(ret_type, {})
	create_functions(ret_type, {})
end

local function generate_arg_jump_table(ret, current_args)
	local indent = "\t"
	for i = 0, #current_args do indent = indent .. "\t" end

	print(indent .. "switch (args[" .. tostring(#current_args) .. "]) {")

	for i, arg_type in ipairs(TYPES) do
		if #current_args + 1 < MAX_ARGS then
			print(indent .. "case '" .. arg_type .. "':")
			current_args[#current_args + 1] = arg_type
			generate_arg_jump_table(ret, current_args)
			current_args[#current_args] = nil
		else
			current_args[#current_args + 1] = arg_type
			print(indent .. "case '" .. arg_type .. "': return " .. get_func_name(ret, current_args) .. ";")
			current_args[#current_args] = nil
		end
	end

	print(indent .. "case '\\0': return " .. get_func_name(ret, current_args) .. ";")
	print(indent .. "default: return NULL;")
	print(indent .. "}")
end

local function generate_ret_jump_table()
	local indent = "\t"
	print(indent .. "switch (ret) {")
	
	print(indent .. "case 'v':")
	generate_arg_jump_table("v", {})
	for i, arg_type in ipairs(TYPES) do
		print(indent .. "case '" .. arg_type .. "':")
		generate_arg_jump_table(arg_type, {})
	end
	print(indent .. "default: return NULL;")
	print(indent .. "}")
end

print("int luaobjc_fastcall_max_args = " .. tostring(MAX_ARGS) .. ";")
print("")
print("lua_CFunction luaobjc_fastcall_get(char ret, const char *args) {")
generate_ret_jump_table()
print("}")
