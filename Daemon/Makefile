TARGET = iphone:clang:12.4:12.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = kioskd

kioskd_FILES = \
    main.m \
    KioskConfig.m \
    TelemetryCollector.m \
    HTTPServer.m \
    DeviceControl.m

kioskd_CFLAGS = -I. -fobjc-arc
kioskd_FRAMEWORKS = IOKit Foundation
kioskd_PRIVATE_FRAMEWORKS = MobileWiFi
kioskd_LDFLAGS = -Wl,-undefined,dynamic_lookup

kioskd_INSTALL_PATH = /Library/Application Support/HASmartboard

include $(THEOS_MAKE_PATH)/tool.mk
