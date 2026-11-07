# nogram — Telegram client for iOS 6, built with Theos.
#
#   make package FINALPACKAGE=1            -> packages/*.deb
#   make ipa FINALPACKAGE=1                -> packages/nogram.ipa
#
# Optional: bake in api credentials from my.telegram.org
#   make package TG_API_ID=12345 TG_API_HASH=0123456789abcdef0123456789abcdef
# Without them the app asks for api_id / api_hash on first launch.

TARGET := iphone:clang:9.3:6.0
ARCHS = armv7
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
# Vendored MtProtoKit/AFNetworking are full of legacy warnings.
GO_EASY_ON_ME = 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = nogram

MTPROTO_DIR = vendor/MTProtoKit
MTPROTO_MRC_FILES = $(MTPROTO_DIR)/AFHTTPClient.m $(MTPROTO_DIR)/AFHTTPRequestOperation.m $(MTPROTO_DIR)/AFJSONUtilities.m $(MTPROTO_DIR)/AFURLConnectionOperation.m

nogram_FILES = $(wildcard Sources/*.m) $(wildcard $(MTPROTO_DIR)/*.m)
nogram_CFLAGS = -fobjc-arc -Ivendor/include -I$(MTPROTO_DIR) -Ivendor/openssl/include \
	-Wno-deprecated-declarations -Wno-unused-parameter -Wno-nullability-completeness \
	-Wno-unused-variable -Wno-unused-function -Wno-objc-missing-super-calls \
	-Wno-strict-prototypes -Wno-incompatible-pointer-types-discards-qualifiers -Wno-unguarded-availability \
	-Wno-error -Wno-undef-prefix
nogram_LDFLAGS = vendor/openssl/lib/libcrypto.a -lz
nogram_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security SystemConfiguration CFNetwork MobileCoreServices

ifneq ($(TG_API_ID),)
nogram_CFLAGS += -DTG_API_ID=$(TG_API_ID) -DTG_API_HASH='"$(TG_API_HASH)"'
endif

# AFNetworking 1.x is manual retain/release.
$(foreach f,$(MTPROTO_MRC_FILES),$(eval $(f)_CFLAGS = -fno-objc-arc))

include $(THEOS_MAKE_PATH)/application.mk

TL_LAYER := $(shell cat tl/LAYER)

Resources/scheme.json: tl/telegram_api.tl tools/tl2json.py tl/LAYER
	python3 tools/tl2json.py tl/telegram_api.tl $(TL_LAYER) $@

before-all:: Resources/scheme.json

ipa: package
	rm -rf $(THEOS_PACKAGE_DIR)/Payload $(THEOS_PACKAGE_DIR)/nogram.ipa
	mkdir -p $(THEOS_PACKAGE_DIR)/Payload
	cp -R $(THEOS_STAGING_DIR)/Applications/nogram.app $(THEOS_PACKAGE_DIR)/Payload/
	cd $(THEOS_PACKAGE_DIR) && zip -qr nogram.ipa Payload && rm -rf Payload
	@echo "ipa: $(THEOS_PACKAGE_DIR)/nogram.ipa"
