//
//  main.m
//  LuaObjC
//
//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "LuaContext.h"

int main(int argc, char *argv[])
{
	@autoreleasepool {
		LuaContext *context = [[LuaContext alloc] init];
		
		NSString *luaFilePath = [[NSBundle mainBundle] pathForResource:@"main" ofType:@"lua"];
		
		NSError *error;
		id result = [context doFile:luaFilePath error:&error];
		if (error != nil)
			NSLog(@"Error running '%@': %@", luaFilePath, error.localizedDescription);
		
	    return UIApplicationMain(argc, argv, nil, result);
	}
}
