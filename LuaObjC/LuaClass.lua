local cls = objc.new_class("LuaClass", "NSObject")

function cls:description()
	return "Woo-hoo, method overriden!!"
end

cls:register()