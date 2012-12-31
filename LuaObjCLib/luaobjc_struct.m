//  Created by Darren Clark on 12-12-29.


#import "luaobjc_struct.h"

// A struct definition is a table with 4 key/value pairs:
//	STRUCT_NAME_INDEX -> name of struct
//	STRUCT_DEF_INDEX -> struct_def userdata
//	FIELD_NAMES_INDEX -> table mapping field names to indices in struct_def->fields (0 based)
//	FIELD_ORDER_INDEX -> table mapping order of fields to names (1 based, reference to list of field names passed in)
// and various metamethods to allow creating structs


#define STRUCT_MT "struct_mt"
#define STRUCT_DEF_MT "struct_def_mt"

#define STRUCT_TABLE_NAME "struct"

#define STRUCT_NAME_INDEX	1
#define STRUCT_DEF_INDEX	2
#define FIELD_NAMES_INDEX	3
#define FIELD_ORDER_INDEX	4


typedef struct field_info {
	char type;
	size_t offset;
} field_info;

typedef struct struct_def {
	size_t size;
	size_t field_count;
	field_info fields[0];
} struct_def;


static int struct_index(lua_State *L);
static int struct_newindex(lua_State *L);

static int struct_def_call(lua_State *L);
static int struct_def_tostring(lua_State *L);

static int define_struct(lua_State *L);


// pushes objc.struct
static void push_global_struct(lua_State *L);
// Attempts to parse the layout string.
// On success, pushes a structure definition table (see top of file). On failure, raises an error
static struct_def *parse_struct(lua_State *L, int struct_name_index, int layout_index, int names_index);
// returns size of type represented by 'type', else returns 0 on invalid 'type'
static size_t check_type(char type);

// gets a struct_def from a struct instance, otherwise returns NULL
static struct_def *get_struct_def(lua_State *L, int idx);
// get struct type name
static const char *get_struct_name(lua_State *L, int idx);
// returns the struct_def.fields index for field name @ field_idx in struct @ struct_idx
// on failure, returns -1
static int get_struct_field_index(lua_State *L, int struct_idx, int field_idx);
// sets a field on a struct, returns whether it was successful or not
static BOOL set_struct_field(lua_State *L, int struct_idx, int field, int value_idx);
// pushes the value of a field in struct @ struct_idx
// on success: returns YES and pushes value on stack
// on failure: returns NO and NO values are pushed
static BOOL push_struct_field_value(lua_State *L, int struct_idx, int field);

// pushes a new struct instance. may fail if struct type hasn't been registered
// on success, pushes the new userdata and returns YES
// on failure, doesn't push anything and returns NO
static BOOL push_new_struct(lua_State *L, const char *name);
static BOOL push_new_struct_idx(lua_State *L, int name_idx);


void luaobjc_struct_open(lua_State *L) {
	// Remember 'objc' is at the top of the stack!
	
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_STRUCT_MT, STRUCT_MT);
	LUAOBJC_ADD_METHOD("__index", struct_index);
	LUAOBJC_ADD_METHOD("__newindex", struct_newindex);
	lua_pop(L, 1); // pop metatable
	
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_STRUCT_DEF_MT, STRUCT_DEF_MT);
	LUAOBJC_ADD_METHOD("__tostring", struct_def_tostring);
	LUAOBJC_ADD_METHOD("__call", struct_def_call);
	lua_pop(L, 1);
	
	lua_pushstring(L, STRUCT_TABLE_NAME);
	lua_newtable(L);
	
	LUAOBJC_ADD_METHOD("def", define_struct)
	
	lua_settable(L, -3);
}

