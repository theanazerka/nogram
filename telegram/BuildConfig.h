// Build-time configuration that upstream kept in a private, unpublished config.
// api_id / api_hash: pass TG_API_ID / TG_API_HASH to make (or GitHub secrets).
#ifndef TG_BUILD_CONFIG_H
#define TG_BUILD_CONFIG_H

#ifndef TG_API_ID
#define TG_API_ID 0
#endif
#ifndef TG_API_HASH
#define TG_API_HASH ""
#endif

#define SETUP_API_ID(apiId) apiId = TG_API_ID;
#define SETUP_API_HASH(apiHash) apiHash = @TG_API_HASH;

#define TELEGRAM_APP_NAME @"Telegram"
#define TELEGRAM_APPSTORE_ID @686449807

#endif
