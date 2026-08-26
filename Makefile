THEOS_DEVICE_IP = 192.168.50.53
THEOS_DEVICE_PORT = 22
THEOS_DEVICE_USER = root

INSTALL_TARGET_PROCESSES = HASmartboard
TARGET = iphone:clang:12.2:12.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = HASmartboard

HASmartboard_FILES = \
    App/main.m \
    App/AppDelegate.m \
    App/KioskViewController.m \
    App/ScreensaverView.m \
    App/NetworkMonitor.m \
    App/DaemonBridge.m \
    App/TelemetryRelay.m

HASmartboard_CFLAGS = -IApp
HASmartboard_FRAMEWORKS = UIKit Foundation WebKit CoreGraphics
HASmartboard_PRIVATE_FRAMEWORKS = BackBoardServices

include $(THEOS_MAKE_PATH)/application.mk

SUBPROJECTS += Daemon
include $(THEOS_MAKE_PATH)/aggregate.mk