void *luaobjc_struct_check(lua_State *L, int idx, const char *struct_name) {
	void *userdata = luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_STRUCT_MT, STRUCT_MT);
	if (userdata != NULL) {
		// validate structs are both named the same
		const char *ud_name = get_struct_name(L, idx);
		if (strcmp(struct_name, ud_name) != 0)
			userdata = NULL;
	}
	
	if (userdata == NULL) {
		const char *fmt = "struct of type '%s' expected";
		
		size_t final_len = strlen(fmt) + strlen(struct_name) - 1;
		char err_msg[final_len];
		
		sprintf(err_msg, fmt, struct_name);
		err_msg[final_len-1] = '\0';
		
		luaL_argerror(L, idx, err_msg);
	}
	return userdata;
}

static int struct_index(lua_State *L) {
	luaL_checkstring(L, 2);
	
	int field = get_struct_field_index(L, 1, 2);
	if (field == -1) {
		lua_pushfstring(L, "field '%s' not found in struct '%s'", lua_tostring(L, 2), get_struct_name(L, 1));
		lua_error(L);
	}
	
	if (!push_struct_field_value(L, 1, field)) {
		lua_pushfstring(L, "unknown error retrieving '%s' from struct '%s'", lua_tostring(L, 2), get_struct_name(L, 1));
		lua_error(L);
	}
	
	return 1;
}

static int struct_newindex(lua_State *L) {
	luaL_checkstring(L, 2);
	
	int field = get_struct_field_index(L, 1, 2);
	if (field == -1) {
		lua_pushfstring(L, "field '%s' not found in struct '%s'", lua_tostring(L, 2), get_struct_name(L, 1));
		lua_error(L);
	}
	
	BOOL success = set_struct_field(L, 1, field, 3);
	if (!success) {
		lua_pushfstring(L, "invalid type '%s' when setting field '%s' on struct '%s'",
						lua_typename(L, lua_type(L, 3)), lua_tostring(L, 2), get_struct_name(L, 1));
		lua_error(L);
	}
	
	return 0;
}

static int struct_def_call(lua_State *L) {
	int num_args = lua_gettop(L);
	
	lua_rawgeti(L, 1, STRUCT_NAME_INDEX); // ..., name
	push_new_struct_idx(L, -1); // ..., name, struct
	lua_replace(L, -2); // ..., struct
	
	struct_def *def = get_struct_def(L, -1);
	int num_values = num_args - 1;
	
	for (int i = 0; i < MIN(num_values, def->field_count); i++) {
		BOOL success = set_struct_field(L, -1, i, i + 2); // + 2 because struct definition is arg 1
		if (!success) {
			lua_pushfstring(L, "invalid type '%s' when creating struct '%s'",
							lua_typename(L, lua_type(L, i + 2)), get_struct_name(L, -1));
			lua_error(L);
		}
	}
	
	return 1;
}

static int struct_def_tostring(lua_State *L) {
	lua_rawgeti(L, 1, STRUCT_DEF_INDEX); // arg, struct_def
	struct_def *def = (struct_def *)lua_touserdata(L, -1);
	lua_pop(L, 1); // arg
	
	int strings = 0; // counts how many strings to concat
	lua_rawgeti(L, 1, STRUCT_NAME_INDEX); // arg, name
	strings++;
	
	lua_pushfstring(L, " (%d bytes) { ", def->size); // arg, name, bytes
	strings++;
	
	for (int i = 0; i < def->field_count; i++) {
		lua_rawgeti(L, 1, FIELD_ORDER_INDEX); // arg, name, bytes, ..., field order
		lua_rawgeti(L, -1, i+1); // arg, name, bytes, ..., field order, field name
		lua_replace(L, -2); // arg, name, bytes, ..., field name
		strings++;
		
		if (i != def->field_count - 1)
			lua_pushfstring(L, "(%c), ", def->fields[i].type);
		else
			lua_pushfstring(L, "(%c) ", def->fields[i].type);
		strings++;
		
		// arg, name, bytes, ..., field name, field info
		// field name, field info move into '...' for next iteration...
		// arg, name, bytes, ...
	}
	
	lua_pushstring(L, "}"); // arg, name, bytes, "}"
	strings++;
	
	lua_concat(L, strings); // arg, return value
	return 1;
}

