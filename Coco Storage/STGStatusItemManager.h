//
//  STGStatusItemManager.h
//  Coco Storage
//
//  Created by Lukas Tenbrink on 02.05.13.
//  Copyright (c) 2013 Lukas Tenbrink. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "STGRecentUploadView.h"

@class STGPacketQueue;
@class STGDataCaptureEntry;

@protocol STGStatusItemManagerDelegate <NSObject>

-(void)captureScreen:(BOOL)fullScreen;
-(void)captureFile;
-(void)cancelAllUploads;
-(void)togglePauseUploads;
-(void)deleteRecentFile:(STGDataCaptureEntry *)entry;
-(void)cancelQueueFile:(int)index;
-(void)openPreferences;

@end

@interface STGStatusItemManager : NSObject <NSMenuDelegate, STGRecentUploadDelegate>

@property (nonatomic, assign) id<STGStatusItemManagerDelegate> delegate;

@property (nonatomic, retain) NSStatusItem *statusItem;

@property (nonatomic, retain) IBOutlet NSMenu *statusMenu;
@property (nonatomic, retain) IBOutlet NSMenuItem *captureAreaMenuItem;
@property (nonatomic, retain) IBOutlet NSMenuItem *captureFullScreenMenuItem;
@property (nonatomic, retain) IBOutlet NSMenuItem *captureFileMenuItem;

@property (nonatomic, retain) IBOutlet NSMenuItem *recentFilesItem;
@property (nonatomic, retain) IBOutlet NSMenuItem *noRecentFilesItem;

@property (nonatomic, retain) IBOutlet NSMenuItem *currentUploadsItem;
@property (nonatomic, retain) IBOutlet NSMenuItem *noCurrentUploadItem;
@property (nonatomic, retain) IBOutlet NSMenuItem *moreCurrentUploadsItem;

@property (nonatomic, retain) IBOutlet NSMenuItem *pauseUploadsItem;

- (IBAction)captureArea:(id)sender;
- (IBAction)captureFullScreen:(id)sender;
- (IBAction)captureFile:(id)sender;

- (IBAction)openStorageAccount:(id)sender;
- (IBAction)openMyFiles:(id)sender;
- (IBAction)openPreferences:(id)sender;
- (IBAction)quit:(id)sender;

- (IBAction)cancelUploads:(id)sender;
- (IBAction)togglePauseUploads:(id)sender;

- (IBAction)openRecentFile:(id)sender;
- (IBAction)deleteRecentFile:(id)sender;
- (IBAction)copyRecentFileLink:(id)sender;

- (IBAction)cancelQueueFile:(id)sender;

- (void)updateRecentFiles:(NSArray *)recentFiles;
- (void)updateUploadQueue:(STGPacketQueue *)packetQueue currentProgress:(float)currentFileProgress;
- (void)updatePauseDownloadItem;

- (void)setStatusItemUploadProgress:(float)progress;

@end
