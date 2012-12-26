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

-- Benchmarks
printHeader("Benchmarks")

for j = 1, 5 do
	collectgarbage("stop")
	objc.benchmark_start("Func call speed")
	for i = 0, 1000 do
		testClassInstance:a_benchmark_method(i, true, 56.6)
	end
	objc.benchmark_end("Func call speed")
	collectgarbage("collect")
end

-- End
printHeader("... Done tests")