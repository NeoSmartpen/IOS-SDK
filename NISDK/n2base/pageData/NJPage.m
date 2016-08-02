//
//  NJPage.m
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJPage.h"
#import "NJNode.h"
#import "NJStroke.h"
#import "NJVoiceMemo.h"
#import "NJVoiceManager.h"
#import "NJTransformation.h"
#import "NJNotebookPaperInfo.h"
#import "PDFPageConverter.h"
//NSArray * _notePdf = [@"note_0301.pdf", @"note_0302.pdf", @"note_0303.pdf"];

@interface NJPage() {
    float mX[MAX_NODE_NUMBER], mY[MAX_NODE_NUMBER], mFP[MAX_NODE_NUMBER];
    int mN;
}
@property (strong, nonatomic) UIBezierPath *renderingPath;
@property (strong, nonatomic) NJTransformation* transformation;
@property (strong, nonatomic) NJNotebookPaperInfo *paperInfo;
@property (nonatomic) float page_x;
@property (nonatomic) float page_y;
@property (nonatomic) BOOL dirtyBit;

@property (nonatomic) int contentReadPosition;
@property (strong, nonatomic) NSData *contentData;
@property (strong, nonatomic) NSURL *fileUrl;

@end

@implementation NJPage
{
//    NSDictionary *_notePdfFileNames;
}
@synthesize dirtyBit = _dirtyBit;
@synthesize pageGuid = _pageGuid;

- (void)dealloc
{
    _strokes = nil;
//    _image = nil;
    _voiceMemo = nil;
    _contentData = nil;
    _renderingPath = nil;
    _transformation = nil;
    _paperInfo = nil;
}

- (id) initWithNotebookId:(int)notebookId andPageNumber:(int)pageNumber
{
    self = [super init];
    if(!self) {
        return nil;
    }
    self.notebookId = notebookId;
    self.pageNumber = pageNumber;
    self.strokes = [[NSMutableArray alloc] init];
    self.transformation = [[NJTransformation alloc] init];
    self.paperInfo = [NJNotebookPaperInfo sharedInstance];
    /* Get Paper size */
    [self.paperInfo getPaperDotcodeRangeForNotebook:(int)notebookId PageNumber:pageNumber Xmax:&_page_x Ymax:&_page_y];
    CGSize paperSize;
    paperSize.width = _page_x;
    paperSize.height = _page_y;
    /* set paper size and input scale. Input scale is used to nomalize stroke data */
    self.paperSize = paperSize;
    self.dirtyBit = NO;

    _pageHasChanged = NO;

    return self;
}
- (BOOL) dirtyBit
{
    return _dirtyBit;
}
- (void) setDirtyBit:(BOOL)dirtyBit
{
    if (_dirtyBit == dirtyBit) {
        return;
    }
    _dirtyBit = dirtyBit;
    if (_dirtyBit == NO) {
        //Will be saved automatically if dirty is YES.
        _pageHasChanged = YES;
        [self saveToURL:self.fileUrl];
    }
}

- (void) setPageGuid:(NSString *)pageGuid
{
    if (_pageGuid == pageGuid) {
        return;
    }
    _pageGuid = pageGuid;

    if ([_pageGuid isEqualToString:@""]) {
        NSLog(@"_pageGuid: @""");
    }
    _pageHasChanged = YES;
    [self saveToURL:self.fileUrl];

}

