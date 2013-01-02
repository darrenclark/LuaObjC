//  Created by Darren Clark on 12-12-30.

#import "luaobjc_luaclass.h"
#import "luaobjc_object.h"
#import "luaobjc_sel_cache.h"
#import "luaobjc_selector.h"

#import "ffi.h"
#import <objc/runtime.h>

#define LUACLASS_MT "luaclass_mt"
#define LUACLASSES	"luaclasses"


#define METHOD_FUNC_INDEX	1
#define METHOD_FFI_INDEX	2
#define METHOD_SIG_INDEX	3


typedef struct luaclass {
	Class class;
	BOOL registered;
} luaclass;

typedef struct method_ffi_info {
	ffi_cif cif;
	ffi_closure *closure;
	ffi_type *args[0];
} method_ffi_info;


static luaclass *check_luaclass(lua_State *L, int idx);

static int new_luaclass(lua_State *L);
static int luaclass_newindex(lua_State *L);
static int luaclass_register(lua_State *L);

// Determines the selector and method for a given string at 'str_idx'
static void determine_selector_method(lua_State *L, int str_idx, Class cls, SEL *sel, Method *method);
// Binds a ObjC function to a Lua function
static void bind_method(lua_State *L, int luaclass_idx, int func_idx, SEL sel, const char *type_encoding);
// Returns the ffi_type for a objc type
static ffi_type *type_for_objc_type(const char *type_encoding);

void luaobjc_luaclass_open(lua_State *L) {
	// 'objc' global is at the top of the stack. make sure it is still there
	// at the end of this function!
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_LUACLASS_MT, LUACLASS_MT);
	// set the __index field of luaclass_mt to luaclass_mt
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	
	LUAOBJC_ADD_METHOD("register", luaclass_register);
	LUAOBJC_ADD_METHOD("__newindex", luaclass_newindex);
	lua_pop(L, 1); // pop metatable
	
	// Maps 'Class' to a classes fenv
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_LUACLASSES, LUACLASSES);
	lua_pop(L, 1);
	
	LUAOBJC_ADD_METHOD("new_class", new_luaclass);
}

static luaclass *check_luaclass(lua_State *L, int idx) {
	return (luaclass *)luaobjc_checkudata(L, idx, LUAOBJC_REGISTRY_LUACLASS_MT, LUACLASS_MT);
}

static int new_luaclass(lua_State *L) {
	const char *class_name = luaL_checkstring(L, 1);
	const char *super_class_name = luaL_checkstring(L, 2);
	
	// don't try and create an already existing class...
	Class class = objc_getClass(class_name);
	if (class != NULL) {
		lua_pushfstring(L, "class '%s' already exists", class_name);
		lua_error(L);
	}
	
	// make sure the super class exists
	Class super_class = objc_getClass(super_class_name);
	if (super_class == NULL) {
		lua_pushfstring(L, "super class '%s' doesn't exist", super_class_name);
		lua_error(L);
	}
	
	// All good to go, lets create our class!
	luaclass *luaclass = lua_newuserdata(L, sizeof(luaclass)); // ..., luaclass
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_LUACLASS_MT, LUACLASS_MT); // ..., luaclass, luaclass_mt
	lua_setmetatable(L, -2); // ..., luaclass
	
	lua_newtable(L); // ..., luaclass, fenv
	lua_setfenv(L, -2); // ..., luaclass
	
	luaclass->class = objc_allocateClassPair(super_class, class_name, 0);
	luaclass->registered = NO;
	
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_LUACLASSES, LUACLASSES); // luaclass, luaclasses
	lua_pushlightuserdata(L, (void *)luaclass->class); // luaclass, luaclasses, class
	lua_getfenv(L, -3); // luaclass, luaclasses, class, luaclass
	lua_rawset(L, -3); // luaclass, luaclasses
	lua_pop(L, 1); // luaclass
	
	return 1;
}

static int luaclass_register(lua_State *L) {
	luaclass *class = check_luaclass(L, 1);
	if (class->registered) {
		lua_pushfstring(L, "class '%s' has already been registered", class_getName(class->class));
		lua_error(L);
	}
	
	objc_registerClassPair(class->class);
	class->registered = YES;
	return 1;
}

static int luaclass_newindex(lua_State *L) {
	luaclass *cls = check_luaclass(L, 1);
	// make sure k is a string
	luaL_checkstring(L, 2);
	// make sure v is a function
	luaL_checktype(L, 3, LUA_TFUNCTION);
	
	SEL selector = NULL;
	Method method = NULL;
	determine_selector_method(L, 2, cls->class, &selector, &method);
	
	if (method == NULL) {
		// no info to go by, so just assume that they want a method something like: @@:
		// we also want to create it in our own internal usable format that includes
		// | between each type
		
		int num_types = 3; // return, self, _cmd
		
		// loop through selector name and count up additional args
		const char *sel_char = (const char *)selector;
		while (*sel_char != '\0') {
			if (*sel_char == ':') {
				num_types++;
			}
			sel_char++;
		}
		
		int sig_len = num_types * 2; // 1 char per type + |
		char sig[sig_len];
		for (int i = 0; i < num_types; i++) {
			sig[i * 2 + 0] = '@';
			sig[i * 2 + 1] = (i == num_types - 1) ? '\0' : '|';
		}
		
		bind_method(L, 1, 3, selector, sig);
	} else {
		const char *enc = method_getTypeEncoding(method);
		int num_args = method_getNumberOfArguments(method);
		
		size_t enc_len = strlen(enc);
		enc_len += num_args; // extra room for '|'
		char enc_fixed[enc_len + 1];
		
		luaobjc_method_sig_convert(enc, enc_fixed);
		
		bind_method(L, 1, 3, selector, enc_fixed);
	}
	
	return 0;
}


