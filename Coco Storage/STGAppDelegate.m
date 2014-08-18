//
//  STGAppDelegate.m
//  Coco Storage
//
//  Created by Lukas Tenbrink on 23.04.13.
//  Copyright (c) 2013 Lukas Tenbrink. All rights reserved.
//

#import "STGAppDelegate.h"

#import <Sparkle/Sparkle.h>

#import "STGDataCaptureManager.h"

#import "STGDataCaptureEntry.h"

#import "STGHotkeyHelper.h"
#import "STGHotkeyHelperEntry.h"

#import "STGSystemHelper.h"
#import "STGFileHelper.h"
#import "STGNetworkHelper.h"

#import "MASPreferencesWindowController.h"

#import "STGStatusItemManager.h"

#import "STGPacketQueue.h"

#import "STGAPIConfiguration.h"
#import "STGAPIConfigurationStorage.h"
#import "STGAPIConfigurationMediacrush.h"

#import "STGJSONHelper.h"

#import "STGCreateAlbumWindowController.h"

#import "STGMovieCaptureSession.h"

#import "STGUncompletedUploadList.h"

STGAppDelegate *sharedAppDelegate;

@implementation STGAppDelegate

#pragma mark - Initializer

- (id)init
{
    self = [super init];
    
    if (self)
    {
        sharedAppDelegate = self;
        
        [self setRecentFilesArray:[[NSMutableArray alloc] init]];
    }
    
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSMutableDictionary *standardDefaults = [[NSMutableDictionary alloc] init];
    [STGOptionsManager registerDefaults:standardDefaults];
    [STGWelcomeWindowController registerStandardDefaults:standardDefaults];
    [standardDefaults setObject:[NSArray array] forKey:@"recentEntries"];
    [standardDefaults setObject:[NSArray array] forKey:@"uploadQueue"];
    [standardDefaults setObject:[NSNumber numberWithBool:NO] forKey:@"pauseUploads"];
    [standardDefaults setObject:@"0.0" forKey:@"lastVersion"];
    [[NSUserDefaults standardUserDefaults] registerDefaults:standardDefaults];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self setNetworkManager:[[STGNetworkManager alloc] init]];
    [_networkManager setDelegate:self];
    
    [self setHotkeyHelper:[[STGHotkeyHelper alloc] initWithDelegate:self]];
    [[self hotkeyHelper] linkToSystem];
    
    [STGAPIConfiguration setCurrentConfiguration:[STGAPIConfigurationMediacrush standardConfiguration]];
    [[STGAPIConfiguration currentConfiguration] setDelegate:_networkManager];
    
    [self setOptionsManager:[[STGOptionsManager alloc] init]];
    [_optionsManager setDelegate:self];
    
    [self setWelcomeWC:[[STGWelcomeWindowController alloc] initWithWindowNibName:@"STGWelcomeWindowController"]];
    [_welcomeWC setWelcomeWCDelegate:self];
    if (![[[NSUserDefaults standardUserDefaults] stringForKey:@"lastVersion"] isEqualToString:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]])
    {
        // Show the update log?
    }
    
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"showWelcomeWindowOnLaunch"] == 1)
    {
        [self openWelcomeWindow:self];
    }
    
    [self setStatusItemManager:[[STGStatusItemManager alloc] init]];
    [_statusItemManager setDelegate:self];
    
    [self setCreateAlbumWC:[[STGCreateAlbumWindowController alloc] initWithWindowNibName:@"STGCreateAlbumWindowController"]];
    [_createAlbumWC setDelegate:self];
    [self setCaptureMovieWC:[[STGMovieCaptureWindowController alloc] initWithWindowNibName:@"STGMovieCaptureWindowController"]];
    [_captureMovieWC setDelegate:self];

    [self readFromUserDefaults];

    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
        
    [_statusItemManager updateRecentFiles:_recentFilesArray];
    [_statusItemManager updateUploadQueue:[_networkManager packetUploadV1Queue] currentProgress:0.0];
    [_statusItemManager updatePauseDownloadItem];
    [self updateShortcuts];
    
    [self setAssistiveDeviceTimer:[NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(assistiveDeviceTimerFired:) userInfo:nil repeats:YES]];
  
