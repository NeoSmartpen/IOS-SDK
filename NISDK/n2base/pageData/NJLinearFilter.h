//
//  NJNode.h
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NJLinearFilter : NSObject
+ (NJLinearFilter *) sharedInstance;
- (void) applyToX :(float *)x Y:(float *)y pressure:(float *)p size:(int)size;
@end