- (void) setPaperSize:(CGSize)paperSize
{
    _paperSize = paperSize;
    _inputScale = MAX(paperSize.width, paperSize.height);
    
}
- (NSMutableArray *)voiceMemo
{
    if (_voiceMemo == nil) {
        _voiceMemo = [[NSMutableArray alloc] init];
    }
    return _voiceMemo;
}
- (void)setTransformationWithOffsetX:(float)x offset_y:(float)y scale:(float)scale
{
    self.transformation.offset_x = x;
    self.transformation.offset_y = y;
    self.transformation.scale = scale;
    for (NJStroke *stroke in self.strokes) {
        [stroke setTransformation:self.transformation];
    }
}
- (void) addMedia:(NJMedia *)media
{
    if (media.type == MEDIA_STROKE) {
        NJStroke *stroke = (NJStroke *)media;
        [stroke setTransformation:self.transformation];
    }
    else if(media.type == MEDIA_VOICE) {
        NJVoiceMemo *vm = (NJVoiceMemo *)media;
        if (vm.status == VOICEMEMO_START || vm.status == VOICEMEMO_PAGE_CHANGED) {
            BOOL addVM = YES;
            for (NSDictionary *memo in _voiceMemo) {
                if ([vm.fileName isEqualToString:(NSString *)[memo objectForKey:@"fileName"]]) {
                    addVM = NO;
                    break;
                }
            }
            if (addVM) {
                UInt64 timestamp = [NJVoiceManager getNumberFor:VM_NUMBER_TIME from:vm.fileName];
                UInt32 noteId = (UInt32)[NJVoiceManager getNumberFor:VM_NUMBER_NOTE_ID from:vm.fileName];
                UInt32 pageId = (UInt32)[NJVoiceManager getNumberFor:VM_NUMBER_PAGE_ID from:vm.fileName];
                NSDictionary *vmData = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        [NSNumber numberWithUnsignedInteger:noteId], @"noteId",
                                        [NSNumber numberWithUnsignedInteger:pageId], @"pageNumber",
                                        [NSNumber numberWithLongLong:timestamp], @"timestamp",
                                        vm.fileName, @"fileName", nil];
                [self.voiceMemo addObject:vmData];
            }
        }	
    }
    [self.strokes addObject:media];
    _pageHasChanged = YES;
}
- (void) addStrokes:(NJStroke *)stroke
{
    [stroke setTransformation:self.transformation];
    [self.strokes addObject:stroke];
    _pageHasChanged = YES;
    self.dirtyBit = YES;
}
- (void) insertStrokeByTimestamp:(NJStroke *)stroke
{
    [stroke setTransformation:self.transformation];
    NSUInteger count = [self.strokes count];
    NSUInteger index;
    for (index = 0; index < count; index++) {
        NJStroke *aStroke = self.strokes[index];
        if (stroke->start_time < aStroke->start_time) {
            break;
        }
    }
    [self.strokes insertObject:stroke atIndex:index];
    _pageHasChanged = YES;
    self.dirtyBit = YES;
}

/* Make an image from pdf.
 * Don't call this function from inside UIGraphicsBeginImageContextWithOptions.
 * It causes Memory fault.
 */
