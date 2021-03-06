//
//  STGStatusItemManager.m
//  Coco Storage
//
//  Created by Lukas Tenbrink on 02.05.13.
//  Copyright (c) 2013 Lukas Tenbrink. All rights reserved.
//

#import "STGStatusItemManager.h"

#import "STGAPIConfiguration.h"

#import "STGRecentUploadView.h"
#import "STGCreateAlbumWindowController.h"

#import "STGDataCaptureEntry.h"
#import "STGUploadedEntry.h"

#import "STGPacketQueue.h"
#import "STGPacket.h"

#import "STGStatusItemDrawingHelper.h"

@interface STGStatusItemManager ()

@property (nonatomic, assign) float uploadProgress;
@property (nonatomic, assign) float isSyncingOpacity;

- (void)updateGUIElements;

@end

@implementation STGStatusItemManager

- (id)init
{
    self = [super init];
    
    if (self)
    {
        NSNib *nib = [[NSNib alloc] initWithNibNamed:@"STGStatusItemManager" bundle:nil];
        
        NSArray *topLevelObjects;
        [nib instantiateWithOwner:self topLevelObjects:&topLevelObjects];
        
        [_statusMenu setAutoenablesItems:NO];
        _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:STGStatusItemWidth];
        [_statusItem setMenu:_statusMenu];
        
        [self setStatusItemView:[[STGStatusItemView alloc] initWithFrame:NSMakeRect(0.0, 0.0, [_statusItem length], [[NSStatusBar systemStatusBar] thickness])]];
        [_statusItemView setStatusItem:_statusItem];
        [_statusItemView setDelegate:self];
        [_statusItemView setMenu:[_statusItem menu]];
        [_statusItem setView:_statusItemView];

        [_statusItem setTitle:@""];
        [_statusItem setHighlightMode:YES];
        [_statusItem setToolTip:@"Coco Storage"];
        [_statusItemView setImage:[STGStatusItemDrawingHelper getIcon:0 uploadProgress:0.0 opacity:0.0]];
                
        [self updateGUIElements];
        
        [self setTimer:[NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES]];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    
    return self;
}

