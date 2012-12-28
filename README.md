#LuaObjC - Objective C bindings for Lua

## Usage

### Warnings

- Still very much a WIP, not throughly tested!
- Only tested when building for iOS.  Should build for Mac, however you'll need to modify `build-luajit.sh` to build LuaJIT for Mac.  Also, may or may not work when compiling for 64 bit.

### Setup

- Use the `build-luajit.sh` script to build `libluajit.a`. If you aren't running Xcode 4.5 or want to support `armv6`, you may need to slightly tweak it.
- Include the LuaObjCLib folder and files in your Xcode project.
	- **NOTE: ARC is NOT supported. If you wish to use ARC, you will want to compile LuaObjCLib separately and link it with your binary**
- Setup Xcode to link your binary with `libluajit.a`

### Starting up LuaObjC

The `LuaContext` class handles creating a Lua context and initializing LuaObjC. It also supports running Lua files. For example, to run a file, `main.lua`, we can do this:

	LuaContext *context = [[LuaContext alloc] init];
	NSString *filePath = [[NSBundle mainBundle] pathForResource:@"main" ofType:@"lua"];
	[context doFile:filePath error:NULL];

### Lua API

- `objc.class(name)` - Get a reference to an Objective C class. You can then use this to create instances of that class:

		local NSMutableArray = objc.class("NSMutableArray")
		local myArray = NSMutableArray:array()

- Selectors are mapped to Lua functions by replacing all `:` with `_`. Trailing `_` are optional.

		-- to call 'replaceObject:atIndex:'
		myArray:replaceObject_atIndex(object, index)

- By default, all references to Objective-C objects are weak. To create a strong reference, use `objc.strong(object)` the object will be autoreleased when the Lua GC collects the object

		-- make myArray a strong reference
		objc.strong(myArray)
		-- if we change our mind, we can set it back to a weak reference (will also autorelease it now)
		objc.weak(myArray)

- Some Objective C types are automatically converted for you

	- NSString - string
	- NSNumber - number (or boolean)

- Sometimes you need to force a conversion, we can use `objc.to_objc` and `objc.to_lua`
	
		local desc = myArray:description()  -- desc is a Lua string
		desc = objc.to_objc(desc) 			-- desc is a NSString now
		
		-- We can also use to_objc and to_lua to convert tables <-> NSArray/NSDictionary
		local tbl = objc.to_lua(myArray)

- Each Objective C userdata has a table to attach your own values to!

		local myObject = objc.class("NSObject"):alloc():init()
		myObject.hello_world = "Hello World!"
		print(myObject.hello_world) -- prints "Hello World!"

		-- However, this is only per userdata:
		local myObject2 = myObject:retain() -- returns new userdata
		print(myObject2.hello_world) -- prints "nil"

		-- so you may want to make a point of passing around the userdata instead of getting new references to the same Objective C object:
		local myObject3 = myObject
		print(myObject3.hello_world) -- prints "Hello World!"


## License

Released under the MIT license - see LICENSE.