- (UIImage *) getBackgroundImage
{
    UIImage * image = nil;
    NJNotebookPaperInfo *noteInfo = [[NJNotebookPaperInfo alloc]init];
    NSString *pdfFileName = [noteInfo backgroundFileNameForSection:0 owner:0 note:_notebookId];
    if (pdfFileName) {
        NSURL *pdfURL = [[NSBundle mainBundle] URLForResource:pdfFileName withExtension:nil];
        CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL( (__bridge CFURLRef) pdfURL );
        int pageOffset = [noteInfo pdfPageOffsetForSection:0 owner:0 note:_notebookId];
        CGPDFPageRef pdfPage = CGPDFDocumentGetPage(pdf, self.pageNumber - pageOffset);
        image = [PDFPageConverter convertPDFPageToImage:pdfPage withResolution:144];
    }
    return image;
}
- (UIImage *) drawPageWithImage:(UIImage *)image size:(CGRect)bounds drawBG:(BOOL)drawBG opaque:(BOOL)opaque
{
    CGRect imageBounds = bounds;
    if (image==nil)
    {
        if(drawBG)
            image = [self getBackgroundImage];
    }
    else {
        // For drawInRect, if the image size does not fit it will resize image.
        imageBounds.size = [image size];
    }
    @autoreleasepool {
        
    UIGraphicsBeginImageContextWithOptions(bounds.size, opaque, 0.0);
    if (image) {
        [image drawInRect:imageBounds];
    }
    else {
        if (opaque) {
            UIBezierPath *rectpath = [UIBezierPath bezierPathWithRect:bounds];
            [[UIColor colorWithWhite:0.95f alpha:1] setFill];
            [rectpath fill];
        }
    }
    
    CGSize paperSize=self.paperSize;
    float xRatio=bounds.size.width/paperSize.width;
    float yRatio=bounds.size.height/paperSize.height;
    float screenRatio = (xRatio > yRatio) ? yRatio:xRatio;

    NJMedia *media;
    for (int i=0; i < [self.strokes count]; i++) {
        media = self.strokes[i];
        if (media.type == MEDIA_STROKE) {
            [(NJStroke *)media renderNodesWithFountainPenWithSize:bounds scale:1.0 screenRatio:screenRatio offsetX:0.0 offsetY:0.0];
        }
        else if(media.type == MEDIA_VOICE) {
            NJVoiceMemo *voice = (NJVoiceMemo *)media;
            NSLog(@"Voice Memo : %@ status %d", voice.fileName, voice.status);
        }
    }
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
    }
}
- (UIImage *) drawPageWithImage:(UIImage *)image size:(CGRect)bounds forMode:(NeoMediaRenderingMode)mode
{
    CGRect imageBounds = bounds;
    if (image==nil)
    {
        image = [self getBackgroundImage];
    }
    else {
        // For drawInRect, if the image size does not fit it will resize image.
        imageBounds.size = [image size];
    }
    @autoreleasepool {
    UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0);
    if (image) {
        [image drawInRect:imageBounds];
    }
    else {
        UIBezierPath *rectpath = [UIBezierPath bezierPathWithRect:bounds];
        [[UIColor colorWithWhite:0.95f alpha:1] setFill];
        [rectpath fill];
    }
    CGSize paperSize=self.paperSize;
    float xRatio=bounds.size.width/paperSize.width;
    float yRatio=bounds.size.height/paperSize.height;
    float screenRatio = (xRatio > yRatio) ? yRatio:xRatio;
    
    NJMedia *media;
    int i=0;
    if (mode == MEDIA_RENDER_REPLAY_READY_STROKE) {
        i=(int)[self.strokes count];
    }
    BOOL withVoice = NO;
    for (; i < [self.strokes count]; i++) {
        media = self.strokes[i];
        if (media.type == MEDIA_STROKE) {
            [(NJStroke *)media renderNodesWithFountainPenWithSize:bounds scale:1.0 screenRatio:screenRatio offsetX:0.0 offsetY:0.0 withVoice:withVoice forMode:mode];
        }
        else if(media.type == MEDIA_VOICE) {
            NJVoiceMemo *voice = (NJVoiceMemo *)media;
            NSLog(@"Voice Memo : %@ status %d", voice.fileName, voice.status);
            if (voice.status == VOICEMEMO_START || voice.status == VOICEMEMO_PAGE_CHANGED) {
                withVoice = YES;
            }
            else
                withVoice = NO;
        }
    }
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
    }
}
- (UIImage *) drawPageBackgroundImage:(UIImage *)image size:(CGRect)bounds
{
    CGRect imageBounds = bounds;
    if (image==nil)
    {
        image = [self getBackgroundImage];
    }
    else {
        // For drawInRect, if the image size does not fit it will resize image.
        imageBounds.size = [image size];
    }
    @autoreleasepool {
    UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0);
    if (image) {
        [image drawInRect:imageBounds];
    }
    else {
        UIBezierPath *rectpath = [UIBezierPath bezierPathWithRect:bounds];
        [[UIColor colorWithWhite:0.95f alpha:1] setFill];
        [rectpath fill];
    }
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
    }
}
- (UIImage *) drawStroke: (NJStroke *)stroke withImage:(UIImage *)image
                     size:(CGRect)bounds scale:(float)scale
                  offsetX:(float)offset_x offsetY:(float)offset_y drawBG:(BOOL)drawBG opaque:(BOOL)opaque
{
    CGRect imageBounds = bounds;
    if (image==nil)
    {
        if(drawBG)
        image = [self getBackgroundImage];
    }
    else {
        // For drawInRect, if the image size does not fit it will resize image.
        imageBounds.size = [image size];
    }
@autoreleasepool {
    // autoreleasepool added by namSSan 2015-02-13 - refer to
    //http://stackoverflow.com/questions/19167732/coregraphics-drawing-causes-memory-warnings-crash-on-ios-7
    //UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0);
    UIGraphicsBeginImageContextWithOptions(bounds.size, opaque, 0.0);
    if (image) {
        
        [image drawInRect:imageBounds];
    }
    else {
        if (opaque) {
            UIBezierPath *rectpath = [UIBezierPath bezierPathWithRect:bounds];
            [[UIColor colorWithWhite:0.95f alpha:1] setFill];
            [rectpath fill];
        }
    }
    CGSize paperSize=self.paperSize;
    float xRatio=bounds.size.width/paperSize.width;
    float yRatio=bounds.size.height/paperSize.height;
    float screenRatio = (xRatio > yRatio) ? yRatio:xRatio;

    [stroke renderNodesWithFountainPenWithSize:bounds scale:scale screenRatio:screenRatio offsetX:offset_x offsetY:offset_y];
    UIImage *newImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return newImg;
}
}
- (UIImage *) drawStrokesFrom:(NSInteger)start to:(NSInteger)end time:(UInt64)timestamp withImage:(UIImage *)image
                    withVoice:(BOOL)withVoice forMode:(NeoMediaRenderingMode)mode
                    size:(CGRect)bounds scale:(float)scale
                      offsetX:(float)offset_x offsetY:(float)offset_y nextIndex:(NSInteger *)nextIndex
{
    CGRect imageBounds = bounds;
    if (image==nil)
    {
        image = [self getBackgroundImage];
    }
    else {
        // For drawInRect, if the image size does not fit it will resize image.
        imageBounds.size = [image size];
    }

@autoreleasepool {
    UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0);
    if (image) {
        [image drawInRect:imageBounds];
    }
    else {
        UIBezierPath *rectpath = [UIBezierPath bezierPathWithRect:bounds];
        [[UIColor colorWithWhite:0.95f alpha:1] setFill];
        [rectpath fill];
    }
    CGSize paperSize=self.paperSize;
    float xRatio=bounds.size.width/paperSize.width;
    float yRatio=bounds.size.height/paperSize.height;
    float screenRatio = (xRatio > yRatio) ? yRatio:xRatio;
    if (nextIndex != NULL) {
        *nextIndex = end + 1;
    }
    for (int i = (int)start; i <= end && i < [_strokes count]; i++) {
        NJStroke *stroke = [_strokes objectAtIndex:i];
        if (timestamp != 0 && stroke->start_time > timestamp && nextIndex != NULL) {
            *nextIndex = i;
            break;
        }
        if (stroke.type == MEDIA_STROKE) {
            [stroke renderNodesWithFountainPenWithSize:bounds scale:scale screenRatio:screenRatio offsetX:offset_x offsetY:offset_y withVoice:withVoice forMode:mode];
        }
        else if(stroke.type == MEDIA_VOICE && nextIndex != NULL)
        {
            *nextIndex = i;
            break;
        }
    }
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}
}
- (NSArray *) drawStroke2: (NJStroke *)stroke withImage:(UIImage *)image
                     size:(CGRect)bounds scale:(float)scale
                  offsetX:(float)offset_x offsetY:(float)offset_y withVoice:(BOOL)withVoice forMode:(NeoMediaRenderingMode)mode
{
    NSMutableArray *imgArray = [NSMutableArray array];
    CGRect imageBounds = bounds;
    if (image==nil)
    {
        image = [self getBackgroundImage];
    }
    else {
        // For drawInRect, if the image size does not fit it will resize image.
        imageBounds.size = [image size];
    }

    UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0);
    if (image) {
        [image drawInRect:imageBounds];
    }
    else {
        UIBezierPath *rectpath = [UIBezierPath bezierPathWithRect:bounds];
        [[UIColor colorWithWhite:0.95f alpha:1] setFill];
        [rectpath fill];
    }
    CGSize paperSize=self.paperSize;
    float xRatio=bounds.size.width/paperSize.width;
    float yRatio=bounds.size.height/paperSize.height;
    float screenRatio = (xRatio > yRatio) ? yRatio:xRatio;
    
    [stroke renderNodesWithFountainPenWithSize:bounds scale:scale screenRatio:screenRatio offsetX:offset_x offsetY:offset_y withVoice:withVoice forMode:mode];
    UIImage *bgImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    [imgArray addObject:bgImage];
    
    
    UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0);
    [image drawAtPoint:CGPointZero];
    [stroke renderNodesWithFountainPenWithSize:bounds scale:scale screenRatio:screenRatio offsetX:offset_x offsetY:offset_y strokeColor:[UIColor grayColor]];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [imgArray addObject:newImage];
    
    return imgArray;
}
- (NSArray *) drawStroke2: (NJStroke *)stroke withImage:(UIImage *)image
                    size:(CGRect)bounds scale:(float)scale
                 offsetX:(float)offset_x offsetY:(float)offset_y
{
    NSArray * imgArray = [self drawStroke2: stroke withImage:image
                                      size:bounds scale:scale
                                   offsetX:offset_x offsetY:offset_y withVoice:NO forMode:MEDIA_RENDER_STROKE];
    return imgArray;
}


