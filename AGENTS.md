# AGENTS.md — handoff for AI coding agents

Read this whole file before touching anything. It records what the project is, how the build
really works, every non-obvious fix that was needed, and the plan for what is left. `CLAUDE.md`
points here.

The owner speaks Russian and wants answers in Russian. They test on a real jailbroken iOS 6
device and cannot easily pull crash logs (see "Debugging on device").

---

## 1. Goal

Revive the **original Telegram iOS 4.9.1** client (upstream: `peter-iakovlev/Telegram`, public
branch, sources dated 2018-08-27) so that it:

1. runs on **iOS 6** (armv7, jailbroken, installed via Cydia or AppSync),
2. is built with **Theos** on **GitHub Actions** (no Xcode, no Mac),
3. can **log in** again.

It must stay the original app. Do not replace it with a rewrite: the owner explicitly rejected
that. An earlier minimal rewrite (`lite/`) was deleted on purpose; do not bring it back.

### Why login is broken upstream

4.9.1 speaks MTProto API **layer 86** (`Telegraph/TGTLSerialization.mm` → `currentLayer` returns 86)
and sends `auth.sendCode` with the ancient constructor `0xccfd70cf` (hand-written in
`Telegraph/TLRPCauth_sendCode.mm`, layer ~50). Telegram servers answer such clients with
`UPDATE_APP_TO_LOGIN`. Old layers also use 32-bit user/chat ids; the server has used 64-bit ids
since layer ~133. Fixing login means moving the app to the **current layer (232)**. See §6.

---

## 2. Status (keep this section updated)

| Stage | State |
|---|---|
| 1. Original 4.9.1 compiles and links for armv7 / iOS 6 with Theos in CI | **done** |
| 1b. No strong imports missing from iOS 6 (dyld launch crash) | **done**, enforced in CI |
| 1c. App actually starts on iOS 6 | **unknown**: the first build crashed at launch from a missing vImage symbol; that is fixed, waiting for the owner to retest |
| 2. TL layer 232 generator in the original class format | **not started** (analysis done, see §6) |
| 3. App code adapted to layer 232 (64-bit ids, new auth flow) | **not started** |

Network transport is already prepared for modern servers (see §5, MtProtoKit patches).

---

## 3. Repository layout

```
telegram/                  upstream Telegram 4.9.1 tree (Telegraph/, legacy/, thirdparty/, submodules/, Watch/Bridge, Share/)
  Makefile                 Theos build of the whole app (read it, it is commented)
  sources.mk               GENERATED file lists (tools/gen-telegram-mk.py) — do not edit by hand
  BuildConfig.h            replaces upstream's private config: SETUP_API_ID/HASH, TELEGRAM_APPSTORE_ID, implicit MobileCoreServices
  control                  Debian control (package org.telegram.legacy)
  compat/
    TGAvailabilityShim.m   __isOSVersionAtLeast (runtime for @available; compiler-rt is not linked)
    TGCrashCatcher.m       on-device crash reporter (see §8)
    lib/libc++.tbd, libc++abi.tbd   link stubs generated from real iOS 6 dylibs
  include/                 symlinks emulating framework headers: <LegacyComponents/..>, <SSignalKit/..>, <MTProtoKit/..>,
                           <MtProtoKit/..>, <MTProtoKitDynamic/..>, <WebP/..>, <HockeySDK/..>, <libtgvoip/..>, <thirdparty/..>
  lc -> submodules/LegacyComponents/LegacyComponents   (short path, see §4 "argument length")
  tl -> legacy/TL/TL                                     (short path)
  vendor -> ../vendor
  thirdparty/AFNetworking/*.h -> vendor MtProtoKit AF headers (upstream include path)
config.h                   shim: upstream includes "../../config.h" from Telegraph/
vendor/
  MtProtoKit-4.9.1/        MtProtoKit at commit 8198b64 (2018-08-14, the revision 4.9.1 builds against) + patches
  openssl/                 OpenSSL 1.0.2 headers + armv7-only libcrypto.a
tl/telegram_api.tl, tl/LAYER   current API schema (from tdlib, layer 232) — input for stage 2
tools/                     all build helpers (below)
.github/workflows/build.yml  CI: build, iOS 6 import check, Cydia repo publish
```