static void determine_selector_method(lua_State *L, int str_idx, Class cls, SEL *sel, Method *method) {
	*sel = NULL;
	*method = NULL;
	
	size_t len;
	const char *str = lua_tolstring(L, str_idx, &len);
	
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
		
	SEL selector = luaobjc_get_sel(L, transformed);
	
	Method m = class_getInstanceMethod(cls, selector);
	if (m != NULL) {
		*sel = selector;
		*method = m;
		return;
	} else if (m == NULL && !has_args) {
		// Try again by adding one arg to the end
		transformed[len] = ':';
		SEL fallback = luaobjc_get_sel(L, transformed);
		m = class_getInstanceMethod(cls, fallback);
		
		if (m) {
			*sel = fallback;
			*method = m;
			return;
		} else {
			*sel = selector;
		}
	}
}


static void method_binding(ffi_cif *cif, void *ret, void *args[], void *userdata) {
	lua_State *L = (lua_State *)userdata;
	
	id target = *(id *)args[0];
	SEL sel = *(SEL *)args[1];
	
	Class cls = [target class];
	
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_LUACLASSES, LUACLASSES); // luaclasses
	lua_pushlightuserdata(L, (void *)cls); // luaclasses, cls
	lua_rawget(L, -2); // luaclasses, fenv
	
	lua_pushlightuserdata(L, (void *)sel); // luaclasses, fenv, sel
	lua_rawget(L, -2); // luaclasses, fenv, tbl
	
	lua_pushinteger(L, METHOD_FUNC_INDEX); // luaclasses, fenv, tbl, METHOD_FUNC_INDEX
	lua_rawget(L, -2); // luaclasses, fenv, tbl, func
	
	if (!lua_isfunction(L, -1))
		[NSException raise:@"LuaClassInvalidMethodCall" format:@"No function found in '%@' for '%s'", cls, (const char *)sel];
	
	lua_pushinteger(L, METHOD_SIG_INDEX); // luaclasses, fenv, tbl, func, METHOD_SIG_INDEX
	lua_rawget(L, -3); // luaclasses, fenv, tbl, func, sig
	
	const char *sig = lua_tostring(L, -1);
	lua_pop(L, 1); // luaclasses, fenv, tbl, func
	
	int res = lua_pcall(L, 0, sig[0] != 'v' ? 1 : 0, 0);
	if (res != 0) {
		NSLog(@"Error running [%@ %s]: %s", cls, (const char *)sel, lua_tolstring(L, -1, NULL));
	}
	
	if (lua_isnoneornil(L, -1) || res != 0) {
		// return a default value
		switch (sig[0]) {
			case 'c': *(char *)ret = 0; break;
			case 'i': *(int *)ret = 0; break;
			case 's': *(short *)ret = 0; break;
			case 'l': *(long *)ret = 0; break;
			case 'q': *(long long *)ret = 0; break;
			case 'C': *(unsigned char *)ret = 0; break;
			case 'I': *(unsigned int *)ret = 0; break;
			case 'S': *(unsigned short *)ret = 0; break;
			case 'L': *(unsigned long *)ret = 0; break;
			case 'Q': *(unsigned long long *)ret = 0; break;
			case 'f': *(float *)ret = 0.0f; break;
			case 'd': *(double *)ret = 0.0; break;
			case 'B': *(_Bool *)ret = false; break;
			case 'v': break; // void, do nothing
			case '*': *(void **)ret = NULL; break;
			case '@': *(id *)ret = NULL; break;
			case '#': *(Class *)ret = NULL; break;
			case ':': *(SEL *)ret = NULL; break;
		}
	} else {
		switch (sig[0]) {
			case 'c': {
				if (lua_isboolean(L, -1))
					*(BOOL *)ret = (BOOL)lua_toboolean(L, -1);
				else
					*(char *)ret = (char)lua_tonumber(L, -1);
			} break;
			case 'i': *(int *)ret = (int)lua_tonumber(L, -1); break;
			case 's': *(short *)ret = (short)lua_tonumber(L, -1); break;
			case 'l': *(long *)ret = (long)lua_tonumber(L, -1); break;
			case 'q': *(long long *)ret = (long long)lua_tonumber(L, -1); break;
			case 'C': *(unsigned char *)ret = (unsigned char)lua_tonumber(L, -1); break;
			case 'I': *(unsigned int *)ret = (unsigned int)lua_tonumber(L, -1); break;
			case 'S': *(unsigned short *)ret = (unsigned short)lua_tonumber(L, -1); break;
			case 'L': *(unsigned long *)ret = (unsigned long)lua_tonumber(L, -1); break;
			case 'Q': *(unsigned long long *)ret = (unsigned long long)lua_tonumber(L, -1); break;
			case 'f': *(float *)ret = (float)lua_tonumber(L, -1); break;
			case 'd': *(double *)ret = (double)lua_tonumber(L, -1); break;
			case 'B': *(_Bool *)ret = (_Bool)lua_toboolean(L, -1); break;
			case 'v': break; // void, do nothing
			case '*': *(const char **)ret = lua_tostring(L, -1); break;
			case '@': *(id *)ret = luaobjc_to_objc(L, -1); break;
			case '#': *(Class *)ret = (Class)luaobjc_to_objc(L, -1); break;
			case ':': *(SEL *)ret = (SEL)luaobjc_selector_check_s(L, -1); break;
		}
	}
	
	lua_pop(L, 4); // (empty stack)
}

