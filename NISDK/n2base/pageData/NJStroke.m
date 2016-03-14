//
//  NJStroke.m
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJStroke.h"
#import "NJNode.h"
#import "NJTransformation.h"
#import "NJLinearFilter.h"

#define MAX_NODE_NUMBER 1024

@interface NJStroke(){
    float colorRed, colorGreen, colorBlue, colorAlpah;
}
@property (strong, nonatomic) UIBezierPath *renderingPath;
@end
@implementation NJStroke
@synthesize transformation=_transformation;
- (instancetype) init
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    self.type = MEDIA_STROKE;
     _penThickness = 0;
    return self;
}
- (instancetype) initWithSize:(int)size
{
    self = [self init];
    if (!self) return nil;
    _dataCount = size;
    point_x = (float *)calloc(size, sizeof(float));
    point_y = (float *)calloc(size, sizeof(float));
    point_p = (float *)calloc(size, sizeof(float));
    time_stamp = (UInt64 *)calloc(size, sizeof(UInt64));
    start_time = 0;
    _inputScale = 1;
    [self initColor];
    return self;
}
- (instancetype) initWithRawDataX:(float *)x Y:(float*)y pressure:(float *)p time_diff:(int *)time
                        penColor:(UInt32)penColor penThickness:(NSUInteger)thickness startTime:(UInt64)start_at size:(int)size
{
    self = [self init];
    if (!self) return nil;
    int time_lapse = 0;
    int i = 0;
    if (size < 3) {
        //We nee at least 3 point to render.
        //Warning!! I'm assume x, y, p are c style arrays that have at least 3 spaces.
        for (i = size; i < 3; i++) {
            x[i] = x[size -1];
            y[i] = y[size -1];
            p[i] = p[size -1];
            time[i]=0;
        }
        size = 3;
    }
    _dataCount = size;
    point_x = (float *)malloc(sizeof(float) * size);
    point_y = (float *)malloc(sizeof(float) * size);
    point_p = (float *)malloc(sizeof(float) * size);
    time_stamp = (UInt64 *)malloc(sizeof(UInt64) * size);
    start_time = start_at;
    // pen Thickness in UI is range 1~3. convert it to 0 ~ 2.
    if (thickness > (sizeof(penThicknessScale)/sizeof(float))) {
        thickness = 1;
    }
    _penThickness = thickness - 1;
    memcpy(point_x, x, sizeof(float) * size);
    memcpy(point_y, y, sizeof(float) * size);
    memcpy(point_p, p, sizeof(float) * size);
    for (i=0; i<size; i++) {
        time_lapse += time[i];
        time_stamp[i] = start_at + time_lapse;
    }

    _inputScale = 1;
    if (penColor == 0) {
        [self initColor];
    }
    else {
        self.penColor = penColor;
    }
    return self;
}
- (instancetype) initWithRawDataX:(float *)x Y:(float*)y pressure:(float *)p time_diff:(int *)time
                                penColor:(UInt32)penColor penThickness:(NSUInteger)thickness startTime:(UInt64)start_at size:(int)size normalizer:(float)inputScale
{
    self = [self init];
    if (!self) return nil;
    int time_lapse = 0;
    int i = 0;
    if (size < 3) {
        //We nee at least 3 point to render.
        //Warning!! I'm assume x, y, p are c style arrays that have at least 3 spaces.
        for (i = size; i < 3; i++) {
            x[i] = x[size -1];
            y[i] = y[size -1];
            p[i] = p[size -1];
            time[i]=0;
        }
        size = 3;
    }
    _dataCount = size;
    point_x = (float *)malloc(sizeof(float) * size);
    point_y = (float *)malloc(sizeof(float) * size);
    point_p = (float *)malloc(sizeof(float) * size);
    time_stamp = (UInt64 *)malloc(sizeof(UInt64) * size);
    start_time = start_at;
    // pen Thickness in UI is range 1~3. convert it to 0 ~ 2.
    if (thickness > (sizeof(penThicknessScale)/sizeof(float))) {
        thickness = 1;
    }
    _penThickness = thickness - 1;
    memcpy(point_p, p, sizeof(float) * size);
    for (i=0; i<size; i++) {
        point_x[i] = x[i] / inputScale;
        point_y[i] = y[i] / inputScale;
        time_lapse += time[i];
        time_stamp[i] = start_at + time_lapse;
    }
    [[NJLinearFilter sharedInstance] applyToX:point_x Y:point_y pressure:point_p size:size];
    _inputScale = inputScale;
    if (penColor == 0) {
        [self initColor];
    }
    else {
        self.penColor = penColor;
    }
    return self;
}
- (instancetype) initWithStroke:(NJStroke *)stroke normalizer:(float)inputScale
{
    self = [self init];
    if (!self) return nil;
    _dataCount = stroke.dataCount;
    point_x = (float *)malloc(sizeof(float) * _dataCount);
    point_y = (float *)malloc(sizeof(float) * _dataCount);
    point_p = (float *)malloc(sizeof(float) * _dataCount);
    time_stamp = (UInt64 *)malloc(sizeof(UInt64) * _dataCount);
    start_time = stroke->start_time;
    memcpy(point_p, stroke->point_p, sizeof(float) * _dataCount);

    _inputScale = inputScale;
    for (int i=0; i < _dataCount; i++) {
        point_x[i] = stroke->point_x[i] / inputScale;
        point_y[i] = stroke->point_y[i] / inputScale;
        time_stamp[i] = stroke->time_stamp[i];
    }
    [[NJLinearFilter sharedInstance] applyToX:point_x Y:point_y pressure:point_p size:_dataCount];
    [self initColor];
    return self;
}
+ (NJStroke *) strokeFromData:(NSData *)data at:(int *)position
{
    NJStroke *stroke = [[NJStroke alloc] init];
    if (stroke == nil) return nil;
    [stroke initFromData:data at:position];
    return stroke;
}

