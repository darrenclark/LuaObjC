//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#ifdef __cplusplus
#define LUAOBJC_EXTERN			extern "C"
#define LUAOBJC_EXTERN_BEGIN	extern "C" {
#define LUAOBJC_EXTERN_END		}
#else
#define LUAOBJC_EXTERN
#define LUAOBJC_EXTERN_BEGIN
#define LUAOBJC_EXTERN_END
#endif

LUAOBJC_EXTERN_BEGIN
#import "lua.h"
#import "lualib.h"
#import "lauxlib.h"
LUAOBJC_EXTERN_END


// To speed up often used metatable lookups (luaL_getmetatable), we can use
// lua_ref instead.  However, to prevent having to store the int's on the C side
// (and have to worry about multiple contexts, multithreading, etc...) we can
// predetermine the int values (since lua_ref returns values in sequential order
// like this: 1, 2, 3, ...). This requires luaobjc to be the first external
// Lua lib opened.  If this conflicts with something else, simply define
// LUAOBJC_DISABLE_FAST_LOOKUPS to use strings instead


#ifndef LUAOBJC_DISABLE_FAST_LOOKUPS
// Fast lookups (via a int & lua_getref)

// [+1, 0, ?]
#define LUAOBJC_NEW_REGISTERY_TABLE(L, expected_ref, name)					\
	do {																	\
		(void)name;															\
		lua_newtable(L);													\
		lua_pushvalue(L, -1);												\
		int tmp_ = lua_ref(L, -1);											\
		assert(tmp_ == expected_ref);										\
	} while(0)

// [+1, 0, ?]
#define LUAOBJC_GET_REGISTRY_TABLE(L, ref, name)	(void)name; lua_getref(L, ref)

#else
// Slow lookups (via a string & luaL_getmetatable)

// [+1, 0, ?]
#define LUAOBJC_NEW_REGISTERY_TABLE(L, expected_ref, name)					\
	do {																	\
		lua_newtable(L);													\
		lua_pushvalue(L, -1);												\
		lua_setfield(L, LUA_REGISTRYINDEX, name);							\
	} while(0)


// [+1, 0, ?]
#define LUAOBJC_GET_REGISTRY_TABLE(L, ref, name)	lua_getfield(L, LUA_REGISTRYINDEX, name)

#endif


// Numbers for use with above fast registry lookups
// NOTE: The order is very important! See luaobjc_open!!!
#define LUAOBJC_REGISTRY_OBJECT_MT		1
#define LUAOBJC_REGISTRY_UNKNOWN_MT		2
#define LUAOBJC_REGISTRY_BENCHMARKS		3
#define LUAOBJC_REGISTRY_SEL_CACHE		4
#define LUAOBJC_REGISTRY_SELECTOR_MT	5
#define LUAOBJC_REGISTRY_STRUCT_MT		6
#define LUAOBJC_REGISTRY_STRUCT_DEF_MT	7
#define LUAOBJC_REGISTRY_LUACLASS_MT	8


// Sets t[lua_name] = func_ptr, where t is the table at the top of the stack
#define LUAOBJC_ADD_METHOD(lua_name, func_ptr) \
	lua_pushstring(L, lua_name);											\
	lua_pushcfunction(L, func_ptr);											\
	lua_settable(L, -3);													\

LUAOBJC_EXTERN_BEGIN
extern const char *luaobjc_namespace;
LUAOBJC_EXTERN_END

LUAOBJC_EXTERN void luaobjc_open(lua_State *L);
LUAOBJC_EXTERN void *luaobjc_checkudata(lua_State *L, int ud, int ref, const char *tname);
