//  Created by Darren Clark on 12-12-30.

#import "luaobjc_luaclass.h"
#import "luaobjc_object.h"
#import "luaobjc_sel_cache.h"

#import "ffi.h"
#import <objc/runtime.h>

#define LUACLASS_MT "luaclass_mt"
#define LUACLASSES	"luaclasses"

typedef struct luaclass {
	Class class;
	BOOL registered;
} luaclass;

static luaclass *check_luaclass(lua_State *L, int idx);

static int new_luaclass(lua_State *L);
static int luaclass_newindex(lua_State *L);
static int luaclass_register(lua_State *L);

// Determines the selector and method for a given string at 'str_idx'
static void determine_selector_method(lua_State *L, int str_idx, Class cls, SEL *sel, Method *method);
// Binds a ObjC function to a Lua function
static void bind_method(lua_State *L, int luaclass_idx, int func_idx, SEL sel, const char *type_encoding);


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
			*sel = selector;
			*method = m;
			return;
		}
	}
}


static void method_binding(ffi_cif *cif, void *ret, void *args[], void *userdata) {
	lua_State *L = (lua_State *)userdata;
	
	id target = *(id *)args[0];
	SEL sel = *(SEL *)args[1];
	
	Class cls = [target class];
	
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_LUACLASSES, LUACLASSES);
	lua_pushlightuserdata(L, (void *)cls);
	lua_rawget(L, -2);
	
	lua_pushlightuserdata(L, (void *)sel);
	lua_rawget(L, -2);
	
	if (!lua_isfunction(L, -1))
		[NSException raise:@"LuaClassInvalidMethodCall" format:@"No function found in '%@' for '%s'", cls, (const char *)sel];
	
	if (lua_pcall(L, 0, 1, 0) != 0) {
		NSLog(@"Error running [%@ %s]: %s", cls, (const char *)sel, lua_tolstring(L, -1, NULL));
		*(id *)ret = nil;
		
		return;
	}
	
	// TODO: actually support real args
	*(id *)ret = [NSString stringWithUTF8String:lua_tolstring(L, -1, NULL)];
}

static void bind_method(lua_State *L, int luaclass_idx, int func_idx, SEL sel, const char *type_encoding) {
	// map the selector to the function
	lua_getfenv(L, luaclass_idx); // ..., fenv
	lua_pushlightuserdata(L, (void*)sel); // ..., fenv, sel
	lua_pushvalue(L, func_idx); // ..., fenv, sel, func
	lua_rawset(L, -3); // ..., fenv
	
	char objc_encoding[strlen(type_encoding)];
	luaobjc_method_sig_revert(type_encoding, objc_encoding);
	
	luaclass *class = check_luaclass(L, luaclass_idx);
	
	static ffi_cif cif;
	static ffi_type *args[2];
	static ffi_closure *closure;
	
	void(*bound_method)(void);
	
	closure = ffi_closure_alloc(sizeof(ffi_closure), (void **)&bound_method);
	
	args[0] = &ffi_type_pointer;
	args[1] = &ffi_type_pointer;
	
	ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &ffi_type_pointer, args);
	ffi_prep_closure_loc(closure, &cif, method_binding, (void *)L, bound_method);
	
	class_replaceMethod(class->class, sel, (IMP)bound_method, objc_encoding);
}
