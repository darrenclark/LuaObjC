//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc.h"
#import "luaobjc_object.h"
#import "luaobjc_benchmark.h"
#import "luaobjc_sel_cache.h"
#import "luaobjc_selector.h"
#import "luaobjc_struct.h"
#import "luaobjc_luaclass.h"

#define LUA_NAMESPACE	"objc"

const char *luaobjc_namespace = LUA_NAMESPACE;


void luaobjc_open(lua_State *L) {
	lua_newtable(L);
	lua_setglobal(L, LUA_NAMESPACE);
	lua_getglobal(L, LUA_NAMESPACE);
	
	luaobjc_object_open(L);  // LUAOBJC_REGISTRY_OBJECT_MT, LUAOBJC_REGISTRY_OBJECTS, LUAOBJC_REGISTRY_UNKNOWN_MT
	luaobjc_benchmark_open(L); // LUAOBJC_REGISTRY_BENCHMARKS
	luaobjc_sel_cache_open(L); // LUAOBJC_REGISTRY_SEL_CACHE
	luaobjc_selector_open(L); // LUAOBJC_REGISTRY_SELECTOR_MT
	luaobjc_struct_open(L); // LUAOBJC_REGISTRY_STRUCT_MT, LUAOBJC_REGISTRY_STRUCT_DEF_MT
	luaobjc_luaclass_open(L); // LUAOBJC_REGISTRY_LUACLASS_MT, LUAOBJC_REGISTRY_LUACLASSES
	
	lua_pop(L, 1); // pop 'objc' global
}

void *luaobjc_checkudata(lua_State *L, int ud, int ref, const char *tname) {
#ifndef LUAOBJC_DISABLE_FAST_LOOKUPS
	
	// Based heavily on luaL_checkudata
	
	void *p = lua_touserdata(L, ud);
	if (p != NULL) {  /* value is a userdata? */
		if (lua_getmetatable(L, ud)) {  /* does it have a metatable? */
			LUAOBJC_GET_REGISTRY_TABLE(L, ref, tname);  /* get correct metatable */
			if (!lua_rawequal(L, -1, -2))  /* not the same? */
				p = NULL;  /* value is a userdata with wrong metatable */
			lua_pop(L, 2);  /* remove both metatables */
		}
	}
	
	if (p == NULL) {
		char err_msg[256];
		snprintf(err_msg, sizeof(err_msg), "%s expected, got %s",
				 tname, luaL_typename(L, ud));
		luaL_argerror(L, ud, err_msg);
	}
	
	return p;
#else
	
	return luaL_checkudata(L, ud, tname);
	
#endif
}