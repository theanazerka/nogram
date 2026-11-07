#!/usr/bin/env python3
"""Apply the nogram patches to a flat copy of MtProtoKit (2018-2019 revisions).

Usage: patch-mtprotokit.py <dir>

- iOS 6 SDK compatibility: endian.h, CFAutorelease, AFNetworking import path
- initConnection#c1cd5ea9 for modern layers (>= 100)
- current production RSA key (fingerprint d09d1d85de64fd85)
- p_q_inner_data_dc + RSA_PAD auth key exchange (current servers)
- raw RSA through OpenSSL (Security.framework keychain needs entitlements)
"""
import os
import re
import sys

D = sys.argv[1]

ENDIAN = ('#include <machine/endian.h>\n#ifndef __BYTE_ORDER\n#   define __BYTE_ORDER BYTE_ORDER\n'
          '#   define __LITTLE_ENDIAN LITTLE_ENDIAN\n#   define __BIG_ENDIAN BIG_ENDIAN\n#endif')

RSA_KEY = r'''[[NSDictionary alloc] initWithObjectsAndKeys:@"-----BEGIN RSA PUBLIC KEY-----\n"
"MIIBCgKCAQEA6LszBcC1LGzyr992NzE0ieY+BSaOW622Aa9Bd4ZHLl+TuFQ4lo4g\n"
"5nKaMBwK/BIb9xUfg0Q29/2mgIR6Zr9krM7HjuIcCzFvDtr+L0GQjae9H0pRB2OO\n"
"62cECs5HKhT5DZ98K33vmWiLowc621dQuwKWSQKjWf50XYFw42h21P2KXUGyp2y/\n"
"+aEyZ+uVgLLQbRA1dEjSDZ2iGRy12Mk5gpYc397aYp438fsJoHIgJ2lgMv5h7WY9\n"
"t6N/byY9Nw9p21Og3AoXSL2q/2IJ1WRUhebgAdGVMlV1fkuOQoEzR7EdpqtQD9Cs\n"
"5+bfo3Nhmcyvk5ftB0WkJ9z6bNZ7yxrP8wIDAQAB\n"
"-----END RSA PUBLIC KEY-----", @"key", [[NSNumber alloc] initWithUnsignedLongLong:0xd09d1d85de64fd85UL], @"fingerprint", nil],
'''

RSA_PAD = r'''

// nogram: RSA_PAD scheme required by current Telegram servers for auth key generation.
// https://core.telegram.org/mtproto/auth_key#presenting-proof-of-work-server-authentication
static NSData *MTRsaModulus(NSString *publicKey)
{
    BIO *keyBio = BIO_new(BIO_s_mem());
    const char *keyData = [publicKey UTF8String];
    BIO_write(keyBio, keyData, (int)strlen(keyData));
    RSA *rsaKey = PEM_read_bio_RSAPublicKey(keyBio, NULL, NULL, NULL);
    BIO_free(keyBio);
    if (rsaKey == NULL)
        return nil;
    NSMutableData *result = [[NSMutableData alloc] initWithLength:(NSUInteger)BN_num_bytes(rsaKey->n)];
    BN_bn2bin(rsaKey->n, result.mutableBytes);
    RSA_free(rsaKey);
    return result;
}

NSData *MTRsaEncryptWithPad(NSString *publicKey, NSData *data)
{
    if (data.length > 144)
        return nil;
    NSData *modulus = MTRsaModulus(publicKey);
    if (modulus.length != 256)
        return nil;

    NSMutableData *dataWithPadding = [[NSMutableData alloc] initWithData:data];
    NSUInteger paddingLength = 192 - data.length;
    if (paddingLength != 0)
    {
        NSMutableData *padding = [[NSMutableData alloc] initWithLength:paddingLength];
        __unused int r = SecRandomCopyBytes(kSecRandomDefault, paddingLength, padding.mutableBytes);
        [dataWithPadding appendData:padding];
    }
    NSMutableData *reversed = [[NSMutableData alloc] initWithLength:192];
    const uint8_t *src = dataWithPadding.bytes;
    uint8_t *dst = reversed.mutableBytes;
    for (NSUInteger i = 0; i < 192; i++)
        dst[i] = src[191 - i];

    for (int attempt = 0; attempt < 64; attempt++)
    {
        NSMutableData *tempKey = [[NSMutableData alloc] initWithLength:32];
        __unused int r = SecRandomCopyBytes(kSecRandomDefault, 32, tempKey.mutableBytes);

        NSMutableData *keyAndData = [[NSMutableData alloc] initWithData:tempKey];
        [keyAndData appendData:dataWithPadding];

        NSMutableData *dataWithHash = [[NSMutableData alloc] initWithData:reversed];
        [dataWithHash appendData:MTSha256(keyAndData)];

        NSMutableData *zeroIv = [[NSMutableData alloc] initWithLength:32];
        MTAesEncryptInplace(dataWithHash, tempKey, zeroIv);

        NSData *aesHash = MTSha256(dataWithHash);
        NSMutableData *keyAesEncrypted = [[NSMutableData alloc] initWithLength:32];
        uint8_t *x = keyAesEncrypted.mutableBytes;
        const uint8_t *k = tempKey.bytes;
        const uint8_t *h = aesHash.bytes;
        for (int i = 0; i < 32; i++)
            x[i] = k[i] ^ h[i];
        [keyAesEncrypted appendData:dataWithHash];

        if (memcmp(keyAesEncrypted.bytes, modulus.bytes, 256) >= 0)
            continue;

        NSData *encrypted = MTRsaEncrypt(publicKey, keyAesEncrypted);
        if (encrypted.length < 256)
        {
            NSMutableData *padded = [[NSMutableData alloc] initWithLength:256 - encrypted.length];
            [padded appendData:encrypted];
            encrypted = padded;
        }
        return encrypted;
    }
    return nil;
}
'''

