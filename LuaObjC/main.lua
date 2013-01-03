-- Returns name of class to be used as the application delegate

-- Setup our path so we can include Lua files from our app bundle
local mainBundle = objc.class("NSBundle"):mainBundle()
local resourcePath = mainBundle:resourcePath()
package.path = package.path .. ";" .. resourcePath .. "/?.lua"

-- Load our LuaAppDelegate class and return the name of it
require "LuaAppDelegate"
return "LuaAppDelegate"