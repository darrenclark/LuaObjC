//  Created by Darren Clark on 12-12-28.

// Contains macros for reading args from Lua.
// Format:
//	LUAOBJC_ARGS_LUA_(type)
// where:
//	(type) -> which type:
//		CHAR - handles bool/char
//		NUMBER - handles any numbers
//		BOOL - C/C++ _Bool/bool
//		CSTRING - char * string
//		OBJECT - Objective-C object
//		SEL - selector


// -----------
// Lua -> C macros
// -----------

#define LUAOBJC_ARGS_LUA_CHAR(_var_, _idx_)	\
	char _var_;												\
	if (lua_isboolean(L, _idx_)) {							\
		_var_ = lua_toboolean(L, _idx_);					\
	} else {												\
		_var_ = luaL_checknumber(L, _idx_);					\
	}

#define LUAOBJC_ARGS_LUA_NUMBER(_var_, _idx_, _type_) \
	_type_ _var_ = luaL_checknumber(L, _idx_);

#define LUAOBJC_ARGS_LUA_BOOL(_var_, _idx_) \
	luaL_argcheck(L, lua_isboolean(L, _idx_), _idx_, "`boolean' expected"); \
	_Bool _var_ = lua_toboolean(L, _idx_);

#define LUAOBJC_ARGS_LUA_CSTRING(_var_, _idx_) \
	const char *_var_ = NULL;								\
	{														\
		BOOL isstring = lua_isstring(L, _idx_);				\
		BOOL isnil = lua_isnil(L, _idx_);					\
		luaL_argcheck(L, isstring || isnil, _idx_, "`string' expected"); \
															\
		if (isstring)										\
			_var_ = lua_tostring(L, _idx_);					\
	}

#define LUAOBJC_ARGS_LUA_OBJECT(_var_, _idx_) \
	id _var_ = nil;											\
	{														\
		if (lua_isnumber(L, _idx_)) {						\
			double tmp_ = lua_tonumber(L, _idx_);			\
			_var_ = [NSNumber numberWithDouble:tmp_];		\
		} else if (lua_isboolean(L, _idx_)) {				\
			BOOL tmp_ = lua_toboolean(L, _idx_);			\
			_var_ = [NSNumber numberWithBool:tmp_];			\
		} else if (lua_isstring(L, _idx_)) {				\
			const char *tmp_ = lua_tolstring(L, _idx_, NULL);	\
			_var_ = [NSString stringWithUTF8String:tmp_];	\
		} else {											\
			_var_ = luaobjc_object_check_or_nil(L, _idx_);	\
		}													\
	}

#define LUAOBJC_ARGS_LUA_SEL(_var_, _idx_) \
	SEL _var_ = NULL;										\
	if (!lua_isnil(L, _idx_))								\
		_var_ = luaobjc_selector_check(L, _idx_);
