TARGET = iphone:clang:12.2:12.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = kioskd

kioskd_FILES = \
    main.m \
    TelemetryCollector.m \
    HTTPServer.m \
    HAReporter.m \
    DeviceControl.m

kioskd_CFLAGS = -I.
kioskd_FRAMEWORKS = IOKit Foundation
kioskd_PRIVATE_FRAMEWORKS = MobileWiFi BackBoardServices

kioskd_INSTALL_PATH = /Library/Application\ Support/HASmartboard

include $(THEOS_MAKE_PATH)/tool.mk
