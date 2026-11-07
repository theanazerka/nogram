#import "TL.h"

#import <MTProtoKit/MTGzip.h>

static const int32_t TLVectorId = 0x1cb5c415;
static const int32_t TLBoolTrueId = (int32_t)0x997275b5;
static const int32_t TLBoolFalseId = (int32_t)0xbc799737;
static const int32_t TLGzipPackedId = 0x3072cfa1;

#pragma mark - Schema

@interface TLParam ()
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, strong) NSString *flagField;
@property (nonatomic) int flagBit;
@property (nonatomic) bool isFlags;
@end

@implementation TLParam
@end

@interface TLCombinator ()
@property (nonatomic) int32_t cid;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, strong) NSArray *params;
@end

@implementation TLCombinator
@end

@interface TLSchema ()
{
    NSMutableDictionary *_constructorsById;
    NSMutableDictionary *_constructorsByName;
    NSMutableDictionary *_methodsByName;
}
@property (nonatomic) int32_t layer;
@end

static TLCombinator *TLMakeCombinator(NSArray *item)
{
    TLCombinator *combinator = [[TLCombinator alloc] init];
    combinator.cid = (int32_t)[item[0] longLongValue];
    combinator.name = item[1];
    combinator.type = item[2];
    NSMutableArray *params = [[NSMutableArray alloc] init];
    for (NSArray *p in item[3])
    {
        TLParam *param = [[TLParam alloc] init];
        param.name = p[0];
        NSString *type = p[1];
        NSRange q = [type rangeOfString:@"?"];
        if (q.location != NSNotFound)
        {
            NSString *cond = [type substringToIndex:q.location];
            type = [type substringFromIndex:q.location + 1];
            NSRange dot = [cond rangeOfString:@"."];
            param.flagField = [cond substringToIndex:dot.location];
            param.flagBit = [[cond substringFromIndex:dot.location + 1] intValue];
        }
        param.type = type;
        param.isFlags = [type isEqualToString:@"#"];
        [params addObject:param];
    }
    combinator.params = params;
    return combinator;
}

@implementation TLSchema

+ (TLSchema *)shared
{
    static TLSchema *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        instance = [[TLSchema alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        _constructorsById = [[NSMutableDictionary alloc] init];
        _constructorsByName = [[NSMutableDictionary alloc] init];
        _methodsByName = [[NSMutableDictionary alloc] init];

        NSString *path = [[NSBundle mainBundle] pathForResource:@"scheme" ofType:@"json"];
        NSData *data = path != nil ? [NSData dataWithContentsOfFile:path] : nil;
        NSDictionary *json = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![json isKindOfClass:[NSDictionary class]])
        {
            NSLog(@"[TL] scheme.json is missing or corrupted");
            return self;
        }
        _layer = (int32_t)[json[@"layer"] intValue];
        for (NSArray *item in json[@"c"])
        {
            TLCombinator *c = TLMakeCombinator(item);
            _constructorsById[@(c.cid)] = c;
            _constructorsByName[c.name] = c;
        }
        for (NSArray *item in json[@"m"])
        {
            TLCombinator *m = TLMakeCombinator(item);
            _methodsByName[m.name] = m;
        }
    }
    return self;
}

- (TLCombinator *)constructorWithId:(int32_t)cid
{
    return _constructorsById[@(cid)];
}

- (TLCombinator *)constructorWithName:(NSString *)name
{
    return _constructorsByName[name];
}

- (TLCombinator *)methodWithName:(NSString *)name
{
    return _methodsByName[name];
}

@end

#pragma mark - Helpers

