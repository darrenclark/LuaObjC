//  Created by Darren Clark on 12-12-28.

#import "luaobjc.h"

LUAOBJC_EXTERN void luaobjc_selector_open(lua_State *L);

// check that the arg at idx is a selector
LUAOBJC_EXTERN SEL luaobjc_selector_check(lua_State *L, int idx);
// check that the arg at idx is a selector OR string. if string, returns SEL
// that corresponds to that name
LUAOBJC_EXTERN SEL luaobjc_selector_check_s(lua_State *L, int idx);

// push a selector
LUAOBJC_EXTERN void luaobjc_selector_push(lua_State *L, SEL sel);
// push a selector from its name
LUAOBJC_EXTERN void luaobjc_selector_push_s(lua_State *L, const char *name);