static int define_struct(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	luaL_checkstring(L, 2);
	luaL_checktype(L, 3, LUA_TTABLE);
	
	push_global_struct(L); // args..., objc.struct
	lua_pushstring(L, name); // args..., objc.struct, name
	lua_rawget(L, -2); // args..., objc.struct, existing
	
	// already defined?
	if (!lua_isnil(L, -1)) {
		lua_pop(L, 2); // args...
		lua_pushfstring(L, "struct '%s' already exists", name); // args..., error
		lua_error(L);
	}
	
	lua_pop(L, 1); // args..., objc.struct
	
	parse_struct(L, 1, 2, 3); // args..., objc.struct, def
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_STRUCT_DEF_MT, STRUCT_DEF_MT); // args..., objc.struct, def, struct_def_mt
	lua_setmetatable(L, -2); // args..., objc.struct, def
	
	lua_pushstring(L, name); // args..., objc.struct, def, name
	lua_pushvalue(L, -2); // args..., objc.struct, def, name, def
	lua_rawset(L, -4); // args..., objc.struct, def
	
	lua_replace(L, -2); // args..., def
	
	return 1;
}


// Utility

static void push_global_struct(lua_State *L) {
	lua_getglobal(L, luaobjc_namespace);
	lua_getfield(L, -1, STRUCT_TABLE_NAME);
	lua_replace(L, -2);
}

static struct_def *parse_struct(lua_State *L, int struct_name_index, int layout_index, int names_index) {
	// fields in a struct are aligned to a the size of the type, so we have to be
	// very careful how we layout the struct. for example:
	//
	// struct {
	//	char a;
	//	short b;
	//	int c;
	//	char d;
	//	char e;
	// }
	//
	// becomes this in memory (-'s are blank bytes)
	// a-bb cccc de--
	
	size_t layout_len;
	const char *layout = lua_tolstring(L, layout_index, &layout_len);
	
	if (layout_len == 0) {
		lua_pushstring(L, "struct layout can't be 0 length");
		lua_error(L);
	}
	
	if (lua_objlen(L, names_index) != layout_len) {
		lua_pushstring(L, "struct layout count doesn't match field names count");
		lua_error(L);
	}
	
	lua_newtable(L); // structure definition table - ..., table
	struct_def *def = (struct_def *)lua_newuserdata(L, sizeof(struct_def) + sizeof(field_info) * layout_len); // ..., table, struct_def
	lua_newtable(L); // table mapping field names to indices - ..., table, struct_def, names_table
	
	size_t current_offset = 0;
	
	for (int i = 0; i < layout_len; i++) {
		// Get/check type
		char type = layout[i];
		size_t size = check_type(type);
		
		if (size == 0) {
			lua_pop(L, 3); // ...
			lua_pushfstring(L, "invalid struct layout character: %c", type);
			lua_error(L);
		}
		
		// Set names_table[name] = i
		lua_pushinteger(L, i + 1); // since lua starts counting at 1 - ..., table, struct_def, names_table, i + 1
		lua_gettable(L, names_index); // ..., table, struct_def, names_table, field_name
		
		if (lua_type(L, -1) == LUA_TSTRING) {
			lua_pushinteger(L, i); // ..., table, struct_def, names_table, field_name, i
			lua_rawset(L, -3); // ..., table, struct_def, names_table
		} else {
			lua_pop(L, 4); // ...
			lua_pushfstring(L, "struct field name not found for field '%d'. note: must be a string", i);
			lua_error(L);
		}
		
		// adjust alignment until aligned correctly
		while (current_offset % size != 0)
			current_offset++;
		
		def->fields[i].type = type;
		def->fields[i].offset = current_offset;
		
		current_offset += size;
	}
	
	// make sure we are aligned to a 4 byte boundary
	while (current_offset % 4 != 0)
		current_offset++;
	
	def->field_count = layout_len;
	def->size = current_offset;
	
	// attach name, struct_def and names_table to table
	// ..., table, struct_def, names_table
	lua_pushvalue(L, struct_name_index); // ..., table, struct_def, names_table, name
	lua_rawseti(L, -4, STRUCT_NAME_INDEX); // ..., table, struct_def, names_table
	
	lua_pushvalue(L, -2); // ..., table, struct_def, names_table, struct_def
	lua_rawseti(L, -4, STRUCT_DEF_INDEX); // ..., table, struct_def, names_table
	
	lua_rawseti(L, -3, FIELD_NAMES_INDEX); // ..., table, struct_def
	lua_pop(L, 1); // ..., table
	
	lua_pushvalue(L, names_index); // ..., table, names list table
	lua_rawseti(L, -2, FIELD_ORDER_INDEX);
	// ..., table
	
	return def;
}

