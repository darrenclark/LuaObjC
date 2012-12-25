//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "LuaContext.h"

NSString *LuaContextErrorDomain = @"LuaContextError";

@interface LuaContext () {
	lua_State *lua_;
}

@end


@implementation LuaContext

@synthesize lua = lua_;

- (id)init {
	self = [super init];
	if (!self)
		return nil;
	
	lua_ = luaL_newstate();
	luaL_openlibs(lua_);
	luaobjc_open(lua_);
	
	return self;
}

- (void)dealloc {
	lua_close(lua_);
	[super dealloc];
}

- (BOOL)doFile:(NSString *)fullPath error:(NSError **)error {
	int ret = luaL_loadfile(lua_, [fullPath UTF8String]);
	if (ret != LUA_OK) {
		if (error != NULL)
			*error = [self readLuaError:ret];
		lua_pop(lua_, 1);
		return NO;
	}
	
	ret = lua_pcall(lua_, 0, 0, 0);
	if (ret != LUA_OK) {
		if (error != NULL)
			*error = [self readLuaError:ret];
		lua_pop(lua_, 1);
		return NO;
	}
	
	return YES;
}

- (NSError *)readLuaError:(int)errorCode {
	const char *errorString = lua_tostring(lua_, -1);
	if (errorString == NULL) {
		errorString = "Unknown error";
	}
	
	NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithUTF8String:errorString]
														 forKey:NSLocalizedDescriptionKey];
	return [NSError errorWithDomain:LuaContextErrorDomain
							   code:errorCode
						   userInfo:userInfo];
}

@end