/* Initialize stroke from file. */
- (BOOL) initFromData:(NSData *)data at:(int *)position
{
    UInt32 penColor, nodeCount;
    Float32 x, y, pressure;
    *position += 1; //skip type
    if ([self readValueFromData:data to:&penColor at:position length:sizeof(UInt32)] == NO) {
        return NO;
    }
    unsigned char thickness;
    if ([self readValueFromData:data to:&thickness at:position length:sizeof(unsigned char)] == NO) {
        return NO;
    }
    _penThickness = thickness;
    if ([self readValueFromData:data to:&nodeCount at:position length:sizeof(UInt32)] == NO) {
        return NO;
    }
    point_x = (float *)calloc(nodeCount, sizeof(float));
    point_y = (float *)calloc(nodeCount, sizeof(float));
    point_p = (float *)calloc(nodeCount, sizeof(float));
    time_stamp = (UInt64 *)calloc(nodeCount, sizeof(UInt64));
    self.penColor = penColor;
    _dataCount = nodeCount;
    [self readValueFromData:data to:&start_time at:position length:sizeof(UInt64)];
    unsigned char timeDiff;
    UInt64 timeStamp = start_time;
    for (int i=0; i < nodeCount;i++ ) {
        [self readValueFromData:data to:&x at:position length:sizeof(Float32)];
        [self readValueFromData:data to:&y at:position length:sizeof(Float32)];
        [self readValueFromData:data to:&pressure at:position length:sizeof(Float32)];
        [self readValueFromData:data to:&timeDiff at:position length:sizeof(unsigned char)];
        timeStamp += timeDiff;
        [self setDataX:x y:y pressure:pressure time_stamp:timeStamp at:i];
    }
    return YES;
}

- (void) normalize:(float)inputScale
{
    if (_inputScale != 1) {
        // already normalized.
        return;
    }
    _inputScale = inputScale;
    for (int i=0; i < _dataCount; i++) {
        point_x[i] = point_x[i] / inputScale;
        point_y[i] = point_y[i] / inputScale;
    }
    [[NJLinearFilter sharedInstance] applyToX:point_x Y:point_y pressure:point_p size:_dataCount];
}

- (NJTransformation *)transformation
{
    if (_transformation == nil) {
        _transformation = [[NJTransformation alloc] init];
    }
    return _transformation;
}
- (void)setTransformation:(NJTransformation *)transformation
{
    [self.transformation setValueWithTransformation:transformation];
    _targetScale = transformation.scale;
}
- (void) dealloc
{
    free(point_x);
    free(point_y);
    free(point_p);
    free(time_stamp);
}
- (void) setPenColor:(UInt32)penColor
{
    _penColor = penColor;
    colorAlpah = (penColor>>24)/255.0f;
    colorRed = ((penColor>>16)&0x000000FF)/255.0f;
    colorGreen = ((penColor>>8)&0x000000FF)/255.0f;
    colorBlue = (penColor&0x000000FF)/255.0f;;
}
- (void)initColor
{
    colorRed = 0.2f;
    colorGreen = 0.2f;
    colorBlue = 0.2f;
    colorAlpah = 1.0f;
    UInt32 alpah = (UInt32)(colorAlpah * 255) & 0x000000FF;
    UInt32 red = (UInt32)(colorRed * 255) & 0x000000FF;
    UInt32 green = (UInt32)(colorGreen * 255) & 0x000000FF;
    UInt32 blue = (UInt32)(colorBlue * 255) & 0x000000FF;
    _penColor = (alpah << 24) | (red << 16) | (green << 8) | blue;
}
- (void) setDataX:(float)x y:(float)y pressure:(float)pressure time_stamp:(UInt64)time at:(int)index
{
    if (index >= _dataCount) return;
    point_x[index] = x;
    point_y[index] = y;
    point_p[index] = pressure;
    time_stamp[index] = time;
}
- (UIBezierPath *)renderingPath
{
    if (_renderingPath == nil) {
        _renderingPath = [UIBezierPath bezierPath];
        [_renderingPath setLineWidth:1.0];
        [_renderingPath fill];
    }
    return _renderingPath;
}


