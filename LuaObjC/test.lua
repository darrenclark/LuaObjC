print("Hello, world!")

local function printHeader(title)
	print("")
	print("-----------")
	print("-- " .. title)
	print("-----------")
end

-- Misc. tests
printHeader("Misc. tests")
local NSString = objc.class("NSString")
print("NSString:", NSString, "metatable:", getmetatable(NSString))

local testClass = objc.class("TestClassForLua")
testClass:testMethod()
testClass:dynamicMethod()

local testClassInstance = testClass:alloc():init()
print(testClassInstance, testClassInstance:description())


-- Test return values
printHeader("Test return values")
local returnTestMethods = {
	"boolTest",
	"intTest",
	"shortTest",
	"longTest",
	"longLongTest",
	"unsignedCharTest",
	"unsignedIntTest",
	"unsignedShortTest",
	"unsignedLongTest",
	"unsignedLongLongTest",
	"floatTest",
	"doubleTest",
	"cBoolTest",
	"voidTest",
	"charStringTest",
	"constCharStringTest",
	"objectTest",
	"classTest"
}

for i, methodName in ipairs(returnTestMethods) do
	local ret = testClassInstance[methodName]()
	print(methodName, type(ret), ret)
end

-- Struct tests
printHeader("'Unknown' tests")
local cgRect = testClassInstance:testStruct()
print(cgRect, getmetatable(cgRect))
local sel = testClassInstance:testSelector()
print(sel, getmetatable(sel))

-- End
printHeader("... Done tests")