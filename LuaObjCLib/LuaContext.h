//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import <Foundation/Foundation.h>

#import "lua.h"
#import "lualib.h"
#import "lauxlib.h"


extern NSString *LuaContextErrorDomain;


@interface LuaContext : NSObject

@property (nonatomic, readonly) lua_State *lua;

- (BOOL)doFile:(NSString *)fullPath error:(NSError **)error;

@end
