//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc.h"

LUAOBJC_EXTERN void luaobjc_object_open(lua_State *L);

// Pushes an Objective C object and converts various classes to Lua types
LUAOBJC_EXTERN void luaobjc_object_push(lua_State *L, id object);
// Pushes an Objective C object WITHOUT converting to Lua types
LUAOBJC_EXTERN void luaobjc_object_push_strict(lua_State *L, id object);

// Checks that an Objective C object lightuserdata is a index 'idx'
LUAOBJC_EXTERN id luaobjc_object_check(lua_State *L, int idx);
LUAOBJC_EXTERN id luaobjc_object_check_or_nil(lua_State *L, int idx);