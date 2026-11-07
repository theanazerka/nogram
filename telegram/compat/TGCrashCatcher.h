#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Append a line to the launch trace (see TGCrashCatcher.m).
void TGTraceMark(const char *mark);
void TGTraceMarkf(NSString *format, ...);
// True if this class' deferred +load crashed in an earlier launch.
bool TGTraceShouldSkipDeferredLoad(NSString *className);

#ifdef __cplusplus
}
#endif
