//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc_object.h"
#import <objc/runtime.h>

#define METATABLE_NAME "luaobjc_object_mt"

static int get_class(lua_State *L);


void luaobjc_object_open(lua_State *L) {
	// 'objc' global is already on the stack! be sure to leave it at the top
	// when this function returns!
	
	luaL_newmetatable(L, METATABLE_NAME);
	lua_pop(L, 1);
	
	lua_pushstring(L, "class");
	lua_pushcfunction(L, get_class);
	lua_settable(L, -3);
}

void luaobjc_object_push(lua_State *L, id object) {
	if (object == nil) {
		lua_pushnil(L);
	} else {
		lua_pushlightuserdata(L, object);
		luaL_setmetatable(L, METATABLE_NAME);
	}
}



static int get_class(lua_State *L) {
	const char *class_name = luaL_checkstring(L, 1);
	id class = objc_getClass(class_name);
	luaobjc_object_push(L, class);
	return 1;
}