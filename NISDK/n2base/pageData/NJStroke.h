//
//  NJStroke.h
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NJMedia.h"
#import "configure.h"

@class NJNode;
@interface NJStroke : NJMedia {
    @public
    float *point_x, *point_y, *point_p;
    UInt64 *time_stamp;
    UInt64 start_time;
}

@property (strong, nonatomic) NSArray *nodes;
@property (nonatomic) int dataCount;
@property (strong, nonatomic) NSArray *xData;
@property (strong, nonatomic) NSArray *yData;
@property (strong, nonatomic) NSArray *pData;
@property (nonatomic) float inputScale;
@property (nonatomic) float targetScale;
@property (strong, nonatomic) NJTransformation *transformation;
@property (nonatomic) UInt32 penColor;
@property (nonatomic) NSUInteger penThickness;

- (instancetype) initWithSize:(int)size;
- (instancetype) initWithRawDataX:(float *)point_x Y:(float*)point_y pressure:(float *)point_p
                        time_diff:(int *)time penColor:(UInt32)penColor penThickness:(NSUInteger)thickness startTime:(UInt64)start_at size:(int)size;
- (instancetype) initWithRawDataX:(float *)x Y:(float*)y pressure:(float *)p time_diff:(int *)time
                        penColor:(UInt32)penColor penThickness:(NSUInteger)thickness startTime:(UInt64)start_at size:(int)size normalizer:(float)inputScale;
- (instancetype) initWithStroke:(NJStroke *)stroke normalizer:(float)inputScale;
- (void) normalize:(float)inputScale;

- (void) setDataX:(float)x y:(float)y pressure:(float)pressure time_stamp:(UInt64)time at:(int)index;
- (void) renderNodesWithFountainPenWithSize:(CGRect)bounds scale:(float)scale screenRatio:(float)screenRatio
                                    offsetX:(float)offset_x offsetY:(float)offset_y withVoice:(BOOL)withVoice forMode:(NeoMediaRenderingMode)mode;
- (void) renderNodesWithFountainPenWithSize:(CGRect)bounds scale:(float)scale screenRatio:(float)screenRatio
                                    offsetX:(float)offset_x offsetY:(float)offset_y;
- (void) renderNodesWithFountainPenWithSize:(CGRect)bounds scale:(float)scale screenRatio:(float)screenRatio
                                    offsetX:(float)offset_x offsetY:(float)offset_y strokeColor:(UIColor *)color;



- (float *)arrayPointX;
- (float *)arrayPointY;
- (float *)arrayPointP;


+ (NJStroke *) strokeFromData:(NSData *)data at:(int *)position;




@end