- (UIImage *) renderPageWithImage:(UIImage *)image size:(CGRect)bounds
{
@autoreleasepool {
    CGSize paperSize=self.paperSize;
    float aspect_ratio = paperSize.width/paperSize.height;
    float H = bounds.size.height;
    float W = bounds.size.width;
    float dimension = MIN(H, W/aspect_ratio);
    NJTransformation *newTransformaion = [[NJTransformation alloc] initWithOffsetX:0 offsetY:0 scale:dimension];
    NJTransformation *currTransformation = self.transformation;
    CGRect imageBounds = bounds;
    if (image==nil)
    {
        image = [self getBackgroundImage];
    }
    else {
        // For drawInRect, if the image size does not fit it will resize image.
        imageBounds.size = [image size];
    }

    UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0);
    if (image) {
        [image drawInRect:imageBounds];
    }
    else {
        UIBezierPath *rectpath = [UIBezierPath bezierPathWithRect:bounds];
        [[UIColor colorWithWhite:0.95f alpha:1] setFill];
        [rectpath fill];
    }
    float xRatio=bounds.size.width/paperSize.width;
    float yRatio=bounds.size.height/paperSize.height;
    float screenRatio = (xRatio > yRatio) ? yRatio:xRatio;
    NJMedia *media;
    NJStroke *aStroke;
    for (int i=0; i < [self.strokes count]; i++) {
        media = (NJMedia *)self.strokes[i];
        if (media.type != MEDIA_STROKE) continue;
        aStroke = (NJStroke *)media;
        [aStroke setTransformation:newTransformaion];
@autoreleasepool {
        [aStroke renderNodesWithFountainPenWithSize:bounds scale:1.0 screenRatio:screenRatio offsetX:0.0 offsetY:0.0];
}
        [aStroke setTransformation:currTransformation];
    }
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextFlush(context);
    UIGraphicsEndImageContext();
    return newImage;
}
}

