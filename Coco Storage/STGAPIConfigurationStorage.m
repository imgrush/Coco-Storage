//
//  STGAPIConfigurationStorage.m
//  Coco Storage
//
//  Created by Lukas Tenbrink on 08.08.14.
//  Copyright (c) 2014 Lukas Tenbrink. All rights reserved.
//

#import "STGAPIConfigurationStorage.h"

#import "STGNetworkHelper.h"
#import "STGPacket.h"
#import "STGJSONHelper.h"
#import "STGPacketQueue.h"

#import "STGDataCaptureEntry.h"

STGAPIConfigurationStorage *standardConfiguration;

@implementation STGAPIConfigurationStorage

@synthesize delegate;

+ (STGAPIConfigurationStorage *)standardConfiguration
{
    if (!standardConfiguration)
    {
        standardConfiguration = [[STGAPIConfigurationStorage alloc] init];
        
//        [standardConfiguration setGetObjectInfoLink:@"https://api.stor.ag/v1/object/%@?key=%@"];
//        [standardConfiguration setCfsBaseLink:@"https://api.stor.ag/v2/cfs%@?key=%@"];
    }
    
    return standardConfiguration;
}

- (NSString *)apiHostName
{
    return @"stor.ag";
}

- (BOOL)hasAPIKeys
{
    return YES;
}

- (BOOL)canReachServer
{
    return [STGNetworkHelper isWebsiteReachable:@"stor.ag"];
}

