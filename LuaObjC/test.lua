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
printHeader("Struct tests")
CGRect = objc.struct.def("CGRect", "ffff", {"x","y","width","height"})
print(tostring(CGRect))

local myRect = CGRect(10.0, 20.0, 30.0, 40.0)
for i, field in ipairs{"x", "y", "width", "height"} do
	myRect[field] = myRect[field] + 5.0
	print("CGRect", field, myRect[field])
end

testClassInstance:printRect(myRect)
testClassInstance:printRect(testClassInstance:testStruct())

testClassInstance:unknownPt2(testClassInstance:unknownPt1())

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
print(testClassInstance:performSelector(sel))

sel = testClassInstance:testSelector()
testClassInstance:performSelector(sel)

-- Benchmarks
printHeader("Benchmarks")

for j = 1, 5 do
	collectgarbage("stop")
	objc.benchmark_start("Func lookup speed")
	for i = 0, 5000 do
		local method = testClassInstance.emptyMethod
		testClassInstance.emptyMethod = nil
	end
	objc.benchmark_end("Func lookup speed")
	collectgarbage("collect")
end

for j = 1, 5 do
	collectgarbage("stop")
	objc.benchmark_start("Fast call speed")
	for i = 0, 5000 do
		testClassInstance:emptyMethod()
	end
	objc.benchmark_end("Fast call speed")
	collectgarbage("collect")
end

for j = 1, 5 do
	collectgarbage("stop")
	objc.benchmark_start("FFI call speed")
	for i = 0, 5000 do
		testClassInstance:charStringTest()
	end
	objc.benchmark_end("FFI call speed")
	collectgarbage("collect")
end

for j = 1, 5 do
	collectgarbage("stop")
	objc.benchmark_start("Slow call speed")
	for i = 0, 5000 do
		testClassInstance:testStruct()
	end
	objc.benchmark_end("Slow call speed")
	collectgarbage("collect")
end

-- Class tests
printHeader("Classes")

-- Setup our path so we can include LuaClass
local mainBundle = objc.class("NSBundle"):mainBundle()
local resourcePath = mainBundle:resourcePath()
package.path = package.path .. ";" .. resourcePath .. "/?.lua"


require("LuaClass")
local luaObj = objc.class("LuaClass"):alloc():init():autorelease()
print(tostring(luaObj))
luaObj:testMethod()

-- End
printHeader("... Done tests")