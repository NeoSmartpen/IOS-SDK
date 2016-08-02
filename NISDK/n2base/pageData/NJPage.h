//
//  NJPage.h
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NJMedia.h"

#define MAX_NODE_NUMBER 1024

@class NJStroke;

@interface NJPage : NSObject
@property (strong, nonatomic) NSMutableArray *strokes;
@property (nonatomic) BOOL pageHasChanged;
@property (nonatomic) CGRect bounds;
@property (strong, nonatomic) UIImage *image;
@property (nonatomic) CGSize paperSize; //notebook size
@property (nonatomic) float screenRatio;
@property (nonatomic) int notebookId;
@property (nonatomic) int pageNumber;
@property (nonatomic) float inputScale;
@property (nonatomic) UInt32 penColor;
@property (nonatomic) NSDate *cTime;
@property (nonatomic) NSDate *mTime;
@property (strong, nonatomic) NSMutableArray *voiceMemo;
@property (nonatomic, strong) NSString *pageGuid;

- (id) initWithNotebookId:(int)notebookId andPageNumber:(int)pageNumber;
- (void) addMedia:(NJMedia *)media;
- (void) addStrokes:(NJStroke *)stroke;
- (void) insertStrokeByTimestamp:(NJStroke *)stroke;
- (UIImage *) drawPageWithImage:(UIImage *)image size:(CGRect)bounds drawBG:(BOOL)drawBG opaque:(BOOL)opaque;
- (UIImage *) drawPageWithImage:(UIImage *)image size:(CGRect)bounds forMode:(NeoMediaRenderingMode)mode;
- (UIImage *) drawPageBackgroundImage:(UIImage *)image size:(CGRect)bounds;
- (UIImage *) drawStroke: (NJStroke *)stroke withImage:(UIImage *)image
                    size:(CGRect)bounds scale:(float)scale
                 offsetX:(float)offset_x offsetY:(float)offset_y drawBG:(BOOL)drawBG opaque:(BOOL)opaque;
- (UIImage *) drawStrokesFrom:(NSInteger)start to:(NSInteger)end time:(UInt64)timestamp withImage:(UIImage *)image
                    withVoice:(BOOL)withVoice forMode:(NeoMediaRenderingMode)mode
                         size:(CGRect)bounds scale:(float)scale
                      offsetX:(float)offset_x offsetY:(float)offset_y nextIndex:(NSInteger *)nextIndex;
- (NSArray *) drawStroke2: (NJStroke *)stroke withImage:(UIImage *)image
                     size:(CGRect)bounds scale:(float)scale
                  offsetX:(float)offset_x offsetY:(float)offset_y;
- (NSArray *) drawStroke2: (NJStroke *)stroke withImage:(UIImage *)image
                     size:(CGRect)bounds scale:(float)scale
                  offsetX:(float)offset_x offsetY:(float)offset_y withVoice:(BOOL)withVoice forMode:(NeoMediaRenderingMode)mode;
- (UIImage *) renderPageWithImage:(UIImage *)image size:(CGRect)bounds;
- (void)setTransformationWithOffsetX:(float)x offset_y:(float)y scale:(float)scale;
- (BOOL) dirtyBit;
- (void) setDirtyBit:(BOOL)dirtyBit;
- (BOOL) saveToURL:(NSURL *)url;
- (BOOL) readFromURL:(NSURL *)url error:(NSError *__autoreleasing *)outError;
- (CGRect)imageSize:(int)size;
@end