- (void)handlePacket:(STGPacket *)entry fullResponse:(NSData *)response urlResponse:(NSURLResponse *)urlResponse
{
    NSUInteger responseCode = 0;
    if ([urlResponse isKindOfClass:[NSHTTPURLResponse class]])
    {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) urlResponse;
        
        responseCode = [httpResponse statusCode];
        
//        NSLog(@"Status (ERROR!): (%li) %@", (long)[httpResponse statusCode], [NSHTTPURLResponse localizedStringForStatusCode:[httpResponse statusCode]]);
//        
//        NSDictionary *headerFields = [httpResponse allHeaderFields];
//        NSLog(@"----Headers----");
//        for (NSObject *key in [headerFields allKeys])
//        {
//            NSLog(@"\"%@\" : \"%@\"", key, [headerFields objectForKey:key]);
//        }
    }

    if ([[entry packetType] isEqualToString:@"uploadFile"])
    {
        NSDictionary *dictionary = [STGJSONHelper getDictionaryJSONFromData:response];
        
        NSString *uploadID = [dictionary objectForKey:@"id"];
        NSString *link = uploadID ? [NSString stringWithFormat:@"http://stor.ag/e/%@", uploadID] : nil;
        
        if (link)
        {
            [[[entry userInfo] objectForKey:@"dataCaptureEntry"] setOnlineLink:link];
            
            if ([[NSUserDefaults standardUserDefaults] integerForKey:@"displayNotification"] == 1)
            {
                NSUserNotification *notification = [[NSUserNotification alloc] init];
                
                [notification setTitle:[NSString stringWithFormat:@"Coco Storage Upload complete: %@!", link]];
                [notification setInformativeText:@"Click to view the uploaded file"];
                [notification setSoundName:nil];
                [notification setUserInfo:[NSDictionary dictionaryWithObject:link forKey:@"uploadLink"]];
                
                [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
            }
            
            if (![[[NSUserDefaults standardUserDefaults] stringForKey:@"completionSound"] isEqualToString:@"noSound"])
            {
                NSSound *sound = [NSSound soundNamed:[[NSUserDefaults standardUserDefaults] stringForKey:@"completionSound"]];
                
                if (sound)
                    [sound play];
            }
            
            if ([[NSUserDefaults standardUserDefaults] integerForKey:@"linkCopyToPasteboard"] == 1)
            {
                [[NSPasteboard generalPasteboard] clearContents];
                [[NSPasteboard generalPasteboard] setString:link forType:NSPasteboardTypeString];
            }
            
            if ([[NSUserDefaults standardUserDefaults] integerForKey:@"linkOpenInBrowser"] == 1)
            {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:link]];
            }
            
            if ([[self delegate] respondsToSelector:@selector(didUploadDataCaptureEntry:)])
            {
                [[self delegate] didUploadDataCaptureEntry:[[entry userInfo] objectForKey:@"dataCaptureEntry"] success:YES];
            }
        }
        else
        {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Coco Storage Upload Error" defaultButton:@"Open Preferences" alternateButton:@"OK" otherButton:nil informativeTextWithFormat:@"Coco Storage could not complete your file upload... Make sure your Storage key is valid, and try again.\nHTTP Status: %@ (%li)", [NSHTTPURLResponse localizedStringForStatusCode:responseCode], responseCode];
            [alert beginSheetModalForWindow:nil modalDelegate:self didEndSelector:@selector(keyMissingSheetDidEnd:returnCode:contextInfo:) contextInfo:nil];
            
            NSLog(@"Upload file (error?). Response:\n%@\nStatus: %li (%@)", response, responseCode, [NSHTTPURLResponse localizedStringForStatusCode:responseCode]);
            
            if ([[self delegate] respondsToSelector:@selector(didUploadDataCaptureEntry:)])
            {
                [[self delegate] didUploadDataCaptureEntry:[[entry userInfo] objectForKey:@"dataCaptureEntry"] success:NO];
            }
        }
    }
    else if ([[entry packetType] isEqualToString:@"deleteFile"])
    {
        NSDictionary *dictionary = [STGJSONHelper getDictionaryJSONFromData:response];
        
        NSString *message = [dictionary objectForKey:@"message"];
        
        if ([message isEqualToString:@"Object deleted."])
        {
            
        }
        else
        {
            /*            [[[_statusItemManager statusItem] menu] cancelTracking];
             NSAlert *alert = [NSAlert alertWithMessageText:@"Coco Storage Upload Error" defaultButton:@"Open Preferences" alternateButton:@"OK" otherButton:nil informativeTextWithFormat:@"Coco Storage could not complete your file deletion... Make sure your Storage key is valid, and try again.\nHTTP Status: %@ (%li)", [NSHTTPURLResponse localizedStringForStatusCode:responseCode], responseCode];
             [alert beginSheetModalForWindow:nil modalDelegate:self didEndSelector:@selector(keyMissingSheetDidEnd:returnCode:contextInfo:) contextInfo:nil];*/
            
            if (responseCode != 500) //Not found, probably
                NSLog(@"Delete file (error?). Response:\n%@\nStatus: %li (%@)", response, responseCode, [NSHTTPURLResponse localizedStringForStatusCode:responseCode]);
        }
    }
    else if ([[entry packetType] isEqualToString:@"getAPIStatus"])
    {
        NSDictionary *dictionary = nil;
        if ([response length] > 0)
            dictionary = [STGJSONHelper getDictionaryJSONFromData:response];
        
        NSString *stringStatus = dictionary ? [dictionary objectForKey:@"status"] : nil;

        if ([[self delegate] respondsToSelector:@selector(updateAPIStatus:validKey:)])
        {
            if ([[[entry userInfo] objectForKey:@"apiVersion"] integerValue] == 1)
                [[self delegate] updateAPIStatus:[stringStatus isEqualToString:@"ok"] validKey:responseCode != 401];
        }
    }
    else if ([[entry packetType] isEqualToString:@"cfs:getFileList"])
    {
        NSArray *filesRoot = [STGJSONHelper getArrayJSONFromData:response];
        
        NSLog(@"Files: %@", filesRoot);
    }
    else if ([[entry packetType] isEqualToString:@"cfs:deleteFile"])
    {
        if (responseCode != 200)
            NSLog(@"File deletion failed: %@. Response:\n%@\nStatus: %li (%@)", [[entry urlRequest] URL], response, responseCode, [NSHTTPURLResponse localizedStringForStatusCode:responseCode]);
    }
    else
    {
        NSLog(@"Unknown packet entry. Entry: \"%@\"\nResponse:\n%@\nStatus: %li (%@)", [entry packetType], response, responseCode, [NSHTTPURLResponse localizedStringForStatusCode:responseCode]);
    }
}

