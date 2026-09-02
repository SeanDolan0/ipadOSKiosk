ifndef THEOS
$(error THEOS is not set. In WSL run: export THEOS=$$HOME/theos)
endif

THEOS_DEVICE_IP = 192.168.50.53
THEOS_DEVICE_PORT = 22
THEOS_DEVICE_USER = root

INSTALL_TARGET_PROCESSES = HASmartboard
TARGET = iphone:clang:12.4:12.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = HASmartboard

HASmartboard_FILES = \
    App/main.m \
    App/AppDelegate.m \
    App/KioskViewController.m \
    App/SettingsViewController.m \
    App/ScreensaverView.m \
    App/NetworkMonitor.m \
    App/DaemonBridge.m \
    Daemon/MQTTClient.c

HASmartboard_CFLAGS = -IApp -IDaemon -fobjc-arc
HASmartboard_FRAMEWORKS = UIKit Foundation WebKit CoreGraphics IOKit AVFoundation AudioToolbox
HASmartboard_PRIVATE_FRAMEWORKS = BackBoardServices
HASmartboard_RESOURCE_FILES = HASmartboard/Info.plist Resources/SwipeNav.js

include $(THEOS_MAKE_PATH)/application.mk

SUBPROJECTS += Daemon
include $(THEOS_MAKE_PATH)/aggregate.mk
