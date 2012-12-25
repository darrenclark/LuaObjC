print("Hello, world!")

local NSString = objc.class("NSString")
print("NSString:", NSString, "metatable:", getmetatable(NSString))