//    [_packetSupportQueue addEntry:[STGPacketCreator cfsDeleteFilePacket:@"/foo2.png" link:[[STGAPIConfiguration standardConfiguration] cfsBaseLink] key:[self getApiKey]]];
//    [_packetUploadV2Queue addEntry:[STGPacketCreator cfsPostFilePacket:@"/foo9.png" fileURL:[STGFileHelper urlFromStandardPath:[[self getCFSFolder] stringByAppendingPathComponent:@"/foo2/foo2.png"]] link:[[STGAPIConfiguration standardConfiguration] cfsBaseLink] key:[self getApiKey]]];
}

#pragma mark - Properties

- (void)readFromUserDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSData *uncompletedUploadsData = [defaults objectForKey:@"UploadQueue"];
    if (uncompletedUploadsData)
    {
        STGUncompletedUploadList *uncompletedUploads = [NSKeyedUnarchiver unarchiveObjectWithData:uncompletedUploadsData];
        [uncompletedUploads queueAll:[_networkManager packetUploadV1Queue] inConfiguration:[STGAPIConfiguration currentConfiguration] withKey:[self getApiKey]];
    }

    [_networkManager setUploadsPaused:[[NSUserDefaults standardUserDefaults] boolForKey:@"pauseUploads"]];
    
    NSData *recentFilesData = [defaults objectForKey:@"RecentUploads"];
    if (recentFilesData)
        [self setRecentFilesArray:[NSKeyedUnarchiver unarchiveObjectWithData:recentFilesData]];
    if (![_recentFilesArray isKindOfClass:[NSMutableArray class]])
        [self setRecentFilesArray:[[NSMutableArray alloc] init]];
    
    [STGSystemHelper setStartOnSystemLaunch:[[NSUserDefaults standardUserDefaults] integerForKey:@"startAtLogin"] == 1];
    
    [STGSystemHelper createDockTile];
    [STGSystemHelper setDockTileVisible:([[NSUserDefaults standardUserDefaults] integerForKey:@"showDockIcon"] == 1)];
    
    [_sparkleUpdater setAutomaticallyChecksForUpdates:[[NSUserDefaults standardUserDefaults] integerForKey:@"autoUpdate"] == 1];
    
//    [[_networkManager cfsSyncCheck] setBasePath:[self getCFSFolder]];
    
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"promptedAssistiveDeviceRegister"] && ![STGSystemHelper isAssistiveDevice])
    {
        [self promptAssistiveDeviceRegister];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"promptedAssistiveDeviceRegister"];
    }
}

- (void)saveProperties
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    STGUncompletedUploadList *uncompletedUploads = [[STGUncompletedUploadList alloc] initWithPacketQueue:[_networkManager packetUploadV1Queue]];
    [defaults setObject:[NSKeyedArchiver archivedDataWithRootObject:uncompletedUploads] forKey:@"UploadQueue"];
    
    [defaults setObject:[NSKeyedArchiver archivedDataWithRootObject:_recentFilesArray] forKey:@"RecentUploads"];
    
    [[NSUserDefaults standardUserDefaults] setObject:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] forKey:@"lastVersion"];
    
    [[NSUserDefaults standardUserDefaults] synchronize];    
}

#pragma mark - Timer

- (void)assistiveDeviceTimerFired:(NSTimer *)timer
{
    if ([[self hotkeyHelper] hotkeyStatus] != STGHotkeyStatusOkay)
    {
        if ([STGSystemHelper isAssistiveDevice])
        {
            if (![[self hotkeyHelper] linkToSystem])
                [STGSystemHelper restartUsingSparkle];
        }
        
        [[self optionsManager] updateHotkeyStatus];
    }
}

#pragma mark - Capturing

-(void)captureScreen:(BOOL)fullScreen;
{
    if ([_networkManager isAPIKeyValid:YES])
    {
        [STGDataCaptureManager startScreenCapture:fullScreen tempFolder:[self getTempFolder] silent:[[NSUserDefaults standardUserDefaults] integerForKey:@"playScreenshotSound"] == 0 delegate:self];
    }
}

- (void)captureMovie
{
    [_captureMovieWC showWindow:self];
    [NSApp  activateIgnoringOtherApps:YES];
}

- (void)captureFile
{
    if ([_networkManager isAPIKeyValid:YES])
    {
        [STGDataCaptureManager startFileCaptureWithTempFolder:[self getTempFolder] delegate:self];
    }
}

