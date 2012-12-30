//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "luaobjc.h"
#import "luaobjc_object.h"

LUAOBJC_EXTERN_BEGIN
extern int luaobjc_fastcall_max_args;
lua_CFunction luaobjc_fastcall_get(luaobjc_method_info *info);
LUAOBJC_EXTERN_END