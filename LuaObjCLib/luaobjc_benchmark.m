//  Created by Darren Clark on 12-12-26.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.


#import "luaobjc_benchmark.h"


static int benchmark_start(lua_State *L);
static int benchmark_end(lua_State *L);

#define REGISTRY_TABLE "luaobjc_benchmarks"


void luaobjc_benchmark_open(lua_State *L) {
	// 'objc' global is already on the stack here!
	
	LUAOBJC_ADD_METHOD("benchmark_start", benchmark_start)
	LUAOBJC_ADD_METHOD("benchmark_end", benchmark_end);
	
	// create/add the REGISTRY_TABLE for tracking running benchmarks
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_BENCHMARKS, REGISTRY_TABLE);
	lua_pop(L, 1);
}

static int benchmark_start(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_BENCHMARKS, REGISTRY_TABLE);
	
	// Check if we are overwriting an existing benchmark
	lua_getfield(L, -1, name);
	if (!lua_isnil(L, -1)) {
		NSLog(@"WARNING: Overwriting LuaObjC benchmark '%s'", name);
	}
	lua_pop(L, 1);
	
	lua_pushnumber(L, CFAbsoluteTimeGetCurrent());
	lua_setfield(L, -2, name);
	
	lua_pop(L, 1); // pop REGISTRY_TABLE
	
	return 0;
}

static int benchmark_end(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_BENCHMARKS, REGISTRY_TABLE);
	
	// Get start time
	lua_getfield(L, -1, name);
	if (lua_isnil(L, -1)) {
		NSLog(@"WARNING: attempted to end benchmark '%s' that hasn't been started", name);
		lua_pop(L, 2);
		return 0;
	}
	
	double start = lua_tonumber(L, -1);
	double end = CFAbsoluteTimeGetCurrent();
	
	NSLog(@"BENCHMARK '%s' took %f seconds", name, end - start);
	
	lua_pop(L, 1); // pop start time
	lua_pushnil(L);
	lua_setfield(L, -2, name); // remove start time
	
	lua_pop(L, 1); // pop REGISTRY_TABLE
	
	return 0;
}