#define FILE_VERSION 1
- (void) readContentOfURL:(NSURL *)fileUrl
{
    self.contentData = [NSData dataWithContentsOfURL:fileUrl];
    self.contentReadPosition = 0;
}
- (BOOL) readDataTo:(void *)buffer length:(int)length
{
    if (self.contentData.length < self.contentReadPosition + length) {
        return NO;
    }
    NSRange range = {self.contentReadPosition, length};
    [self.contentData getBytes:buffer range:range];
    self.contentReadPosition += length;
    return YES;
}
- (void) finishReadContent
{
    self.contentData = nil;
}
- (NeoMediaType) readTypeFromData:(NSData*)data at:(int)position
{
    unsigned char type;
    NSRange range = {position, sizeof(unsigned char)};
    [data getBytes:&type range:range];
    return (NeoMediaType)type;
}
- (BOOL) readFromURL:(NSURL *)url error:(NSError *__autoreleasing *)outError
{
    int strokeCount;
    self.fileUrl = url;
    NSString *path = [[url path] stringByAppendingPathComponent:@"page.data"];
    [self readContentOfURL:[NSURL fileURLWithPath:path]];
    CGSize paperSize;
    paperSize.width = self.page_x;
    paperSize.height = self.page_y;
    self.paperSize = paperSize;
    char neo;
    // Start read file content
    [self readDataTo:&neo length:sizeof(char)];
    if (neo != 'n') return YES;
    [self readDataTo:&neo length:sizeof(char)];
    if (neo != 'e') return YES;
    [self readDataTo:&neo length:sizeof(char)];
    if (neo != 'o') return YES;
    UInt32 version;
    [self readDataTo:&version length:sizeof(UInt32)];
    if (version != FILE_VERSION) return YES;
    Float32 sizeData;
    [self readDataTo:&sizeData length:sizeof(Float32)];
    if (sizeData != 0) {
        paperSize.width = sizeData;
        [self readDataTo:&sizeData length:sizeof(Float32)];
        if (sizeData != 0) {
            paperSize.height = sizeData;
            self.paperSize = paperSize;
        }
    }
    
    UInt64 ctimeInterval;
    [self readDataTo:&ctimeInterval length:sizeof(UInt64)];
    self.cTime = [self convertIntervalToNSDate:ctimeInterval];
    UInt64 mtimeInterval;
    [self readDataTo:&mtimeInterval length:sizeof(UInt64)];
    self.mTime = [self convertIntervalToNSDate:mtimeInterval];
    
    unsigned char dirtyBit = 0;
    [self readDataTo:&dirtyBit length:sizeof(unsigned char)];
    if (dirtyBit == 0) {
        _dirtyBit = NO;
    }
    else {
        _dirtyBit = YES;
    }
    
    [self readDataTo:&strokeCount length:sizeof(UInt32)];
    int position;
    NeoMediaType type;
    NJMedia *media;
    for (int count = 0; count < strokeCount;count++ ) {
        position = self.contentReadPosition;
        type = [self readTypeFromData:self.contentData at:position];
        if (type == MEDIA_STROKE) {
            media = (NJMedia *)[NJStroke strokeFromData:self.contentData at:&position];
            self.contentReadPosition = position;
            if (media == nil) break;
            [self addMedia:media];
        }
        else if (type == MEDIA_VOICE) {
            NJVoiceMemo *vm = [NJVoiceMemo voiceMemoFromData:self.contentData at:&position];
            self.contentReadPosition = position;
            if (vm == nil) break;
            // Check if the vm file still exists or not
            if ([NJVoiceManager isVoiceMemoFileExist:vm.fileName ]) {
                [self addMedia:vm];
            }
        }
    }

    //page guid size
    UInt32 guidSizeData;
    [self readDataTo:&guidSizeData length:sizeof(UInt32)];
    //page guid data
    unsigned char guidDataBytes[guidSizeData];
    [self readDataTo:guidDataBytes length:guidSizeData];
    NSData *guidData = [NSData dataWithBytes:(const void*)guidDataBytes length:guidSizeData];
    _pageGuid = [[NSString alloc] initWithData:guidData encoding:NSUTF8StringEncoding];
    
    [self finishReadContent];
    path = [[url path] stringByAppendingPathComponent:@"image.jpg"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]){
        self.image = [UIImage imageWithContentsOfFile:path];
    }
    return YES;
}
- (NSDateComponents *) dateComponentsFromTimestamp:(NSTimeInterval)timestamp
{
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSDateComponents *weekdayComponents = [[NSCalendar currentCalendar] components:NSWeekdayCalendarUnit fromDate:date];
    return weekdayComponents;
}
- (BOOL) saveToURL:(NSURL *)url
{
    //saving isn't needed for SDK
    return NO;
    if (_pageHasChanged == NO) {
        NSLog(@"no changes, return from  saveToURL");
        return NO;
    }
    __block NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:[url path]] ||
        [fm createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&error])
    {
        self.fileUrl = url;
        NSString *path = [[url path] stringByAppendingPathComponent:@"page.data"];
        NSMutableData *pageData = [[NSMutableData alloc] init];
        // Start write file content
        char neo[3] = {'n', 'e', 'o'};
        [pageData appendBytes:neo length:3];
        UInt32 version = FILE_VERSION;
        [pageData appendBytes:&version length:sizeof(UInt32)];
        // Paper information
        CGSize paperSize = self.paperSize;
        Float32 sizeData = (Float32)paperSize.width;
        [pageData appendBytes:&sizeData length:sizeof(Float32)];
        sizeData = (Float32)paperSize.height;
        [pageData appendBytes:&sizeData length:sizeof(Float32)];
        // Creation time & modification time
        UInt64 ctimeInterval = [self.cTime timeIntervalSince1970];
        [pageData appendBytes:&ctimeInterval length:sizeof(UInt64)];
        UInt64 mtimeInterval = [[NSDate date] timeIntervalSince1970];
        [pageData appendBytes:&mtimeInterval length:sizeof(UInt64)];
        unsigned char dirtyBit = (self.dirtyBit ? 1:0);
        [pageData appendBytes:&dirtyBit length:sizeof(unsigned char)];
        
        // Media
        UInt32 strokeCount = (UInt32)[self.strokes count];
        [pageData appendBytes:&strokeCount length:sizeof(UInt32)];
        NJMedia *media;
        for (int count=0; count < strokeCount; count++) {
            media = [self.strokes objectAtIndex:count];
            if (media.type == MEDIA_STROKE) {
                [(NJStroke *)media writeMediaToData:pageData];
            }
            else if(media.type == MEDIA_VOICE) {
                [(NJVoiceMemo *)media writeMediaToData:pageData];
            }
        }
        
        NSData* guidData = [self.pageGuid dataUsingEncoding:NSUTF8StringEncoding];
        //guid data size
        UInt32 guidSizeData = (UInt32)[guidData length];
        [pageData appendBytes:&guidSizeData length:sizeof(UInt32)];
        //guid data
        unsigned char *guidDataBytes = (unsigned char *)[guidData bytes];
        [pageData appendBytes:guidDataBytes length:[guidData length]];
        
        [fm createFileAtPath:path contents:pageData attributes:nil];

        UIImage *image=[self renderPageWithImage:nil size:[self imageSize:0]];
        if (image) {
            path = [[url path] stringByAppendingPathComponent:@"image.jpg"];
            [UIImageJPEGRepresentation(image, 1.0) writeToFile:path atomically:YES];
        }
        UIImage *thumb=[self renderPageWithImage:nil size:[self imageSize:300]];
        if (thumb) {
            path = [[url path] stringByAppendingPathComponent:@"thumb.jpg"];
            [UIImageJPEGRepresentation(thumb, 1.0) writeToFile:path atomically:YES];
        }
        _pageHasChanged = NO;
        NSLog(@"saveToURL saved");
        return YES;
    }
    return NO;
}

- (CGRect)imageSize:(int)size
{
    float targetShortSize = ((size == 0)? 1024.0f : size);
    float ratio = 1;
    float shortSize;
    if (self.page_x < self.page_y) {
        shortSize = self.page_x;
    }
    else {
        shortSize = self.page_y;
    }
    ratio = targetShortSize/shortSize;
    
    CGSize retSize;
    retSize.width = self.page_x*ratio;
    retSize.height = self.page_y*ratio;
    CGRect ret;
    ret.size = retSize;
    CGPoint origin = {0.0f, 0.0f};
    ret.origin = origin;
    return ret;
}

- (NSDate *)convertIntervalToNSDate:(UInt64)interval
{
    NSTimeInterval timeInterval = (double)(interval/1000);
    
    NSDate *time = [[NSDate alloc]initWithTimeIntervalSince1970:timeInterval];
    
    return  time;
}
@end
