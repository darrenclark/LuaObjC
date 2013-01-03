//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import <Foundation/Foundation.h>

#import "luaobjc.h"


extern NSString *LuaContextErrorDomain;


@interface LuaContext : NSObject

@property (nonatomic, readonly) lua_State *lua;

// On Success: Returns result of running file 'fullPath' and sets error to nil
// On Failure: Returns nil and returns an NSError through 'error'
- (id)doFile:(NSString *)fullPath error:(NSError **)error;

@end
