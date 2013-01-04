local cls = objc.new_class("LuaClass", "NSObject", {"UIAlertViewDelegate", "RectTest"})
cls:property("x", objc.RETAIN)
cls:property("y", objc.RETAIN)
cls:property("width", objc.RETAIN)
cls:property("height", objc.RETAIN)
cls:register()

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

-- TEMP FIX. PROPERTIES ARE BROKEN
local savedRect = CGRect(0,0,0,0)
local savedPt = CGPoint(1,1)
function cls:setRect_(rect)
	--savedRect = rect
	savedPt = rect
end

function cls:rect()
	--return savedRect
	return savedPt
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