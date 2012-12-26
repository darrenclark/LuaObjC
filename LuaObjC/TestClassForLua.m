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


- (BOOL)boolTest {
	return YES;
}

- (int)intTest {
	return 1;
}

- (short)shortTest {
	return 2;
}

- (long)longTest {
	return 3;
}

- (long long)longLongTest {
	return 4;
}

- (unsigned char)unsignedCharTest {
	return 5;
}

- (unsigned int)unsignedIntTest {
	return 6;
}

- (unsigned short)unsignedShortTest {
	return 7;
}

- (unsigned long)unsignedLongTest {
	return 8;
}

- (unsigned long long)unsignedLongLongTest {
	return 9;
}

- (float)floatTest {
	return 11.1992;
}

- (double)doubleTest {
	return 5.11;
}

- (_Bool)cBoolTest {
	return true;
}

- (void)voidTest {
	return;
}

- (char *)charStringTest {
	return "Hello world!";
}

- (const char *)constCharStringTest {
	return "Hello world! (const)";
}

- (id)objectTest {
	return [NSDictionary dictionary];
}

- (Class)classTest {
	return [NSArray class];
}

@end