- (void) renderNodesWithFountainPenWithSize:(CGRect)bounds scale:(float)scale screenRatio:(float)screenRatio
                            offsetX:(float)offset_x offsetY:(float)offset_y
{
    [self renderNodesWithFountainPenWithSize:bounds scale:scale screenRatio:screenRatio offsetX:offset_x offsetY:offset_y strokeColor:nil];
}

- (void) renderNodesWithFountainPenWithSize:(CGRect)bounds scale:(float)scale screenRatio:(float)screenRatio
                                    offsetX:(float)offset_x offsetY:(float)offset_y withVoice:(BOOL)withVoice forMode:(NeoMediaRenderingMode)mode
{
#define VM_REPLAY_WIDTH 4
#define VM_PREVIEW_WIDTH 1
#define VM_READY_OUTER_WIDTH 4
#define VM_REPLAY_INNER_WIDTH 2
    UIColor *color = nil;
    if (withVoice) {
        if(mode == MEDIA_RENDER_REPLAY_VOICE) {
            color = [UIColor colorWithRed:0.627 green:0.0392 blue:0.1961 alpha:1];
            [self renderNodesWithFountainPenWithSize:bounds scale:VM_REPLAY_WIDTH screenRatio:screenRatio offsetX:offset_x offsetY:offset_y strokeColor:color];
        }
        else if(mode == MEDIA_RENDER_REPLAY_PREVIEW_VOICE) {
            color = [UIColor colorWithRed:0.627 green:0.0392 blue:0.1961 alpha:1];
            [self renderNodesWithFountainPenWithSize:bounds scale:VM_PREVIEW_WIDTH screenRatio:screenRatio offsetX:offset_x offsetY:offset_y strokeColor:color];
        }
        else if(mode == MEDIA_RENDER_REPLAY_READY_VOICE) {
            color = [UIColor colorWithRed:0.627 green:0.0392 blue:0.1961 alpha:0.4];
            [self renderNodesWithFountainPenWithSize:bounds scale:VM_READY_OUTER_WIDTH screenRatio:screenRatio offsetX:offset_x offsetY:offset_y strokeColor:color];
            color = [UIColor colorWithRed:0.627 green:0.0392 blue:0.1961 alpha:0.9];
            [self renderNodesWithFountainPenWithSize:bounds scale:VM_REPLAY_INNER_WIDTH screenRatio:screenRatio offsetX:offset_x offsetY:offset_y strokeColor:color];
        }
        else {
            [self renderNodesWithFountainPenWithSize:bounds scale:scale screenRatio:screenRatio offsetX:offset_x offsetY:offset_y strokeColor:color];
        }
    }
    else
        [self renderNodesWithFountainPenWithSize:bounds scale:scale screenRatio:screenRatio offsetX:offset_x offsetY:offset_y strokeColor:color];
}
//Structure to save trace back path
typedef struct {
    CGPoint endPoint;
    CGPoint ctlPoint1;
    CGPoint ctlPoint2;
}PathPointsStruct;

