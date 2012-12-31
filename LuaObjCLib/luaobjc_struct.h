//  Created by Darren Clark on 12-12-29.


#import "luaobjc.h"

LUAOBJC_EXTERN void luaobjc_struct_open(lua_State *L);

// Checks that a stack index is a struct and that the types match.
LUAOBJC_EXTERN void *luaobjc_struct_check(lua_State *L, int idx, const char *struct_name);
// Returns YES/NO depending on if object at index is _any_ kind of struct
LUAOBJC_EXTERN BOOL luaobjc_struct_is_struct(lua_State *L, int idx);

// Attempts to push a struct of type 'struct_name' and fill it with the values pointed to by 'data' (if data != NULL)
// On success, pushes a new struct and returns a pointer to it
// On failure, doesn't push anything and returns NULL
LUAOBJC_EXTERN void *luaobjc_struct_push(lua_State *L, const char *struct_name, void *data);