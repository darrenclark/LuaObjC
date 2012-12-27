//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc_object.h"
#import "luaobjc_sel_cache.h"

#import <objc/message.h>
#import <objc/runtime.h>

#define OBJECT_MT	"luaobjc_object_mt"
#define UNKNOWN_MT	"luaobjc_unknown_mt"


typedef struct method_info {
	id target;
	SEL selector;
	Method method;
} method_info;

static const method_info invalid_method_info = { NULL, NULL, NULL };

// a valid method_info is one with at least target & selector != NULL. If
// method is NULL, it just forces us to use the slower way to invoke the method
static inline BOOL method_info_is_valid(method_info info) {
	return info.target != NULL && info.selector != NULL;
}



static int get_class(lua_State *L);

static int obj_index(lua_State *L);
static int obj_call_method(lua_State *L);

// Utility methods
static method_info lookup_method(lua_State *L, const char *str, size_t len, id target);
static void convert_lua_arg(lua_State *L, int lua_idx, NSInvocation *invocation, 
							int invocation_idx, const char *encoding);
static BOOL is_class(id object);
static const char *arg_encoding_skip_type_qualifiers(const char *encoding);
static const char *arg_encoding_skip_stack_numbers(const char *current_pos);


void luaobjc_object_open(lua_State *L) {
	// 'objc' global is already on the stack! be sure to leave it at the top
	// when this function returns!
	
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
	
	lua_pushstring(L, "__index");
	lua_pushcfunction(L, obj_index);
	lua_settable(L, -3);
	
	lua_pop(L, 1); // pop metatable
	
	
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_UNKNOWN_MT, UNKNOWN_MT);
	lua_pop(L, 1);
	
	
	lua_pushstring(L, "class");
	lua_pushcfunction(L, get_class);
	lua_settable(L, -3);
}

void luaobjc_object_push(lua_State *L, id object) {
	// Cache classes for faster lookup
	static Class ObjCNumber = Nil, ObjCString = Nil;
	if (ObjCNumber == Nil || ObjCString == Nil) {
		ObjCNumber = [NSNumber class];
		ObjCString = [NSString class];
	}
	
	
	if (object == nil) {
		lua_pushnil(L);
	} else if ([object isKindOfClass:ObjCNumber]) {
		lua_pushnumber(L, [object doubleValue]);
	} else if ([object isKindOfClass:ObjCString]) {
		lua_pushstring(L, [object UTF8String]);
	} else {
		lua_pushlightuserdata(L, object);
		LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
		lua_setmetatable(L, -2);
	}
}

void luaobjc_object_push_strict(lua_State *L, id object) {
	if (object == nil) {
		lua_pushnil(L);
	} else {
		lua_pushlightuserdata(L, object);
		LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
		lua_setmetatable(L, -2);
	}
}

id luaobjc_object_check(lua_State *L, int idx) {
	void *object = luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
	luaL_argcheck(L, object != NULL, idx, "Objective C object expected");
	return (id)object;
}

id luaobjc_object_check_or_nil(lua_State *L, int idx) {
	if (lua_isnil(L, idx))
		return nil;
	void *object = luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
	luaL_argcheck(L, object != NULL, idx, "Objective C object (or nil) expected");
	return (id)object;
}


void luaobjc_unknown_push(lua_State *L, const void *bytes, size_t len) {
	size_t *userdata = (size_t *)lua_newuserdata(L, sizeof(size_t) + len);
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_UNKNOWN_MT, UNKNOWN_MT);
	lua_setmetatable(L, -2);
	
	userdata[0] = len;
	memcpy(userdata + 1, bytes, len);
}

luaobjc_unknown luaobjc_unknown_check(lua_State *L, int idx, size_t len) {
	size_t *userdata = luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_UNKNOWN_MT, UNKNOWN_MT);
	luaL_argcheck(L, userdata != NULL, idx, "Objective C 'unknown' expected.");
	
	luaobjc_unknown unknown;
	unknown.length = userdata[0];
	unknown.bytes = (void *)(userdata + 1);
	
	if (len > 0)
		luaL_argcheck(L, len == unknown.length, idx, "Objective C 'unknown' length incorrect.");
	
	return unknown;
}


static int get_class(lua_State *L) {
	const char *class_name = luaL_checkstring(L, 1);
	id class = objc_getClass(class_name);
	luaobjc_object_push_strict(L, class);
	return 1;
}