- (void)createAlbum
{
    NSMutableArray *uploadIDList = [[NSMutableArray alloc] initWithCapacity:[_recentFilesArray count]];
    
    for (STGDataCaptureEntry *entry in _recentFilesArray)
    {
        [uploadIDList addObject:[entry onlineID]];
    }
    
    [_createAlbumWC setUploadIDList:uploadIDList];
    
    [_createAlbumWC showWindow:self];
    [NSApp  activateIgnoringOtherApps:YES];
}

#pragma mark - Uploading

-(void)uploadEntries:(NSArray *)entries
{
    if (entries && [entries count] > 0)
    {
        for (STGDataCaptureEntry *entry in entries)
        {
            if (entry)
            {
                [[STGAPIConfiguration currentConfiguration] sendFileUploadPacket:[_networkManager packetUploadV1Queue] apiKey:[self getApiKey] entry:entry public:YES];
            }
        }
    }
}

- (void)cancelAllUploads
{
    [[_networkManager packetUploadV1Queue] cancelAllEntries];
}

-(void)deleteRecentFile:(STGDataCaptureEntry *)entry
{
    [[STGAPIConfiguration currentConfiguration] sendFileDeletePacket:[_networkManager packetSupportQueue] apiKey:[self getApiKey] entry:entry];
    
    [_recentFilesArray removeObject:entry];
    [_statusItemManager updateRecentFiles:_recentFilesArray];
}

-(void)cancelQueueFile:(int)index
{
    [[_networkManager packetUploadV1Queue] cancelEntryAtIndex:index];
}

-(void)togglePauseUploads
{
    BOOL pause = ![[NSUserDefaults standardUserDefaults] boolForKey:@"pauseUploads"];
    
    [[NSUserDefaults standardUserDefaults] setBool:pause forKey:@"pauseUploads"];
    
    [_networkManager setUploadsPaused:pause];
    
    [_statusItemManager setStatusItemUploadProgress:0.0];
    [_statusItemManager updatePauseDownloadItem];
}

#pragma mark - Windows

- (void)openPreferences
{
    [_optionsManager openPreferencesWindow];
}

- (IBAction)openPreferences:(id)sender
{
    [_optionsManager openPreferencesWindow];
}

- (IBAction)openWelcomeWindow:(id)sender
{
    [_welcomeWC showWindow:self];
    
    [NSApp  activateIgnoringOtherApps:YES];
}

#pragma mark - Shortcuts

- (void)updateShortcuts
{
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [_hotkeyHelper removeAllShortcutEntries];
    
    [_hotkeyHelper addShortcutEntry:[STGHotkeyHelperEntry entryWithAllStatesAndUserInfo:[NSDictionary dictionaryWithObject:@"hotkeyChange" forKey:@"action"]]];
    
    [self tryAddingStandardShortcut:@"hotkeyCaptureArea" action:@"captureArea" menuItem:[_statusItemManager captureAreaMenuItem]];
    [self tryAddingStandardShortcut:@"hotkeyCaptureFullScreen" action:@"captureFullScreen" menuItem:[_statusItemManager captureFullScreenMenuItem]];
    [self tryAddingStandardShortcut:@"hotkeyCaptureFile" action:@"captureFile" menuItem:[_statusItemManager captureFileMenuItem]];
}

- (void)tryAddingStandardShortcut:(NSString *)charsDefaultsKey action:(NSString *)action menuItem:(NSMenuItem *)menuItem
{
    NSString *hotkey = [[NSUserDefaults standardUserDefaults] stringForKey:charsDefaultsKey];

    if ([hotkey length] > 0)
    {
        NSInteger modifiers = [[NSUserDefaults standardUserDefaults] integerForKey:[charsDefaultsKey stringByAppendingString:@"Modifiers"]];
        
        [_hotkeyHelper addShortcutEntry:[STGHotkeyHelperEntry entryWithCharacter:hotkey modifiers:modifiers userInfo:[NSDictionary dictionaryWithObject:action forKey:@"action"]]];
        
        if (menuItem != nil)
        {
            [menuItem setKeyEquivalent:hotkey];
            [menuItem setKeyEquivalentModifierMask:modifiers];
        }        
    }
}

