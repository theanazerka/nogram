#!/bin/bash
# Fast local compile check of one source file of telegram/ without Theos/ld64.
# Uses the host clang (Linux works) against an iPhoneOS 11.4 SDK.
#
#   SDK=/path/to/iPhoneOS11.4.sdk tools/local-syntax-check.sh telegram/Telegraph/TGAppDelegate.mm
#   # all files, 4 in parallel:
#   grep -E '^\s' telegram/sources.mk | sed 's/^\t//; s/ \\$//' | (cd telegram && xargs -P4 -n1 ../tools/local-syntax-check.sh)
#
# SDK: git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks && git -C sdks sparse-checkout set iPhoneOS11.4.sdk
# C++ headers: the SDK only ships libstdc++ 4.2; install libc++ headers (apt install libc++-18-dev).
set -u
SDK=${SDK:?set SDK to an iPhoneOS11.4.sdk path}
LIBCXX=${LIBCXX:-/usr/lib/llvm-18/include/c++/v1}

f="${1#telegram/}"
cd "$(dirname "$0")/../telegram" || exit 1

Q=""
for d in . Share Telegraph Telegraph/API Telegraph/AdHoc Telegraph/thirdparty/ogg/ogg Telegraph/thirdparty/opusenc \
    Telegraph/thirdparty/opusfile Watch/Bridge legacy/TL legacy/TL/TL legacy/TelegraphKit legacy/TelegraphKit/Third-Party/FMDB \
    submodules/LegacyComponents/LegacyComponents thirdparty thirdparty/Lottie/lottie-ios/Classes/PublicHeaders \
    thirdparty/Lottie/lottie-ios/Classes/Private thirdparty/Lottie/lottie-ios/Classes/Models thirdparty/Lottie/lottie-ios/Classes/Extensions \
    thirdparty/Lottie/lottie-ios/Classes/RenderSystem thirdparty/RMIntro/core thirdparty/RMIntro/platform/common thirdparty/RMIntro/platform/ios \
    thirdparty/SSignalKit/SSignalKit thirdparty/Stripe thirdparty/lz4 thirdparty/sqlcipher thirdparty/VideoEncoder vendor/MtProtoKit-4.9.1 \
    submodules/libtgvoip submodules/libtgvoip/webrtc_dsp; do
  Q="$Q -iquote $d"
done

PCH=""
case "$f" in
  tl/*|Telegraph/*|legacy/*|thirdparty/Stripe/*|thirdparty/RMIntro/*|thirdparty/lz4/*|thirdparty/sqlcipher/*|thirdparty/VideoEncoder/*|Watch/*|Share/*)
    PCH="-include Telegraph/Telegraph-Prefix.pch";;
esac
LANGFLAGS=""
case "$f" in *.mm|*.cpp|*.cc) LANGFLAGS="-std=gnu++11 -nostdinc++ -isystem $LIBCXX";; esac

clang -target armv7-apple-ios6.0 -mfpu=neon -isysroot "$SDK" -fsyntax-only -fobjc-arc -fblocks \
  -include BuildConfig.h $PCH $LANGFLAGS \
  -Iinclude -Ivendor/openssl/include -Ilegacy/TelegraphKit -Ilegacy/TL/TL -Ilegacy/TL -Ithirdparty/SSignalKit \
  -Isubmodules/libtgvoip -Isubmodules/libtgvoip/webrtc_dsp -Ithirdparty/Lottie/lottie-ios/Classes/PublicHeaders \
  -ITelegraph/thirdparty/ogg -ITelegraph/thirdparty/opus/include -ITelegraph/thirdparty/opus/include/opus -ITelegraph \
  -Ithirdparty/Stripe $Q \
  -DNS_BLOCK_ASSERTIONS -DSQLITE_TEMP_STORE=2 -DSQLITE_HAS_CODEC=1 -DSQLCIPHER_CRYPTO_CC=1 -DSQLITE_ENABLE_FTS3 \
  -DTGVOIP_USE_CUSTOM_CRYPTO -DWEBRTC_APM_DEBUG_DUMP=0 -DWEBRTC_POSIX -DTGVOIP_HAVE_TGLOG \
  -Wno-everything -ferror-limit=50 "$f" 2>&1 | grep -E "error:" | sed "s|^|[$f] |"