static int obj_index(lua_State *L) {
	//id object = luaobjc_object_check(L, 1);
	// we know this is gonna be a object, so screw checking it
	id object = lua_touserdata(L, 1);
	
	size_t field_len;
	const char *field_name = luaL_checklstring(L, 2, &field_len);
	
	// check if it is a method on object
	method_info method = lookup_method(L, field_name, field_len, object);
	if (method_info_is_valid(method)) {
		method_info *userdata = (method_info *)lua_newuserdata(L, sizeof(method_info));
		*userdata = method;
		lua_pushcclosure(L, obj_call_method, 1);
		return 1;
	} else {
		NSString *error_msg = [NSString stringWithFormat:@"Unable to resolve method '%s'"
							   @"for object '%@' of type '%@'", field_name, object, [object class]];
		lua_pushstring(L, [error_msg UTF8String]);
		lua_error(L);
	}
	
	return 0; // should never reach here
}

// The whole purpose of the fastcall function is the bypass the NSInvocation song and dance
// Returns -1 when it can't call the function directly, otherwise returns nargs like Lua functions should
static inline int fastcall(lua_State *L, method_info *info, const char *type_encoding) {
	// For now, just test if it matches the format v@:
	const char *current_pos = type_encoding;
	current_pos = arg_encoding_skip_type_qualifiers(current_pos);
	
	if (current_pos[0] != 'v')
		return -1;
	
	current_pos = NSGetSizeAndAlignment(current_pos, NULL, NULL);
	current_pos = arg_encoding_skip_stack_numbers(current_pos);
	
	current_pos = arg_encoding_skip_type_qualifiers(current_pos);
	if (current_pos[0] != '@')
		return -1;
	
	current_pos = NSGetSizeAndAlignment(current_pos, NULL, NULL);
	current_pos = arg_encoding_skip_stack_numbers(current_pos);
	
	if (current_pos[0] != ':')
		return -1;
	
	current_pos = NSGetSizeAndAlignment(current_pos, NULL, NULL);
	current_pos = arg_encoding_skip_stack_numbers(current_pos);
	
	if (current_pos[0] != '\0')
		return -1;
	
	((id(*)(id,SEL))objc_msgSend)(info->target, info->selector);
	return 0;
}