// returns 0 if invalid type, else returns size
static size_t check_type(char type) {
	switch (type) {
		case 'c': return sizeof(char);
		case 'i': return sizeof(int);
		case 's': return sizeof(short);
		case 'l': return sizeof(long);
		case 'q': return sizeof(long long);
		case 'C': return sizeof(unsigned char);
		case 'I': return sizeof(unsigned int);
		case 'S': return sizeof(unsigned short);
		case 'L': return sizeof(unsigned long);
		case 'Q': return sizeof(unsigned long long);
		case 'f': return sizeof(float);
		case 'd': return sizeof(double);
		default: return 0;
	}
}

static struct_def *get_struct_def(lua_State *L, int idx) {
	lua_getfenv(L, idx); // ..., fenv
	lua_rawgeti(L, -1, STRUCT_DEF_INDEX); // ..., fenv, struct_def
	
	struct_def *def = (struct_def *)lua_touserdata(L, -1);
	lua_pop(L, 2); // ...
	return def;
}

static const char *get_struct_name(lua_State *L, int idx) {
	lua_getfenv(L, idx); // ..., fenv
	lua_rawgeti(L, -1, STRUCT_NAME_INDEX); // ..., fenv, name
	
	const char *name = lua_tostring(L, -1);
	lua_pop(L, 2); // ...
	return name;
}

static int get_struct_field_index(lua_State *L, int struct_idx, int field_idx) {
	lua_getfenv(L, struct_idx); // ..., fenv
	lua_rawgeti(L, -1, FIELD_NAMES_INDEX); // ..., fenv, field names
	
	lua_pushvalue(L, field_idx); // ..., fenv, field names, field name
	lua_rawget(L, -2); // ..., fenv, field names, result
	
	int result = -1;
	if (lua_isnumber(L, -1)) {
		result = lua_tonumber(L, -1);
	}
	
	lua_pop(L, 3); // ...
	return result;
}

static BOOL set_struct_field(lua_State *L, int struct_idx, int field, int value_idx) {
	struct_def *def = get_struct_def(L, struct_idx);
	if (field >= def->field_count)
		return NO;
	
	field_info field_info = def->fields[field];
	// validate Lua type is valid with C type
	if (field_info.type == 'c') {
		if (!lua_isboolean(L, value_idx) && !lua_isnumber(L, value_idx))
			return NO;
	} else {
		if (!lua_isnumber(L, value_idx))
			return NO;
	}
	
	// get the address where we need to write the new value
	void *struct_ptr = lua_touserdata(L, struct_idx);
	void *ptr = (void *)(((char *)struct_ptr) + field_info.offset);
	
	// write our value
	switch (field_info.type) {
		case 'c': {
			char val;
			if (lua_isboolean(L, value_idx)) {
				val = lua_toboolean(L, value_idx);
			} else {
				val = (char)lua_tonumber(L, value_idx);
			}
			*(char *)ptr = val;
		} break;
		case 'i': *(int *)ptr = (int)lua_tonumber(L, value_idx); break;
		case 's': *(short *)ptr = (short)lua_tonumber(L, value_idx); break;
		case 'l': *(long *)ptr = (long)lua_tonumber(L, value_idx); break;
		case 'q': *(long long *)ptr = (long long)lua_tonumber(L, value_idx); break;
		case 'C': *(unsigned char *)ptr = (unsigned char)lua_tonumber(L, value_idx); break;
		case 'I': *(unsigned int *)ptr = (unsigned int)lua_tonumber(L, value_idx); break;
		case 'S': *(unsigned short *)ptr = (unsigned short)lua_tonumber(L, value_idx); break;
		case 'L': *(unsigned long *)ptr = (unsigned long)lua_tonumber(L, value_idx); break;
		case 'Q': *(unsigned long long *)ptr = (unsigned long long)lua_tonumber(L, value_idx); break;
		case 'f': *(float *)ptr = (float)lua_tonumber(L, value_idx); break;
		case 'd': *(double *)ptr = (double)lua_tonumber(L, value_idx); break;
		default: return NO;
	}
	
	return YES;
}

