//  Created by Darren Clark on 12-12-26.

#import "luaobjc.h"

// SEL's are cached via a Lua table to avoid calling sel_getUid, as it uses
// a lock to avoid multithreading issues.  To avoid this for every Lua -> ObjC
// call, SEL's are cached in a Lua table.

LUAOBJC_EXTERN void luaobjc_sel_cache_open(lua_State *L);
LUAOBJC_EXTERN SEL luaobjc_get_sel(lua_State *L, const char *name);