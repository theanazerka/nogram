#import <Foundation/Foundation.h>

// Builds inputCheckPasswordSRP for 2FA login.
// https://core.telegram.org/api/srp
// Slow (PBKDF2 100000 rounds), call off the main thread.
// Returns nil if the algorithm is unsupported or server parameters are unsafe.
NSDictionary *TGNComputePasswordCheck(NSDictionary *accountPassword, NSString *password);
