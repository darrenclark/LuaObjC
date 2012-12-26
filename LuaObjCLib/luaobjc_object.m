//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc_object.h"
#import <objc/runtime.h>

#define METATABLE_NAME "luaobjc_object_mt"


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
static method_info lookup_method(const char *str, size_t len, id target);
static BOOL is_class(id object);
static const char *arg_encoding_skip_type_qualifiers(const char *encoding);


void luaobjc_object_open(lua_State *L) {
	// 'objc' global is already on the stack! be sure to leave it at the top
	// when this function returns!
	
	luaL_newmetatable(L, METATABLE_NAME);
	
	lua_pushstring(L, "__index");
	lua_pushcfunction(L, obj_index);
	lua_settable(L, -3);
	
	lua_pop(L, 1); // pop metatable
	
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
		luaL_setmetatable(L, METATABLE_NAME);
	}
}

void luaobjc_object_push_strict(lua_State *L, id object) {
	if (object == nil) {
		lua_pushnil(L);
	} else {
		lua_pushlightuserdata(L, object);
		luaL_setmetatable(L, METATABLE_NAME);
	}
}

id luaobjc_object_check(lua_State *L, int idx) {
	void *object = luaL_checkudata(L, idx, METATABLE_NAME);
	luaL_argcheck(L, object != NULL, idx, "Objective C object expected");
	return (id)object;
}

id luaobjc_object_check_or_nil(lua_State *L, int idx) {
	if (lua_isnil(L, idx))
		return nil;
	void *object = luaL_checkudata(L, idx, METATABLE_NAME);
	luaL_argcheck(L, object != NULL, idx, "Objective C object (or nil) expected");
	return (id)object;
}


static int get_class(lua_State *L) {
	const char *class_name = luaL_checkstring(L, 1);
	id class = objc_getClass(class_name);
	luaobjc_object_push_strict(L, class);
	return 1;
}

static int obj_index(lua_State *L) {
	id object = luaobjc_object_check(L, 1);
	
	size_t field_len;
	const char *field_name = luaL_checklstring(L, 2, &field_len);
	
	// check if it is a method on object
	method_info method = lookup_method(field_name, field_len, object);
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

static int obj_call_method(lua_State *L) {
	method_info *info = (method_info *)lua_touserdata(L, lua_upvalueindex(1));
	
	id target = info->target;
	SEL sel = info->selector;
	
	// TODO: read arguments from Lua
	// TODO: use objc_msgSend directly when possible
	
	NSMethodSignature *methodSig = [target methodSignatureForSelector:sel];
	
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
	[invocation setArgument:&target atIndex:0];
	[invocation setArgument:&sel atIndex:1];
	[invocation invoke];
	
	char return_type_buf[256];
	if (info->method) {
		method_getReturnType(info->method, return_type_buf, 256);
	} else {
		strncpy(return_type_buf, [methodSig methodReturnType], 256);
	}
	
	const char *return_type = arg_encoding_skip_type_qualifiers(return_type_buf);
	
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
		case '*': { // NOTE: see default case, as this doesn't seem to actually be used for char*
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
			// if it is a char * string
			if (return_type[0] == '^' && (return_type[1] == 'c' || return_type[1] == 'C')) {
				const char *str;
				[invocation getReturnValue:&str];
				if (str == NULL)
					lua_pushnil(L);
				else
					lua_pushstring(L, str);
				return 1;
			}
			
			// TODO: handle other types like SEL, structs, unions, pointers, etc...
			return 0;
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
static method_info lookup_method(const char *str, size_t len, id target) {
	char transformed[len + 2]; // include 2 extra so we can append the last ':' optionally
	strncpy(transformed, str, len);
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
	
	SEL sel = sel_getUid(transformed);
	SEL fallback_sel = NULL;
	
	Method m = target_class ? class_getInstanceMethod(target_class, sel) : class_getClassMethod(target, sel);
	if (m == NULL && !has_args) {
		// Try again by adding one arg to the end
		transformed[len] = ':';
		fallback_sel = sel_getUid(transformed);
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
