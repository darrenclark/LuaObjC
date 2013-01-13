//  Created by Darren Clark on 12-12-25.
//  Copyright (c) 2012 Darren Clark. All rights reserved.

// Used for testing features of LuaObjCLib as they are developed


#import <Foundation/Foundation.h>

// used in LuaClass to test passing structs to ObjC methods implemented in Lua
@protocol RectTest <NSObject>
@optional
- (void)setRect:(CGRect)rect;
- (CGRect)rect;
- (void)setPt:(CGPoint)pt;
- (CGPoint)pt;
@end


@interface TestClassForLua : NSObject <RectTest>

+ (void)testMethod;

- (void)testInstanceMethod:(NSString *)string;

- (CGRect)testStruct;
- (void)testStructPt2:(CGRect)rect;
- (SEL)testSelector;
- (id)testSelectorPt2;

- (CGAffineTransform)unknownPt1;
- (void)unknownPt2:(CGAffineTransform)unknown;

- (void)printRect:(CGRect)rect;

- (int)a:(int)a benchmark:(BOOL)benchmark method:(double)method;
- (void)emptyMethod;

- (BOOL)boolTest;
- (int)intTest;
- (short)shortTest;
- (long)longTest;
- (long long)longLongTest;
- (unsigned char)unsignedCharTest;
- (unsigned int)unsignedIntTest;
- (unsigned short)unsignedShortTest;
- (unsigned long)unsignedLongTest;
- (unsigned long long)unsignedLongLongTest;
- (float)floatTest;
- (double)doubleTest;
- (_Bool)cBoolTest;
- (void)voidTest;
- (char *)charStringTest;
- (const char *)constCharStringTest;
- (id)objectTest;
- (Class)classTest;

- (void)breakpoint;

- (NSString *)underscore_method:(NSString *)msgPt1 _pt2:(NSString *)msgPt2;

@end