- (NSEvent *)keyPressed:(NSEvent *)event entry:(STGHotkeyHelperEntry *)entry userInfo:(NSDictionary *)userInfo
{
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"pauseUploads"])
    {
        if ([[userInfo objectForKey:@"action"] isEqualToString:@"hotkeyChange"])
        {
            NSEvent *hotkeyReturnEvent = [_optionsManager keyPressed:event];
            
            if (hotkeyReturnEvent != event)
            {
                [self performSelectorOnMainThread:@selector(updateShortcuts) withObject:nil waitUntilDone:NO];
            }
            
            event = hotkeyReturnEvent;
        }
        if ([[userInfo objectForKey:@"action"] isEqualToString:@"captureFullScreen"])
        {
            [self captureScreen:YES];
            
            return nil;
        }
        if ([[userInfo objectForKey:@"action"] isEqualToString:@"captureArea"])
        {
            [self captureScreen:NO];
            
            return nil;
        }
        if ([[userInfo objectForKey:@"action"] isEqualToString:@"captureFile"])
        {
            [self captureFile];
            
            return nil;
        }        
    }
    
    return event;
}

#pragma mark NSApp

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self saveProperties];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    if ([[notification userInfo] objectForKey:@"uploadLink"])
    {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[[notification userInfo] objectForKey:@"uploadLink"]]];
    }
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    if ([_networkManager isAPIKeyValid:YES])
    {
        NSURL *url = [STGFileHelper urlFromStandardPath:filename];
        
        if (url && [url isFileURL] && [[NSFileManager defaultManager] fileExistsAtPath:[url path]])
        {
            STGDataCaptureEntry *entry = [STGDataCaptureManager captureFile:url tempFolder:[self getTempFolder]];
            
            [[STGAPIConfiguration currentConfiguration] sendFileUploadPacket:[_networkManager packetUploadV1Queue] apiKey:[self getApiKey] entry:entry public:YES];
        }
        
        return YES;
    }
    
    return NO;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    if ([_networkManager isAPIKeyValid:YES])
    {
        for (NSString *filename in filenames)
        {
            NSURL *url = [STGFileHelper urlFromStandardPath:filename];
            
            if (url && [url isFileURL] && [[NSFileManager defaultManager] fileExistsAtPath:[url path]])
            {
                STGDataCaptureEntry *entry = [STGDataCaptureManager captureFile:url tempFolder:[self getTempFolder]];
                
                [[STGAPIConfiguration currentConfiguration] sendFileUploadPacket:[_networkManager packetUploadV1Queue] apiKey:[self getApiKey] entry:entry public:YES];
            }
        }
    }
}

#pragma mark - Getters

- (void)keyMissingSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (returnCode == 1)
        [self performSelectorOnMainThread:@selector(openPreferences:) withObject:self waitUntilDone:NO];
}

- (void)assistiveDeviceFailedSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (returnCode == 1)
        [[NSWorkspace sharedWorkspace] openURL:
         [NSURL fileURLWithPath:@"/System/Library/PreferencePanes/Security.prefPane"]];
}

- (void)promptAssistiveDeviceRegister
{
    NSAlert *alert = [NSAlert alertWithMessageText:@"Coco Storage" defaultButton:@"Register as an assistive device" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"To make use of hotkeys, Coco Storage requires access as an assistive device. This requires administrative rights. "];
    [alert beginSheetModalForWindow:nil modalDelegate:self didEndSelector:@selector(assistiveDevicePromptSheetDidEnd:returnCode:contextInfo:) contextInfo:nil];

    [NSApp  activateIgnoringOtherApps:YES];
}

- (void)assistiveDevicePromptSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (returnCode == 1)
        [self registerAsAssistiveDevice];
}

- (void)registerAsAssistiveDevice
{
    NSString *error;
    NSString *output;
    BOOL success = [STGSystemHelper registerAsAssistiveDevice:[[NSBundle mainBundle] bundleIdentifier] error:&error output:&output];
    if (!success)
    {
        if (error != nil)
            NSLog(@"Assistive Device error: %@", error);
        if (error != nil)
            NSLog(@"Assistive Device log: %@", output);

        if (error == nil)
            error = @"Unknown error";
        if ([error isEqualToString:@"Error: columns service, client, client_type are not unique"])
            error = @"Coco Storage is already registered, but most likely not enabled. You can change that in the system preferences.";
        
        NSAlert *alert = [NSAlert alertWithMessageText:@"Coco Storage Error" defaultButton:@"Open System Preferences" alternateButton:@"OK" otherButton:nil informativeTextWithFormat:@"Error while registering for administrative rights: %@\n", error];
        [alert beginSheetModalForWindow:nil modalDelegate:self didEndSelector:@selector(assistiveDeviceFailedSheetDidEnd:returnCode:contextInfo:) contextInfo:nil];

        [NSApp  activateIgnoringOtherApps:YES];
    }
    else
    {
        if (![[self hotkeyHelper] linkToSystem])
            [STGSystemHelper restartUsingSparkle];
    }

    [_optionsManager updateHotkeyStatus];
}

