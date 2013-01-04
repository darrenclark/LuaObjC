-- Returns name of class to be used as the application delegate

-- Setup our path so we can include Lua files from our app bundle
local mainBundle = objc.class("NSBundle"):mainBundle()
local resourcePath = mainBundle:resourcePath()
package.path = package.path .. ";" .. resourcePath .. "/?.lua"

-- Define some common structs
CGRect = objc.struct.def("CGRect", "ffff", {"x","y","width","height"})
CGPoint = objc.struct.def("CGPoint", "ff", {"x","y"})
CGSize = objc.struct.def("CGSize", "ff", {"width","height"})

-- Load our LuaAppDelegate class and return the name of it
require "LuaAppDelegate"
return "LuaAppDelegate"