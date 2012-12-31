//  Created by Darren Clark on 12-12-30.

#import "luaobjc_luaclass.h"
#import <objc/runtime.h>

#define LUACLASS_MT "luaclass_mt"


typedef struct luaclass {
	Class class;
	BOOL registered;
} luaclass;

static luaclass *check_luaclass(lua_State *L, int idx);

static int new_luaclass(lua_State *L);
static int luaclass_register(lua_State *L);


void luaobjc_luaclass_open(lua_State *L) {
	// 'objc' global is at the top of the stack. make sure it is still there
	// at the end of this function!
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_LUACLASS_MT, LUACLASS_MT);
	// set the __index field of luaclass_mt to luaclass_mt
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	
	LUAOBJC_ADD_METHOD("register", luaclass_register);
	lua_pop(L, 1); // pop metatable
	
	LUAOBJC_ADD_METHOD("new_class", new_luaclass);
}

static luaclass *check_luaclass(lua_State *L, int idx) {
	return (luaclass *)luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_LUACLASS_MT, LUACLASS_MT);
}

static int new_luaclass(lua_State *L) {
	const char *class_name = luaL_checkstring(L, 1);
	const char *super_class_name = luaL_checkstring(L, 2);
	
	// don't try and create an already existing class...
	Class class = objc_getClass(class_name);
	if (class != NULL) {
		lua_pushfstring(L, "class '%s' already exists", class_name);
		lua_error(L);
	}
	
	// make sure the super class exists
	Class super_class = objc_getClass(super_class_name);
	if (super_class == NULL) {
		lua_pushfstring(L, "super class '%s' doesn't exist", super_class_name);
		lua_error(L);
	}
	
	// All good to go, lets create our class!
	luaclass *luaclass = lua_newuserdata(L, sizeof(luaclass));
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_LUACLASS_MT, LUACLASS_MT);
	lua_setmetatable(L, -2);
	
	luaclass->class = objc_allocateClassPair(super_class, class_name, 0);
	luaclass->registered = NO;
	
	return 1;
}

static int luaclass_register(lua_State *L) {
	luaclass *class = check_luaclass(L, 1);
	if (class->registered) {
		lua_pushfstring(L, "class '%s' has already been registered", class_getName(class->class));
		lua_error(L);
	}
	
	objc_registerClassPair(class->class);
	class->registered = YES;
	return 1;
}
