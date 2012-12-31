//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc_object.h"
#import "luaobjc_args.h"
#import "luaobjc_fastcall.h"
#import "luaobjc_fficall.h"
#import "luaobjc_sel_cache.h"
#import "luaobjc_selector.h"
#import "luaobjc_struct.h"

#define OBJECT_MT	"luaobjc_object_mt"
#define UNKNOWN_MT	"luaobjc_unknown_mt"


typedef struct luaobjc_object {
	id object;
	BOOL strong;
} luaobjc_object;


static int get_class(lua_State *L);
static int to_objc(lua_State *L);
static int to_lua(lua_State *L);
static int strong_ref(lua_State *L);
static int weak_ref(lua_State *L);

static int object_index(lua_State *L);
static int object_newindex(lua_State *L);
static int object_tostring(lua_State *L);
static int object_gc(lua_State *L);
static int generic_call(lua_State *L);

// Utility methods
static luaobjc_method_info *lookup_method_info(lua_State *L, int idx, id target);
static void convert_lua_arg(lua_State *L, int lua_idx, NSInvocation *invocation, 
							int invocation_idx, const char *encoding);
static BOOL is_class(id object);
static const char *arg_encoding_skip_type_qualifiers(const char *encoding);
static const char *arg_encoding_skip_stack_numbers(const char *current_pos);
static luaobjc_method_info *push_method_info(lua_State *L, id target, SEL sel, int num_args, const char *sig, size_t sig_len);


void luaobjc_object_open(lua_State *L) {
	// 'objc' global is already on the stack! be sure to leave it at the top
	// when this function returns!
	
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
	
	LUAOBJC_ADD_METHOD("__index", object_index);
	LUAOBJC_ADD_METHOD("__newindex", object_newindex)
	LUAOBJC_ADD_METHOD("__tostring", object_tostring)
	LUAOBJC_ADD_METHOD("__gc", object_gc)
	
	lua_pop(L, 1); // pop metatable
	
	
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_UNKNOWN_MT, UNKNOWN_MT);
	lua_pop(L, 1);
	
	LUAOBJC_ADD_METHOD("class", get_class)
	LUAOBJC_ADD_METHOD("to_objc", to_objc)
	LUAOBJC_ADD_METHOD("to_lua", to_lua)
	LUAOBJC_ADD_METHOD("strong", strong_ref)
	LUAOBJC_ADD_METHOD("weak", weak_ref)
}

static inline void object_push_internal(lua_State *L, id object) {
	// don't use a light userdata so that we can use lua_setfenv
	luaobjc_object *new_userdata = lua_newuserdata(L, sizeof(luaobjc_object));
	new_userdata->object = object;
	new_userdata->strong = NO;
	
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
	lua_setmetatable(L, -2);
	
	lua_newtable(L);
	lua_setfenv(L, -2);
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
		object_push_internal(L, object);
	}
}

void luaobjc_object_push_strict(lua_State *L, id object) {
	if (object == nil) {
		lua_pushnil(L);
	} else {
		object_push_internal(L, object);
	}
}

id luaobjc_object_get(lua_State*L, int idx) {
	luaobjc_object *userdata = lua_touserdata(L, idx);
	if (userdata != NULL) {
		if (lua_getmetatable(L, idx)) {  /* does it have a metatable? */
			LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);  /* get correct metatable */
			if (!lua_rawequal(L, -1, -2))  /* not the same? */
				userdata = NULL;  /* value is a userdata with wrong metatable */
			lua_pop(L, 2);  /* remove both metatables */
		}
	}
	return userdata != NULL ? userdata->object : nil;
}

id luaobjc_object_check(lua_State *L, int idx) {
	luaobjc_object *userdata = luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
	luaL_argcheck(L, userdata != NULL, idx, "Objective C object expected");
	return userdata->object;
}

id luaobjc_object_check_or_nil(lua_State *L, int idx) {
	if (lua_isnil(L, idx))
		return nil;
	luaobjc_object *userdata = luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_OBJECT_MT, OBJECT_MT);
	luaL_argcheck(L, userdata != NULL, idx, "Objective C object (or nil) expected");
	return userdata->object;
}