static int obj_call_method(lua_State *L) {
	const int arg_buf_len = 1024;
	char arg_buf[arg_buf_len];
	
	method_info *info = (method_info *)lua_touserdata(L, lua_upvalueindex(1));
	
	id target = info->target;
	SEL sel = info->selector;
	
	const char *type_encoding = NULL;
	if (info->method) {
		type_encoding = method_getTypeEncoding(info->method);
		int fastcall_ret = fastcall(L, info, type_encoding);
		if (fastcall_ret != -1)
			return fastcall_ret;
	}
	
	
	NSMethodSignature *methodSig = [target methodSignatureForSelector:sel];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
	
	[invocation setArgument:&target atIndex:0];
	[invocation setArgument:&sel atIndex:1];
	
	// Handle arguments from Lua
	if (info->method && type_encoding) {
		const char *current_pos = type_encoding;
		int current_arg = -1; // since the return value is at the start
		for (;;) {
			current_pos = arg_encoding_skip_type_qualifiers(current_pos);
			
			// Handle argument
			if (current_arg >= 2) {
				convert_lua_arg(L, current_arg, invocation, current_arg, current_pos);
			}
			
			// Move to next argument
			current_pos = NSGetSizeAndAlignment(current_pos, NULL, NULL);
			current_pos = arg_encoding_skip_stack_numbers(current_pos);
			
			if (current_pos[0] == '\0') // reached end of args
				break;
			
			current_arg++;
		}
	} else {
		NSUInteger arg_count = [methodSig numberOfArguments];
		// we start at 2 because target/selector are args 0/1. luckily, since
		// Lua starts counting at 1 and our first arg is the target, the NSInvocation
		// and Lua arg indexes line up perfectly!
		NSUInteger current_arg = 2;
		for (; current_arg < arg_count; current_arg++) {
			convert_lua_arg(L, current_arg, invocation, current_arg, 
							[methodSig getArgumentTypeAtIndex:current_arg]);
		}
	}
	
	[invocation invoke];
	
	// Read the return type information
	if (info->method) {
		method_getReturnType(info->method, arg_buf, arg_buf_len);
	} else {
		strncpy(arg_buf, [methodSig methodReturnType], arg_buf_len);
	}
	
	const char *return_type = arg_encoding_skip_type_qualifiers(arg_buf);
	
	// Return (possibly) a value to Lua
	switch (return_type[0]) {
		case 'c': {
			char val;
			[invocation getReturnValue:&val];
			// since BOOL is a signed char, we can assume that if it is 0 or 1,
			// we'll just return a boolean.
			if (val == NO || val == YES) {
				lua_pushboolean(L, val);
			} else {
				lua_pushnumber(L, val);
			}
		} break;
		case 'i': {
			int val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 's': {
			short val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'l': {
			long val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'q': {
			long long val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'C': {
			unsigned char val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'I': {
			unsigned int val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'S': {
			unsigned short val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'L': {
			unsigned long val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'Q': {
			unsigned long long val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'f': {
			float val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'd': {
			double val;
			[invocation getReturnValue:&val];
			lua_pushnumber(L, val);
		} break;
		case 'B': {
			_Bool val;
			[invocation getReturnValue:&val];
			lua_pushboolean(L, val);
		} break;
		case 'v': return 0;
		case '*': {
			const char *str;
			[invocation getReturnValue:&str];
			if (str == NULL)
				lua_pushnil(L);
			else
				lua_pushstring(L, str);
		} break;
		case '@': // Both objects and classes are treated they same by us
		case '#': {
			id val;
			[invocation getReturnValue:&val];
			luaobjc_object_push(L, val);
		} break;
		default: {
			NSUInteger unknown_size;
			NSGetSizeAndAlignment(return_type, &unknown_size, NULL);
			
			char buffer[unknown_size];
			[invocation getReturnValue:&buffer];
			
			luaobjc_unknown_push(L, buffer, unknown_size);
		}
	}
	
	return 1;
}

// Gets a method_info from a target object & lua string
// When used in Lua to call a method, a selector will contain _'s for :'s, so
// we need to transform them back into proper objective c selectors
//
// some examples (Lua string -> ObjC selector):
//
// processObject = processObject OR processObject:
// processObject_ = processObject:
// find_inList = find:inList:  (we know to append a ':' here because we have one in the middle)
// find_inList_ = find:inList:
//
// TODO: implement a way to call selectors that don't conform to this (for example,
// selectors with _'s in them)
static method_info lookup_method(lua_State *L, const char *str, size_t len, id target) {
	char transformed[len + 2]; // include 2 extra so we can append the last ':' optionally
	memcpy(transformed, str, len);
	transformed[len] = '\0';
	transformed[len+1] = '\0';
	
	BOOL has_args = NO;
	
	// replace all _'s with :'s
	for (int i = 0; i < len; i++) {
		if (transformed[i] == '_') {
			transformed[i] = ':';
			has_args = YES;
		}
	}
	
	// if we have at least one other ':' and no trailing ':', we need to add the trailing ':'
	if (has_args && transformed[len-1] != ':')
		transformed[len] = ':';
	
	// if target is a class, target_class should be null...
	Class target_class = is_class(target) ? NULL : object_getClass(target);
	
	SEL sel = luaobjc_get_sel(L, transformed);
	SEL fallback_sel = NULL;
	
	Method m = target_class ? class_getInstanceMethod(target_class, sel) : class_getClassMethod(target, sel);
	if (m == NULL && !has_args) {
		// Try again by adding one arg to the end
		transformed[len] = ':';
		fallback_sel = luaobjc_get_sel(L, transformed);
		m = target_class ? class_getInstanceMethod(target_class, fallback_sel) : class_getClassMethod(target, fallback_sel);
	}
	
	if (m == NULL) {
		// We can still see if the method is handled via forwardInvocation:
		BOOL sel_worked = [target respondsToSelector:sel];
		BOOL fallback_worked = NO;
		if (!sel_worked)
			fallback_worked = [target respondsToSelector:fallback_sel];
		
		if (sel_worked || fallback_worked) {
			method_info mi;
			mi.target = target;
			mi.selector = sel_worked ? sel : fallback_sel;
			mi.method = NULL;
			return mi;
		}
		
		return invalid_method_info;
	}
	
	method_info info;
	info.target = target;
	info.selector = fallback_sel == NULL ? sel : fallback_sel;
	info.method = m;
	return info;
}

// converts an arg from from the lua value at lua_idx into the argument at invocation_idx
// in invocation
static void convert_lua_arg(lua_State *L, int lua_idx, NSInvocation *invocation, 
	int invocation_idx, const char *encoding) {
	
	encoding = arg_encoding_skip_type_qualifiers(encoding);
	
	switch (encoding[0]) {
		case 'c': {
			char val;
			if (lua_isboolean(L, lua_idx)) {
				val = lua_toboolean(L, lua_idx);
			} else {
				val = luaL_checknumber(L, lua_idx);
			}
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'i': {
			int val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 's': {
			short val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'l': {
			long val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'q': {
			long long val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'C': {
			unsigned char val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'I': {
			unsigned int val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'S': {
			unsigned short val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'L': {
			unsigned long val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'Q': {
			unsigned long long val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'f': {
			float val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'd': {
			double val = luaL_checknumber(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'B': {
			luaL_argcheck(L, lua_isboolean(L, lua_idx), lua_idx, "`boolean' expected");
			_Bool val = lua_toboolean(L, lua_idx);
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'v': break;
		case '*': {
			BOOL isstring = lua_isstring(L, lua_idx);
			BOOL isnil = lua_isnil(L, lua_idx);
			luaL_argcheck(L, isstring || isnil, lua_idx, "`string' expected");
			
			const char *str = NULL;
			if (isstring)
				str = lua_tostring(L, lua_idx);
			[invocation setArgument:&str atIndex:invocation_idx];
		} break;
		case '@': // Both objects and classes are treated they same by us
		case '#': {
			// Auto convert some Lua values into Objective C values
			if (lua_isnumber(L, lua_idx)) {
				double val = lua_tonumber(L, lua_idx);
				
				NSNumber *number = (NSNumber *)CFNumberCreate(kCFAllocatorDefault,
															  kCFNumberDoubleType, &val);
				[number autorelease];
				
				[invocation setArgument:&number atIndex:invocation_idx];
			} else if (lua_isboolean(L, lua_idx)) {
				int val = lua_toboolean(L, lua_idx);
				
				NSNumber *number = (NSNumber *)CFNumberCreate(kCFAllocatorDefault,
															  kCFNumberIntType, &val);
				[number autorelease];
				
				[invocation setArgument:&number atIndex:invocation_idx];
			} else if (lua_isstring(L, lua_idx)) {
				const char *str = lua_tolstring(L, lua_idx, NULL);
				NSString *objc_str = [NSString stringWithUTF8String:str];
				[invocation setArgument:&objc_str atIndex:invocation_idx];
			} else {
				id val = luaobjc_object_check_or_nil(L, lua_idx);
				[invocation setArgument:&val atIndex:invocation_idx];
			}
		} break;
		default: {
			if (encoding[0] == '^' && lua_isnil(L, lua_idx)) {
				void *val = NULL;
				[invocation setArgument:val atIndex:invocation_idx];
			} else {
				NSUInteger arg_size;
				NSGetSizeAndAlignment(encoding, &arg_size, NULL);
				
				luaobjc_unknown unknown = luaobjc_unknown_check(L, lua_idx, arg_size);
				[invocation setArgument:unknown.bytes atIndex:invocation_idx];
			}
		}
	}
}


// Checks whether object is a Class. This is used for determining whether class_getClassMethod
// or class_getInstanceMethod should be called.
static BOOL is_class(id object) {
	Class cls = object_getClass(object);
	// since the Class of a class is a metaclass, we can just check for that.
	return class_isMetaClass(cls);
}

// Returns a pointer to the character after type qualifiers have been skipped
static const char *arg_encoding_skip_type_qualifiers(const char *encoding) {	
	const char *index = encoding;
	while (*index != '\0') {
		char ch = *index;
		switch (ch) {
		case 'r':
		case 'R':
		case 'o':
		case 'O':
		case 'n':
		case 'N':
		case 'V':
			index++;
			break;
		default:
			return index;
		}
	}
	
	return NULL;
}

// Returns a pointer to the character after the weird method_getTypeEncoding numbers
static const char *arg_encoding_skip_stack_numbers(const char *current_pos) {
	while (current_pos[0] != '\0' && current_pos[0] >= '0' && current_pos[0] <= '9')
		current_pos++;
	return current_pos;
}