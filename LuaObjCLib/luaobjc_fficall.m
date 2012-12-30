//  Created by Darren Clark on 12-12-29.


#import "luaobjc_fficall.h"
#import "luaobjc_args.h"
#import "luaobjc_selector.h"
#import "ffi.h"

static int fficall(lua_State *L);
static BOOL type_supported(const char *c);

union arg_value {
	char c;
	int i;
	short s;
	long l;
	long long q;
	unsigned char C;
	unsigned int I;
	unsigned short S;
	unsigned long L;
	unsigned long long Q;
	float f;
	double d;
	_Bool B;
	void *ptr;
};


lua_CFunction luaobjc_fficall_get(luaobjc_method_info *info) {
	const char *ret = info->sig; // ret is first value in sig
	BOOL ret_supported = type_supported(ret) || (*ret == 'v');
	if (!ret_supported)
		return NULL;
	
	for (int i = 0; i < info->num_args; i++) {
		if (!type_supported(luaobjc_method_sig_arg(info->sig, i)))
			return NULL;
	}
	
	return fficall;
}

static int fficall(lua_State *L) {
	luaobjc_method_info *info = (luaobjc_method_info *)lua_touserdata(L, lua_upvalueindex(1));
	
	ffi_cif cif;
	ffi_type *types[info->num_args];
	ffi_type *ret_type;
	void *values[info->num_args];
	union arg_value value_holders[info->num_args];
	union arg_value ret_value;
	
	// Set ret_type
	switch (info->sig[0]) {
		case 'c': ret_type = &ffi_type_sint8; break;
		case 'i': ret_type = &ffi_type_sint32; break;
		case 's': ret_type = &ffi_type_sint16; break;
		case 'l': ret_type = &ffi_type_sint32; break;
		case 'q': ret_type = &ffi_type_sint64; break;
		case 'C': ret_type = &ffi_type_uint8; break;
		case 'I': ret_type = &ffi_type_uint32; break;
		case 'S': ret_type = &ffi_type_uint16; break;
		case 'L': ret_type = &ffi_type_uint32; break;
		case 'Q': ret_type = &ffi_type_uint64; break;
		case 'f': ret_type = &ffi_type_float; break;
		case 'd': ret_type = &ffi_type_double; break;
		case 'B': ret_type = &ffi_type_uint8; break;
		case 'v': ret_type = &ffi_type_pointer; break;
		case '*': ret_type = &ffi_type_pointer; break;
		case '@': ret_type = &ffi_type_pointer; break;
		case '#': ret_type = &ffi_type_pointer; break;
		case ':': ret_type = &ffi_type_pointer; break;
		default: {
			lua_pushstring(L, "ffi call panic! invalid return type");
			lua_error(L);
		}
	}

	
	// Process arguments
	
	// "Hidden ObjC args - self, _cmd
	values[0] = &(value_holders[0]);
	values[1] = &(value_holders[1]);
	types[0] = &ffi_type_pointer;
	types[1] = &ffi_type_pointer;
	value_holders[0].ptr = (void *)info->target;
	value_holders[1].ptr = (void *)info->selector;
	
	for (int i = 2; i < info->num_args; i++) {
		const char *arg_enc = luaobjc_method_sig_arg(info->sig, i);
		int lua_idx = i;
		
		values[i] = &(value_holders[i]);
		
		switch (arg_enc[0]) {
			case 'c': {
				LUAOBJC_ARGS_LUA_CHAR(val, lua_idx)
				types[i] = &ffi_type_sint8;
				value_holders[i].c = val;
			} break;
			case 'i': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, int)
				types[i] = &ffi_type_sint32;
				value_holders[i].i = val;
			} break;
			case 's': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, short)
				types[i] = &ffi_type_sint16;
				value_holders[i].s = val;
			} break;
			case 'l': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, long)
				types[i] = &ffi_type_sint32;
				value_holders[i].l = val;
			} break;
			case 'q': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, long long)
				types[i] = &ffi_type_sint64;
				value_holders[i].q = val;
			} break;
			case 'C': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned char)
				types[i] = &ffi_type_uint8;
				value_holders[i].C = val;
			} break;
			case 'I': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned int)
				types[i] = &ffi_type_uint32;
				value_holders[i].I = val;
			} break;
			case 'S': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned short)
				types[i] = &ffi_type_uint16;
				value_holders[i].S = val;
			} break;
			case 'L': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned long)
				types[i] = &ffi_type_uint32;
				value_holders[i].L = val;
			} break;
			case 'Q': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, unsigned long long)
				types[i] = &ffi_type_uint64;
				value_holders[i].Q = val;
			} break;
			case 'f': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, float)
				types[i] = &ffi_type_float;
				value_holders[i].f = val;
			} break;
			case 'd': {
				LUAOBJC_ARGS_LUA_NUMBER(val, lua_idx, double)
				types[i] = &ffi_type_double;
				value_holders[i].d = val;
			} break;
			case 'B': {
				LUAOBJC_ARGS_LUA_BOOL(val, lua_idx)
				types[i] = &ffi_type_uint8;
				value_holders[i].B = val;
			} break;
			case '*': {
				LUAOBJC_ARGS_LUA_CSTRING(str, lua_idx);
				types[i] = &ffi_type_pointer;
				value_holders[i].ptr = (void *)str;
			} break;
			case '@': // Both objects and classes are treated they same by us
			case '#': {
				// Auto convert some Lua values into Objective C values
				LUAOBJC_ARGS_LUA_OBJECT(val, lua_idx)
				types[i] = &ffi_type_pointer;
				value_holders[i].ptr = (void *)val;
			} break;
			case ':': {
				LUAOBJC_ARGS_LUA_SEL(sel, lua_idx)
				types[i] = &ffi_type_pointer;
				value_holders[i].ptr = (void *)sel;
			} break;
			default: {
				if (arg_enc[0] == '^' && lua_isnil(L, lua_idx)) {
					types[i] = &ffi_type_pointer;
					value_holders[i].ptr = NULL;
				} else {
					lua_pushstring(L, "ffi call panic! invalid argument type");
					lua_error(L);
				}
			}
		}
	}
	
	// Setup and perform the actual FFI call
	if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, info->num_args, ret_type, types) != FFI_OK) {
		lua_pushstring(L, "ffi call panic! ffi_prep_cif failed");
		lua_error(L);
	}
	ffi_call(&cif, (void(*)(void))objc_msgSend, &ret_value, values);
	
	
	// Return (possibly) a value to Lua
	switch (info->sig[0]) {
		case 'c': {
			char val = ret_value.c;
			// since BOOL is a signed char, we can assume that if it is 0 or 1,
			// we'll just return a boolean.
			if (val == NO || val == YES) {
				lua_pushboolean(L, val);
			} else {
				lua_pushnumber(L, val);
			}
		} break;
		case 'i': {
			int val = ret_value.i;
			lua_pushnumber(L, val);
		} break;
		case 's': {
			short val = ret_value.s;
			lua_pushnumber(L, val);
		} break;
		case 'l': {
			long val = ret_value.l;
			lua_pushnumber(L, val);
		} break;
		case 'q': {
			long long val = ret_value.q;
			lua_pushnumber(L, val);
		} break;
		case 'C': {
			unsigned char val = ret_value.C;
			lua_pushnumber(L, val);
		} break;
		case 'I': {
			unsigned int val = ret_value.I;
			lua_pushnumber(L, val);
		} break;
		case 'S': {
			unsigned short val = ret_value.S;
			lua_pushnumber(L, val);
		} break;
		case 'L': {
			unsigned long val = ret_value.L;
			lua_pushnumber(L, val);
		} break;
		case 'Q': {
			unsigned long long val = ret_value.Q;
			lua_pushnumber(L, val);
		} break;
		case 'f': {
			float val = ret_value.f;
			lua_pushnumber(L, val);
		} break;
		case 'd': {
			double val = ret_value.d;
			lua_pushnumber(L, val);
		} break;
		case 'B': {
			_Bool val = ret_value.B;
			lua_pushboolean(L, val);
		} break;
		case 'v': return 0; // push nothing on void
		case '*': {
			const char *str = (const char *)ret_value.ptr;
			if (str == NULL)
				lua_pushnil(L);
			else
				lua_pushstring(L, str);
		} break;
		case '@': // Both objects and classes are treated they same by us
		case '#': {
			id val = (id)ret_value.ptr;
			luaobjc_object_push(L, val);
		} break;
		case ':': {
			SEL val = (SEL)ret_value.ptr;
			luaobjc_selector_push(L, val);
		} break;
		default: {
			lua_pushstring(L, "ffi call panic! invalid return type");
			lua_error(L);
		}
	}
	
	return 1;
}

static BOOL type_supported(const char *c) {
	switch (c[0]) {
		case 'c':
		case 'i':
		case 's':
		case 'l':
		case 'q':
		case 'C':
		case 'I':
		case 'S':
		case 'L':
		case 'Q':
		case 'f':
		case 'd':
		case 'B':
		case '*':
		case '@':
		case '#':
		case ':':
			return YES;
		default:
			return NO;
	}
}