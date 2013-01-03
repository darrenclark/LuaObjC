local cls = objc.new_class("LuaAppDelegate", "UIResponder", {"UIApplicationDelegate"})
cls:property("window", objc.RETAIN)
cls:register()

function cls:application_didFinishLaunchingWithOptions_(application, options)
	local frame = objc.class("UIScreen"):mainScreen():bounds();
	local window = objc.class("UIWindow"):alloc():initWithFrame(frame):autorelease()
	window:setBackgroundColor(objc.class("UIColor"):whiteColor())
	window:makeKeyAndVisible()
	
	self:setWindow(window)
	
	self:performSelector_withObject_afterDelay_(objc.sel("runLuaTests"), nil, .5)
	
	return true
end

function cls:runLuaTests()
	require 'test'
end