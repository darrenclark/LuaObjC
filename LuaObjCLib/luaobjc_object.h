//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc.h"
#import <objc/message.h>
#import <objc/runtime.h>


LUAOBJC_EXTERN void luaobjc_object_open(lua_State *L);

// Pushes an Objective C object and converts NSNumber/NSString to lua numbers/strings
// For converting more complex types like NSArray/NSDictionary, use luobjc_to_lua
LUAOBJC_EXTERN void luaobjc_object_push(lua_State *L, id object);
// Pushes an Objective C object WITHOUT converting to Lua types
LUAOBJC_EXTERN void luaobjc_object_push_strict(lua_State *L, id object);

// Gets an Objective C object without checking and without any conversions
LUAOBJC_EXTERN id luaobjc_object_get(lua_State*L, int idx);
// Checks that an Objective C object lightuserdata is a index 'idx'
LUAOBJC_EXTERN id luaobjc_object_check(lua_State *L, int idx);
LUAOBJC_EXTERN id luaobjc_object_check_or_nil(lua_State *L, int idx);

// Converts a Lua value to an object (including table -> dictionary/array)
LUAOBJC_EXTERN id luaobjc_to_objc(lua_State *L, int idx);
// Converts a Objective C object to Lua and pushes it onto the stack
// This does more conversions than luaobjc_object_push
LUAOBJC_EXTERN void luaobjc_to_lua(lua_State *L, id object);

// For dealing with return values/args unknown to our Lua bindings. (For example,
// unions, bitfields, pointers to unknown data types).
typedef struct luaobjc_unknown {
	size_t length;
	void *bytes;
} luaobjc_unknown;

// Note: _COPIES_ 'len' bytes from 'bytes'
LUAOBJC_EXTERN void luaobjc_unknown_push(lua_State *L, const void *bytes, size_t len);
// pass in 0 for 'len' if you don't want to check the lengths
LUAOBJC_EXTERN luaobjc_unknown luaobjc_unknown_check(lua_State *L, int idx, size_t len);


// Various info cached about a method from the __index metamethod
typedef struct luaobjc_method_info {
	id target;
	SEL selector;
	int num_args;
	const char *sig;
} luaobjc_method_info;

LUAOBJC_EXTERN const char *luaobjc_method_sig_arg(const char *sig, int idx);
