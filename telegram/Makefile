# Original Telegram iOS 4.9.1 (peter-iakovlev/Telegram), built with Theos for iOS 6 / armv7.
#
#   make package FINALPACKAGE=1 [TG_API_ID=... TG_API_HASH=...]
#   make ipa FINALPACKAGE=1
#
# Upstream builds LegacyComponents, SSignalKit, Lottie, libtgvoip and MtProtoKit as
# embedded dynamic frameworks, which iOS 6 cannot load; here they are all compiled
# statically into the app binary. File lists come from the Xcode projects via
# tools/gen-telegram-mk.py (sources.mk).

TARGET := iphone:clang:11.4:6.0
ARCHS = armv7
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
GO_EASY_ON_ME = 1

include $(THEOS)/makefiles/common.mk
include sources.mk

# Theos' vendor/include ships private-header replacements for UIKit, Foundation,
# MobileCoreServices, MapKit... that shadow the SDK and break this code base.
THEOS_VENDOR_INCLUDE_PATH := $(THEOS_PROJECT_DIR)/include

APPLICATION_NAME = Telegram

MTPROTO_DIR = vendor/MtProtoKit-4.9.1
MTPROTO_MRC_FILES = $(MTPROTO_DIR)/AFHTTPClient.m $(MTPROTO_DIR)/AFHTTPRequestOperation.m $(MTPROTO_DIR)/AFJSONUtilities.m $(MTPROTO_DIR)/AFURLConnectionOperation.m
MTPROTO_FILES = $(wildcard $(MTPROTO_DIR)/*.m)

Telegram_FILES = $(TG_APP_FILES) $(TG_LEGACYCOMPONENTS_FILES) $(TG_SSIGNALKIT_FILES) $(TG_LOTTIE_FILES) $(TG_VOIP_FILES) $(MTPROTO_FILES)

# Xcode resolved "Foo.h" through header maps; emulate that with -iquote for every header dir.
TG_QUOTE_DIRS = . Share Telegraph Telegraph/API Telegraph/AdHoc Telegraph/thirdparty/ogg/ogg Telegraph/thirdparty/opusenc \
	Telegraph/thirdparty/opusfile Watch/Bridge legacy/TL legacy/TL/TL legacy/TelegraphKit legacy/TelegraphKit/Third-Party/FMDB \
	submodules/LegacyComponents/LegacyComponents thirdparty thirdparty/Lottie/lottie-ios/Classes/AnimatableLayers \
	thirdparty/Lottie/lottie-ios/Classes/AnimatableProperties thirdparty/Lottie/lottie-ios/Classes/Extensions \
	thirdparty/Lottie/lottie-ios/Classes/MacCompatability thirdparty/Lottie/lottie-ios/Classes/Models \
	thirdparty/Lottie/lottie-ios/Classes/Private thirdparty/Lottie/lottie-ios/Classes/PublicHeaders \
	thirdparty/Lottie/lottie-ios/Classes/RenderSystem thirdparty/Lottie/lottie-ios/Classes/RenderSystem/AnimatorNodes \
	thirdparty/Lottie/lottie-ios/Classes/RenderSystem/InterpolatorNodes thirdparty/Lottie/lottie-ios/Classes/RenderSystem/ManipulatorNodes \
	thirdparty/Lottie/lottie-ios/Classes/RenderSystem/RenderNodes thirdparty/RMIntro/3rdparty/linmath thirdparty/RMIntro/core \
	thirdparty/RMIntro/platform/common thirdparty/RMIntro/platform/ios thirdparty/SSignalKit/SSignalKit thirdparty/Stripe \
	thirdparty/lz4 thirdparty/sqlcipher thirdparty/VideoEncoder $(MTPROTO_DIR) \
	submodules/libtgvoip submodules/libtgvoip/webrtc_dsp

Telegram_CFLAGS = -fobjc-arc -include BuildConfig.h \
	-Iinclude -Ivendor/openssl/include -Ilegacy/TelegraphKit -Ilegacy/TL/TL -Ilegacy/TL -Ithirdparty/SSignalKit \
	-Isubmodules/libtgvoip -Isubmodules/libtgvoip/webrtc_dsp -Ithirdparty/Lottie/lottie-ios/Classes/PublicHeaders \
	-ITelegraph/thirdparty/ogg -ITelegraph/thirdparty/opus/include -ITelegraph/thirdparty/opus/include/opus -ITelegraph \
	-Ithirdparty/Stripe \
	$(foreach d,$(TG_QUOTE_DIRS),-iquote $(d)) \
	-DNS_BLOCK_ASSERTIONS -DSQLITE_TEMP_STORE=2 -DSQLITE_HAS_CODEC=1 -DSQLCIPHER_CRYPTO_CC=1 -DSQLITE_ENABLE_FTS3 \
	-DTGVOIP_USE_CUSTOM_CRYPTO -DWEBRTC_APM_DEBUG_DUMP=0 -DWEBRTC_POSIX -DTGVOIP_HAVE_TGLOG \
	-Wno-everything -Wno-error -ferror-limit=0
Telegram_CCFLAGS = -std=gnu++11 -stdlib=libc++
Telegram_LDFLAGS = -ObjC -stdlib=libc++ \
	vendor/openssl/lib/libcrypto.a thirdparty/WebP.framework/WebP Telegraph/thirdparty/opus/lib/libopus.a \
	Telegraph/thirdparty/HockeySDK-iOS-3/HockeySDK.embeddedframework/HockeySDK.framework/HockeySDK \
	-lz -lc++ -licucore

# Present on iOS 6.
Telegram_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security SystemConfiguration CFNetwork MobileCoreServices \
	AVFoundation AudioToolbox CoreMedia CoreVideo ImageIO MediaPlayer AssetsLibrary MapKit MessageUI CoreTelephony \
	CoreLocation AddressBook AddressBookUI CoreText Accelerate OpenGLES GLKit QuickLook CoreImage CoreMotion PassKit
# Newer than iOS 6: weak-linked, upstream already checks availability at runtime.
Telegram_WEAK_FRAMEWORKS = Photos PhotosUI Contacts ContactsUI CallKit Intents PushKit WebKit SafariServices \
	LocalAuthentication VideoToolbox CoreSpotlight AVKit Vision WatchConnectivity CloudKit NotificationCenter

ifneq ($(TG_API_ID),)
Telegram_CFLAGS += -DTG_API_ID=$(TG_API_ID) -DTG_API_HASH='"$(TG_API_HASH)"'
endif

# Upstream prefix header only applies to the app target.
$(foreach f,$(TG_APP_FILES),$(eval $(f)_CFLAGS += -include Telegraph/Telegraph-Prefix.pch))
# AFNetworking 1.x inside MtProtoKit is manual retain/release.
$(foreach f,$(MTPROTO_MRC_FILES),$(eval $(f)_CFLAGS += -fno-objc-arc))

include $(THEOS_MAKE_PATH)/application.mk

ipa: package
	rm -rf $(THEOS_PACKAGE_DIR)/Payload $(THEOS_PACKAGE_DIR)/Telegram.ipa
	mkdir -p $(THEOS_PACKAGE_DIR)/Payload
	cp -R $(THEOS_STAGING_DIR)/Applications/Telegram.app $(THEOS_PACKAGE_DIR)/Payload/
	cd $(THEOS_PACKAGE_DIR) && zip -qr Telegram.ipa Payload && rm -rf Payload
	@echo "ipa: $(THEOS_PACKAGE_DIR)/Telegram.ipa"
