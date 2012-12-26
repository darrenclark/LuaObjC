//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.


#import "TestClassForLua.h"

@implementation TestClassForLua

+ (void)testMethod {
	NSLog(@"+testMethod called!");
}


+ (BOOL)respondsToSelector:(SEL)aSelector {
	if ([NSStringFromSelector(aSelector) isEqualToString:@"dynamicMethod"])
		return YES;
	else
		return [super respondsToSelector:aSelector];
}

+ (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
	if ([NSStringFromSelector(aSelector) isEqualToString:@"dynamicMethod"]) {
		NSMethodSignature *methodSig = [NSMethodSignature signatureWithObjCTypes:"v@:"];
		return methodSig;
	} else {
		return [super methodSignatureForSelector:aSelector];
	}
}

+ (void)forwardInvocation:(NSInvocation *)anInvocation {
	if ([NSStringFromSelector(anInvocation.selector) isEqualToString:@"dynamicMethod"]) {
		NSLog(@"+dynamicMethod called!");
	} else {
		[super forwardInvocation:anInvocation];
	}
}

@end
