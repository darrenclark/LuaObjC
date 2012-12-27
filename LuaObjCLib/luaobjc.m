//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc.h"
#import "luaobjc_object.h"
#import "luaobjc_benchmark.h"
#import "luaobjc_sel_cache.h"

#define LUA_NAMESPACE	"objc"

void luaobjc_open(lua_State *L) {
	lua_newtable(L);
	lua_setglobal(L, LUA_NAMESPACE);
	lua_getglobal(L, LUA_NAMESPACE);
	
	luaobjc_object_open(L);
	luaobjc_benchmark_open(L);
	luaobjc_sel_cache_open(L);
	
	lua_pop(L, 1); // pop 'objc' global
}