static float penThicknessScale[] = {600.0, 300.0, 180 };
- (void) renderNodesWithFountainPenWithSize:(CGRect)bounds scale:(float)lineScale screenRatio:(float)screenRatio
                                    offsetX:(float)offset_x offsetY:(float)offset_y strokeColor:(UIColor *)color
{
    float scale = 1.0f;
    scale *= _targetScale;
    float penThicknessScaler = penThicknessScale[_penThickness];
    float lineThicknessScale = (float)1.0f/penThicknessScaler;
    float scaled_pen_thickness = lineScale * scale * lineThicknessScale;
    float x0, x1, x2, x3, y0, y1, y2, y3, p0, p1, p2, p3;
    float vx01, vy01, vx21, vy21; // unit tangent vectors 0->1 and 1<-2
    float norm;
    float n_x0, n_y0, n_x2, n_y2; // the normals
    
    CGPoint temp, endPoint, controlPoint1, controlPoint2;
    
    if(isEmpty(color)) {
        [[[UIColor alloc] initWithRed:colorRed green:colorGreen blue:colorBlue alpha:colorAlpah] setStroke];
        [[[UIColor alloc] initWithRed:colorRed green:colorGreen blue:colorBlue alpha:colorAlpah] setFill];
        
    } else {
        [color setStroke];
        [color setFill];
    }
    
    // the first actual point is treated as a midpoint
    x0 = point_x[ 0 ] * scale + offset_x + 0.1f;
    y0 = point_y[ 0 ] * scale + offset_y;
    p0 = point_p[ 0 ];
    x1 = point_x[ 1 ] * scale + offset_x + 0.1f;
    y1 = point_y[ 1 ] * scale + offset_y;
    p1 = point_p[ 1 ];
    
    vx01 = x1 - x0;
    vy01 = y1 - y0;
    // instead of dividing tangent/norm by two, we multiply norm by 2
    norm = (float)sqrt(vx01 * vx01 + vy01 * vy01 + 0.0001f) * 2.0f ;
    vx01 = vx01 / norm * scaled_pen_thickness * p0;
    vy01 = vy01 / norm * scaled_pen_thickness * p0;
    n_x0 = vy01;
    n_y0 = -vx01;
    
    // Trip back path will be saved.
    PathPointsStruct *pathPointStore = (PathPointsStruct *)malloc(sizeof(PathPointsStruct) * (_dataCount + 2));
    int pathSaveIndex = 0;
    temp.x = x0 + n_x0;
    temp.y = y0 + n_y0;
    [self.renderingPath removeAllPoints];
    [self.renderingPath moveToPoint:temp];
    endPoint.x = x0 + n_x0;
    endPoint.y = y0 + n_y0;
    controlPoint1.x = x0 - n_x0 - vx01;
    controlPoint1.y = y0 - n_y0 - vy01;
    controlPoint2.x = x0 + n_x0 - vx01;
    controlPoint2.y = y0 + n_y0 - vy01;
    //Save last path. I'll be back here....
    pathPointStore[pathSaveIndex].endPoint = endPoint;
    pathPointStore[pathSaveIndex].ctlPoint1 = controlPoint1;
    pathPointStore[pathSaveIndex].ctlPoint2 = controlPoint2;
    pathSaveIndex++;
    for ( int i=2; i < _dataCount-1; i++ ) {
@autoreleasepool {
        // (x0,y0) and (x2,y2) are midpoints, (x1,y1) and (x3,y3) are actual
        // points
        x3 = point_x[i] * scale + offset_x;// + 0.1f;
        y3 = point_y[i] * scale + offset_y;
        p3 = point_p[i];
        
        x2 = (x1 + x3) / 2.0f;
        y2 = (y1 + y3) / 2.0f;
        p2 = (p1 + p3) / 2.0f;
        vx21 = x1 - x2;
        vy21 = y1 - y2;
        norm = (float) sqrt(vx21 * vx21 + vy21 * vy21 + 0.0001) * 2.0f;
        vx21 = vx21 / norm * scaled_pen_thickness * p2;
        vy21 = vy21 / norm * scaled_pen_thickness * p2;
        n_x2 = -vy21;
        n_y2 = vx21;
        
        if (norm < 0.6) {
            continue;
        }
        // The + boundary of the stroke
        endPoint.x = x2 + n_x2;
        endPoint.y = y2 + n_y2;
        controlPoint1.x = x1 + n_x0;
        controlPoint1.y = y1 + n_y0;
        controlPoint2.x = x1 + n_x2;
        controlPoint2.y = y1 + n_y2;
        [self.renderingPath addCurveToPoint:endPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
        
        // THe - boundary of the stroke
        endPoint.x = x0 - n_x0;
        endPoint.y = y0 - n_y0;
        controlPoint1.x = x1 - n_x2;
        controlPoint1.y = y1 - n_y2;
        controlPoint2.x = x1 - n_x0;
        controlPoint2.y = y1 - n_y0;
        pathPointStore[pathSaveIndex].endPoint = endPoint;
        pathPointStore[pathSaveIndex].ctlPoint1 = controlPoint1;
        pathPointStore[pathSaveIndex].ctlPoint2 = controlPoint2;
        pathSaveIndex++;
        x0 = x2;
        y0 = y2;
        p0 = p2;
        x1 = x3;
        y1 = y3;
        p1 = p3;
        vx01 = -vx21;
        vy01 = -vy21;
        n_x0 = n_x2;
        n_y0 = n_y2;
}}
    
    // the last actual point is treated as a midpoint
    x2 = point_x[ _dataCount-1 ] * scale + offset_x;// + 0.1f;
    y2 = point_y[ _dataCount-1 ] * scale + offset_y;
    p2 = point_p[ _dataCount-1 ];
    
    vx21 = x1 - x2;
    vy21 = y1 - y2;
    norm = (float) sqrt(vx21 * vx21 + vy21 * vy21 + 0.0001) * 2.0f;
    vx21 = vx21 / norm * scaled_pen_thickness * p2;
    vy21 = vy21 / norm * scaled_pen_thickness * p2;
    n_x2 = -vy21;
    n_y2 = vx21;
    
    endPoint.x = x2 + n_x2;
    endPoint.y = y2 + n_y2;
    controlPoint1.x = x1 + n_x0;
    controlPoint1.y = y1 + n_y0;
    controlPoint2.x = x1 + n_x2;
    controlPoint2.y = y1 + n_y2;
    [self.renderingPath addCurveToPoint:endPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
    endPoint.x = x2 - n_x2;
    endPoint.y = y2 - n_y2;
    controlPoint1.x = x2 + n_x2 - vx21;
    controlPoint1.y = y2 + n_y2 - vy21;
    controlPoint2.x = x2 - n_x2	- vx21;
    controlPoint2.y = y2 - n_y2 - vy21;
    [self.renderingPath addCurveToPoint:endPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
    endPoint.x = x0 - n_x0;
    endPoint.y = y0 - n_y0;
    controlPoint1.x = x1 - n_x2;
    controlPoint1.y = y1 - n_y2;
    controlPoint2.x = x1 - n_x0;
    controlPoint2.y = y1 - n_y0;
    [self.renderingPath addCurveToPoint:endPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
    // Trace back to the starting point
    for (int index = pathSaveIndex - 1; index >= 0; index--) {
        endPoint = pathPointStore[index].endPoint;
        controlPoint1 = pathPointStore[index].ctlPoint1;
        controlPoint2 = pathPointStore[index].ctlPoint2;
@autoreleasepool {
        [self.renderingPath addCurveToPoint:endPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
}
    }
    [self.renderingPath fill];
    [self.renderingPath removeAllPoints];
    free(pathPointStore);
}
/* Save stroke to a file */
- (BOOL) writeMediaToData:(NSMutableData *)data
{
    Float32 x, y, pressure;
    UInt64 time_lapse = start_time;
    unsigned char timeDiff;
    unsigned char kind = (unsigned char)MEDIA_STROKE;
    [data appendBytes:&kind length:sizeof(unsigned char)];
    UInt32 penColor = (UInt32)self.penColor;
    [data appendBytes:&penColor length:sizeof(UInt32)];
    unsigned char thickness = _penThickness;
    [data appendBytes:&thickness length:sizeof(unsigned char)];
    UInt32 nodeCount = (UInt32)self.dataCount;
    [data appendBytes:&nodeCount length:sizeof(UInt32)];
    [data appendBytes:&start_time length:sizeof(UInt64)];
    for (int i = 0; i < nodeCount; i++) {
        x = point_x[i];
        y = point_y[i];
        pressure = point_p[i];
        timeDiff = time_stamp[i] - time_lapse;
        time_lapse = time_stamp[i];
        [data appendBytes:&x length:sizeof(Float32)];
        [data appendBytes:&y length:sizeof(Float32)];
        [data appendBytes:&pressure length:sizeof(Float32)];
        [data appendBytes:&timeDiff length:sizeof(unsigned char)];
    }
    return YES;
}

-(NSArray *)xData
{
    
    NSMutableArray * array = [[NSMutableArray alloc] initWithCapacity:self.dataCount];
    
    for(int i=0; i < self.dataCount; i++) {
        
        [array addObject:[[NSNumber alloc] initWithFloat:point_x[i]]];
    }
    
    return array;
}


-(NSArray *)yData
{
    
    NSMutableArray * array = [[NSMutableArray alloc] initWithCapacity:self.dataCount];
    
    for(int i=0; i < self.dataCount; i++) {
        
        [array addObject:[[NSNumber alloc] initWithFloat:point_y[i]]];
    }
    
    return array;
}


- (float *)arrayPointX
{
    
    return point_x;
}

- (float *)arrayPointY
{
    return point_y;
}

- (float *)arrayPointP
{
    return point_p;
}
@end