PQ_INNER = '''                } else {
                    // nogram: p_q_inner_data_dc#a9f55f95 + RSA_PAD (required by current servers)
                    int32_t dcId = (int32_t)mtProto.datacenterId;
                    if (mtProto.media)
                        dcId = -dcId;
                    MTBuffer *innerDataBuffer = [[MTBuffer alloc] init];
                    [innerDataBuffer appendInt32:(int32_t)0xa9f55f95];
                    [innerDataBuffer appendTLBytes:pqBytes];
                    [innerDataBuffer appendTLBytes:_dhP];
                    [innerDataBuffer appendTLBytes:_dhQ];
                    [innerDataBuffer appendBytes:_nonce.bytes length:_nonce.length];
                    [innerDataBuffer appendBytes:_serverNonce.bytes length:_serverNonce.length];
                    [innerDataBuffer appendBytes:_newNonce.bytes length:_newNonce.length];
                    [innerDataBuffer appendInt32:dcId];

                    NSData *encryptedData = MTRsaEncryptWithPad([publicKey objectForKey:@"key"], innerDataBuffer.data);

'''


def path(name):
    return os.path.join(D, name)


def edit(name, fn):
    p = path(name)
    if not os.path.exists(p):
        return
    s = open(p, encoding='utf-8').read()
    t = fn(s)
    if t != s:
        open(p, 'w', encoding='utf-8').write(t)
        print('patched', name)


def endian(s):
    return re.sub(r'#if TARGET_OS_IPHONE\n#\s*import <endian.h>\n#endif', ENDIAN, s)


edit('MTInputStream.m', endian)
edit('MTOutputStream.m', endian)
edit('MTHttpRequestOperation.m', lambda s: s.replace('#import "../thirdparty/AFNetworking/AFHTTPRequestOperation.h"', '#import "AFHTTPRequestOperation.h"'))
edit('PingFoundation.h', lambda s: s if 'sys/socket.h' in s else s.replace('#import <Foundation/Foundation.h>', '#import <Foundation/Foundation.h>\n#include <sys/socket.h>', 1))
edit('PingFoundation.m', lambda s: s if 'PFCFAutorelease' in s else s.replace('#import "PingFoundation.h"\n', '#import "PingFoundation.h"\n\nextern id objc_autorelease(id value);\nstatic inline CFTypeRef PFCFAutorelease(CFTypeRef obj) { return obj ? (__bridge CFTypeRef)objc_autorelease((__bridge id)obj) : NULL; }\n#define CFAutorelease PFCFAutorelease\n', 1))