- (BOOL)hotkeysEnabled
{
    return [[self hotkeyHelper] hotkeyStatus] == STGHotkeyStatusOkay;
}

- (NSString *)getApiKey
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"mainStorageKey"];
}

- (NSString *)getCFSFolder
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"cfsFolder"];
}

- (NSString *)getTempFolder
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"tempFolder"];
}

#pragma mark Network Delegate

- (void)serverStatusChanged:(STGNetworkManager *)networkManager
{
    [_statusItemManager updateServerStatus:[networkManager serverStatus]];
}

- (void)fileUploadProgressChanged:(STGNetworkManager *)networkManager
{
    [_statusItemManager updateUploadQueue:[networkManager packetUploadV1Queue] currentProgress:[networkManager fileUploadProgress]];
}

- (void)fileUploadQueueChanged:(STGNetworkManager *)networkManager
{
    [_statusItemManager updateUploadQueue:[networkManager packetUploadV1Queue] currentProgress:[networkManager fileUploadProgress]];
}

- (void)fileUploadCompleted:(STGNetworkManager *)networkManager entry:(STGDataCaptureEntry *)entry successful:(BOOL)successful
{
    if (successful)
    {
        [_recentFilesArray addObject:entry];
        
        while (_recentFilesArray.count > 100)
            [_recentFilesArray removeObjectAtIndex:0];
        
        [_statusItemManager updateRecentFiles:_recentFilesArray];
    }
    
    if ([entry deleteOnCompletetion] &&
        ((successful && [[NSUserDefaults standardUserDefaults] integerForKey:@"keepAllScreenshots"] == 0)
         || (!successful && [[NSUserDefaults standardUserDefaults] integerForKey:@"keepFailedScreenshots"] == 0)))
    {
        if ([entry fileURL] && [[NSFileManager defaultManager] fileExistsAtPath:[[entry fileURL] path]])
        {
            NSError *error = nil;
            
            [[NSFileManager defaultManager] removeItemAtURL:[entry fileURL] error:&error];
            
            if (error)
                NSLog(@"%@", error);
        }
        else
        {
            NSLog(@"Problem: Trying to delete entry without URL!");
        }
    }
}

#pragma mark Album Controller Delegate

- (void)createAlbumWithIDs:(NSArray *)entryIDs
{
    [[STGAPIConfiguration currentConfiguration] sendAlbumCreatePacket:[_networkManager packetUploadV1Queue] apiKey:[self getApiKey] entries:entryIDs];
}

#pragma mark Movie Controller Delegate

- (void)startMovieCapture:(STGMovieCaptureWindowController *)movieCaptureWC
{
    if ([_networkManager isAPIKeyValid:YES] && (_currentMovieCapture == nil || ![_currentMovieCapture isRecording]))
    {
        [self performSelector:@selector(startMovieCaptureIgnoringDelay:) withObject:movieCaptureWC afterDelay:[[movieCaptureWC recordDelay] doubleValue]];
    }
}

- (void)startMovieCaptureIgnoringDelay:(STGMovieCaptureWindowController *)movieCaptureWC
{
    STGMovieCaptureSession *session = [STGDataCaptureManager startScreenMovieCapture:[movieCaptureWC recordRect] display:[[movieCaptureWC recordDisplayID] unsignedIntValue] length:[[movieCaptureWC recordDuration] doubleValue] tempFolder:[self getTempFolder] recordVideo:[movieCaptureWC recordsVideo] recordComputerAudio:[movieCaptureWC recordsComputerAudio] recordMicrophoneAudio:[movieCaptureWC recordsMicrophoneAudio] quality:[movieCaptureWC quality] delegate:self];
    
    [self setCurrentMovieCapture:session];
}

#pragma mark Data Capture Manager Melegate

- (void)dataCaptureCompleted:(STGDataCaptureEntry *)entry sender:(id)sender
{
    [[STGAPIConfiguration currentConfiguration] sendFileUploadPacket:[_networkManager packetUploadV1Queue] apiKey:[self getApiKey] entry:entry public:YES];
}

@end

