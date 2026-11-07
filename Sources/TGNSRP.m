#import "TGNSRP.h"

#import <Security/Security.h>
#import <MTProtoKit/MTEncryption.h>

#import "TL.h"

static NSData *TGNConcat(NSArray *parts)
{
    NSMutableData *result = [[NSMutableData alloc] init];
    for (NSData *part in parts)
        [result appendData:part];
    return result;
}

static NSData *TGNPad256(NSData *data)
{
    if (data.length >= 256)
        return data;
    NSMutableData *result = [[NSMutableData alloc] initWithLength:256 - data.length];
    [result appendData:data];
    return result;
}

static NSData *TGNIntData(int32_t value)
{
    uint8_t bytes[4] = { (uint8_t)(value >> 24), (uint8_t)(value >> 16), (uint8_t)(value >> 8), (uint8_t)value };
    return [NSData dataWithBytes:bytes length:4];
}

// SH(data, salt) := H(salt | data | salt)
static NSData *TGNSaltedHash(NSData *data, NSData *salt)
{
    return MTSha256(TGNConcat(@[salt, data, salt]));
}

static NSData *TGNXor(NSData *a, NSData *b)
{
    NSMutableData *result = [[NSMutableData alloc] initWithData:a];
    uint8_t *r = result.mutableBytes;
    const uint8_t *bb = b.bytes;
    for (NSUInteger i = 0; i < MIN(a.length, b.length); i++)
        r[i] ^= bb[i];
    return result;
}

static bool TGNIsGood(NSData *value, NSData *p)
{
    // 1 < value < p - 1 and value is 2048 bit-ish; MTCheckIsSafeGAOrB does the full check.
    return value.length > 0 && MTCheckIsSafeGAOrB(value, p);
}

NSDictionary *TGNComputePasswordCheck(NSDictionary *accountPassword, NSString *password)
{
    NSDictionary *algo = TLDict(accountPassword, @"current_algo");
    if (!TLIs(algo, @"passwordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow"))
        return nil;

    NSData *salt1 = algo[@"salt1"];
    NSData *salt2 = algo[@"salt2"];
    int32_t g = TLInt(algo, @"g");
    NSData *p = algo[@"p"];
    NSData *gB = accountPassword[@"srp_B"];
    id srpId = accountPassword[@"srp_id"];
    if (salt1 == nil || salt2 == nil || p.length != 256 || gB == nil || srpId == nil)
        return nil;

    if (!MTCheckIsSafeG((unsigned int)g) || !TGNIsGood(gB, p))
        return nil;

    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];

    // x := PH2(password, salt1, salt2)
    NSData *ph1 = TGNSaltedHash(TGNSaltedHash(passwordData, salt1), salt2);
    NSData *pbkdf = MTPBKDF2(ph1, salt1, 100000);
    if (pbkdf == nil)
        return nil;
    NSData *x = TGNSaltedHash(pbkdf, salt2);

    NSData *gData = TGNIntData(g);
    NSData *gPadded = TGNPad256(gData);
    NSData *gBPadded = TGNPad256(gB);

    // v := g^x mod p ; k := H(p | g)
    NSData *v = MTExp(gData, x, p);
    NSData *k = MTSha256(TGNConcat(@[p, gPadded]));
    NSData *kV = MTModMul(k, v, p);

    NSData *a = nil;
    NSData *gA = nil;
    for (int attempt = 0; attempt < 16; attempt++)
    {
        NSMutableData *random = [[NSMutableData alloc] initWithLength:256];
        __unused int status = SecRandomCopyBytes(kSecRandomDefault, 256, random.mutableBytes);
        a = random;
        gA = MTExp(gData, a, p);
        if (TGNIsGood(gA, p))
            break;
        gA = nil;
    }
    if (gA == nil)
        return nil;
    NSData *gAPadded = TGNPad256(gA);

    // u := H(g_a | g_b)
    NSData *u = MTSha256(TGNConcat(@[gAPadded, gBPadded]));
    if (MTIsZero(u))
        return nil;

    // t := (g_b - k_v) mod p ; s_a := t^(a + u * x) mod p
    NSData *t = MTModSub(gB, kV, p);
    NSData *exponent = MTAdd(a, MTMul(u, x));
    NSData *sA = MTExp(t, exponent, p);
    NSData *kA = MTSha256(TGNPad256(sA));

    // M1 := H(H(p) xor H(g) | H(salt1) | H(salt2) | g_a | g_b | k_a)
    NSData *m1 = MTSha256(TGNConcat(@[
        TGNXor(MTSha256(p), MTSha256(gPadded)),
        MTSha256(salt1),
        MTSha256(salt2),
        gAPadded,
        gBPadded,
        kA
    ]));

    return @{@"_": @"inputCheckPasswordSRP", @"srp_id": srpId, @"A": gAPadded, @"M1": m1};
}