id luaobjc_to_objc(lua_State *L, int idx) {
	// TODO: *maybe* handle LUA_TFUNCTION/LUA_TTHREAD -> Objective-C block or NSInvocation???
	
	// convert negative idx to a positive one so it doesn't get goofed up after
	// the stack being changed
	if (idx < -1)
		idx = lua_gettop(L) + (idx + 1);
	
	int type = lua_type(L, idx);
	if (type == LUA_TNIL) {
		return nil;
	} else if (type == LUA_TBOOLEAN) {
		return [NSNumber numberWithBool:lua_toboolean(L, idx)];
	} else if (type == LUA_TNUMBER) {
		return [NSNumber numberWithDouble:lua_tonumber(L, idx)];
	} else if (type == LUA_TSTRING) {
		return [NSString stringWithUTF8String:lua_tostring(L, idx)];
	} else if (type == LUA_TUSERDATA) {
		return luaobjc_object_get(L, idx);
	} else if (type == LUA_TTABLE) {
		// determine if it is a array or dictionary table
		lua_rawgeti(L, idx, 1); // check for t[1]
		BOOL is_dict = lua_isnoneornil(L, -1);
		lua_pop(L, 1);
		
		if (is_dict) {
			NSMutableDictionary *dict = [NSMutableDictionary dictionary];
			lua_pushnil(L); // key
			while (lua_next(L, idx) != 0) {
				// key is at -2, value is at -1
				id key = luaobjc_to_objc(L, -2);
				id value = luaobjc_to_objc(L, -1);
				
				if (key == nil) key = [NSNull null];
				if (value == nil) value = [NSNull null];
				
				[dict setObject:value forKey:key];
				
				lua_pop(L, 1); // pop value
			}
			lua_pop(L, 1); // pop key
			return dict;
		} else {
			NSMutableArray *array = [NSMutableArray array];
			lua_pushnil(L); // key
			while (lua_next(L, idx) != 0) {
				// key is at -2, values is at -1
				id value = luaobjc_to_objc(L, -1);
				if (value == nil) value = [NSNull null];
				
				[array addObject:value];
				
				lua_pop(L, 1);
			}
			lua_pop(L, 1); // pop key
			return array;
		}
	} else {
		return nil;
	}
}