- (void)timerFired:(NSTimer *)timer
{
    if (_isSyncing && _uploadProgress == 0.0)
    {
        if (_isSyncingOpacity < 1.0)
            [self setIsSyncingOpacity:_isSyncingOpacity + 0.25];
    }
    else if(_isSyncing)
    {
        if (_isSyncingOpacity > 0.5)
            [self setIsSyncingOpacity:_isSyncingOpacity - 0.25];
    }
    else
    {
        if (_isSyncingOpacity > 0.0)
            [self setIsSyncingOpacity:_isSyncingOpacity - 0.25];
    }

    [_statusItemView setImage:[STGStatusItemDrawingHelper getIcon:_ticks uploadProgress:_uploadProgress opacity:_isSyncingOpacity]];
    
    if (_isSyncingOpacity > 0.0 || _uploadProgress > 0.0)
    {
        if ([timer timeInterval] != 0.1)
        {
            [timer invalidate];
            [self setTimer:[NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES]];
            [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        }
    }
    else
    {
        if ([timer timeInterval] != 1.0)
        {
            [timer invalidate];
            [self setTimer:[NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES]];
            [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        }
    }
    
    [self setTicks:_ticks + 1];
}

- (void)updateGUIElements
{
    NSString *cfsLinkTitle = [[STGAPIConfiguration currentConfiguration] hasCFS] ? [[STGAPIConfiguration currentConfiguration] cfsLinkTitle] : nil;
    [[self cfsLinkItem] setHidden:cfsLinkTitle == nil];
    [[self cfsSectionSeparatorItem] setHidden:cfsLinkTitle == nil];
    if (cfsLinkTitle)
        [[self fileListLinkItem] setTitle:cfsLinkTitle];

    NSString *accountLinkTitle = [[STGAPIConfiguration currentConfiguration] accountLinkTitle];
    [[self accountLinkItem] setHidden:accountLinkTitle == nil];
    if (accountLinkTitle)
        [[self accountLinkItem] setTitle:accountLinkTitle];
    
    NSString *fileListLinkTitle = [[STGAPIConfiguration currentConfiguration] fileListLinkTitle];
    [[self fileListLinkItem] setHidden:fileListLinkTitle == nil];
    if (fileListLinkTitle)
        [[self fileListLinkItem] setTitle:fileListLinkTitle];
    
    [_createAlbumMenuItem setHidden:![[STGAPIConfiguration currentConfiguration] hasAlbums]];
}

- (void)updateRecentFiles:(NSArray *)recentFiles
{
    [[_recentFilesItem submenu] removeAllItems];
    
    if ([recentFiles count] == 0)
    {
        [[_recentFilesItem submenu] addItem:_noRecentFilesItem];
    }
    else
    {
        for (int i = 0; i < [recentFiles count] && i < 10; i++)
        {
            STGUploadedEntry *entry = [recentFiles objectAtIndex:(int)[recentFiles count] - i - 1];
   
            NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"Recent upload" action:@selector(openRecentFile:) keyEquivalent:@""];
            [menuItem setTarget:self];
            
            NSViewController *tempController = [[NSViewController alloc] initWithNibName:@"STGRecentFileView" bundle:nil];
            
            STGRecentUploadView *itemView = (STGRecentUploadView *)[tempController view];
            [menuItem setView:itemView];
            [itemView setCaptureEntry:entry];
            [itemView setRecentUploadDelegate:self];
            
            NSString *displayName = [entry entryName];
            NSImage *displayImage = [entry entryIcon];
            
            [[[menuItem view] viewWithTag:10] setImage:displayImage];
            [[itemView viewWithTag:11] setStringValue:displayName];
            [[itemView viewWithTag:12] setStringValue:[[entry onlineLink] absoluteString]];
            [[itemView viewWithTag:13] setAction:@selector(deleteRecentFile:)];
            [[itemView viewWithTag:13] setTarget:self];
            [[itemView viewWithTag:14] setAction:@selector(copyRecentFileLink:)];
            [[itemView viewWithTag:14] setTarget:self];
            
            [[_recentFilesItem submenu] addItem:menuItem];
        }
    }
}

- (void)updateUploadQueue:(STGPacketQueue *)packetQueue currentProgress:(float)currentFileProgress
{
    [[_currentUploadsItem submenu] removeAllItems];
    
    NSMutableArray *uploadEntries = [[NSMutableArray alloc] init];
    
    for (STGPacket *entry in [packetQueue uploadQueue])
    {
        if ([[entry packetType] isEqualToString:@"uploadFile"])
        {
            [uploadEntries addObject:entry];
        }
    }
    
    if ([uploadEntries count] == 0)
    {
        [[_currentUploadsItem submenu] addItem:_noCurrentUploadItem];
    }
    else
    {
        [[_currentUploadsItem submenu] addItem:_cancelUploadsMenuItem];
        [[_currentUploadsItem submenu] addItem:[NSMenuItem separatorItem]];
        
        for (int i = 0; i < [uploadEntries count] && i < 10; i++)
        {
            if (i < 9 || [uploadEntries count] == 10)
            {
                float progress = (i == 0) ? currentFileProgress : 0.0;
                NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%3.2f%%)", [[[[[uploadEntries objectAtIndex:i] userInfo] objectForKey:@"dataCaptureEntry"] fileURL] lastPathComponent], progress * 100] action:@selector(cancelQueueFile:) keyEquivalent:@""];
                [menuItem setTarget:self];
                [menuItem setImage:[NSImage imageNamed:@"NSStopProgressTemplate"]];
                [menuItem setTag:i];
                
                [[_currentUploadsItem submenu] addItem:menuItem];
            }
            else
            {
                [[_currentUploadsItem submenu] addItem:_moreCurrentUploadsItem];
            }
        }
    }
}

- (void)setStatusItemUploadProgress:(float)progress
{
    [self setUploadProgress:progress];
}