- (void)cancelPacketUpload:(STGPacket *)entry
{
    if ([[entry packetType] isEqualToString:@"uploadFile"])
    {
        if ([[self delegate] respondsToSelector:@selector(didUploadDataCaptureEntry:)])
        {
            [[self delegate] didUploadDataCaptureEntry:[[entry userInfo] objectForKey:@"dataCaptureEntry"] success:NO];            
        }
    }
}

- (void)sendStatusPacket:(STGPacketQueue *)packetQueue apiKey:(NSString *)apiKey
{
    NSURLRequest *request = [STGPacket defaultRequestWithUrl:[NSString stringWithFormat:@"https://api.stor.ag/v1/status?key=%@", apiKey] httpMethod:@"GET" contentParts:nil];
    
    STGPacket *packet = [STGPacket genericPacketWithRequest:request packetType:@"getAPIStatus" userInfo:[NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:1] forKey:@"apiVersion"]];

    [packetQueue addEntry:packet];
    
//    [_packetSupportQueue addEntry:[STGPacketCreator apiStatusPacket:@"https://api.stor.ag/v2/status?key=%@" apiInfo:2 key:[self getApiKey]]];
}

- (void)sendFileUploadPacket:(STGPacketQueue *)packetQueue apiKey:(NSString *)apiKey entry:(STGDataCaptureEntry *)entry public:(BOOL)publicFile
{
    NSData *contentPart = [STGPacket contentPartObjectsForKeys:
                           [NSDictionary dictionaryWithObjectsAndKeys:
                            @"file", @"name",
                            [[entry fileURL] lastPathComponent], @"filename",
                            publicFile ? @"false" : @"true", @"private",
                            nil] content:[NSData dataWithContentsOfURL:[entry fileURL]]];
    NSArray *requestParts = [NSArray arrayWithObject:contentPart];
    
    NSURLRequest *request = [STGPacket defaultRequestWithUrl:[NSString stringWithFormat:@"https://api.stor.ag/v1/object?key=%@", apiKey] httpMethod:@"POST" contentParts:requestParts];
    
    STGPacket *packet = [STGPacket genericPacketWithRequest:request packetType:@"uploadFile" userInfo:[NSMutableDictionary dictionaryWithObject:entry forKey:@"dataCaptureEntry"]];
    
    [packetQueue addEntry:packet];
}

- (void)sendFileDeletePacket:(STGPacketQueue *)packetQueue apiKey:(NSString *)apiKey entry:(STGDataCaptureEntry *)entry
{
    NSUInteger entryIDLoc = [[entry onlineLink] rangeOfString:@"/" options:NSBackwardsSearch].location;
    
    if (entryIDLoc == NSNotFound)
        NSLog(@"Could not find ID in online link!");
    
    NSString *entryID = [[entry onlineLink] substringFromIndex:entryIDLoc + 1];
    NSString *urlString = [NSString stringWithFormat:@"https://api.stor.ag/v1/object/%@?key=%@", entryID, apiKey];
    
    NSURLRequest *request = [STGPacket defaultRequestWithUrl:urlString httpMethod:@"DELETE" fileName:[[entry fileURL] lastPathComponent] mainBodyData:[NSData dataWithContentsOfURL:[entry fileURL]]];
    
    STGPacket *packet = [STGPacket genericPacketWithRequest:request packetType:@"deleteFile" userInfo:[NSMutableDictionary dictionaryWithObject:entry forKey:@"dataCaptureEntry"]];

    [packetQueue addEntry:packet];
}

