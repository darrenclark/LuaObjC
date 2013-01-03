local cls = objc.new_class("LuaClass", "NSObject", {"UIAlertViewDelegate"})

function cls:description()
	return "Woo-hoo, method overriden!!"
end

function cls:testMethod()
	print("[LuaClass testMethod] called! description is: " .. self:description())
end

function cls:argTest_(arg)
	print("[LuaClass argTest:] called! arg is: " .. tostring(arg))
end

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

cls:register()