//  Created by Darren Clark on 12-12-30.

#import "luaobjc_luaclass.h"
#import "luaobjc_object.h"
#import "luaobjc_sel_cache.h"
#import "luaobjc_selector.h"
#import "luaobjc_struct.h"

#import "ffi.h"
#import <objc/runtime.h>

#define LUACLASS_MT "luaclass_mt"
#define LUACLASSES	"luaclasses"


#define METHOD_FUNC_INDEX	1
#define METHOD_FFI_INDEX	2
#define METHOD_SIG_INDEX	3

typedef enum property_memory_policy {
	property_memory_policy_assign = 0,
	property_memory_policy_retain = 1,
	property_memory_policy_copy = 2,
} property_memory_policy;


typedef struct luaclass {
	Class class;
	BOOL registered;
} luaclass;


typedef struct method_ffi_info {
	ffi_cif cif;
	ffi_closure *closure;
	ffi_type *args[0];
} method_ffi_info;


typedef struct ivar_info {
	Ivar ivar;
	property_memory_policy memory_policy;
} ivar_info;


static luaclass *check_luaclass(lua_State *L, int idx);

static int new_luaclass(lua_State *L);
static int luaclass_newindex(lua_State *L);
static int luaclass_register(lua_State *L);
static int luaclass_property(lua_State *L);

// Determines the selector and method for a given string at 'str_idx'
static void determine_selector_method(lua_State *L, int str_idx, Class cls, SEL *sel, Method *method, const char **types);
// Checks through this class + superclass(es) protocols to find a method
// returns YES and puts the method in out_description on success. otherwise returns NO
static BOOL check_protocols_for_selector(Class cls, SEL sel, struct objc_method_description *out_description);
// Binds a ObjC function to a Lua function
static void bind_method(lua_State *L, int luaclass_idx, int func_idx, SEL sel, const char *type_encoding);
// Binds property setter/getters
static void bind_property(Class cls, ivar_info ivar_info, const char *setter, const char *getter);
// Returns the ffi_type for a objc type
static ffi_type *type_for_objc_type(lua_State *L, const char *type_encoding);

void luaobjc_luaclass_open(lua_State *L) {
	// 'objc' global is at the top of the stack. make sure it is still there
	// at the end of this function!
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_LUACLASS_MT, LUACLASS_MT);
	// set the __index field of luaclass_mt to luaclass_mt
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	
	LUAOBJC_ADD_METHOD("register", luaclass_register);
	LUAOBJC_ADD_METHOD("property", luaclass_property);
	LUAOBJC_ADD_METHOD("__newindex", luaclass_newindex);
	lua_pop(L, 1); // pop metatable
	
	// Maps 'Class' to a classes fenv
	LUAOBJC_NEW_REGISTERY_TABLE(L, LUAOBJC_REGISTRY_LUACLASSES, LUACLASSES);
	lua_pop(L, 1);
	
	LUAOBJC_ADD_METHOD("new_class", new_luaclass);
	
	LUAOBJC_CONSTANT("ASSIGN", property_memory_policy_assign);
	LUAOBJC_CONSTANT("RETAIN", property_memory_policy_retain);
	LUAOBJC_CONSTANT("COPY", property_memory_policy_copy);
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
	
	// add any protocols?
	if (lua_type(L, 3) == LUA_TTABLE) {
		int i = 1;
		for (;; i++) {
			lua_rawgeti(L, 3, i); // ..., luaclass, protocol
			if (lua_isstring(L, -1)) {
				const char *protocol_name = lua_tostring(L, -1);
				Protocol *protocol = objc_getProtocol(protocol_name);
				lua_pop(L, 1); // ..., luaclass
				
				if (protocol != NULL) {
					class_addProtocol(luaclass->class, protocol);
				} else {
					NSLog(@"Protocol '%s' not found", protocol_name);
				}
			} else if (lua_isnoneornil(L, -1)) {
				lua_pop(L, 1); // ..., luaclass
				break;
			}
		}
	}
	
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_LUACLASSES, LUACLASSES); // luaclass, luaclasses
	lua_pushlightuserdata(L, (void *)luaclass->class); // luaclass, luaclasses, class
	lua_pushvalue(L, -3); // luaclass, luaclasses, class, luaclass
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