static BOOL push_struct_field_value(lua_State *L, int struct_idx, int field) {
	struct_def *def = get_struct_def(L, struct_idx);
	if (field >= def->field_count)
		return NO;
	
	field_info field_info = def->fields[field];
	
	// get the address to read from
	void *struct_ptr = lua_touserdata(L, struct_idx);
	void *ptr = (void *)(((char *)struct_ptr) + field_info.offset);
	
	// read the value at ptr
	switch (field_info.type) {
		case 'c': {
			char val = *(char *)ptr;
			if (val == NO || val == YES)
				lua_pushboolean(L, val);
			else
				lua_pushnumber(L, val);
		} break;
		case 'i': lua_pushnumber(L, *(int *)ptr); break;
		case 's': lua_pushnumber(L, *(short *)ptr); break;
		case 'l': lua_pushnumber(L, *(long *)ptr); break;
		case 'q': lua_pushnumber(L, *(long long *)ptr); break;
		case 'C': lua_pushnumber(L, *(unsigned char *)ptr); break;
		case 'I': lua_pushnumber(L, *(unsigned int *)ptr); break;
		case 'S': lua_pushnumber(L, *(unsigned short *)ptr); break;
		case 'L': lua_pushnumber(L, *(unsigned long *)ptr); break;
		case 'Q': lua_pushnumber(L, *(unsigned long long *)ptr); break;
		case 'f': lua_pushnumber(L, *(float *)ptr); break;
		case 'd': lua_pushnumber(L, *(double *)ptr); break;
		default: return NO;
	}
	
	return YES;
}

static BOOL push_new_struct(lua_State *L, const char *name) {
	lua_pushstring(L, name);
	return push_new_struct_idx(L, -1);
}

static BOOL push_new_struct_idx(lua_State *L, int name_idx) {
	// change to positive idx if negative (adding 1 because the top is -1)
	if (name_idx < 0) name_idx = lua_gettop(L) + name_idx + 1;
	
	push_global_struct(L); // ..., objc.struct
	lua_pushvalue(L, name_idx); // ..., objc.struct, name
	lua_rawget(L, -2); // ..., objc.struct, struct definition
	
	if (lua_isnil(L, -1)) {
		lua_pop(L, 2); // ...
		return NO;
	}
	
	lua_replace(L, -2); // ..., struct definition
	
	lua_rawgeti(L, -1, STRUCT_DEF_INDEX); // ..., struct definition, struct_def
	struct_def *def = (struct_def *)lua_touserdata(L, -1);
	lua_pop(L, 1); // ..., struct definition
	
	lua_newuserdata(L, def->size); // ..., struct definition, struct
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_STRUCT_MT, STRUCT_MT); // ..., struct definition, struct, mt
	lua_setmetatable(L, -2); // ..., struct definition, struct
	
	lua_pushvalue(L, -2); // ..., struct definition, struct, struct definition
	lua_setfenv(L, -2); // ..., struct definition, struct
	
	lua_replace(L, -2); // ..., struct
	
	return YES;
}
