//  Created by Darren Clark on 12-12-28.


#import "luaobjc_selector.h"
#import "luaobjc_sel_cache.h"

#define SELECTOR_MT "luaobjc_selector"

static int sel(lua_State *L);
static int selector_tostring(lua_State *L);


void luaobjc_selector_open(lua_State *L) {
	// 'objc' global is at the top of the stack. make sure it is still there
	// at the end of this function!
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_SELECTOR_MT, SELECTOR_MT);
	
	lua_pushstring(L, "__tostring");
	lua_pushcfunction(L, selector_tostring);
	lua_settable(L, -3);
	
	lua_pop(L, 1); // pop metatable
	
	lua_pushstring(L, "sel");
	lua_pushcfunction(L, sel);
	lua_settable(L, -3);
}


SEL luaobjc_selector_check(lua_State *L, int idx) {
	return (SEL)luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_SELECTOR_MT, SELECTOR_MT);
}

SEL luaobjc_selector_check_s(lua_State *L, int idx) {
	if (lua_isstring(L, idx)) {
		const char *sel_name = lua_tostring(L, idx);
		return luaobjc_get_sel(L, sel_name);
	} else {
		return luaobjc_selector_check(L, idx);
	}
}

void luaobjc_selector_push(lua_State *L, SEL sel) {
	lua_pushlightuserdata(L, sel);
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_SELECTOR_MT, SELECTOR_MT);
	lua_setmetatable(L, -2);
}

void luaobjc_selector_push_s(lua_State *L, const char *name) {
	SEL sel = luaobjc_get_sel(L, name);
	luaobjc_selector_push(L, sel);
}


static int sel(lua_State *L) {
	const char *sel_name = luaL_checkstring(L, 1);
	luaobjc_selector_push_s(L, sel_name);
	return 1;
}

static int selector_tostring(lua_State *L) {
	// since SEL's point to their name, we can easily use that to get our name
	lua_pushstring(L, (const char *)lua_touserdata(L, 1));
	return 1;
}