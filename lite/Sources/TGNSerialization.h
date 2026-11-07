#import <Foundation/Foundation.h>
#import <MTProtoKit/MTSerialization.h>

// MTSerialization backed by the runtime TL engine (see TL.h).
@interface TGNSerialization : NSObject <MTSerialization>
@end
