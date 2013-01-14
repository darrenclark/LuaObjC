local super = objc.new_class("LuaSuperClass", "NSObject")
super:register()

function super:init()
	self = objc.super(self, "init")
	if self == nil then
		return nil
	end
	
	print("LuaSuperClass init")
	return self
end

function super:theMethod()
	print("LuaSuperClass method called!")
end


local sub = objc.new_class("LuaSubClass", "LuaSuperClass")
sub:register()

function sub:init()
	self = objc.super(self, "init")
	if self == nil then
		return nil
	end
	
	print("LuaSubClass init")
	return self
end

function sub:theMethod()
	print("LuaSubClass method called!")
end