def init_connection(s):
    if 'nogram: current servers use initConnection' in s:
        return s
    old_simple = '''        bool layerSupportsLangpacks = [_serialization currentLayer] >= 67;

        [buffer appendInt32:(int32_t)(layerSupportsLangpacks ? 0xc7481da6 : 0x69796de9)];'''
    if old_simple in s:
        return s.replace(old_simple, '''        bool layerSupportsLangpacks = [_serialization currentLayer] >= 67;
        // nogram: current servers use initConnection#c1cd5ea9 (flags, optional proxy/params).
        if ([_serialization currentLayer] >= 100) {
            [buffer appendInt32:(int32_t)0xc1cd5ea9];
            [buffer appendInt32:0];
            layerSupportsLangpacks = true;
        } else {
            [buffer appendInt32:(int32_t)(layerSupportsLangpacks ? 0xc7481da6 : 0x69796de9)];
        }''')
    # Revisions with proxy support already write flags; only the constructor id changes.
    return s.replace('[buffer appendInt32:(int32_t)0x785188b8];', '[buffer appendInt32:(int32_t)([_serialization currentLayer] >= 100 ? 0xc1cd5ea9 : 0x785188b8)]; // nogram: current servers use initConnection#c1cd5ea9')


edit('MTRequestMessageService.m', init_connection)


def encryption(s):
    if 'MTRsaEncryptWithPad' in s:
        return s
    s = s.replace('NSData *MTRsaEncrypt(NSString *publicKey, NSData *data)\n{\n#if TARGET_OS_IOS',
                  'NSData *MTRsaEncrypt(NSString *publicKey, NSData *data)\n{\n#if 0 // nogram: always use OpenSSL raw RSA', 1)
    return s + RSA_PAD


edit('MTEncryption.m', encryption)
edit('MTEncryption.h', lambda s: s if 'MTRsaEncryptWithPad' in s else s.replace(
    'NSData *MTRsaEncrypt(NSString *publicKey, NSData *data);',
    'NSData *MTRsaEncrypt(NSString *publicKey, NSData *data);\nNSData *MTRsaEncryptWithPad(NSString *publicKey, NSData *data);', 1))

# SRP helpers used by Telegram 4.9.1's TGTwoStepUtils but missing from 2018 revisions.
SRP_HELPERS = r'''

bool MTIsZero(NSData *value) {
    BIGNUM *bnValue = BN_bin2bn(value.bytes, (int)value.length, NULL);
    bool isZero = BN_is_zero(bnValue);
    BN_free(bnValue);
    return isZero;
}

bool MTCheckIsSafeB(NSData *b, NSData *p) {
    BIGNUM *bnB = BN_bin2bn(b.bytes, (int)b.length, NULL);
    BIGNUM *bnP = BN_bin2bn(p.bytes, (int)p.length, NULL);
    BIGNUM *bnZero = BN_new();
    BN_zero(bnZero);
    bool result = BN_cmp(bnB, bnZero) == 1 && BN_cmp(bnB, bnP) == -1;
    BN_free(bnB);
    BN_free(bnP);
    BN_free(bnZero);
    return result;
}
'''
edit('MTEncryption.m', lambda s: s if 'bool MTIsZero(' in s else s + SRP_HELPERS)
edit('MTEncryption.h', lambda s: s if 'MTIsZero' in s else s.replace(
    'NSData *MTRsaEncryptWithPad(NSString *publicKey, NSData *data);',
    'NSData *MTRsaEncryptWithPad(NSString *publicKey, NSData *data);\nbool MTIsZero(NSData *value);\nbool MTCheckIsSafeB(NSData *b, NSData *p);', 1))


def auth(s):
    anchor = 'serverPublicKeys = [[NSArray alloc] initWithObjects:\n'
    if 'd09d1d85de64fd85' not in s and anchor in s:
        s = s.replace(anchor, anchor + RSA_KEY, 1)
    marker = '                } else {\n                    MTBuffer *innerDataBuffer = [[MTBuffer alloc] init];\n                    [innerDataBuffer appendInt32:(int32_t)0x83c95aec];'
    if marker in s:
        start = s.index(marker)
        end = s.index('                    _dhEncryptedData = encryptedData;\n                }\n', start)
        s = s[:start] + PQ_INNER + s[end:]
    return s


edit('MTDatacenterAuthMessageService.m', auth)
