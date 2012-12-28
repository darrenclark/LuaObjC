//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc.h"

LUAOBJC_EXTERN_BEGIN
extern int luaobjc_fastcall_max_args;
lua_CFunction luaobjc_fastcall_get(char ret, const char *args);
LUAOBJC_EXTERN_END