static int luaclass_property(lua_State *L) {
	luaclass *class = check_luaclass(L, 1);
	if (class->registered) {
		lua_pushfstring(L, "can't add property, class '%s' has already been registered", class_getName(class->class));
		lua_error(L);
	}
	
	const char *name = luaL_checkstring(L, 2);
	
	static const char *memory_policy_error = "expected objc.ASSIGN, objc.RETAIN, or objc.COPY";
	luaL_argcheck(L, lua_isnumber(L, 3), 3, memory_policy_error);
	int memory_policy = lua_tonumber(L, 3);
	luaL_argcheck(L, memory_policy >= property_memory_policy_assign && memory_policy <= property_memory_policy_copy, 3, memory_policy_error);
	
	unsigned int size, alignment;
	NSGetSizeAndAlignment("@", &size, &alignment);
	BOOL success = class_addIvar(class->class, name, size, (uint8_t)alignment, "@");
	
	Ivar ivar = class_getInstanceVariable(class->class, name);
	ivar_info ivar_info;
	
	ivar_info.ivar = ivar;
	ivar_info.memory_policy = (property_memory_policy)memory_policy;
	
	int setter_len = strlen(name) + 5; // 3 for "set", one for ':', one for \0
	char setter[setter_len]; 
	
	strcpy(setter, "set");
	strcpy((char *)setter + 3, name);
	
	if (setter[3] >= 'a' && setter[3] <= 'z')
		setter[3] = setter[3] += ('A' - 'a'); // convert to uppercase
	setter[setter_len - 2] = ':';
	setter[setter_len - 1] = '\0';
	
	bind_property(class->class, ivar_info, setter, name);
	
	return 0;
}

static int luaclass_newindex(lua_State *L) {
	luaclass *cls = check_luaclass(L, 1);
	// make sure k is a string
	luaL_checkstring(L, 2);
	// make sure v is a function
	luaL_checktype(L, 3, LUA_TFUNCTION);
	
	SEL selector = NULL;
	Method method = NULL;
	const char *types = NULL;
	determine_selector_method(L, 2, cls->class, &selector, &method, &types);
	
	if (method != NULL) {
		const char *enc = method_getTypeEncoding(method);
		int num_args = method_getNumberOfArguments(method);
		
		size_t enc_len = strlen(enc);
		enc_len += num_args; // extra room for '|'
		char enc_fixed[enc_len + 1];
		
		luaobjc_method_sig_convert(enc, enc_fixed);
		
		bind_method(L, 1, 3, selector, enc_fixed);
	} else if (types != NULL) {
		size_t enc_len = strlen(types) * 2; // we want to make sure we have enough room for '|'
		char enc_fixed[enc_len + 1];
		
		luaobjc_method_sig_convert(types, enc_fixed);
		
		bind_method(L, 1, 3, selector, enc_fixed);
	} else {
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
	}
	
	return 0;
}


static void determine_selector_method(lua_State *L, int str_idx, Class cls, SEL *sel, Method *method, const char **types) {
	*sel = NULL;
	*method = NULL;
	*types = NULL;
	
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
	} else {
		struct objc_method_description method_description;
		if (check_protocols_for_selector(cls, selector, &method_description)) {
			*sel = selector;
			*types = method_description.types;
			return;
		}
	}
	
	if (m == NULL && !has_args) {
		// Try again by adding one arg to the end
		transformed[len] = ':';
		SEL fallback = luaobjc_get_sel(L, transformed);
		m = class_getInstanceMethod(cls, fallback);
		
		if (m) {
			*sel = fallback;
			*method = m;
			return;
		} else {
			struct objc_method_description method_description;
			if (check_protocols_for_selector(cls, selector, &method_description)) {
				*sel = fallback;
				*types = method_description.types;
				return;
			} else {
				// otherwise, just use default selector
				*sel = selector;
				return;
			}
		}
	} else {
		*sel = selector;
	}
}