void luaobjc_to_lua(lua_State *L, id object) {
	if (object == nil) {
		lua_pushnil(L);
	} else if ([object isKindOfClass:[NSString class]]) {
		lua_pushstring(L, [object UTF8String]);
	} else if ([object isKindOfClass:[NSNumber class]]) {
		lua_pushnumber(L, [object doubleValue]);
	} else if ([object isKindOfClass:[NSArray class]]) {
		lua_newtable(L);
		int i = 1;
		for (id value in object) {
			luaobjc_to_lua(L, value);
			lua_rawseti(L, -2, i);
			i++;
		}
	} else if ([object isKindOfClass:[NSDictionary class]]) {
		lua_newtable(L);
		for (id key in object) {
			luaobjc_to_lua(L, key);
			luaobjc_to_lua(L, [object objectForKey:key]);
			lua_rawset(L, -3);
		}
	} else {
		lua_pushnil(L);
	}
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

const char *luaobjc_method_sig_arg(const char *sig, int idx) {
	int current_idx = -1;
	while (*sig != '\0') {
		if (*sig == '|') {
			current_idx++;
			if (current_idx == idx) return sig + 1; // return char after |
		}
		sig++;
	}
	return sig;
}

size_t luaobjc_method_sig_arg_len(const char *sig) {
	int count = 0;
	while (*sig != '|' && *sig != '\0') {
		count++;
		sig++;
	}
	return count;
}

BOOL luaobjc_method_sig_struct_name(const char *struct_arg, char *ret) {
	if (*struct_arg != '{') return NO;
	
	// copy the struct name into struct_name
	char *ret_ptr = ret;
	const char *enc_ptr = struct_arg + 1; // skip past the '{'
	while (*enc_ptr != '=' && *enc_ptr != '}' && *enc_ptr != '\0') {
		*ret_ptr = *enc_ptr;
		ret_ptr++;
		enc_ptr++;
	}
	*ret_ptr = '\0';
	return YES;
}

static int get_class(lua_State *L) {
	const char *class_name = luaL_checkstring(L, 1);
	id class = objc_getClass(class_name);
	luaobjc_object_push_strict(L, class);
	return 1;
}

static int to_objc(lua_State *L) {
	id object = luaobjc_to_objc(L, 1);
	luaobjc_object_push(L, object);
	return 1;
}

static int to_lua(lua_State *L) {
	id object = luaobjc_object_check_or_nil(L, 1);
	luaobjc_to_lua(L, object);
	return 1;
}

static int strong_ref(lua_State *L) {
	luaobjc_object_check(L, 1);
	luaobjc_object *object = (luaobjc_object *)lua_touserdata(L, 1);
	if (!object->strong) {
		object->strong = YES;
		[object->object retain];
	}
	
	return 0;
}

static int weak_ref(lua_State *L) {
	luaobjc_object_check(L, 1);
	luaobjc_object *object = (luaobjc_object *)lua_touserdata(L, 1);
	if (object->strong) {
		object->strong = NO;
		[object->object autorelease];
	}
	
	return 0;
}

static int object_index(lua_State *L) {
	// check if it exists in our table
	lua_getfenv(L, 1); // t, k, fenv
	lua_pushvalue(L, 2); // t, k, fenv, k
	lua_rawget(L, -2); // t, k, fenv, v
	
	if (!lua_isnil(L, -1)) {
		lua_replace(L, -2); // t, k, v
		return 1;
	} else {
		lua_pop(L, 1); // t, k, fenv
	}
	
	// we know this is gonna be a object, so no need to check it
	id object = luaobjc_object_get(L, 1);
	
	// check if it is a method on object
	luaobjc_method_info *method_info = lookup_method_info(L, 2, object);
	if (method_info != NULL) {
		// t, k, fenv, method_info
		
		lua_CFunction c_func = luaobjc_fastcall_get(method_info);
		if (c_func != NULL) {
			lua_pushcclosure(L, c_func, 1);
		} else {
			c_func = luaobjc_fficall_get(method_info);
			if (c_func != NULL) {
				lua_pushcclosure(L, c_func, 1);
			} else {
				lua_pushcclosure(L, generic_call, 1);
			}
		}
		// t, k, fenv, cfunc
		
		// cache it in our fenv
		lua_pushvalue(L, 2); // t, k, fenv, cfunc, k
		lua_pushvalue(L, -2); // t, k, fenv, cfunc, k, cfunc
		lua_rawset(L, -4); // t, k, fenv, cfunc
		
		// set our stack so the cfunc is just after the args and return it
		lua_replace(L, -2); // t, k, cfunc
		return 1;
	} else {
		lua_pop(L, 1); // t, k
		lua_pushnil(L); // t, k, nil
		return 1;
	}
}

static int object_newindex(lua_State *L) {
	lua_getfenv(L, 1); // t, k, v, fenv
	
	lua_pushvalue(L, 2); // t, k, v, fenv, k
	lua_pushvalue(L, 3); // t, k, v, fenv, k, v
	lua_rawset(L, -3); // t, k, v, fenv
	
	lua_pop(L, 1); // t, k, v
	return 1;
}

static int object_tostring(lua_State *L) {
	id object = luaobjc_object_get(L, 1);
	NSString *description = [object description];
	if (description)
		lua_pushstring(L, [description UTF8String]);
	else
		lua_pushnil(L);
	return 1;
}

static int object_gc(lua_State *L) {
	luaobjc_object *userdata = (luaobjc_object *)lua_touserdata(L, 1);
	if (userdata->strong) {
		userdata->strong = NO;
		[userdata->object autorelease];
	}
	
	return 0;
}

static int generic_call(lua_State *L) {
	luaobjc_method_info *info = (luaobjc_method_info *)lua_touserdata(L, lua_upvalueindex(1));
	
	id target = info->target;
	SEL sel = info->selector;
		
	NSMethodSignature *methodSig = [target methodSignatureForSelector:sel];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
	
	[invocation setArgument:&target atIndex:0];
	[invocation setArgument:&sel atIndex:1];
	
	// Handle arguments from Lua
	// we start at 2 because target/selector are args 0/1. luckily, since
	// Lua starts counting at 1 and the fact that our first arg is the target,
	// the invocation and Lua arg indexes line up perfectly!
	NSUInteger current_arg = 2;
	for (; current_arg < info->num_args; current_arg++) {
		convert_lua_arg(L, current_arg, invocation, current_arg, luaobjc_method_sig_arg(info->sig, current_arg));
	}
	
	[invocation invoke];
	
	const char *return_type = info->sig; // return value is first type in sig
	
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
		case ':': {
			SEL val;
			[invocation getReturnValue:&val];
			luaobjc_selector_push(L, val);
		} break;
		case '{': {
			size_t enc_len = luaobjc_method_sig_arg_len(return_type);
			char struct_name[enc_len]; // no need to +1 because it already won't count '{'
			luaobjc_method_sig_struct_name(return_type, struct_name);
			
			void *structptr = luaobjc_struct_push(L, struct_name, NULL);
			if (structptr != NULL) {
				[invocation getReturnValue:structptr];
				break;
			} //  *** else, fallthrough to default ***
		}
		// BE CAREFUL! case '{' falls through to here sometimes!!!
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

// Gets a luaobjc_method_info from a target object & lua string
// FOUND: pushes a luaobjc_method_info userdata on the stack & returns it
// NOT FOUND: pushes NOTHING and returns NULL
//
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
static luaobjc_method_info *lookup_method_info(lua_State *L, int idx, id target) {
	size_t len;
	const char *str = luaL_checklstring(L, idx, &len);
	
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
	SEL used_sel = NULL;
	
	Method m = target_class ? class_getInstanceMethod(target_class, sel) : class_getClassMethod(target, sel);
	if (m != NULL) {
		used_sel = sel;
	} else if (m == NULL && !has_args) {
		// Try again by adding one arg to the end
		transformed[len] = ':';
		fallback_sel = luaobjc_get_sel(L, transformed);
		m = target_class ? class_getInstanceMethod(target_class, fallback_sel) : class_getClassMethod(target, fallback_sel);
		
		if (m) used_sel = fallback_sel;
	}
	
	if (m != NULL) {
		// transform the type encoding into something easily reusable. the goal is
		// to perform this transformation (using | to split arguments):
		// v0@4:4  ->  v|@|:  (note, we cannot simply replace numbers w/ |s because
		// of some certain Objective C type encodings
		
		const char *enc = method_getTypeEncoding(m);
		const char *enc_next;
		size_t enc_len = strlen(enc);
		int num_args = method_getNumberOfArguments(m);
		enc_len += num_args; // extra room for '|'
		
		char enc_fixed[enc_len + 1];
		char *enc_fixed_ptr = enc_fixed; // for our current index into enc_fixed
		
		
		enc = arg_encoding_skip_type_qualifiers(enc);
		for (;;) {
			enc_next = NSGetSizeAndAlignment(enc, NULL, NULL);
			if (enc_next == NULL) break;
			
			// copy argument
			while (enc != enc_next) {
				*enc_fixed_ptr = *enc;
				enc_fixed_ptr++;
				enc++;
			}
			
			enc = arg_encoding_skip_stack_numbers(enc);
			enc = arg_encoding_skip_type_qualifiers(enc);
			
			if (*enc != '\0') {
				*enc_fixed_ptr = '|';
				enc_fixed_ptr++;
			} else {
				*enc_fixed_ptr = '\0';
				enc_fixed_ptr++;
				break;
			}
		}
		
		return push_method_info(L, target, used_sel, num_args, enc_fixed, strlen(enc_fixed));
	} else {
		// We can still see if the method is handled via forwardInvocation:
		BOOL sel_worked = [target respondsToSelector:sel];
		BOOL fallback_worked = NO;
		if (!sel_worked)
			fallback_worked = [target respondsToSelector:fallback_sel];
		
		if (sel_worked || fallback_worked) {
			used_sel = sel_worked ? sel : fallback_sel;
			
			// See above for details regarding the format of the method signature string
			NSMethodSignature *methodSig = [target methodSignatureForSelector:used_sel];
			NSMutableString *sigStr = [NSMutableString string];
			
			const char *arg_str;
			
			arg_str = arg_encoding_skip_type_qualifiers([methodSig methodReturnType]);
			[sigStr appendFormat:@"%s|", arg_str];
			
			int arg_count = [methodSig numberOfArguments];
			for (int arg_idx = 0; arg_idx < arg_count; arg_idx++) {
				arg_str = arg_encoding_skip_type_qualifiers([methodSig getArgumentTypeAtIndex:arg_idx]);
				
				if (arg_idx != arg_count - 1)
					[sigStr appendFormat:@"%s|", arg_str];
				else
					[sigStr appendFormat:@"%s", arg_str];
			}
			
			return push_method_info(L, target, used_sel, arg_count, [sigStr UTF8String], [sigStr length]);
		}
	}
	
	return NULL;
}


// converts an arg from from the lua value at lua_idx into the argument at invocation_idx
// in invocation
static void convert_lua_arg(lua_State *L, int lua_idx, NSInvocation *invocation, 
	int invocation_idx, const char *encoding) {
	
	switch (encoding[0]) {
		case 'c': {
			LUAOBJC_ARGS_LUA_CHAR(val, lua_idx)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'i': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, int)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 's': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, short)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'l': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, long)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'q': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, long long)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'C': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned char)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'I': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned int)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'S': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned short)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'L': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned long)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'Q': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned long long)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'f': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, float)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'd': {
			LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, double)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'B': {
			LUAOBJC_ARGS_LUA_BOOL(val, lua_idx)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case 'v': break;
		case '*': {
			LUAOBJC_ARGS_LUA_CSTRING(str, lua_idx);
			[invocation setArgument:&str atIndex:invocation_idx];
		} break;
		case '@': // Both objects and classes are treated they same by us
		case '#': {
			// Auto convert some Lua values into Objective C values
			LUAOBJC_ARGS_LUA_OBJECT(val, lua_idx)
			[invocation setArgument:&val atIndex:invocation_idx];
		} break;
		case ':': {
			LUAOBJC_ARGS_LUA_SEL(sel, lua_idx)
			[invocation setArgument:&sel atIndex:invocation_idx];
		} break;
		case '{': {
			// we want to still handle 'unknown' types, so check if we are for sure
			// dealing with a struct before getting too far along
			if (luaobjc_struct_is_struct(L, lua_idx)) {
				size_t enc_len = luaobjc_method_sig_arg_len(encoding);
				char struct_name[enc_len]; // no need to +1 because it already won't count '{'
				luaobjc_method_sig_struct_name(encoding, struct_name);
				
				void *val = luaobjc_struct_check(L, lua_idx, struct_name);
				[invocation setArgument:val atIndex:invocation_idx];
				break;
			} // *** else, fallthrough to 'default'
		}
		// BE CAREFUL! case '{' falls through to here!
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
	
	return index;
}

// Returns a pointer to the character after the weird method_getTypeEncoding numbers
static const char *arg_encoding_skip_stack_numbers(const char *current_pos) {
	while (current_pos[0] != '\0' && current_pos[0] >= '0' && current_pos[0] <= '9')
		current_pos++;
	return current_pos;
}

static luaobjc_method_info *push_method_info(lua_State *L, id target, SEL sel, int num_args, const char *sig, size_t sig_len) {
	size_t size = sizeof(luaobjc_method_info) + sig_len + 1;
	luaobjc_method_info *pushed = (luaobjc_method_info *)lua_newuserdata(L, size);
	pushed->target = target;
	pushed->selector = sel;
	pushed->num_args = num_args;
	
	pushed->sig = (char*)pushed + sizeof(luaobjc_method_info);
	memcpy((char*)(pushed->sig), sig, sig_len);
	*(char*)(pushed->sig + sig_len) = '\0';
	
	return pushed;
}
