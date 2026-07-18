# LocationMocker Tweak — Theos Makefile
# 构建: make package THEOS_PACKAGE_SCHEME=rootless
# 安装: make package install THEOS_DEVICE_IP=192.168.x.x

export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64 arm64e
export INSTALL_TARGET_PROCESSES = locationd SpringBoard

# rootless 兼容
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LocationMocker
$(TWEAK_NAME)_FILES = Tweak.x
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -I.
$(TWEAK_NAME)_FRAMEWORKS = UIKit CoreLocation Foundation
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = CoreLocation
$(TWEAK_NAME)_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 locationd SpringBoard 2>/dev/null; sbreload || respring"