- (void)menuWillOpen:(NSMenu *)menu
{
    NSArray *clipboardCapturableItems = [STGAPIConfiguration validUploadActions:[STGDataCaptureManager getActionsFromPasteboard:[NSPasteboard generalPasteboard]] forConfiguration:[STGAPIConfiguration currentConfiguration]];
    [[self captureClipboardMenuItem] setEnabled:[clipboardCapturableItems count] > 0];
}

- (void)menuDidClose:(NSMenu *)menu
{
    for (NSMenuItem *item in [[_recentFilesItem submenu] itemArray])
    {
        if ([[item view] isKindOfClass:[STGRecentUploadView class]])
        {
            [(STGRecentUploadView *)[item view] setIsHighlighted:NO];
        }
    }
}

- (void)updatePauseDownloadItem
{
    BOOL pause = [[NSUserDefaults standardUserDefaults] boolForKey:@"pauseUploads"];
    
    if (pause)
    {
        [_pauseUploadsItem setState:NSOnState];
    }
    else
    {
        [_pauseUploadsItem setState:NSOffState];
    }
}

- (void)updateServerStatus:(STGServerStatus)status
{
    NSString *tooltipString = @"Unknown";
    NSString *statusString = @"Unknown";
    NSInteger availability = 0;
    
    if (status == STGServerStatusOnline)
    {
        tooltipString = @"OK";
        statusString = @"Server: Online";
        
        availability = 2;
    }
    if (status == STGServerStatusServerOffline)
    {
        tooltipString = @"Offline";
        statusString = @"Server: Offline";
    }
    if (status == STGServerStatusClientOffline)
    {
        tooltipString = @"No internet connection";
        statusString = @"No internet connection";
    }
    if (status == STGServerStatusServerBusy)
    {
        tooltipString = @"Busy";
        statusString = @"Server: Busy";
    }
    if (status == STGServerStatusServerV1Busy)
    {
        tooltipString = @"No quick uploads";
        statusString = @"No quick uploads";
        
        availability = 1;
    }
    if (status == STGServerStatusServerV2Busy)
    {
        tooltipString = @"No CFS";
        statusString = @"No CFS";
        
        availability = 1;
    }
    if (status == STGServerStatusInvalidKey)
    {
        tooltipString = @"Invalid Key";
        statusString = @"Invalid Key";
    }

    [_serverStatusItem setTitle:statusString];
    [_serverStatusItem setImage:[NSImage imageNamed:availability == 2 ? @"NSStatusAvailable" : (availability == 1 ? @"NSStatusPartiallyAvailable" : @"NSStatusUnavailable")]];
    [_statusItemView setToolTip:[NSString stringWithFormat:@"Coco Storage - Server status: %@\nDrag and drop anything here to upload it!", tooltipString]];
}

- (BOOL)typeChooserViewOpen
{
    return [_statusItemView typeChooserViewOpen];
}

- (void)closeTypeChooserView
{
    [_statusItemView closeTypeChooserView];
}

- (IBAction)captureArea:(id)sender
{
    if ([_delegate respondsToSelector:@selector(captureScreen:)])
    {
        [_delegate captureScreen:NO];
    }
}

- (IBAction)captureFullScreen:(id)sender
{
    if ([_delegate respondsToSelector:@selector(captureScreen:)])
    {
        [_delegate captureScreen:YES];
    }
}

- (void)captureMovie:(id)sender
{
    if ([_delegate respondsToSelector:@selector(captureMovie)])
    {
        [_delegate captureMovie];
    }
}

- (IBAction)captureFile:(id)sender
{
    if ([_delegate respondsToSelector:@selector(captureFile)])
    {
        [_delegate captureFile];
    }
}

- (void)captureClipboard:(id)sender
{
    [self captureClipboard];
}