static void TLFail(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void TLFail(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *reason = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    @throw [NSException exceptionWithName:@"TLException" reason:reason userInfo:nil];
}

static bool TLIsBareTypeName(NSString *type)
{
    NSRange dot = [type rangeOfString:@"." options:NSBackwardsSearch];
    NSString *last = dot.location == NSNotFound ? type : [type substringFromIndex:dot.location + 1];
    if (last.length == 0)
        return false;
    unichar c = [last characterAtIndex:0];
    return c >= 'a' && c <= 'z';
}

static bool TLIsGenericType(NSString *type)
{
    return type == nil || [type isEqualToString:@"X"] || [type isEqualToString:@"!X"] || [type isEqualToString:@"Object"];
}

static NSString *TLInnerType(NSString *type, NSUInteger prefixLength)
{
    return [type substringWithRange:NSMakeRange(prefixLength, type.length - prefixLength - 1)];
}

static bool TLValuePresent(id value, NSString *type)
{
    if (value == nil || value == [NSNull null])
        return false;
    if ([type isEqualToString:@"true"])
        return [value boolValue];
    return true;
}

#pragma mark - Writer

static void TLWriteInt32(NSMutableData *out, int32_t value)
{
    uint32_t v = (uint32_t)value;
    uint8_t b[4] = { (uint8_t)v, (uint8_t)(v >> 8), (uint8_t)(v >> 16), (uint8_t)(v >> 24) };
    [out appendBytes:b length:4];
}

static void TLWriteInt64(NSMutableData *out, int64_t value)
{
    TLWriteInt32(out, (int32_t)(value & 0xffffffff));
    TLWriteInt32(out, (int32_t)((uint64_t)value >> 32));
}

static void TLWriteBytes(NSMutableData *out, NSData *data)
{
    NSUInteger length = data.length;
    NSUInteger header;
    if (length < 254)
    {
        uint8_t l = (uint8_t)length;
        [out appendBytes:&l length:1];
        header = 1;
    }
    else
    {
        uint8_t b[4] = { 254, (uint8_t)length, (uint8_t)(length >> 8), (uint8_t)(length >> 16) };
        [out appendBytes:b length:4];
        header = 4;
    }
    [out appendData:data];
    NSUInteger padding = (4 - ((header + length) % 4)) % 4;
    if (padding != 0)
    {
        uint8_t zero[4] = {0, 0, 0, 0};
        [out appendBytes:zero length:padding];
    }
}

static NSData *TLDataFromValue(id value)
{
    if ([value isKindOfClass:[NSData class]])
        return value;
    if ([value isKindOfClass:[NSString class]])
        return [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
    TLFail(@"expected bytes/string, got %@", [value class]);
    return nil;
}

static void TLWriteValue(NSMutableData *out, id value, NSString *type);
static void TLWriteBoxed(NSMutableData *out, NSDictionary *object);

static void TLWriteFields(NSMutableData *out, TLCombinator *combinator, NSDictionary *object)
{
    NSMutableDictionary *flagValues = [[NSMutableDictionary alloc] init];
    for (TLParam *param in combinator.params)
    {
        if (param.isFlags)
        {
            uint32_t flags = 0;
            for (TLParam *other in combinator.params)
            {
                if (other.flagField != nil && [other.flagField isEqualToString:param.name])
                {
                    if (TLValuePresent(object[other.name], other.type))
                        flags |= (1u << other.flagBit);
                }
            }
            flagValues[param.name] = @(flags);
            TLWriteInt32(out, (int32_t)flags);
            continue;
        }

        id value = object[param.name];
        if (param.flagField != nil)
        {
            uint32_t flags = [flagValues[param.flagField] unsignedIntValue];
            if ((flags & (1u << param.flagBit)) == 0)
                continue;
            if ([param.type isEqualToString:@"true"])
                continue;
            if (!TLValuePresent(value, param.type))
                TLFail(@"%@: field %@ shares flag bit %d but is missing", combinator.name, param.name, param.flagBit);
        }
        else if (value == nil || value == [NSNull null])
        {
            TLFail(@"%@: missing required field %@", combinator.name, param.name);
        }
        TLWriteValue(out, value, param.type);
    }
}

static void TLWriteBoxed(NSMutableData *out, NSDictionary *object)
{
    if (![object isKindOfClass:[NSDictionary class]])
        TLFail(@"expected TL object, got %@", [object class]);
    NSString *name = object[@"_"];
    TLCombinator *combinator = [[TLSchema shared] constructorWithName:name];
    if (combinator == nil)
        combinator = [[TLSchema shared] methodWithName:name];
    if (combinator == nil)
        TLFail(@"unknown TL combinator %@", name);
    TLWriteInt32(out, combinator.cid);
    TLWriteFields(out, combinator, object);
}

static void TLWriteValue(NSMutableData *out, id value, NSString *type)
{
    if ([type isEqualToString:@"int"])
        TLWriteInt32(out, (int32_t)[value intValue]);
    else if ([type isEqualToString:@"long"])
        TLWriteInt64(out, [value longLongValue]);
    else if ([type isEqualToString:@"double"])
    {
        double d = [value doubleValue];
        int64_t bits;
        memcpy(&bits, &d, 8);
        TLWriteInt64(out, bits);
    }
    else if ([type isEqualToString:@"string"] || [type isEqualToString:@"bytes"])
        TLWriteBytes(out, TLDataFromValue(value));
    else if ([type isEqualToString:@"int128"] || [type isEqualToString:@"int256"])
    {
        NSData *data = TLDataFromValue(value);
        NSUInteger expected = [type isEqualToString:@"int128"] ? 16 : 32;
        if (data.length != expected)
            TLFail(@"%@ must be %d bytes", type, (int)expected);
        [out appendData:data];
    }
    else if ([type isEqualToString:@"Bool"])
        TLWriteInt32(out, [value boolValue] ? TLBoolTrueId : TLBoolFalseId);
    else if ([type isEqualToString:@"true"])
    {
    }
    else if ([type hasPrefix:@"Vector<"] || [type hasPrefix:@"vector<"])
    {
        bool boxed = [type characterAtIndex:0] == 'V';
        NSString *inner = TLInnerType(type, 7);
        if (![value isKindOfClass:[NSArray class]])
            TLFail(@"expected array for %@", type);
        if (boxed)
            TLWriteInt32(out, TLVectorId);
        TLWriteInt32(out, (int32_t)[(NSArray *)value count]);
        for (id item in (NSArray *)value)
            TLWriteValue(out, item, inner);
    }
    else if ([value isKindOfClass:[NSData class]] && TLIsGenericType(type))
        [out appendData:value]; // pre-serialized query
    else if (TLIsBareTypeName(type))
    {
        TLCombinator *combinator = [[TLSchema shared] constructorWithName:type];
        if (combinator == nil)
            TLFail(@"unknown bare type %@", type);
        TLWriteFields(out, combinator, value);
    }
    else
        TLWriteBoxed(out, value);
}

NSData *TLSerialize(NSDictionary *object)
{
    NSMutableData *out = [[NSMutableData alloc] init];
    TLWriteBoxed(out, object);
    return out;
}

NSData *TLSerializeSafe(NSDictionary *object, NSError **error)
{
    @try
    {
        return TLSerialize(object);
    }
    @catch (NSException *e)
    {
        NSLog(@"[TL] serialize failed: %@", e.reason);
        if (error != NULL)
            *error = [NSError errorWithDomain:@"TL" code:1 userInfo:@{NSLocalizedDescriptionKey: e.reason ?: @"TL error"}];
        return nil;
    }
}

#pragma mark - Reader

typedef struct
{
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger offset;
} TLReader;

static void TLEnsure(TLReader *r, NSUInteger count)
{
    if (r->offset + count > r->length)
        TLFail(@"unexpected end of data (need %d at %d of %d)", (int)count, (int)r->offset, (int)r->length);
}

static int32_t TLReadInt32(TLReader *r)
{
    TLEnsure(r, 4);
    const uint8_t *p = r->bytes + r->offset;
    r->offset += 4;
    return (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
}

static int64_t TLReadInt64(TLReader *r)
{
    uint32_t lo = (uint32_t)TLReadInt32(r);
    uint32_t hi = (uint32_t)TLReadInt32(r);
    return (int64_t)(((uint64_t)hi << 32) | lo);
}

static NSData *TLReadRaw(TLReader *r, NSUInteger count)
{
    TLEnsure(r, count);
    NSData *data = [NSData dataWithBytes:r->bytes + r->offset length:count];
    r->offset += count;
    return data;
}

static NSData *TLReadBytes(TLReader *r)
{
    TLEnsure(r, 1);
    NSUInteger length = r->bytes[r->offset];
    NSUInteger header = 1;
    if (length >= 254)
    {
        TLEnsure(r, 4);
        const uint8_t *p = r->bytes + r->offset;
        length = (NSUInteger)p[1] | ((NSUInteger)p[2] << 8) | ((NSUInteger)p[3] << 16);
        header = 4;
    }
    r->offset += header;
    NSData *data = TLReadRaw(r, length);
    NSUInteger padding = (4 - ((header + length) % 4)) % 4;
    TLEnsure(r, padding);
    r->offset += padding;
    return data;
}

static NSString *TLStringFromData(NSData *data)
{
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s == nil)
        s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    return s ?: @"";
}

static id TLReadValue(TLReader *r, NSString *type);

static NSMutableDictionary *TLReadFields(TLReader *r, TLCombinator *combinator)
{
    NSMutableDictionary *object = [[NSMutableDictionary alloc] initWithCapacity:combinator.params.count + 1];
    object[@"_"] = combinator.name;
    for (TLParam *param in combinator.params)
    {
        if (param.isFlags)
        {
            object[param.name] = @((uint32_t)TLReadInt32(r));
            continue;
        }
        if (param.flagField != nil)
        {
            uint32_t flags = [object[param.flagField] unsignedIntValue];
            if ((flags & (1u << param.flagBit)) == 0)
                continue;
            if ([param.type isEqualToString:@"true"])
            {
                object[param.name] = @YES;
                continue;
            }
        }
        id value = TLReadValue(r, param.type);
        if (value != nil)
            object[param.name] = value;
    }
    return object;
}

static id TLReadObjectWithId(TLReader *r, int32_t cid)
{
    if (cid == TLGzipPackedId)
    {
        NSData *packed = TLReadBytes(r);
        NSData *unpacked = [MTGzip decompress:packed];
        if (unpacked == nil)
            TLFail(@"gzip_packed: decompression failed");
        TLReader inner = { unpacked.bytes, unpacked.length, 0 };
        return TLReadValue(&inner, nil);
    }
    if (cid == TLBoolTrueId)
        return @YES;
    if (cid == TLBoolFalseId)
        return @NO;
    TLCombinator *combinator = [[TLSchema shared] constructorWithId:cid];
    if (combinator == nil)
        TLFail(@"unknown constructor 0x%08x", (uint32_t)cid);
    return TLReadFields(r, combinator);
}

static id TLReadValue(TLReader *r, NSString *type)
{
    if ([type isEqualToString:@"int"])
        return @(TLReadInt32(r));
    if ([type isEqualToString:@"long"])
        return @(TLReadInt64(r));
    if ([type isEqualToString:@"double"])
    {
        int64_t bits = TLReadInt64(r);
        double d;
        memcpy(&d, &bits, 8);
        return @(d);
    }
    if ([type isEqualToString:@"string"])
        return TLStringFromData(TLReadBytes(r));
    if ([type isEqualToString:@"bytes"])
        return TLReadBytes(r);
    if ([type isEqualToString:@"int128"])
        return TLReadRaw(r, 16);
    if ([type isEqualToString:@"int256"])
        return TLReadRaw(r, 32);
    if ([type isEqualToString:@"true"])
        return @YES;
    if ([type hasPrefix:@"Vector<"] || [type hasPrefix:@"vector<"])
    {
        NSString *inner = TLInnerType(type, 7);
        if ([type characterAtIndex:0] == 'V')
        {
            int32_t cid = TLReadInt32(r);
            if (cid == TLGzipPackedId)
            {
                NSData *unpacked = [MTGzip decompress:TLReadBytes(r)];
                if (unpacked == nil)
                    TLFail(@"gzip_packed: decompression failed");
                TLReader nested = { unpacked.bytes, unpacked.length, 0 };
                return TLReadValue(&nested, type);
            }
            if (cid != TLVectorId)
                TLFail(@"expected vector, got 0x%08x", (uint32_t)cid);
        }
        int32_t count = TLReadInt32(r);
        if (count < 0 || (NSUInteger)count > r->length)
            TLFail(@"bad vector length %d", count);
        NSMutableArray *items = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)count];
        for (int32_t i = 0; i < count; i++)
        {
            id item = TLReadValue(r, inner);
            [items addObject:item ?: [NSNull null]];
        }
        return items;
    }
    if (type != nil && !TLIsGenericType(type) && TLIsBareTypeName(type))
    {
        TLCombinator *combinator = [[TLSchema shared] constructorWithName:type];
        if (combinator == nil)
            TLFail(@"unknown bare type %@", type);
        return TLReadFields(r, combinator);
    }
    // Boxed (Bool included).
    return TLReadObjectWithId(r, TLReadInt32(r));
}

