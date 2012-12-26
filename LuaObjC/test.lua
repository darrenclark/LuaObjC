print("Hello, world!")

local NSString = objc.class("NSString")
print("NSString:", NSString, "metatable:", getmetatable(NSString))

local testClass = objc.class("TestClassForLua")
testClass:testMethod()
