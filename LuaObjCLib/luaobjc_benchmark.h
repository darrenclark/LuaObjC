//  Created by Darren Clark on 12-12-26.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.


#import "luaobjc.h"

// Adds really basic methods for really easy performance testing
// 
// Added methods:
//	objc.benchmark_start(name)
//	objc.benchmark_end(name)

LUAOBJC_EXTERN void luaobjc_benchmark_open(lua_State *L);