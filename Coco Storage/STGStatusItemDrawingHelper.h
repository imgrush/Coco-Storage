//
//  STGStatusItemDrawingHelper.h
//  Coco Storage
//
//  Created by Lukas Tenbrink on 18.05.13.
//  Copyright (c) 2013 Lukas Tenbrink. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface STGStatusItemDrawingHelper : NSObject

+ (NSImage *)getIcon:(int)ticks uploadProgress:(float)uploadProgress opacity:(float)opacity;

@end
