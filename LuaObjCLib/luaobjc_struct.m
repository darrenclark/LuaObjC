//  Created by Darren Clark on 12-12-29.


#import "luaobjc_struct.h"

#define STRUCT_MT "struct_mt"
#define STRUCT_DEF_MT "struct_def_mt"

#define STRUCT_TABLE_NAME "struct"


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
static int struct_call(lua_State *L);

static int struct_def_call(lua_State *L);

static int define_struct(lua_State *L);

static void push_global_struct(lua_State *L);
// Attempts to parse the layout string.
// On success, pushes struct_def userdata AND a table mapping field names -> struct_def.fields indices
static struct_def *parse_struct(lua_State *L, int layout_index, int names_index);
static size_t check_type(char type);


void luaobjc_struct_open(lua_State *L) {
	// Remember 'objc' is at the top of the stack!
	
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_STRUCT_MT, STRUCT_MT);
	lua_pop(L, 1); // pop metatable
	
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_STRUCT_DEF_MT, STRUCT_DEF_MT);
	lua_pop(L, 1);
	
	lua_pushstring(L, STRUCT_TABLE_NAME);
	lua_newtable(L);
	
	LUAOBJC_ADD_METHOD("def", define_struct)
	
	lua_settable(L, -3);
}


static int struct_index(lua_State *L) {
	return 0;
}

static int struct_newindex(lua_State *L) {
	return 0;
}

static int struct_call(lua_State *L) {
	return 0;
}

static int struct_def_call(lua_State *L) {
	return 0;
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
	
	parse_struct(L, 2, 3); // args..., objc.struct, def, names_table
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_STRUCT_DEF_MT, STRUCT_DEF_MT); // args..., objc.struct, def, names_table, struct_def_mt
	lua_setmetatable(L, -3); // args..., objc.struct, def, names_table
	lua_setfenv(L, -2); // args..., objc.struct, def
	
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

static struct_def *parse_struct(lua_State *L, int layout_index, int names_index) {
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
	
	struct_def *def = (struct_def *)lua_newuserdata(L, sizeof(struct_def) + sizeof(field_info) * layout_len); // ..., struct_def
	lua_newtable(L); // table mapping field names to indices - ..., struct_def, names_table
	
	size_t current_offset = 0;
	
	for (int i = 0; i < layout_len; i++) {
		char type = layout[i];
		size_t size = check_type(type);
		
		if (size == 0) {
			lua_pop(L, 2); // ...
			lua_pushfstring(L, "invalid struct layout character: %c", type);
			lua_error(L);
		}
		
		lua_pushinteger(L, i + 1); // since lua starts counting at 1 - ..., struct_def, names_table, i
		lua_gettable(L, names_index); // ..., struct_def, names_table, field_name
		
		if (lua_type(L, -1) == LUA_TSTRING) {
			lua_pushinteger(L, i); // ..., struct_def, names_table, field_name, i
			lua_rawset(L, -3); // ... struct_def, names_table
		} else {
			lua_pop(L, 3); // ...
			lua_pushfstring(L, "struct field name not found for field '%d'. note: must be a string", i);
			lua_error(L);
		}
		
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