static BOOL check_protocols_for_selector(Class cls, SEL sel, struct objc_method_description *out_description) {
	BOOL found_method = NO;
	
	while (!found_method && [(id)cls superclass] != cls) {
		unsigned int count;
		Protocol **protocols = class_copyProtocolList(cls, &count);
		
		for (unsigned int i = 0; i < count; i++) {
			Protocol *p = protocols[i];
			
			unsigned int methods_count;
			struct objc_method_description *methods;
			
			// try required methods
			methods = protocol_copyMethodDescriptionList(p, YES, YES, &methods_count);
			for (unsigned int j = 0; j < methods_count; j++) {
				if (methods[j].name == sel) {
					found_method = YES;
					*out_description = methods[j];
					break;
				}
			}
			free(methods);
			
			if (found_method)
				break;
			
			// try non-required methods
			methods = protocol_copyMethodDescriptionList(p, NO, YES, &methods_count);
			for (unsigned int j = 0; j < methods_count; j++) {
				if (methods[j].name == sel) {
					found_method = YES;
					*out_description = methods[j];
					break;
				}
			}
			free(methods);
		}
		
		free(protocols);
		cls = [cls superclass];
	}
	
	return found_method;
}

static void method_binding(ffi_cif *cif, void *ret, void *args[], void *userdata) {
	lua_State *L = (lua_State *)userdata;
	
	id target = *(id *)args[0];
	SEL sel = *(SEL *)args[1];
	
	Class cls = [target class];
	
	LUAOBJC_GET_REGISTRY_TABLE(L, LUAOBJC_REGISTRY_LUACLASSES, LUACLASSES); // luaclasses
	lua_pushlightuserdata(L, (void *)cls); // luaclasses, cls
	lua_rawget(L, -2); // luaclasses, luaclass
	lua_getfenv(L, -1); // luaclasses, luaclass, fenv
	lua_replace(L, -2); // luaclasses, fenv
	
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
	
	
	// push args to lua
	int num_args = luaobjc_method_sig_num_types(sig) - 2; // -1 for return type and -1 since we don't pass in the selector
	luaobjc_object_push_strict(L, target);
	
	for (int i = 1; i < num_args; i++) { // start at 1 because self/target is already pushed
		int arg_index = i + 1;
		const char *type = luaobjc_method_sig_arg(sig, arg_index);
		
		switch (type[0]) {
			case 'c': {
				char val = *(char *)args[arg_index];
				if (val == 0 || val == 1)
					lua_pushboolean(L, val);
				else
					lua_pushnumber(L, val);
			} break;
			case 'i': lua_pushnumber(L, *(int *)args[arg_index]); break;
			case 's': lua_pushnumber(L, *(short *)args[arg_index]); break;
			case 'l': lua_pushnumber(L, *(long *)args[arg_index]); break;
			case 'q': lua_pushnumber(L, *(long long *)args[arg_index]); break;
			case 'C': lua_pushnumber(L, *(unsigned char *)args[arg_index]); break;
			case 'I': lua_pushnumber(L, *(unsigned int *)args[arg_index]); break;
			case 'S': lua_pushnumber(L, *(unsigned short *)args[arg_index]); break;
			case 'L': lua_pushnumber(L, *(unsigned long *)args[arg_index]); break;
			case 'Q': lua_pushnumber(L, *(unsigned long long *)args[arg_index]); break;
			case 'f': lua_pushnumber(L, *(float *)args[arg_index]); break;
			case 'd': lua_pushnumber(L, *(double *)args[arg_index]); break;
			case 'B': lua_pushboolean(L, *(_Bool *)args[arg_index]); break;
			case '*': {
				const char *str = *(const char **)args[arg_index];
				if (str == NULL) lua_pushnil(L);
				else lua_pushstring(L, str);
			} break;
			case '@': luaobjc_object_push(L, *(id *)args[arg_index]); break;
			case '#': luaobjc_object_push(L, *(Class *)args[arg_index]); break;
			case ':': luaobjc_selector_push(L, *(SEL *)args[arg_index]); break;
			case '{': {
				char struct_name[strlen(type)];
				luaobjc_method_sig_struct_name(type, struct_name);
				luaobjc_struct_push(L, struct_name, args[arg_index]);
			} break;
			default: lua_pushnil(L); break;
		}
	}
	
	int res = lua_pcall(L, num_args, sig[0] != 'v' ? 1 : 0, 0);
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
			case '{':  { // for better or for worse, just zero out *ret here
				char struct_name[strlen(sig)];
				luaobjc_method_sig_struct_name(sig, struct_name);
				size_t size = luaobjc_struct_size(L, struct_name);
				memset(ret, 0, size);
			} break;
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
			case '{': {
				char struct_name[strlen(sig)];
				luaobjc_method_sig_struct_name(sig, struct_name);
				void *struct_ptr = luaobjc_struct_check(L, -1, struct_name);
				size_t size = luaobjc_struct_size(L, struct_name);
				memcpy(ret, struct_ptr, size);
			} break;
		}
	}
	
	lua_pop(L, 4); // (empty stack)
}

