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
testClassInstance:testInstanceMethod("Woot!")

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
	local ret = testClassInstance[methodName](testClassInstance)
	print(methodName, type(ret), ret)
end

-- Struct tests
printHeader("'Unknown' tests")
local cgRect = testClassInstance:testStruct()
testClassInstance:testStructPt2(cgRect)

-- Disabled because on ARM performSelector w/ a method returning void gives a
-- gibberish value
--
--local sel = testClassInstance:testSelector()
--testClassInstance:performSelector(sel)

-- Table access test
printHeader("Table access tests")
testClassInstance.testLuaValue = 5
testClassInstance.testLuaFunc = function()
	print("testClassInstance.testLuaFunc() called!")
end

print("testClassInstance.testValue = " .. testClassInstance.testLuaValue)
testClassInstance.testLuaFunc()


-- Conversion
printHeader("Conversions")
local dict = {}
dict["five"] = 5
dict["two"] = 2
dict["string"] = "Hello, World!"
dict["bool"] = true
print("Dict: " .. objc.to_objc(dict):description())

local array = {}
array[#array+1] = 5
array[#array+1] = 2
array[#array+1] = "Hello, World!"
array[#array+1] = true
print("Array: " .. objc.to_objc(array):description())

print("tostring: " .. tostring(testClassInstance))

local mutableArray = objc.class("NSMutableArray"):array()
mutableArray:addObject("Hello")
mutableArray:addObject("World")
mutableArray:addObject("!")

local luaArray = objc.to_lua(mutableArray)
print("Lua array:")
table.foreach(luaArray, print)

local mutableDict = objc.class("NSMutableDictionary"):dictionary()
mutableDict:setObject_forKey("Test", "string")
mutableDict:setObject_forKey(40, "number")
mutableDict:setObject_forKey(true, "bool")

local luaDict = objc.to_lua(mutableDict)
print("Lua dictionary:")
table.foreach(luaDict, print)

-- Test strong/weak
local instance = testClass:alloc():init():autorelease()
objc.strong(instance)

-- let GC collect it and then release it
instance = nil

-- Selectors
printHeader("Selectors")
local sel = objc.sel("description")
print("objc.sel('description'): " .. tostring(sel))

-- Benchmarks
printHeader("Benchmarks")

for j = 1, 5 do
	collectgarbage("stop")
	objc.benchmark_start("Func call speed")
	for i = 0, 5000 do
		testClassInstance:emptyMethod()
	end
	objc.benchmark_end("Func call speed")
	collectgarbage("collect")
end

-- End
printHeader("... Done tests")