static void bind_method(lua_State *L, int luaclass_idx, int func_idx, SEL sel, const char *type_encoding) {
	int num_args = luaobjc_method_sig_num_types(type_encoding) - 1;
	
	// we store a table with details regarding a method in a table
	//	METHOD_FUNC_INDEX -> the lua function to call
	//	METHOD_FFI_INDEX -> the method_ffi_info struct
	lua_getfenv(L, luaclass_idx); // ..., fenv
	lua_pushlightuserdata(L, (void*)sel); // ..., fenv, sel
	
	lua_newtable(L); // ..., fenv, sel, tbl
	
	lua_pushinteger(L, METHOD_FUNC_INDEX); // ..., fenv, sel, tbl, METHOD_FUNC_INDEX
	lua_pushvalue(L, func_idx); // ..., fenv, sel, tbl, METHOD_FUNC_INDEX, func
	lua_rawset(L, -3); // ..., fenv, sel, tbl
	
	lua_pushinteger(L, METHOD_FFI_INDEX); // ..., fenv, sel, tbl, METHOD_FFI_INDEX
	method_ffi_info *ffi_info = (method_ffi_info *)lua_newuserdata(L, sizeof(method_ffi_info) + sizeof(ffi_type *) * num_args);
	// ..., fenv, sel, tbl, METHOD_FFI_INDEX, method_ffi_info
	lua_rawset(L, -3); // ..., fenv, sel, tbl
	
	lua_pushinteger(L, METHOD_SIG_INDEX); // .., fenv, sel, tbl, METHOD_SIG_INDEX
	lua_pushstring(L, type_encoding); // ..., fenv, sel, tbl, METHOD_SIG_INDEX, type_encoding
	lua_rawset(L, -3); // ..., fenv, sel, tbl
	
	lua_rawset(L, -3); // ..., fenv
	lua_pop(L, 1); // ...
	
	char objc_encoding[strlen(type_encoding)];
	luaobjc_method_sig_revert(type_encoding, objc_encoding);
	
	luaclass *class = check_luaclass(L, luaclass_idx);
	
	void(*bound_method)(void);
	
	ffi_info->closure = ffi_closure_alloc(sizeof(ffi_closure), (void **)&bound_method);
	
	for (int i = 0; i < num_args; i++) {
		const char *method_sig_arg = luaobjc_method_sig_arg(type_encoding, i);
		ffi_type *type = type_for_objc_type(method_sig_arg);
		if (type == NULL) {
			lua_pushfstring(L, "invalid type for [%@ %s]: %c", class->class, (const char *)sel, *method_sig_arg);
			lua_error(L);
		}
		ffi_info->args[i] = type;
	}
	
	ffi_prep_cif(&ffi_info->cif, FFI_DEFAULT_ABI, num_args, type_for_objc_type(type_encoding), ffi_info->args);
	ffi_prep_closure_loc(ffi_info->closure, &ffi_info->cif, method_binding, (void *)L, bound_method);
	
	class_replaceMethod(class->class, sel, (IMP)bound_method, objc_encoding);
}

static ffi_type *type_for_objc_type(const char *type_encoding) {
	// Set ret_type
	switch (type_encoding[0]) {
		case 'c': return &ffi_type_sint8;
		case 'i': return &ffi_type_sint32;
		case 's': return &ffi_type_sint16;
		case 'l': return &ffi_type_sint32;
		case 'q': return &ffi_type_sint64;
		case 'C': return &ffi_type_uint8;
		case 'I': return &ffi_type_uint32;
		case 'S': return &ffi_type_uint16;
		case 'L': return &ffi_type_uint32;
		case 'Q': return &ffi_type_uint64;
		case 'f': return &ffi_type_float;
		case 'd': return &ffi_type_double;
		case 'B': return &ffi_type_uint8;
		case 'v': return &ffi_type_void;
		case '*': return &ffi_type_pointer;
		case '@': return &ffi_type_pointer;
		case '#': return &ffi_type_pointer;
		case ':': return &ffi_type_pointer;
		default: return NULL;
	}
}
