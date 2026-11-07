// Runtime TL (Type Language) engine.
//
// Telegram API objects are represented as plain Foundation values:
//   int / long / double / Bool / true  -> NSNumber
//   string                             -> NSString
//   bytes / int128 / int256            -> NSData
//   Vector<T>                          -> NSArray
//   constructors and methods           -> NSDictionary with key @"_" = predicate name
//
// Example:
//   NSData *req = TLSerialize(@{@"_": @"messages.getDialogs", @"offset_date": @0, ...});
//   id result = TLParse(responseData, @"messages.Dialogs", &error);
//
// Flags fields (type "#") are computed automatically from which optional fields
// are present, so callers never fill "flags" themselves.

#import <Foundation/Foundation.h>

@interface TLParam : NSObject
@property (nonatomic, strong, readonly) NSString *name;
@property (nonatomic, strong, readonly) NSString *type;       // base type without condition
@property (nonatomic, strong, readonly) NSString *flagField;  // nil if unconditional
@property (nonatomic, readonly) int flagBit;
@property (nonatomic, readonly) bool isFlags;                 // type is "#"
@end

@interface TLCombinator : NSObject
@property (nonatomic, readonly) int32_t cid;
@property (nonatomic, strong, readonly) NSString *name;
@property (nonatomic, strong, readonly) NSString *type;
@property (nonatomic, strong, readonly) NSArray *params;      // of TLParam
@end

@interface TLSchema : NSObject
@property (nonatomic, readonly) int32_t layer;
+ (TLSchema *)shared;
- (TLCombinator *)constructorWithId:(int32_t)cid;
- (TLCombinator *)constructorWithName:(NSString *)name;
- (TLCombinator *)methodWithName:(NSString *)name;
@end

#ifdef __cplusplus
extern "C" {
#endif

// Serializes a method call or a boxed constructor. Throws NSException on invalid input.
NSData *TLSerialize(NSDictionary *object);
// Same, but returns nil instead of throwing.
NSData *TLSerializeSafe(NSDictionary *object, NSError **error);

// Parses data as a value of the given TL type (e.g. "messages.Dialogs", "Vector<long>").
// Pass nil for a boxed object of unknown type.
id TLParse(NSData *data, NSString *type, NSError **error);

// Return type of a method, e.g. TLReturnType(@"auth.sendCode") == @"auth.SentCode".
NSString *TLReturnType(NSString *method);

// Convenience accessors that tolerate NSNull / missing keys.
NSString *TLName(id object);                 // object[@"_"]
bool TLIs(id object, NSString *name);
int64_t TLLong(id object, NSString *key);
int32_t TLInt(id object, NSString *key);
bool TLBool(id object, NSString *key);
NSString *TLString(id object, NSString *key);
NSArray *TLArray(id object, NSString *key);
NSDictionary *TLDict(id object, NSString *key);

#ifdef __cplusplus
}
#endif