id TLParse(NSData *data, NSString *type, NSError **error)
{
    if (data == nil)
        return nil;
    @try
    {
        TLReader r = { data.bytes, data.length, 0 };
        return TLReadValue(&r, type);
    }
    @catch (NSException *e)
    {
        NSLog(@"[TL] parse failed (%@): %@", type, e.reason);
        if (error != NULL)
            *error = [NSError errorWithDomain:@"TL" code:2 userInfo:@{NSLocalizedDescriptionKey: e.reason ?: @"TL error"}];
        return nil;
    }
}

NSString *TLReturnType(NSString *method)
{
    return [[TLSchema shared] methodWithName:method].type;
}

#pragma mark - Accessors

NSString *TLName(id object)
{
    if (![object isKindOfClass:[NSDictionary class]])
        return nil;
    return object[@"_"];
}

bool TLIs(id object, NSString *name)
{
    return [TLName(object) isEqualToString:name];
}

static id TLGet(id object, NSString *key)
{
    if (![object isKindOfClass:[NSDictionary class]])
        return nil;
    id value = object[key];
    return value == [NSNull null] ? nil : value;
}

int64_t TLLong(id object, NSString *key)
{
    id value = TLGet(object, key);
    return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0;
}

int32_t TLInt(id object, NSString *key)
{
    id value = TLGet(object, key);
    return [value respondsToSelector:@selector(intValue)] ? [value intValue] : 0;
}

bool TLBool(id object, NSString *key)
{
    id value = TLGet(object, key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : false;
}

NSString *TLString(id object, NSString *key)
{
    id value = TLGet(object, key);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

NSArray *TLArray(id object, NSString *key)
{
    id value = TLGet(object, key);
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

NSDictionary *TLDict(id object, NSString *key)
{
    id value = TLGet(object, key);
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}