### tools/

| Script | Purpose |
|---|---|
| `pbx2files.py` | Parses an `.xcodeproj` (sources per target, build settings with `--settings`). |
| `gen-telegram-mk.py` | Generates `telegram/sources.mk` from the 5 Xcode targets (Telegraph, LegacyComponents, SSignalKit, LottieLibraryIOS, libtgvoip). Handles case-insensitive names, `$` in file names, `Video Encoder` → `VideoEncoder`, path shortening (`lc/`, `tl/`). **Re-run it after adding or removing sources in the Xcode project.** |
| `gen-telegram-resources.py` | Builds the bundle resource folder (`.theos/tgresources`) from the Xcode "Copy Bundle Resources" phase, root icons and launch images, and rewrites Info.plist for iOS 6 (bundle id `org.telegram.legacy`, no launch storyboard). Runs in `before-all`. |
| `patch-mtprotokit.py` | Idempotent patch set for a flat MtProtoKit copy (see §5). |
| `patch-theos-link.py` | Patches Theos to link via `-filelist` (see §4). Applied in CI. |
| `check-ios6-imports.py` | Lists **strong** imports of a Mach-O that real iOS 6.0 dylibs do not export → dyld would kill the app at launch. Run in CI; exit 1 on problems. |
| `make-ios6-tbd.py` | Regenerates `compat/lib/*.tbd` from iOS 6 dylibs (`llvm-readtapi -stubify`). |
| `make-cydia-repo.py` | Builds the flat Cydia repo (Packages, Release, debs, ipa, index.html). |
| `restore-mtime.py` | Sets file mtimes to their last commit time so cached objects are reused in CI. |
| `local-syntax-check.sh` | Fast per-file compile check on Linux with host clang (no toolchain or ld64 needed). |
| `tl2json.py` | Compiles `tl/telegram_api.tl` into a JSON schema (parser reusable for the stage 2 generator). |

---

## 4. Build system (Theos) — facts and gotchas

- **Target**: `iphone:clang:11.4:6.0`, `ARCHS = armv7`. **iOS 11.4 SDK** is the newest SDK whose `.tbd`
  stubs still contain armv7. 10.3 stubs drop armv7-only symbols (`objc_msgSend_stret`, compiler-rt).
  9.3 stubs are tbd-v1, which current ld64 treats as simulator libraries. Do not change the SDK.
- **Toolchain**: Linux, L1ghtmann `iOSToolchain-x86_64` (clang 11 + ld64), installed in CI.
- **Everything is static.** Upstream links LegacyComponents/SSignalKit/Lottie/libtgvoip/MtProtoKit as
  embedded dylibs, which iOS 6 cannot load. All of it goes into one binary. Consequences:
  - duplicate helper symbols between the app and LegacyComponents are renamed in LegacyComponents via
    per-file `-D` flags (`TG_LC_DUP_*` in the Makefile);
  - prebuilt static libs linked directly: `WebP.framework/WebP`, `libopus.a`, HockeySDK (all have armv7).