- (BOOL)captureClipboard
{
    NSArray *actions = [STGDataCaptureManager getActionsFromPasteboard:[NSPasteboard generalPasteboard]];
    actions = [STGAPIConfiguration validUploadActions:actions forConfiguration:[STGAPIConfiguration currentConfiguration]];
    
    if ([actions count] > 0)
    {
        [_statusItemView displayForUploadTypes:actions];
        return YES;
    }
    
    return NO;
}

- (void)createAlbum:(id)sender
{
    if ([_delegate respondsToSelector:@selector(createAlbum)])
    {
        [_delegate createAlbum];
    }
}

- (IBAction)quit:(id)sender
{
    [NSApp terminate:self];
}

- (IBAction)openCFSFolder:(id)sender
{
    [[STGAPIConfiguration currentConfiguration] openCFSLink];
}

- (IBAction)cancelUploads:(id)sender
{
    if ([_delegate respondsToSelector:@selector(cancelAllUploads)])
    {
        [_delegate cancelAllUploads];
    }
}

- (IBAction)togglePauseUploads:(id)sender
{
    if ([_delegate respondsToSelector:@selector(togglePauseUploads)])
    {
        [_delegate togglePauseUploads];
    }
}

- (IBAction)openRecentFile:(id)sender
{
    STGUploadedEntry *entry = [(STGRecentUploadView *)[sender superview] captureEntry];
    
    [[NSWorkspace sharedWorkspace] openURL:[entry onlineLink]];
}

- (IBAction)deleteRecentFile:(id)sender
{
    if ([_delegate respondsToSelector:@selector(deleteRecentFile:)])
    {
        STGUploadedEntry *entry = [(STGRecentUploadView *)[sender superview] captureEntry];

        [_delegate deleteRecentFile:entry];
    }
}

- (IBAction)copyRecentFileLink:(id)sender
{
    NSString *link = [[[sender superview] viewWithTag:12] stringValue];
    NSURL *url = [NSURL URLWithString:link];
    
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] writeObjects:[NSArray arrayWithObject:url]];
    
    [[_statusItem menu] cancelTracking];
}

- (void)recentUploadView:(STGRecentUploadView *)recentUploadView clicked:(NSEvent *)theEvent
{
    [[_statusItem menu] cancelTracking];
    
    [[NSWorkspace sharedWorkspace] openURL:[[recentUploadView captureEntry] onlineLink]];
}

- (IBAction)cancelQueueFile:(id)sender
{
    if ([_delegate respondsToSelector:@selector(cancelQueueFile:)])
    {
        int index = (int)[sender tag];

        [_delegate cancelQueueFile:index];
    }
}

- (IBAction)openStorageAccount:(id)sender
{
    [[STGAPIConfiguration currentConfiguration] openAccountLink];
}

- (IBAction)openMyFiles:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://getstorage.net/panel/object"]];
}

- (IBAction)openPreferences:(id)sender
{
    if ([_delegate respondsToSelector:@selector(openPreferences)])
    {
        [_delegate openPreferences];
    }
}

- (void)openAboutWindow:(id)sender
{
    if ([_delegate respondsToSelector:@selector(openAboutWindow)])
    {
        [_delegate openAboutWindow];
    }
}

-(void)uploadEntries:(NSArray *)entries
{
    if ([_delegate respondsToSelector:@selector(uploadEntries:)])
    {
        [_delegate uploadEntries:entries];
    }
}

- (void)stopRecording:(id)sender
{
    if ([_delegate respondsToSelector:@selector(stopRecording)])
    {
        [_delegate stopRecording];
    }
}

- (void)cancelRecording:(id)sender
{
    if ([_delegate respondsToSelector:@selector(cancelRecording)])
    {
        [_delegate cancelRecording];
    }
}

- (void)setMovieControlsVisible:(BOOL)visible
{
    [_stopRecordingMenuItem setHidden:!visible];
    [_cancelRecordingMenuItem setHidden:!visible];
    [_recordingSectionSeparatorItem setHidden:!visible];

    [_captureMovieMenuItem setEnabled:!visible];
    [self setIsSyncing:visible]; // TODO Remove or replace with something more appropriate later
}

@end
