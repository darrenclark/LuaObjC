//  Created by Darren Clark on 12-12-26.


#import "luaobjc_sel_cache.h"

#import <objc/runtime.h>


#define REGISTRY_TABLE "luaobjc_sel_cache"

void luaobjc_sel_cache_open(lua_State *L) {
	// create & add the REGISTRY_TABLE for tracking string -> selector
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_SEL_CACHE, REGISTRY_TABLE);
	lua_pop(L, 1);
}

SEL luaobjc_get_sel(lua_State *L, const char *name) {
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_SEL_CACHE, REGISTRY_TABLE);
	lua_getfield(L, -1, name);
	
	if (lua_isnil(L, -1)) {
		// cache miss - need to get SEL and set it
		SEL sel = sel_getUid(name);
		lua_pushlightuserdata(L, sel);
		lua_setfield(L, -3, name);
		
		lua_pop(L, 2);
		return sel;
	} else {
		// found in cache, lets just return it
		SEL sel = (SEL)lua_touserdata(L, -1);
		lua_pop(L, 2);
		return sel;
	}
}
