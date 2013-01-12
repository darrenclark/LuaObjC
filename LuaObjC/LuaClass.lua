local cls = objc.new_class("LuaClass", "NSObject", {"UIAlertViewDelegate", "RectTest"})
cls:property("rectObj", objc.RETAIN)
cls:property("pointObj", objc.RETAIN)
cls:register()

cls:decl("+someClassMethod:")
function cls:someClassMethod_(obj)
	print(tostring(obj))
	return obj
end

function cls:description()
	return "Woo-hoo, method overriden!!"
end

function cls:testMethod()
	print("[LuaClass testMethod] called! description is: " .. self:description())
end

function cls:argTest_(arg)
	print("[LuaClass argTest:] called! arg is: " .. tostring(arg))
end

-- Struct tests

function cls:setRect_(rect)
	self:setRectObj(objc.class("NSValue"):valueWithCGRect(rect))
end

function cls:rect()
	return self:rectObj():CGRectValue()
end

function cls:setPt_(point)
	self:setPointObj(objc.class("NSValue"):valueWithCGPoint(point))
end

function cls:pt()
	return self:pointObj():CGPointValue()
end

-- UIAlertView stuff

function cls:showAlert()
	local alertView = objc.class("UIAlertView"):alloc()
	alertView:initWithTitle_message_delegate_cancelButtonTitle_otherButtonTitles_(
		"Hello World!", "This is all from Lua, woot!", self, "Cancel", nil
	)
	alertView:show()
	alertView:autorelease()
end

function cls:alertView_clickedButtonAtIndex_(alertView, buttonIndex)
	print("[LuaClass] Clicked button at index: " .. buttonIndex)
end