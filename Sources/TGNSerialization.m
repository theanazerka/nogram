#import "TGNSerialization.h"

#import <MTProtoKit/MTExportedAuthorizationData.h>
#import <MTProtoKit/MTDatacenterAddressListData.h>
#import <MTProtoKit/MTDatacenterAddress.h>

#import "TL.h"

@implementation TGNSerialization

- (NSUInteger)currentLayer
{
    return (NSUInteger)[TLSchema shared].layer;
}

- (id)parseMessage:(NSData *)data
{
    return TLParse(data, nil, NULL);
}

- (MTExportAuthorizationResponseParser)exportAuthorization:(int32_t)datacenterId data:(__autoreleasing NSData **)data
{
    if (data != NULL)
        *data = TLSerialize(@{@"_": @"auth.exportAuthorization", @"dc_id": @(datacenterId)});
    return ^MTExportedAuthorizationData *(NSData *response)
    {
        id result = TLParse(response, @"auth.ExportedAuthorization", NULL);
        if (!TLIs(result, @"auth.exportedAuthorization"))
            return nil;
        return [[MTExportedAuthorizationData alloc] initWithAuthorizationBytes:result[@"bytes"] authorizationId:TLLong(result, @"id")];
    };
}

- (NSData *)importAuthorization:(int64_t)authId bytes:(NSData *)bytes
{
    return TLSerialize(@{@"_": @"auth.importAuthorization", @"id": @(authId), @"bytes": bytes ?: [NSData data]});
}

- (MTRequestDatacenterAddressListParser)requestDatacenterAddressWithData:(__autoreleasing NSData **)data
{
    if (data != NULL)
        *data = TLSerialize(@{@"_": @"help.getConfig"});
    return ^MTDatacenterAddressListData *(NSData *response)
    {
        id config = TLParse(response, @"Config", NULL);
        if (!TLIs(config, @"config"))
            return nil;
        NSMutableDictionary *list = [[NSMutableDictionary alloc] init];
        for (NSDictionary *option in TLArray(config, @"dc_options"))
        {
            if (TLBool(option, @"cdn"))
                continue;
            NSNumber *dcId = @(TLInt(option, @"id"));
            NSMutableArray *addresses = list[dcId];
            if (addresses == nil)
            {
                addresses = [[NSMutableArray alloc] init];
                list[dcId] = addresses;
            }
            NSData *secret = [option[@"secret"] isKindOfClass:[NSData class]] ? option[@"secret"] : nil;
            [addresses addObject:[[MTDatacenterAddress alloc] initWithIp:TLString(option, @"ip_address") port:(uint16_t)TLInt(option, @"port") preferForMedia:TLBool(option, @"media_only") restrictToTcp:TLBool(option, @"tcpo_only") cdn:false preferForProxy:TLBool(option, @"static") secret:secret]];
        }
        return [[MTDatacenterAddressListData alloc] initWithAddressList:list];
    };
}

- (MTRequestNoopParser)requestNoop:(__autoreleasing NSData **)data
{
    if (data != NULL)
        *data = TLSerialize(@{@"_": @"help.getNearestDc"});
    return ^id (NSData *response)
    {
        return @(TLParse(response, @"NearestDc", NULL) != nil);
    };
}

@end
