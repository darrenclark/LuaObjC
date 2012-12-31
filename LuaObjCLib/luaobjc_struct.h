//  Created by Darren Clark on 12-12-29.


#import "luaobjc.h"

LUAOBJC_EXTERN void luaobjc_struct_open(lua_State *L);
// Checks that a stack index is a struct and that the types match.
LUAOBJC_EXTERN void *luaobjc_struct_check(lua_State *L, int idx, const char *struct_name);