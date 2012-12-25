//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#ifdef __cplusplus
#define LUAOBJC_EXTERN			extern "C"
#define LUAOBJC_EXTERN_BEGIN	extern "C" {
#define LUAOBJC_EXTERN_END		}
#else
#define LUAOBJC_EXTERN
#define LUAOBJC_EXTERN_BEGIN
#define LUAOBJC_EXTERN_END
#endif

LUAOBJC_EXTERN_BEGIN
#import "lua.h"
#import "lualib.h"
#import "lauxlib.h"
LUAOBJC_EXTERN_END


LUAOBJC_EXTERN void luaobjc_open(lua_State *L);