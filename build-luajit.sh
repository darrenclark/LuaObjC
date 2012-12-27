#!/bin/sh

# make sure we have luajit cloned and up-to-date
git submodule update --init ./luajit-2.0

# which archs to build
archs="i386 armv7 armv7s"

# which iphone sdk to use?
sdk_ver="6.0"

# some prep work
rm -vf libluajit.a
rm -rfv luajit-build
mkdir -v luajit-build
cd luajit-2.0/src

# start building!
for arch in $archs; do
	echo "========================================"
	echo "=== Building $arch "
	echo "========================================"

	make clean
	
	IXCODE=`xcode-select -print-path`

	# if we are doing a build for the simulator, make sure we are pointing to iPhoneSimulator
	if [ "$arch" == "i386" ]; then
		ISDK=$IXCODE/Platforms/iPhoneSimulator.platform/Developer
		ISDKVER="iPhoneSimulator$sdk_ver.sdk"
	fi
	# if we are doing a build for the device, make sure we are pointing to iPhoneOS
	if [ "$arch" != "i386" ]; then
		ISDK=$IXCODE/Platforms/iPhoneOS.platform/Developer
		ISDKVER="iPhoneOS$sdk_ver.sdk"
	fi

	ISDKP=$ISDK/usr/bin/
	ISDKF="-arch $arch -isysroot $ISDK/SDKs/$ISDKVER"
	make HOST_CC="clang -m32 -arch i386" CROSS=$ISDKP TARGET_FLAGS="$ISDKF" \
	     TARGET_SYS=iOS

	cp -v libluajit.a ../../luajit-build/$arch
done

# create our fat binary
cd ../../luajit-build
lipo -create $archs -o ../libluajit.a

# clean up some of our mess
cd ..
rm -rf luajit-build