- **Theos `vendor/include` and `Prefix.pch` are disabled.** They ship private-header replacements for
  UIKit/Foundation/MobileCoreServices/... that shadow the SDK. The Makefile points
  `THEOS_VENDOR_INCLUDE_PATH` to an empty dir (with a `.git` marker to satisfy Theos' check) and
  redefines `_THEOS_INTERNAL_IFLAGS_C` without `-include Prefix.pch`.
- **Header maps**: Xcode found `"Foo.h"` anywhere in the project; here every header dir is
  `-iquote`'d (`TG_QUOTE_DIRS`). New header dirs must be added there.
- **Prefix header** `Telegraph/Telegraph-Prefix.pch` applies only to the app target's files (per-file flag).
- **Argument length**: Theos passes the whole file list to one `bash -c` argument, and Linux limits a
  single argument to 128 KiB. Hence the short symlink paths `lc/` and `tl/` in `sources.mk`
  (~114 KB now; watch this when adding files) and the link via `-filelist` (`patch-theos-link.py`).
- **No `$` and no spaces in source file names** (make breaks). Upstream `TLFoo$bar.mm` sources were
  renamed to `TLFoo_bar.mm`; headers keep `$` (they are only `#import`ed).
- **Case-sensitive file system**: upstream was built on macOS. Fixed so far: `PushKit/PushKit.h`,
  `CallKit/CallKit.h`, `UIKit/`, `PGPhotoGaussianBlurFilter.h`, `TLinvokeWithLayer.mm`.
- **C++**: `-std=gnu++11`; link uses `-nostdlib++ -Lcompat/lib -lc++ -lc++abi` with stubs generated from
  real iOS 6 dylibs.
- **Frameworks**: those present on iOS 6 are linked normally; newer ones are `-weak_framework`
  (`Telegram_WEAK_FRAMEWORKS`). A weak framework does **not** make its symbols weak: an iOS 7+ C
  function from a framework that exists on iOS 6 (example: `vImageBuffer_InitWithCGImage` in
  Accelerate) is still a strong import, and dyld kills the app. Resolve such functions with `dlsym` (see
  `TGPhotoEditorUtils.m`) or declare them `weak_import`. CI catches these (`check-ios6-imports.py`).
- **Compiler strictness fixes** applied to upstream: `nil` passed to `bool` params (`TGDatabase.mm`,
  `ActionStage.mm`, `TGGenericModernConversationCompanion.mm`), `endian.h` → `machine/endian.h`,
  `[STPToken new]` via `objc_msgSend`, `stdlib.h` in libtgvoip `checks.cc`, `-DTGVOIP_USE_AUDIO_SESSION`
  removed (header/impl mismatch).

### Local build / checks (Linux)

Full builds need the iOS toolchain (only in CI; GitHub release downloads may be blocked locally).
For quick feedback use `tools/local-syntax-check.sh` (host clang + 11.4 SDK headers + libc++ headers).
`check-ios6-imports.py` needs real iOS 6 dylibs: sparse checkout of `Alex1s/iPhoneOS6.0.sdk`
(see the CI step "Fetch iOS 6 system libraries") and `llvm-objdump`.

---

## 5. MtProtoKit (vendor/MtProtoKit-4.9.1)

Revision **8198b64** of `peter-iakovlev/MtProtoKit` is the one whose API matches the 4.9.1 sources
(`setPayload:metadata:responseParser:`, `MTNetworkSettings`, `initWithSerialization:...useTempAuthKeys:`).
Older (`515bcf4`, the stale submodule pin) and newer (2019 master) revisions do not compile with the app.

`tools/patch-mtprotokit.py` applied:
- iOS 6 SDK compatibility: `endian.h`, `CFAutorelease`, AFNetworking import path.
- Current production RSA key (fingerprint `0xd09d1d85de64fd85`, verified by computing it).
- Auth key exchange: **`p_q_inner_data_dc#a9f55f95` + `RSA_PAD`** (current servers), implemented in
  `MTRsaEncryptWithPad` (`MTEncryption.m`). Raw RSA is done through OpenSSL (Security.framework would
  need keychain entitlements).
- `initConnection`: uses **`#c1cd5ea9` automatically when `currentLayer >= 100`**, the old constructor otherwise.
- `MTIsZero`, `MTCheckIsSafeB` added (used by the app's SRP code in `TGTwoStepUtils`).

TODO for stage 2: `auth.exportedAuthorization.id` / `auth.importAuthorization.id` became `long` in
modern layers, but `MTExportedAuthorizationData.authorizationId` and
`-[MTSerialization importAuthorization:(int32_t)...]` are still 32-bit here. Change them to
`int64_t` (MtProtoKit + `TGTLSerialization`) when switching layers, otherwise DC transfers break.

The handshake changes have **not been tested against live servers** (the sandbox could not reach
Telegram over raw TCP). The serialization algorithm and SRP were verified byte for byte against
Telethon in Python.

---

## 6. Stage 2 plan: TL layer 232 in the original format

### How TL works in 4.9.1

- `legacy/TL/TL/` (588 compiled files, path alias `tl/`): **generated** classes, one header/impl per
  type: `TL<Type>` base plus `TL<Type>$<predicate>` subclasses, e.g. `TLUserStatus$userStatusOnline`.
  Each class implements:
  - `TLconstructorSignature` (constructor id),
  - `TLconstructorName` = **MurmurHash3_x86_32 of the predicate name, seed `-137723950`** (see
    `murMurHash32` in `lc/TGStringUtils.mm`; a Python port reproduces upstream hashes exactly),
  - `TLbuildFromMetaObject:` reading fields by hashed field name (e.g. `expires` → `0x4743fb6b`),
  - `TLfillFieldsWithValues:`.
- `legacy/TL/TL/TLMetaSchemeData.mm` (840 KB): the layer-86 schema as data; `TLMetaClassStore`
  parses objects at runtime from it and maps them to classes by name hash.
- `Telegraph/TL*.mm/h` (233 files): **hand-written** classes for flag-based constructors, with direct
  `TLserialize:` / `TLdeserialize:...`, e.g. `TLMessage$modernMessage` (subclass of the generated
  `TLMessage$messageMeta` that only holds properties). They are registered in
  `TLMetaClassStore::manualObjectParsers` / `manualObjectSerializers`, **keyed by constructor signature**.
- RPCs: `TLRPC<method>` subclasses of `TLMetaRpc` (`TLserialize:`, `responseClass`, `layerVersion`).
  Some are generated (`TLRPCmessages_getDialogs$messages_getDialogs`), many hand-written.
- Vector responses: `NSArray_<Type>` classes.
- Property naming: field `id` → `n_id`; flags are an `int32_t flags` property; `true` flags → `bool`.

The app uses **807** TL symbols (246 RPCs). To list them:
`grep -rhoE '\bTL[A-Za-z_]+\$[A-Za-z_]+\b|\bTLRPC[A-Za-z_]+\b' telegram/Telegraph telegram/legacy/TelegraphKit | sort -u`

### Suggested approach

Write `tools/gen-tl.py` that reads `tl/telegram_api.tl` (layer 232, parser in `tools/tl2json.py`) and
emits, for **every** constructor and method, hand-written-style classes (direct
`TLserialize`/`TLdeserialize` with flags, no meta scheme), registered as manual parsers by signature:

1. Keep **existing class names** so app code keeps compiling: for predicates that had a hand-written
   class (`TLMessage$modernMessage`, `TLUser$modernUser`, ...) generate the property-holding base under
   the old `...Meta` name and the parsing leaf under the old manual name. Build the mapping from the
   old `TLconstructorSignature` values plus the layer-86 schema in `TLMetaSchemeData.mm`.
2. Keep property names (`n_id`, ...). Types: `int`→`int32_t`, `long`→`int64_t`, `double`, `string`→`NSString`,
   `bytes`→`NSData`, `Bool`/`true`→`bool`, `Vector<T>`→`NSArray`, objects → `TL<Type> *`, `int128/256`→`NSData`.
3. Generate RPC classes under the names the app uses (both `TLRPCx_y` and `TLRPCx_y$x_y` forms).
4. Replace `legacy/TL/TL/*` and `Telegraph/TL*` files, bump `currentLayer` to 232 (this also switches
   MtProtoKit to `initConnection#c1cd5ea9`), regenerate `sources.mk`.
5. Fix compile errors in app code (removed/renamed fields, `int32`→`int64`).

### Stage 3: app code

- Login (`TGTelegraph.mm` ~L2040 builds `auth.sendCode`; the login controllers in `Telegraph/`):
  `auth.sendCode#a677244f phone_number api_id api_hash settings:CodeSettings`,
  `auth.signIn#8d52a951` (flags, optional `phone_code`, `email_verification`), `auth.SentCode` variants
  (`auth.sentCodeSuccess`, `auth.sentCodeTypeSetUpEmailRequired`, `auth.sentCodeTypeEmailCode`, ...),
  `auth.authorizationSignUpRequired`. 2FA: `TGTwoStepUtils` already implements SRP
  (`inputCheckPasswordSRP`); check it against `account.password#957b50fb`.
- 64-bit ids: `TGUser.uid`, conversation ids, peer ids, the SQLite schema in `legacy/TelegraphKit/TGDatabase.mm`
  are 32-bit. Users, chats and channels are `long` in layer 232.
- `api_id` / `api_hash`: `BuildConfig.h` defines `SETUP_API_ID/HASH` from `-DTG_API_ID/-DTG_API_HASH`.
  CI passes repository secrets `TG_API_ID` / `TG_API_HASH`. Without them, login sends `api_id = 0`.

---

## 7. CI (.github/workflows/build.yml)

Job `build`: restore caches → apt deps → `tools/restore-mtime.py` → install Theos + toolchain + 11.4 SDK
(cached under key `theos-11.4-v1`; bump the key to force a reinstall) → patch Theos (`--keep-going`,
`-filelist`) → delete the cached `.app` (forces a relink) → `make ipa FINALPACKAGE=1 PACKAGE_VERSION=<control
Version>-<run number>` → **check strong imports against iOS 6 dylibs** (fails the job) → save object cache
(also on failure) → upload artifacts.

- Object cache key `obj-telegram-<sha>`, restored from the latest prefix match. Thanks to
  `restore-mtime.py` an incremental build takes ~2 min, a cold one ~9 min. Changing global CFLAGS
  changes Theos' object-file hash tag and forces a full rebuild.
- Do not use the Debian `git-restore-mtime` package: it relies on `git whatchanged`, which is broken on git 2.5x.
- Error summary step: grep the build log for `error:`; full log is uploaded as `build-log-telegram`.

Job `repo` (only on push to **main**): builds the Cydia repo and force-pushes it to the **`gh-pages`**
branch. Pages must be set to "Deploy from a branch → gh-pages / root". URL:
`https://theanazerka.github.io/nogram/` (add it as a Cydia source; the page also links the debs and the ipa).

---

## 8. Debugging on device

- `telegram/compat/TGCrashCatcher.m` catches uncaught ObjC exceptions and fatal signals and writes
  `Library/Caches/last-crash.txt`. On the next launch, before the app's own launch code runs, it shows
  the report full screen and copies it to the pasteboard. Ask the owner to paste it. Addresses are
  for the unslid binary: subtract the printed `slide`; symbolicate with the unstripped object files
  from CI (`.theos/obj/armv7`) or `atos`.
- A crash **before** `main` (dyld, missing symbol) produces no report. That is what
  `check-ios6-imports.py` is for. Also suspect classes that subclass classes missing on iOS 6 (weak
  superclass: `UIAlertController`, `SFSafariViewController`, `NSTextAttachment`, `NSLayoutManager`,
  `UICollectionViewTransitionLayout`, `UIPercentDrivenInteractiveTransition`,
  `UIScreenEdgePanGestureRecognizer`); the iOS 6 runtime should ignore them, but this is unverified.
- Upstream shipped to the App Store with iOS 8+; many code paths call iOS 7/8 APIs guarded by
  `iosMajorVersion()`. Unguarded ones will show up as `unrecognized selector` reports.

---

## 9. Working rules

- Commit messages in English; explain *why*. Do not commit `.theos/`, `packages/`, `build.log`.
- After source list changes: `python3 tools/gen-telegram-mk.py`.
- Keep `tools/patch-mtprotokit.py` the single source of MtProtoKit changes (idempotent) when possible.
- Verify with CI and, when touching imports or linking, with `check-ios6-imports.py`.
- License: GPL v2 (Telegram/MtProtoKit sources).
