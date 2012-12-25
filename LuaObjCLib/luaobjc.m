//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc.h"
#import "luaobjc_object.h"

#define LUA_NAMESPACE	"objc"

void luaobjc_open(lua_State *L) {
	lua_newtable(L);
	lua_setglobal(L, LUA_NAMESPACE);
	lua_getglobal(L, LUA_NAMESPACE);
	
	luaobjc_object_open(L);
	
	lua_pop(L, 1); // pop 'objc' global
}