//+ (STGPacket *)objectInfoPacket:(NSString *)objectID link:(NSString *)link key:(NSString *)key
//{
//    NSURLRequest *request = [STGPacket defaultRequestWithUrl:[NSString stringWithFormat:link, objectID, key] httpMethod:@"GET" contentParts:nil];
//    
//    STGPacket *packet = [STGPacket genericPacketWithRequest:request packetType:@"getObjectInfo" userInfo:[NSMutableDictionary dictionary]];
//    
//    return packet;
//}
//
//+ (STGPacket *)cfsGenericPacket:(NSString *)httpMethod path:(NSString *)filePath link:(NSString *)link key:(NSString *)key packetType:(NSString *)packetType
//{
//    NSURLRequest *request = [STGPacket defaultRequestWithUrl:[NSString stringWithFormat:link, filePath, key] httpMethod:httpMethod contentParts:nil];
//    
//    STGPacket *packet = [STGPacket genericPacketWithRequest:request packetType:packetType userInfo:[NSMutableDictionary dictionaryWithObject:filePath forKey:@"filePath"]];
//    
//    return packet;
//}
//
//+ (STGPacket *)cfsFileListPacket:(NSString *)filePath link:(NSString *)link recursive:(BOOL)recursive key:(NSString *)key
//{
//    NSURLRequest *request = [STGPacket defaultRequestWithUrl:[NSString stringWithFormat:link, filePath, key] httpMethod:@"GET" contentParts:nil];
//    
//    STGPacket *packet = [STGPacket genericPacketWithRequest:request packetType:@"cfs:getFileList" userInfo:[NSMutableDictionary dictionaryWithObject:filePath forKey:@"filePath"]];
//    
//    return packet;
//}
//
//+ (STGPacket *)cfsFileInfoPacket:(NSString *)filePath link:(NSString *)link key:(NSString *)key
//{
//    return [self cfsGenericPacket:@"HEAD" path:filePath link:link key:key packetType:@"cfs:getFileInfo"];
//}
//
//+ (STGPacket *)cfsPostFilePacket:(NSString *)filePath fileURL:(NSURL *)fileURL link:(NSString *)link key:(NSString *)key
//{
//    NSURL *innerURL = [NSURL URLWithString:filePath];
//    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:@"file", @"name", [innerURL lastPathComponent], @"filename", [[innerURL URLByDeletingLastPathComponent] path], @"folder", nil];
//    
//    NSData *contentPart = [STGPacket contentPartObjectsForKeys:dict content:[NSData dataWithContentsOfURL:fileURL]];
//    
//    NSMutableURLRequest *request = [STGPacket defaultRequestWithUrl:[NSString stringWithFormat:link, @"", key] httpMethod:@"POST" contentParts:[NSArray arrayWithObject:contentPart]];
//    
//    STGPacket *packet = [STGPacket genericPacketWithRequest:request packetType:@"cfs:postFile" userInfo:[NSMutableDictionary dictionaryWithObject:filePath forKey:@"filePath"]];
//    
//    return packet;
//}
//
//+ (STGPacket *)cfsUpdateFilePacket:(NSString *)filePath fileURL:(NSURL *)fileURL link:(NSString *)link key:(NSString *)key
//{
//    NSURLRequest *request = [STGPacket defaultRequestWithUrl:[NSString stringWithFormat:link, filePath, key] httpMethod:@"PUT" fileName:nil mainBodyData:[NSData dataWithContentsOfURL:fileURL]];
//    
//    STGPacket *packet = [STGPacket genericPacketWithRequest:request packetType:@"cfs:updateFile" userInfo:[NSMutableDictionary dictionaryWithObject:filePath forKey:@"filePath"]];
//    
//    return packet;
//}
//
//+ (STGPacket *)cfsDeleteFilePacket:(NSString *)filePath link:(NSString *)link key:(NSString *)key
//{
//    return [self cfsGenericPacket:@"DELETE" path:filePath link:link key:key packetType:@"cfs:deleteFile"];
//}


@end
