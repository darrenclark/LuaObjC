local cls = objc.new_class("LuaClass", "NSObject")

function cls:description()
	return "Woo-hoo, method overriden!!"
end

function cls:testMethod()
	print("[LuaClass testMethod] called!")
end

cls:register()