static void bind_method(lua_State *L, int luaclass_idx, int func_idx, SEL sel, const char *type_encoding) {
	int num_args = luaobjc_method_sig_num_types(type_encoding) - 1;
	
	// we store a table with details regarding a method in a table
	//	METHOD_FUNC_INDEX -> the lua function to call
	//	METHOD_FFI_INDEX -> the method_ffi_info struct
	//	METHOD_SIG_INDEX -> the signature of the method
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
		ffi_type *type = type_for_objc_type(L, method_sig_arg);
		if (type == NULL) {
			lua_pushfstring(L, "invalid type for [%@ %s]: %c", class->class, (const char *)sel, *method_sig_arg);
			lua_error(L);
		}
		ffi_info->args[i] = type;
	}
	
	ffi_prep_cif(&ffi_info->cif, FFI_DEFAULT_ABI, num_args, type_for_objc_type(L, type_encoding), ffi_info->args);
	ffi_prep_closure_loc(ffi_info->closure, &ffi_info->cif, method_binding, (void *)L, bound_method);
	
	class_replaceMethod(class->class, sel, (IMP)bound_method, objc_encoding);
}

static ivar_info get_prop_ivar_info(id obj, SEL selector) {
	Class cls = [obj class];
	while (cls != [cls superclass]) {
		NSValue *val = objc_getAssociatedObject(cls, selector);
		if (val != NULL) {
			ivar_info ivar;
			[val getValue:&ivar];
			return ivar;
		}
		cls = [cls superclass];
	}
	ivar_info ret;
	ret.ivar = NULL;
	return ret;
}

static void prop_set_binding(id self, SEL _cmd, id value) {
	ivar_info ivar = get_prop_ivar_info(self, _cmd);
	
	id prev = object_getIvar(self, ivar.ivar);
	
	if (ivar.memory_policy == property_memory_policy_retain)
		[value retain];
	else if (ivar.memory_policy == property_memory_policy_copy)
		value = [value copy];
	
	object_setIvar(self, ivar.ivar, value);
	
	if (ivar.memory_policy == property_memory_policy_retain
		|| ivar.memory_policy == property_memory_policy_copy) {
		[prev release];
	}
}

static id prop_get_binding(id self, SEL _cmd) {
	ivar_info ivar = get_prop_ivar_info(self, _cmd);
	return object_getIvar(self, ivar.ivar);
}

static void bind_property(Class cls, ivar_info ivar_info, const char *setter, const char *getter) {
	NSValue *boxedIvar = [NSValue value:(void *)&ivar_info withObjCType:@encode(struct ivar_info)];
	struct ivar_info test_ivar;
	[boxedIvar getValue:&test_ivar];
	
	SEL setterSel = sel_getUid(setter);
	objc_setAssociatedObject(cls, setterSel, boxedIvar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	class_addMethod(cls, setterSel, (IMP)prop_set_binding, "v@:@");
	
	SEL getterSel = sel_getUid(getter);
	objc_setAssociatedObject(cls, getterSel, boxedIvar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	class_addMethod(cls, getterSel, (IMP)prop_get_binding, "@@:");
}

static ffi_type *type_for_objc_type(lua_State *L, const char *type_encoding) {
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
		case '{': {
			char struct_name[strlen(type_encoding)];
			luaobjc_method_sig_struct_name(type_encoding, struct_name);
			return luaobjc_struct_get_ffi(L, struct_name);
		}
		default: return NULL;
	}
}
