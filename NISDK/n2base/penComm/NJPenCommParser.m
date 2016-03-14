//
//  NJPenCommParser.m
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJPenCommParser.h"
#import "NJNode.h"
#import "NJPage.h"
#import "NJStroke.h"
#import "NJPageDocument.h"
#import "NJNotebookWriterManager.h"
#import "NeoPenService.h"
#import "NJNotebookPaperInfo.h"
#import "NJVoiceManager.h"
#import <zipzap/zipzap.h>
#import "NJNotebookPaperInfo.h"
#import "NJPenCommManager.h"
#import "NJCommon.h"
#import "MyFunctions.h"

#define POINT_COUNT_MAX 1024

extern NSString *NJPageChangedNotification;
extern NSString *NJPenBatteryLowWarningNotification;
extern NSString *NJPenCommManagerPageChangedNotification;

typedef struct {
    float x, y, pressure;
    unsigned char diff_time;
}dotDataStruct;

typedef enum {
    DOT_CHECK_NONE,
    DOT_CHECK_FIRST,
    DOT_CHECK_SECOND,
    DOT_CHECK_THIRD,
    DOT_CHECK_NORMAL
}DOT_CHECK_STATE;

typedef enum {
    OFFLINE_DOT_CHECK_NONE,
    OFFLINE_DOT_CHECK_FIRST,
    OFFLINE_DOT_CHECK_SECOND,
    OFFLINE_DOT_CHECK_THIRD,
    OFFLINE_DOT_CHECK_NORMAL
}OFFLINE_DOT_CHECK_STATE;

//13bits:data(4bits year,4bits month, 5bits date, ex:14 08 28)
//3bits: cmd, 1bit:dirty bit
typedef enum {
    None = 0x00,
    Email = 0x01,
    Alarm = 0x02,
    Activity = 0x04
} PageArrayCommandState;


typedef struct{
    int page_id;
    float activeStartX;
    float activeStartY;
    float activeWidth;
    float activeHeight;
    float spanX;
    float spanY;
    int arrayX; //email:action array, alarm: month start array
    int arrayY; //email:action array, alarm: month start array
    int startDate;
    int endDate;
    int remainedDate;
    int month;
    int year;
    PageArrayCommandState cmd;
} PageInfoType;

#define PRESSURE_MAX    255
#define PRESSURE_MIN    0
#define PRESSURE_V_MIN    40
#define IDLE_TIMER_INTERVAL 5.0f
#define IDLE_COUNT  (10.0f/IDLE_TIMER_INTERVAL) // 10 seconds

NSString * NJPenCommManagerWriteIdleNotification = @"NJPenCommManagerWriteIdleNotification";

@interface NJPenCommParser() {
    int node_count;
    int node_count_pen;
    dotDataStruct dotData0, dotData1, dotData2;
    DOT_CHECK_STATE dotCheckState;
    OffLineDataDotStruct offlineDotData0, offlineDotData1, offlineDotData2;
    OFFLINE_DOT_CHECK_STATE offlineDotCheckState;
}
@property (weak, nonatomic) id<NJOfflineDataDelegate> offlineDataDelegate;
@property (weak, nonatomic) id<NJPenCalibrationDelegate> penCalibrationDelegate;
@property (weak, nonatomic) id<NJFWUpdateDelegate> fwUpdateDelegate;
@property (weak, nonatomic) id<NJPenStatusDelegate> penStatusDelegate;
@property (weak, nonatomic) id<NJPenPasswordDelegate> penPasswordDelegate;
@property (nonatomic) BOOL penDown;
@property (strong, nonatomic) NSMutableArray *nodes;
@property (strong, nonatomic) NJNotebookWriterManager *writerManager;
@property (nonatomic) float mDotToScreenScale;
@property (strong, nonatomic) NJNotebookPaperInfo *paperInfo;
@property (strong, nonatomic) NSMutableArray *strokeArray;
@property (strong, nonatomic) NJPenCommManager *commManager;
@property (strong, nonatomic) NJVoiceManager *voiceManager;
@property (strong, nonatomic) NSMutableData *offlineData;
@property (strong, nonatomic) NSMutableData *offlinePacketData;
@property (nonatomic) int offlineDataOffset;
@property (nonatomic) int offlineTotalDataSize;
@property (nonatomic) int offlineTotalDataReceived;
@property (nonatomic) int offlineDataSize;
@property (nonatomic) int offlinePacketCount;
@property (nonatomic) int offlinePacketSize;
@property (nonatomic) int offlinePacketOffset;
@property (nonatomic) int offlineLastPacketIndex;
@property (nonatomic) int offlinePacketIndex;
@property (nonatomic) int offlineSliceCount;
@property (nonatomic) int offlineSliceSize;
@property (nonatomic) int offlineLastSliceSize;
@property (nonatomic) int offlineLastSliceIndex;
@property (nonatomic) int offlineSliceIndex;
@property (nonatomic) int offlineOwnerIdRequested;
@property (nonatomic) int offlineNoteIdRequested;
@property (nonatomic) BOOL offlineFileProcessing;
@property (nonatomic) UInt64 offlineLastStrokeStartTime;
@property (strong, nonatomic) NSMutableDictionary *offlineFileParsedList;
@property (nonatomic) BOOL sealReceived;
@property (nonatomic) NSInteger lastSealId;


// FW Update
@property (strong, nonatomic) NSData *updateFileData;
@property (nonatomic) NSInteger updateFilePosition;

@property (nonatomic) int idleCounter;
@property (strong, nonatomic)NSTimer *idleTimer;

@property (nonatomic) PenStateStruct *penStatus;
@property (nonatomic) UInt32 colorFromPen;

@property (nonatomic) PageInfoType *currentPageInfo;
@property (strong, nonatomic) NSMutableArray *dataRowArray;
@property (nonatomic) BOOL sendOneTime;
@property (nonatomic) BOOL alarmOneTime;

@property (nonatomic) UInt32 penTipColor;

@property (nonatomic) UInt16 packetCount;

@property (strong, nonatomic) NJPage *cPage;
@property (nonatomic) BOOL isReadyExchangeSent;
- (void)updateIdleCounter:(NSTimer *)timer;

@end

@implementation NJPenCommParser {
    float point_x[POINT_COUNT_MAX];
    float point_y[POINT_COUNT_MAX];
    float point_p[POINT_COUNT_MAX];
    int time_diff[POINT_COUNT_MAX];
    int point_count;
    UInt64 startTime;
    unsigned char pressureMax;
    UInt32 penColor;
    UInt32 offlinePenColor;
    
    float *point_x_buff;
    float *point_y_buff;
    float *point_p_buff;
    int *time_diff_buff;
    int point_index;
}
@synthesize startX=_startX;
@synthesize startY=_startY;
@synthesize batteryLevel;
@synthesize memoryUsed;
@synthesize fwVersion;

- (id) initWithPenCommManager:(NJPenCommManager *)manager
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _commManager = manager;
    self.paperInfo = [NJNotebookPaperInfo sharedInstance];
    self.strokeArray = [[NSMutableArray alloc] initWithCapacity:3];
    point_count = 0;
    node_count = 0;
    node_count_pen = -1;
    self.idleCounter = 0;
    self.idleTimer = nil;
    self.voiceManager = [NJVoiceManager sharedInstance];
    self.updateFileData = nil;
    self.updateFilePosition = 0;
    pressureMax = PRESSURE_MAX;
    _offlineFileProcessing = NO;
    _shouldSendPageChangeNotification = NO;
    _isReadyExchangeSent = NO;
    self.penThickness = 960.0f;
    self.lastSealId = -1;
    self.cancelFWUpdate = NO;
    self.passwdCounter = 0;
    point_index = 0;
    
    return self;
}
- (void) setPenCommUpDownDataReady:(BOOL)penCommUpDownDataReady
{
    _penCommUpDownDataReady = penCommUpDownDataReady;
    if (penCommUpDownDataReady) {
        [self sendReadyExchangeDataIfReady];
    }
}
- (void) setPenCommIdDataReady:(BOOL)penCommIdDataReady
{
    _penCommIdDataReady = penCommIdDataReady;
    if (penCommIdDataReady) {
        [self sendReadyExchangeDataIfReady];
    }
}
- (void) setPenCommStrokeDataReady:(BOOL)penCommStrokeDataReady
{
    _penCommStrokeDataReady = penCommStrokeDataReady;
    if (penCommStrokeDataReady) {
        [self sendReadyExchangeDataIfReady];
    }
}
- (void) setPenExchangeDataReady:(BOOL)penExchangeDataReady
{
    _penExchangeDataReady = penExchangeDataReady;
    if (penExchangeDataReady) {
        [self sendReadyExchangeDataIfReady];
    }
}
- (void) sendReadyExchangeDataIfReady
{
    if (_penCommIdDataReady && _penCommStrokeDataReady && _penCommUpDownDataReady && _penExchangeDataReady) {
        [self writeReadyExchangeData:YES];
    }
}

- (void) setPenPasswordResponse:(BOOL)penPasswordResponse
{
    _penPasswordResponse = penPasswordResponse;
    if (penPasswordResponse) {
        
        [self sendPenPasswordReponseData];
    }
}
- (void) sendPenPasswordReponseData
{
    if (_penCommIdDataReady && _penCommStrokeDataReady && _penCommUpDownDataReady && _penExchangeDataReady) {
        
        NSString *password = [MyFunctions loadPasswd];

        [self setBTComparePassword:password];
        
    }
}

- (void) sendPenPasswordReponseDataWithPasswd:(NSString *)passwd
{
    if (_penCommIdDataReady && _penCommStrokeDataReady && _penCommUpDownDataReady && _penExchangeDataReady) {

        [self setBTComparePassword:passwd];
    }
}

- (void) setPenDown:(BOOL)penDown
{
    if (point_count > 0) { // both penDown YES and NO
        if (self.strokeHandler){
            penColor = [self.strokeHandler setPenColor];
        }
        
        //NISDK - for the first stroke
        if (self.cPage) {
            NSLog(@"self.cPage setPenDown point_count %d, pen color 0x%x, inputScale %f", point_count, (unsigned int)penColor, self.cPage.inputScale);
            NJStroke *stroke = [[NJStroke alloc] initWithRawDataX:point_x Y:point_y pressure:point_p time_diff:time_diff
                                                         penColor:penColor penThickness:_penThickness startTime:startTime size:point_count
                                                       normalizer:self.cPage.inputScale];
            NSLog(@"setPenDown : self.cPage");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.cPage addStrokes:stroke];
                
            });
        }
        
        if ([self.writerManager documentOpend]) {
            NSLog(@"setPenDown point_count %d, pen color 0x%x, inputScale %f", point_count, (unsigned int)penColor, self.activePageDocument.page.inputScale);
            NJStroke *stroke = [[NJStroke alloc] initWithRawDataX:point_x Y:point_y pressure:point_p time_diff:time_diff
                                                         penColor:penColor penThickness:_penThickness startTime:startTime size:point_count
                                                       normalizer:self.activePageDocument.page.inputScale];
            NSLog(@"setPenDown : documentOpend");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.activePageDocument.page addStrokes:stroke];
                //NSLog(@"PageDataChanged Notification");
                [[NSNotificationCenter defaultCenter]
                            postNotificationName:NJPageChangedNotification
                                        object:self.activePageDocument.page userInfo:nil];
            });
        }
        else {
            NJStroke *stroke = [[NJStroke alloc] initWithRawDataX:point_x Y:point_y pressure:point_p time_diff:time_diff
                                                        penColor:penColor penThickness:_penThickness startTime:startTime size:point_count];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.strokeArray addObject:stroke];
            });
        }
        self.nodes = nil;
        point_count = 0;
    }
    
    if (penDown == YES) {
        NSLog(@"penDown YES");
        if (self.nodes == nil) {
            self.nodes = [[NSMutableArray alloc] init];
        }
        // Just ignore timestamp from Pen. We use Audio timestamp from iPhone.
        /* ken 2015.04.19*/
        UInt64 timeInMiliseconds = (UInt64)([[NSDate date] timeIntervalSince1970]*1000);
        NSLog(@"Stroke start time %llu", timeInMiliseconds);
        startTime = timeInMiliseconds;
         
        dotCheckState = DOT_CHECK_FIRST;
    }
    else {
        NSLog(@"penDown NO");
        dotCheckState = DOT_CHECK_NONE;
        
        _sendOneTime = YES;
    }
    _penDown = penDown;
}

- (NJNotebookWriterManager *) writerManager
{
    if (_writerManager == nil) {
        _writerManager = [NJNotebookWriterManager sharedInstance];
    }
    return _writerManager;
}

- (NJPageDocument *) activePageDocument
{
    //if (_activePageDocument == nil) {
        _activePageDocument = [self.writerManager activePageDocument];
    //}
    return _activePageDocument;
}

- (void) setOfflineDataDelegate:(id)offlineDataDelegate
{
    _offlineDataDelegate = (id<NJOfflineDataDelegate>)offlineDataDelegate;
}
- (void) setPenCalibrationDelegate:(id<NJPenCalibrationDelegate>)penCalibrationDelegate
{
    _penCalibrationDelegate = penCalibrationDelegate;
}
- (void) setFWUpdateDelegate:(id<NJFWUpdateDelegate>)fwUpdateDelegate
{
    _fwUpdateDelegate = fwUpdateDelegate;
}
- (void) setPenStatusDelegate:(id<NJPenStatusDelegate>)penStatusDelegate;
{
    _penStatusDelegate = penStatusDelegate;
}
- (void) setPenPasswordDelegate:(id<NJPenPasswordDelegate>)penPasswordDelegate;
{
    _penPasswordDelegate = penPasswordDelegate;
}

- (void) setCancelFWUpdate:(BOOL)cancelFWUpdate
{
    _cancelFWUpdate = cancelFWUpdate;
}
#pragma mark - Received data


- (float) processPressure:(float)pressure
{
    if (pressure < PRESSURE_V_MIN) pressure = PRESSURE_V_MIN;
    pressure = (pressure)/(pressureMax - PRESSURE_MIN);
    return pressure;
}
- (void) parsePenStrokeData:(unsigned char *)data withLength:(int) length
{
#define STROKE_PACKET_LEN   8
    if (self.penDown == NO || _sealReceived == YES) return;
    unsigned char packet_count = data[0];
    int strokeDataLength = length - 1;
    //        NSLog(@"Received: stroke count = %d, length = %d", packet_count, dataLength);
    data++;
    // 06-Oct-2014 by namSsan
    // checkXcoord X,Y only called once for middle point of the stroke
    //int mid = (pa)
    BOOL shouldCheck = NO;
    int mid = packet_count / 2;
    
    for ( int i =0 ; i < packet_count; i++){
        if ((STROKE_PACKET_LEN * (i+1)) > strokeDataLength) {
            break;
        }
        shouldCheck = NO;
        if(i == mid) shouldCheck = YES;
        [self parsePenStrokePacket:data withLength:STROKE_PACKET_LEN withCoordCheck:shouldCheck];
        data = data + STROKE_PACKET_LEN;
    }

}
- (void) parsePenStrokePacket:(unsigned char *)data withLength:(int)length withCoordCheck:(BOOL)checkCoord
{
    COMM_WRITE_DATA *strokeData = (COMM_WRITE_DATA *)data;
    dotDataStruct aDot;
    float int_x = (float)strokeData->x;
    float int_y = (float)strokeData->y;
    float float_x = (float)strokeData->f_x  * 0.01f;
    float float_y = (float)strokeData->f_y  * 0.01f;
    aDot.diff_time = strokeData->diff_time;
    aDot.pressure = (float)strokeData->force;
    aDot.x = int_x + float_x  - self.startX;
    aDot.y = int_y + float_y  - self.startY;
//    NSLog(@"Raw X %f, Y %f", int_x + float_x, int_y + float_y);
//    NSLog(@"time %d, x %f, y %f, pressure %f", aDot.diff_time, aDot.x, aDot.y, aDot.pressure);
    [self dotChecker:&aDot];
    
    if(checkCoord) {
        float x = int_x + float_x;
        float y = int_y + float_y;
        [self checkXcoord:x Ycoord:y];
    }
}

#define DAILY_PLAN_START_PAGE_606 62
#define DAILY_PLAN_END_PAGE_606 826
#define DAILY_PLAN_START_PAGE_608 42
#define DAILY_PLAN_END_PAGE_608 424

- (void)pageInfoArrayInitNoteId:(UInt32)noteId AndPageNumber:(UInt32)pageNumber
{
    int startPageNumber = 1;
    int index = 0;
    NJNotebookPaperInfo *notebookInfo = [NJNotebookPaperInfo sharedInstance];
    
    NSDictionary *tempInfo = [notebookInfo.notebookPuiInfo objectForKey:[NSNumber numberWithInteger:noteId]];
    PageInfoType *tempPageInfo = [[tempInfo objectForKey:@"page_info"] pointerValue];
    startPageNumber = [notebookInfo getPaperStartPageNumberForNotebook:noteId];
    
    NSArray *keysArray = [notebookInfo.notebookPuiInfo allKeys];
    int count = (int)[keysArray count];
    for (NSNumber *noteIdInfo in keysArray) {
        //NSLog(@"NoteIdInfo : %@", noteIdInfo);
        if (noteId == (UInt32)[noteIdInfo unsignedIntegerValue]) {
            break;
        }
        index++;
    }
    
    if (index == count) {
        NSLog(@"noteId isn't included to pui info");
        _currentPageInfo = NULL;
        return;
    }
    if((tempPageInfo == NULL)||(noteId == 605)) {
        NSLog(@"tempPageInfo == NULL or active Note Id == 605");
        _currentPageInfo = NULL;
        return;
    }
    
    if((noteId == 601) || (noteId == 602) || (noteId == 2)|| (noteId == 604) || (noteId == 609)
            || (noteId == 610)|| (noteId == 611) || (noteId == 612) || (noteId == 613) || (noteId == 614)
            || (noteId == 617) || (noteId == 618) || (noteId == 619)|| (noteId == 620)|| (noteId == 114)
            || (noteId == 700)|| (noteId == 701)|| (noteId == 702)){
        if (pageNumber >= startPageNumber) {
            _currentPageInfo = &tempPageInfo[0];
        }
    }else if((noteId == 615) || (noteId == 616)){
        if (pageNumber >= startPageNumber) {
            _currentPageInfo = &tempPageInfo[0];
        }
    }else if(noteId == 603){
        if (pageNumber >= startPageNumber) {
            if ((pageNumber%2) == 1) {
                _currentPageInfo = &tempPageInfo[0];
            } else if ((pageNumber%2) == 0){
                _currentPageInfo = &tempPageInfo[1];
            }
        }
    }else {
        if (pageNumber >= startPageNumber) {
            _currentPageInfo = &tempPageInfo[0];
        }
    }
    
    if(_currentPageInfo == NULL) {
        NSLog(@"2. _currentPageInfo == NULL");
        return;
    }
    
    //NSLog(@"pageArrayInit _currentPageInfo:%@", self.currentPageInfo);
    
    int rowSize = (_currentPageInfo->activeHeight)/(_currentPageInfo->spanY);
    int colSize = (_currentPageInfo->activeWidth)/(_currentPageInfo->spanX);
    
    _dataRowArray = [[NSMutableArray alloc] initWithCapacity:rowSize];
    
    
    for (int i = 0; i < rowSize; i++) {
        NSMutableArray *dataColArray = [[NSMutableArray alloc] initWithCapacity:colSize];
        for (int j = 0; j < colSize; j++) {
            if (_currentPageInfo->cmd == Email) {
                dataColArray[j] = [NSNumber numberWithInt:0];
                if ((i == _currentPageInfo->arrayY) && (j == _currentPageInfo->arrayX)) {
                    dataColArray[j] = [NSNumber numberWithInt:Email];
                }
            }
        }
        [_dataRowArray insertObject:dataColArray atIndex:i];
    }
    
    _sendOneTime = YES;
    _alarmOneTime = YES;
}

- (void) checkXcoord:(float)x Ycoord:(float)y
{
    if (_currentPageInfo == NULL){
        NSLog(@"3. _currentPageInfo == NULL");
        return;
    }
    
    if (((x < _currentPageInfo->activeStartX) || (x > (_currentPageInfo->activeStartX + _currentPageInfo->activeWidth)))
        || ((y < _currentPageInfo->activeStartY) || (y > (_currentPageInfo->activeStartY + _currentPageInfo->activeHeight)))) {
        //NSLog(@"out of active paper area");
        return;
    }
    int arrayY = (y - _currentPageInfo->activeStartY) / (_currentPageInfo->spanY);
    int arrayX = (x - _currentPageInfo->activeStartX) /(_currentPageInfo->spanX);
    //NSLog(@"arrayX: %d, arrayY: %d",arrayX, arrayY);
    
    if (arrayY >= [_dataRowArray count]) {
        NSLog(@"arrayY is beyond array count");
        return;
    }
    
    NSMutableArray *subArray = [_dataRowArray objectAtIndex:arrayY];
    
    if (arrayX >= [subArray count]) {
        NSLog(@"arrayX is beyond array count");
        return;
    }
    
    if (_currentPageInfo->cmd == Email) {
        //NSLog(@"Email command, before sendOneTime");
        if([subArray[arrayX] intValue] == Email){
            if (_sendOneTime) {
                NSLog(@"Email command, sendOneTime YES");
                //delegate
                if (self.commandHandler != nil) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.commandHandler sendEmailWithPdf];
                    });
                }
                _sendOneTime = NO;
            }
        }
    }
}
- (void)updateIdleCounter:(NSTimer *)timer
{
    if (self.penDown) return;
    if ([self.voiceManager isRecording]) {
        self.idleCounter = IDLE_COUNT;
        return;
    }
    self.idleCounter--;
    if (self.idleCounter <= 0) {
        _commManager.writeActiveState = NO;
    
        [self stopIdleCounter];
    }
}
- (void)stopIdleCounter
{
    [self.idleTimer invalidate];
    self.idleTimer = nil;
}
- (void) parsePenUpDowneData:(unsigned char *)data withLength:(int) length
{
    // see the setter for _penDown. It is doing something important.
    COMM_PENUP_DATA *updownData = (COMM_PENUP_DATA *)data;
    if (updownData->upDown == 0) {
        
        self.penDown = YES;
        node_count_pen = -1;
        node_count = 0;
        self.idleCounter = IDLE_COUNT;
        UInt32 color = updownData->penColor;
        if ((color & 0xFF000000) == 0x01000000 && (color & 0x00FFFFFF) != 0x00FFFFFF && (color & 0x00FFFFFF) != 0x00000000) {
            penColor = color | 0xFF000000; // set Alpha to 255
        }

        NSLog(@"Pen color 0x%x", (unsigned int)penColor);
        
    }
    else {
        [self dotCheckerLast];
        self.penDown = NO;
        
        self.idleCounter = IDLE_COUNT;
        if (self.idleTimer == nil) {
            _commManager.writeActiveState = YES;
#ifdef USE_STROKE_IDLE_TIMER   //this function removed from doc.
            self.idleTimer = [NSTimer timerWithTimeInterval:IDLE_TIMER_INTERVAL target:self
                                                   selector:@selector(updateIdleCounter:) userInfo:nil repeats:YES];
            [[NSRunLoop mainRunLoop] addTimer:self.idleTimer forMode:NSDefaultRunLoopMode];
#endif
        }
    }
    
    UInt64 time = updownData->time;
    NSNumber *timeNumber = [NSNumber numberWithLongLong:time];
    NSNumber *color = [NSNumber numberWithUnsignedInteger:penColor];
    NSString *status = (self.penDown) ? @"down":@"up";
    NSDictionary *stroke = [NSDictionary dictionaryWithObjectsAndKeys:
                            @"updown", @"type",
                            timeNumber, @"time",
                            status, @"status",
                            color, @"color",
                            nil];
    if (self.strokeHandler != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.strokeHandler processStroke:stroke];
        });
    }
}
- (void) parsePenNewIdData:(unsigned char *)data withLength:(int) length
{
    COMM_CHANGEDID2_DATA *newIdData = (COMM_CHANGEDID2_DATA *)data;
    unsigned char section = (newIdData->owner_id >> 24) & 0xFF;
    UInt32 owner = newIdData->owner_id & 0x00FFFFFF;
    UInt32 noteId = newIdData->note_id;
    UInt32 pageNumber = newIdData->page_id;
    NSLog(@"section : %d, owner : %d, note : %d, page : %d", section, (unsigned int)owner, (unsigned int)noteId, (unsigned int)pageNumber);
    
    // Handle seal if section is 4.
    if (section == SEAL_SECTION_ID) {
        // Note ID is delivered as owner ID.
        _lastSealId = owner;
        //_lastSealId = 1;
        //To ignore stroke.
        _sealReceived = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            
            NSLog(@"In order to use same type of notebooks,\nplease move your existing notebook to NoteBox\n instead of checking the seal on the notebook.");
        });
        return;
    }
    
    if(noteId == _lastSealId) {
        
    }
    _lastSealId = -1;
    _sealReceived = NO;
    //pageInfoArrayInit should be performed before checkCoord.
    //sometimes it is called after checkCoord(parsePenStrokePacket) if it is inserted in the following dispatch_async(dispatch_get_main_queue().
    if (self.writerManager.activeNoteBookId != noteId || self.writerManager.activePageNumber != pageNumber) {
        //pui
        [self pageInfoArrayInitNoteId:noteId AndPageNumber:pageNumber];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
    if (self.writerManager.activeNoteBookId != noteId || self.writerManager.activePageNumber != pageNumber) {
        if ([self.paperInfo hasInfoForNotebookId:(int)noteId] == NO) {
            if (section == 0 || section == 3) {
                //Do nothing. This is unkown note for demo.
            }
            else
                return;
        }

        NSLog(@"New Id Data noteId %u, pageNumber %u", (unsigned int)noteId, (unsigned int)pageNumber);
        if (self.strokeHandler != nil) {

            [self.strokeHandler notifyPageChanging];

        }
        
        //Chage X, Y start cordinates.
        [self.paperInfo getPaperDotcodeStartForNotebook:(int)noteId PageNumber: pageNumber startX:&_startX startY:&_startY];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pageOpened:) name:NJNoteBookPageDocumentOpenedNotification object:self.writerManager];
        if ([self.voiceManager isRecording]) {
            [self.voiceManager addVoiceMemoPageChangingTo:noteId pageNumber:pageNumber];
            NSLog(@"****** add changing");
        }
        [self.writerManager activeNotebookIdDidChange:noteId withPageNumber:pageNumber];
        
        //NISDK - for the first stroke
        self.cPage = [[NJPage alloc] initWithNotebookId:noteId andPageNumber:pageNumber];
        if (self.canvasStartDelegate) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.cPage) {
                    [self.canvasStartDelegate firstStrokePage:self.cPage];
                }
                [self.canvasStartDelegate activeNoteId:(int)noteId pageNum:(int)pageNumber];
                
                
            });
        }
        // post notification must called after writer change its active notebook id
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NJPenCommParserPageChangedNotification object:nil userInfo:nil];
            _shouldSendPageChangeNotification = NO;
        });
        
        //NISDK -
        if (self.strokeHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.strokeHandler activeNoteId:(int)noteId pageNum:(int)pageNumber sectionId:(int)section ownderId:(int)owner pageCreated:self.cPage];
                
                
            });
        }
        // sync mode. add pagechanged here
        if ([self.voiceManager isRecording]) {
            [self.voiceManager addVoiceMemoPageChanged];
        }
    } else {
        
        if(_shouldSendPageChangeNotification) {
            
            //NISDK - for the first stroke
            if (self.canvasStartDelegate) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.cPage) {
                        [self.canvasStartDelegate firstStrokePage:self.cPage];
                    }
                    [self.canvasStartDelegate activeNoteId:(int)noteId pageNum:(int)pageNumber];
                    
                    
                });
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:NJPenCommParserPageChangedNotification object:nil userInfo:nil];
                _shouldSendPageChangeNotification = NO;
            });
            
        }
            
    }
    });
}
- (void) parsePenStatusData:(unsigned char *)data withLength:(int) length
{
    self.penStatus = (PenStateStruct *)data;
    NSLog(@"penStatus %d, timezoneOffset %d, timeTick %llu", self.penStatus->penStatus, self.penStatus->timezoneOffset, self.penStatus->timeTick);
    NSLog(@"pressureMax %d, battery %d, memory %d", self.penStatus->pressureMax, self.penStatus->battLevel, self.penStatus->memoryUsed);
    NSLog(@"autoPwrOffTime %d, penPressure %d", self.penStatus->autoPwrOffTime, self.penStatus->penPressure);

    NSLog(@"Getting penstatus finished");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.penStatusDelegate penStatusData:self.penStatus];
    });

    if (self.battMemoryBlock != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.battMemoryBlock(self.penStatus -> battLevel, self.penStatus -> memoryUsed);
            self.battMemoryBlock = nil;
        });
        NSLog(@"battMemoryBlock != nil");
        return;
    }
}

//#define FW_UPDATE_TEST
- (void) parseOfflineFileList:(unsigned char *)data withLength:(int) length
{
    OfflineFileListStruct *fileList = (OfflineFileListStruct *)data;
    int noteCount = MIN(fileList->noteCount, 10);
    
    unsigned char section = (fileList->sectionOwnerId >> 24) & 0xFF;
    UInt32 ownerId = fileList->sectionOwnerId & 0x00FFFFFF;
    
    //exclude owner 28
    if ([self.paperInfo hasInfoForSectionId:(int)section OwnerId:(int)ownerId]){
        dispatch_async(dispatch_get_main_queue(), ^{
            if(!isEmpty(self.offlineDataDelegate) && [self.offlineDataDelegate respondsToSelector:@selector(offlineDataDidReceiveNoteListCount:ForSectionOwnerId:)])
                [self.offlineDataDelegate offlineDataDidReceiveNoteListCount:noteCount ForSectionOwnerId:fileList->sectionOwnerId];
        });
    }
    
#ifdef FW_UPDATE_TEST
    {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDirectory = paths[0];
    NSString *updateFilePath = [documentDirectory stringByAppendingPathComponent:@"Update.zip"];
    NSURL *url = [NSURL fileURLWithPath:updateFilePath];
    [self sendUpdateFileInfoAtUrl:url];
    }
#endif
    
    if (noteCount == 0) return;
    //exclude owner 28
    if ([self.paperInfo hasInfoForSectionId:(int)section OwnerId:(int)ownerId]){
        if (section == SEAL_SECTION_ID) {
            //Just ignore for offline data
            [self requestDelOfflineFile:fileList->sectionOwnerId];
        }
        else {
            NSNumber *sectionOwnerId = [NSNumber numberWithUnsignedInteger:fileList->sectionOwnerId];
            
            NSMutableArray *noteArray = [_offlineFileList objectForKey:sectionOwnerId];
            if (noteArray == nil) {
                noteArray = [[NSMutableArray alloc] initWithCapacity:noteCount];
                [_offlineFileList setObject:noteArray forKey:sectionOwnerId];
            }
            NSLog(@"OfflineFileList owner : %@", sectionOwnerId);
            for (int i=0; i < noteCount; i++) {
                NSNumber *noteId = [NSNumber numberWithUnsignedInteger:fileList->noteId[i]];
                NSLog(@"OfflineFileList note : %@", noteId);
                [noteArray addObject:noteId];
            }
        }
    }
    
    if (fileList->status == 0) {
        NSLog(@"More offline File List remained");
    }
    else {
        if ([[_offlineFileList allKeys] count] > 0) {
            NSLog(@"Getting offline File List finished");
            dispatch_async(dispatch_get_main_queue(), ^{
                if(!isEmpty(self.offlineDataDelegate) && [self.offlineDataDelegate respondsToSelector:@selector(offlineDataDidReceiveNoteList:)])
                    [self.offlineDataDelegate offlineDataDidReceiveNoteList:_offlineFileList];
            });
        }
    }
}

-(BOOL) requestNextOfflineNote
{
    _offlineFileProcessing = YES;
    BOOL needNext = YES;
    NSEnumerator *enumerator = [_offlineFileList keyEnumerator];
    while (needNext) {
        NSNumber *ownerId = [enumerator nextObject];
        if (ownerId == nil) {
            _offlineFileProcessing = NO;
            NSLog(@"Offline data : no more file left");
            return NO;
        }
        NSArray *noteList = [_offlineFileList objectForKey:ownerId];
        if ([noteList count] == 0) {
            [_offlineFileList removeObjectForKey:ownerId];
            continue;
        }
        NSNumber *noteId = [noteList objectAtIndex:0];
        _offlineOwnerIdRequested = (UInt32)[ownerId unsignedIntegerValue];
        _offlineNoteIdRequested = (UInt32)[noteId unsignedIntegerValue];
        [self requestOfflineDataWithOwnerId:_offlineOwnerIdRequested noteId:_offlineNoteIdRequested];
        needNext = NO;
    }
    return YES;
}
-(void) didReceiveOfflineFileForOwnerId:(UInt32)ownerId noteId:(UInt32)noteId
{
    NSNumber *ownerNumber = [NSNumber numberWithUnsignedInteger:_offlineOwnerIdRequested];
    NSNumber *noteNumber = [NSNumber numberWithUnsignedInteger:_offlineNoteIdRequested];
    NSMutableArray *noteList = [_offlineFileList objectForKey:ownerNumber];
    if (noteList == nil) {
        return;
    }
    NSUInteger index = [noteList indexOfObject:noteNumber];
    if (index == NSNotFound) {
        return;
    }
    [noteList removeObjectAtIndex:index];
}
- (void) parseOfflineFileListInfo:(unsigned char *)data withLength:(int) length
{
    OfflineFileListInfoStruct *fileInfo = (OfflineFileListInfoStruct *)data;
    NSLog(@"OfflineFileListInfo file Count %d, size %d", (unsigned int)fileInfo->fileCount, (unsigned int)fileInfo->fileSize);
    _offlineTotalDataSize = fileInfo->fileSize;
    _offlineTotalDataReceived = 0;
    [self notifyOfflineDataStatus:OFFLINE_DATA_RECEIVE_START percent:0.0f];
}
- (void) parseOfflineFileInfoData:(unsigned char *)data withLength:(int) length
{
    OFFLINE_FILE_INFO_DATA *fileInfo = (OFFLINE_FILE_INFO_DATA *)data;
    if (fileInfo->type == 1) {
        NSLog(@"Offline File Info : Zip file");
    }
    else {
        NSLog(@"Offline File Info : Normal file");
    }
    UInt32 fileSize = fileInfo->file_size;
    self.offlinePacketCount = fileInfo->packet_count;
    _offlinePacketSize = fileInfo->packet_size;
    _offlineSliceCount = fileInfo->slice_count;
    _offlineSliceSize = fileInfo->slice_size;
    self.offlineSliceIndex = 0;
    NSLog(@"File size : %d, packet count : %d, packet size : %d", (unsigned int)fileSize, self.offlinePacketCount, _offlinePacketSize);
    NSLog(@"Slice count : %d, slice size : %d", (unsigned int)self.offlineSliceCount, _offlineSliceSize);
    _offlineLastPacketIndex = fileSize/_offlinePacketSize;
    int lastPacketSize = fileSize % _offlinePacketSize;
    if (lastPacketSize == 0) {
        _offlineLastPacketIndex -= 1;
        _offlineLastSliceIndex = _offlineSliceCount - 1;
        _offlineLastSliceSize = _offlineSliceSize;
    }
    else {
        _offlineLastSliceIndex = lastPacketSize / _offlineSliceSize;
        _offlineLastSliceSize = lastPacketSize % _offlineSliceSize;
        if (_offlineLastSliceSize == 0) {
            _offlineLastSliceIndex -= 1;
            _offlineLastSliceSize = _offlineSliceSize;
        }
    }
    self.offlineData = [[NSMutableData alloc] initWithLength:fileSize];
    self.offlinePacketData = nil;
    self.offlineDataOffset = 0;
    self.offlineDataSize = fileSize;
    [self offlineFileAckForType:1 index:0];  // 1 : header, index 0
}
//#define SPEED_TEST
#ifdef SPEED_TEST
static NSTimeInterval startTime4Speed, endTime4Speed;
static int length4Speed;
#endif
- (void) parseOfflineFileData:(unsigned char *)data withLength:(int) length
{
    static int expected_slice = -1;
    static BOOL slice_valid = YES;

    OFFLINE_FILE_DATA *fileData = (OFFLINE_FILE_DATA *)data;
    int index = fileData->index;
    int slice_index = fileData->slice_index;
    unsigned char *dataReceived = &(fileData->data);
    if (slice_index == 0) {
        expected_slice = -1;
        slice_valid = YES;
        self.offlinePacketOffset = 0;
        self.offlinePacketData = [[NSMutableData alloc] initWithCapacity:_offlinePacketSize];
    }
    int lengthToCopy = length - sizeof(fileData->index) - sizeof(fileData->slice_index);
    lengthToCopy = MIN(lengthToCopy, self.offlineSliceSize);
    if (index == _offlineLastPacketIndex && slice_index == _offlineLastSliceIndex) {
        lengthToCopy = _offlineLastSliceSize;
    }
    else if ((self.offlinePacketOffset + lengthToCopy) > self.offlinePacketSize) {
        lengthToCopy = self.offlinePacketSize - self.offlinePacketOffset;
    }
    NSLog(@"Data index : %d, slice index : %d, data size received: %d copied : %d", index, slice_index, length, lengthToCopy);
#ifdef SPEED_TEST
    if (index == 0 && slice_index == 0) {
        startTime4Speed = [[NSDate date] timeIntervalSince1970];
        length4Speed = 0;
    }
    length4Speed += length;
#endif
    if (slice_valid == NO) {
        return;
    }
    expected_slice++;
    if (expected_slice != slice_index ) {
        NSLog(@"Bad slice index : expected %d, received %d", expected_slice, slice_index);
        slice_valid = NO;
        return; // Wait for next start
    }
    [self.offlinePacketData appendBytes:dataReceived length:lengthToCopy];
    _offlinePacketOffset += lengthToCopy;
    if (slice_index == (_offlineSliceCount - 1) || (index == _offlineLastPacketIndex && slice_index == _offlineLastSliceIndex) ) {
        [self offlineFileAckForType:2 index:(unsigned char)index]; // 2 : data
        NSRange range = {index*_offlinePacketSize, _offlinePacketOffset};
        [_offlineData replaceBytesInRange:range withBytes:[_offlinePacketData bytes]];
        _offlineDataOffset += _offlinePacketOffset;
        _offlinePacketOffset = 0;
        float percent = (float)((_offlineTotalDataReceived + _offlineDataOffset) * 100.0)/(float)_offlineTotalDataSize;
        [self notifyOfflineDataStatus:OFFLINE_DATA_RECEIVE_PROGRESSING percent:percent];
        NSLog(@"offlineDataOffset=%d, offlineDataSize=%d", _offlineDataOffset, _offlineDataSize);
    }
    if (self.offlineDataOffset >= self.offlineDataSize) {
#ifdef SPEED_TEST
        endTime4Speed = [[NSDate date] timeIntervalSince1970];
        NSTimeInterval timeLapse = endTime4Speed - startTime4Speed;
        NSLog(@"Offline receiving speed %f bytes/sec", length4Speed/timeLapse);
#endif
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentDirectory = paths[0];
        NSString *offlineFilePath = [documentDirectory stringByAppendingPathComponent:@"OfflineFile"];
        NSURL *url = [NSURL fileURLWithPath:offlineFilePath];
        NSFileManager *fm = [NSFileManager defaultManager];
        __block NSError *error = nil;
        [fm createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&error];
        NSString *path = [offlineFilePath stringByAppendingPathComponent:@"offlineFile.zip"];
        [fm createFileAtPath:path contents:self.offlineData attributes:nil];
        //NISDK
        dispatch_async(dispatch_get_main_queue(), ^{
            if(!isEmpty(self.offlineDataDelegate) && [self.offlineDataDelegate respondsToSelector:@selector(offlineDataPathBeforeParsed:)])
                [self.offlineDataDelegate offlineDataPathBeforeParsed:path];
        });
        ZZArchive* offlineZip = [ZZArchive archiveWithURL:[NSURL fileURLWithPath:path] error:nil];
        ZZArchiveEntry* penDataEntry = offlineZip.entries[0];
        if ([penDataEntry check:&error]) {
            // GOOD
            NSLog(@"Offline zip file received successfully");
            NSData *penData = [penDataEntry newDataWithError:&error];
            if (penData != nil) {
                [self parseOfflinePenData:penData];
            }
            _offlineTotalDataReceived += _offlineDataSize;
        }
        else {
            // BAD
            NSLog(@"Offline zip file received badly");
        }
        _offlinePacketOffset = 0;
        _offlinePacketData = nil;
    }
}
- (void) parseOfflineFileStatus:(unsigned char *)data withLength:(int) length
{
    OfflineFileStatusStruct *fileStatus = (OfflineFileStatusStruct *)data;
    if (fileStatus->status == 1) {
        NSLog(@"OfflineFileStatus success");
        [self didReceiveOfflineFileForOwnerId:_offlineOwnerIdRequested noteId:_offlineNoteIdRequested];
        [self notifyOfflineDataStatus:OFFLINE_DATA_RECEIVE_END percent:100.0f];
    }
    else {
        NSLog(@"OfflineFileStatus fail");
        [self notifyOfflineDataStatus:OFFLINE_DATA_RECEIVE_FAIL percent:0.0f];
    }
}

/* Parse data in a file from Pen. Need to know offline file format.*/
- (BOOL) parseOfflinePenData:(NSData *)penData
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    // To syncronize main thread and bt thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"dispatch_async start");
        UInt32 noteIdBackup = 0;
        UInt32 pageIdBackup = 0;
        BOOL   hasPageBackup = NO;
        int dataPosition=0;
        unsigned long dataLength = [penData length];
        int headerSize = sizeof(OffLineDataFileHeaderStruct);
        dataLength -= headerSize;
        NSRange range = {dataLength, headerSize};
        OffLineDataFileHeaderStruct header;
        [penData getBytes:&header range:range];
        if (self.strokeHandler) {
            [self.strokeHandler notifyDataUpdating:YES];
        }
        if (self.writerManager.activeNoteBookId != header.nNoteId || self.writerManager.activePageNumber != header.nPageId) {
            noteIdBackup = (UInt32)self.writerManager.activeNoteBookId;
            pageIdBackup = (UInt32)self.writerManager.activePageNumber;
            hasPageBackup = YES;
            NSLog(@"Offline New Id Data noteId %u, pageNumber %u", (unsigned int)header.nNoteId, (unsigned int)header.nPageId);
            //Chage X, Y start cordinates.
            [self.paperInfo getPaperDotcodeStartForNotebook:(int)header.nNoteId PageNumber:(int)header.nPageId startX:&_startX startY:&_startY];
            [self.writerManager syncOpenNotebook:header.nNoteId withPageNumber:header.nPageId saveNow:YES];
        }
        
        unsigned char char1, char2;
        OffLineDataStrokeHeaderStruct strokeHeader;
        while (dataPosition < dataLength) {
            if ((dataLength - dataPosition) < (sizeof(OffLineDataStrokeHeaderStruct) + 2)) break;
            range.location = dataPosition++;
            range.length = 1;
            [penData getBytes:&char1 range:range];
            range.location = dataPosition++;
            [penData getBytes:&char2 range:range];
            if (char1 == 'L' && char2 == 'N') {
                range.location = dataPosition;
                range.length = sizeof(OffLineDataStrokeHeaderStruct);
                [penData getBytes:&strokeHeader range:range];
                dataPosition += sizeof(OffLineDataStrokeHeaderStruct);
                if ((dataLength - dataPosition) < (strokeHeader.nDotCount * sizeof(OffLineDataDotStruct))) {
                    break;
                }
                [self.offlineDataDelegate parseOfflineDots:penData startAt:dataPosition withFileHeader:&header andStrokeHeader:&strokeHeader];
                dataPosition += (strokeHeader.nDotCount * sizeof(OffLineDataDotStruct));
                self.offlineLastStrokeStartTime = strokeHeader.nStrokeStartTime; // addedby namSSan 2015-03-10
            }
        }
        [self.writerManager saveEventlog:YES andEvernote:YES andLastStrokeTime:[NSDate dateWithTimeIntervalSince1970:(self.offlineLastStrokeStartTime / 1000.0)]];
        if (hasPageBackup) {
            if(noteIdBackup > 0) {
                [self.paperInfo getPaperDotcodeStartForNotebook:(int)noteIdBackup PageNumber:(int)pageIdBackup startX:&_startX startY:&_startY];
                [self.writerManager syncOpenNotebook:noteIdBackup withPageNumber:pageIdBackup saveNow:YES];
            } else {
                [self.writerManager saveCurrentPage:YES completionHandler:nil];
            }
        }
        if (self.strokeHandler) {
            [self.strokeHandler notifyDataUpdating:NO];
        }
        NSLog(@"dispatch_semaphore_signal");
        dispatch_semaphore_signal(semaphore);
    });
    NSLog(@"dispatch_semaphore_wait start");
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    NSLog(@"dispatch_semaphore_wait end");
    
    return YES;
}
- (void) parseOfflineDots:(NSData *)penData startAt:(int)position withFileHeader:(OffLineDataFileHeaderStruct *)pFileHeader
          andStrokeHeader:(OffLineDataStrokeHeaderStruct *)pStrokeHeader
{
    OffLineDataDotStruct dot;
    NSRange range = {position, sizeof(OffLineDataDotStruct)};
    int dotCount = MIN(MAX_NODE_NUMBER, (pStrokeHeader->nDotCount));
    point_x_buff = malloc(sizeof(float)* dotCount);
    point_y_buff = malloc(sizeof(float)* dotCount);
    point_p_buff = malloc(sizeof(float)* dotCount);
    time_diff_buff = malloc(sizeof(int)* dotCount);
    point_index = 0;
    
    offlineDotCheckState = OFFLINE_DOT_CHECK_FIRST;
    startTime = pStrokeHeader->nStrokeStartTime;
    //    NSLog(@"offline time %llu", startTime);
    UInt32 color = pStrokeHeader->nLineColor;
    if ((color & 0x00FFFFFF) != 0x00FFFFFF && (color & 0x00FFFFFF) != 0x00000000) {
        offlinePenColor = color | 0xFF000000; // set Alpha to 255
    }
    else
        offlinePenColor = 0;
    offlinePenColor = penColor; // 2015-01-28 add for maintaining color feature
    //NSLog(@"offlinePenColor 0x%x", (unsigned int)offlinePenColor);
    for (int i =0; i < pStrokeHeader->nDotCount; i++) {
        [penData getBytes:&dot range:range];
        
        [self dotCheckerForOfflineSync:&dot];

        if(point_index >= MAX_NODE_NUMBER){
            [self offlineDotCheckerLast];
            
            NJStroke *stroke = [[NJStroke alloc] initWithRawDataX:point_x_buff Y:point_y_buff pressure:point_p_buff time_diff:time_diff_buff
                                                         penColor:offlinePenColor penThickness:_penThickness startTime:startTime size:point_index
                                                       normalizer:self.activePageDocument.page.inputScale];
            [self.activePageDocument.page insertStrokeByTimestamp:stroke];
            point_index = 0;
        }
        position += sizeof(OffLineDataDotStruct);
        range.location = position;
    }
    [self offlineDotCheckerLast];
    
    NJStroke *stroke = [[NJStroke alloc] initWithRawDataX:point_x_buff Y:point_y_buff pressure:point_p_buff time_diff:time_diff_buff
                                                 penColor:offlinePenColor penThickness:_penThickness startTime:startTime size:point_index
                                               normalizer:self.activePageDocument.page.inputScale];
    [self.activePageDocument.page insertStrokeByTimestamp:stroke];
    point_index = 0;
    
    free(point_x_buff);
    free(point_y_buff);
    free(point_p_buff);
    free(time_diff_buff);
}

- (void) dotCheckerForOfflineSync:(OffLineDataDotStruct *)aDot
{
    if (offlineDotCheckState == OFFLINE_DOT_CHECK_NORMAL) {
        if ([self offlineDotCheckerForMiddle:aDot]) {
            [self offlineDotAppend:&offlineDotData2];
            offlineDotData0 = offlineDotData1;
            offlineDotData1 = offlineDotData2;
        }
        else {
            NSLog(@"offlineDotChecker error : middle");
        }
        offlineDotData2 = *aDot;
    }
    else if(offlineDotCheckState == OFFLINE_DOT_CHECK_FIRST) {
        offlineDotData0 = *aDot;
        offlineDotData1 = *aDot;
        offlineDotData2 = *aDot;
        offlineDotCheckState = OFFLINE_DOT_CHECK_SECOND;
    }
    else if(offlineDotCheckState == OFFLINE_DOT_CHECK_SECOND) {
        offlineDotData2 = *aDot;
        offlineDotCheckState = OFFLINE_DOT_CHECK_THIRD;
    }
    else if(offlineDotCheckState == OFFLINE_DOT_CHECK_THIRD) {
        if ([self offlineDotCheckerForStart:aDot]) {
            [self offlineDotAppend:&offlineDotData1];
            if ([self offlineDotCheckerForMiddle:aDot]) {
                [self offlineDotAppend:&offlineDotData2];
                offlineDotData0 = offlineDotData1;
                offlineDotData1 = offlineDotData2;
            }
            else {
                NSLog(@"offlineDotChecker error : middle2");
            }
        }
        else {
            offlineDotData1 = offlineDotData2;
            NSLog(@"offlineDotChecker error : start");
        }
        offlineDotData2 = *aDot;
        offlineDotCheckState = OFFLINE_DOT_CHECK_NORMAL;
    }
}

- (void) offlineDotAppend:(OffLineDataDotStruct *)dot
{
    float pressure, x, y;
    
    x = (float)dot->x + (float)dot->fx * 0.01f;
    y = (float)dot->y + (float)dot->fy * 0.01f;
    pressure = [self processPressure:(float)dot->force];
    point_x_buff[point_index] = x - _startX;
    point_y_buff[point_index] = y - _startY;
    point_p_buff[point_index] = pressure;
    time_diff_buff[point_index] = dot->nTimeDelta;
    point_index++;
}

- (BOOL) offlineDotCheckerForStart:(OffLineDataDotStruct *)aDot
{
    static const float delta = 2.0f;
    if (offlineDotData1.x > 150 || offlineDotData1.x < 1) return NO;
    if (offlineDotData1.y > 150 || offlineDotData1.y < 1) return NO;
    if ((aDot->x - offlineDotData1.x) * (offlineDotData2.x - offlineDotData1.x) > 0
        && ABS(aDot->x - offlineDotData1.x) > delta && ABS(offlineDotData1.x - offlineDotData2.x) > delta)
    {
        return NO;
    }
    if ((aDot->y - offlineDotData1.y) * (offlineDotData2.y - offlineDotData1.y) > 0
        && ABS(aDot->y - offlineDotData1.y) > delta && ABS(offlineDotData1.y - offlineDotData2.y) > delta)
    {
        return NO;
    }
    return YES;
}
- (BOOL) offlineDotCheckerForMiddle:(OffLineDataDotStruct *)aDot
{
    static const float delta = 2.0f;
    if (offlineDotData2.x > 150 || offlineDotData2.x < 1) return NO;
    if (offlineDotData2.y > 150 || offlineDotData2.y < 1) return NO;
    if ((offlineDotData1.x - offlineDotData2.x) * (aDot->x - offlineDotData2.x) > 0
        && ABS(offlineDotData1.x - offlineDotData2.x) > delta && ABS(aDot->x - offlineDotData2.x) > delta)
    {
        return NO;
    }
    if ((offlineDotData1.y - offlineDotData2.y) * (aDot->y - offlineDotData2.y) > 0
        && ABS(offlineDotData1.y - offlineDotData2.y) > delta && ABS(aDot->y - offlineDotData2.y) > delta)
    {
        return NO;
    }
    
    return YES;
}
- (BOOL) offlineDotCheckerForEnd
{
    static const float delta = 2.0f;
    if (offlineDotData2.x > 150 || offlineDotData2.x < 1) return NO;
    if (offlineDotData2.y > 150 || offlineDotData2.y < 1) return NO;
    if ((offlineDotData2.x - offlineDotData0.x) * (offlineDotData2.x - offlineDotData1.x) > 0
        && ABS(offlineDotData2.x - offlineDotData0.x) > delta && ABS(offlineDotData2.x - offlineDotData1.x) > delta)
    {
        return NO;
    }
    if ((offlineDotData2.y - offlineDotData0.y) * (offlineDotData2.y - offlineDotData1.y) > 0
        && ABS(offlineDotData2.y - offlineDotData0.y) > delta && ABS(offlineDotData2.y - offlineDotData1.y) > delta)
    {
        return NO;
    }
    return YES;
}

- (void) offlineDotCheckerLast
{
    if ([self offlineDotCheckerForEnd]) {
        [self offlineDotAppend:&offlineDotData2];
        offlineDotData2.x = 0.0f;
        offlineDotData2.y = 0.0f;
    }
    else {
        NSLog(@"offlineDotChecker error : end");
    }
    offlineDotCheckState = OFFLINE_DOT_CHECK_NONE;
}

#if 0  //Offline sync : thread sync test code for future reference
- (BOOL) parseOfflinePenData_new:(NSData *)penData
{
    int dataPosition=0;
    unsigned long dataLength = [penData length];
    int headerSize = sizeof(OffLineDataFileHeaderStruct);
    dataLength -= headerSize;
    NSRange range = {dataLength, headerSize};
    OffLineDataFileHeaderStruct header;
    [penData getBytes:&header range:range];
    NSMutableArray *strokes = [[NSMutableArray alloc] init];
    NSDictionary __block *offlineStrokes = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:header.nNoteId], @"note_id",
                                            [NSNumber numberWithUnsignedInteger:header.nPageId], @"page_number",
                                            strokes, @"strokes", nil];
    unsigned char char1, char2;
    OffLineDataStrokeHeaderStruct strokeHeader;
    while (dataPosition < dataLength) {
        if ((dataLength - dataPosition) < (sizeof(OffLineDataStrokeHeaderStruct) + 2)) break;
        range.location = dataPosition++;
        range.length = 1;
        [penData getBytes:&char1 range:range];
        range.location = dataPosition++;
        [penData getBytes:&char2 range:range];
        if (char1 == 'L' && char2 == 'N') {
            range.location = dataPosition;
            range.length = sizeof(OffLineDataStrokeHeaderStruct);
            [penData getBytes:&strokeHeader range:range];
            dataPosition += sizeof(OffLineDataStrokeHeaderStruct);
            if ((dataLength - dataPosition) < (strokeHeader.nDotCount * sizeof(OffLineDataDotStruct))) {
                break;
            }
            [self parseOfflineDots:penData startAt:dataPosition withFileHeader:&header andStrokeHeader:&strokeHeader toArray:strokes];
            dataPosition += (strokeHeader.nDotCount * sizeof(OffLineDataDotStruct));
        }
    }
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"dispatch_async start");
        
        UInt32 noteIdBackup = 0;
        UInt32 pageIdBackup = 0;
        BOOL   hasPageBackup = NO;
        if (self.strokeHandler) {
            [self.strokeHandler notifyDataUpdating:YES];
        }
        NSNumber *value = (NSNumber *)[offlineStrokes objectForKey:@"note_id"] ;
        UInt32 noteId = (UInt32)[value unsignedIntegerValue];
        value = (NSNumber *)[offlineStrokes objectForKey:@"page_number"] ;
        UInt32 pageId = (UInt32)[value unsignedIntegerValue];
        if (self.writerManager.activeNoteBookId != noteId || self.writerManager.activePageNumber != pageId) {
            noteIdBackup = (UInt32)self.writerManager.activeNoteBookId;
            pageIdBackup = (UInt32)self.writerManager.activePageNumber;
            hasPageBackup = YES;
            NSLog(@"Offline New Id Data noteId %u, pageNumber %u", (unsigned int)noteId, (unsigned int)pageId);
            //Chage X, Y start cordinates.
            [self.paperInfo getPaperDotcodeStartForNotebook:(int)noteId startX:&_startX startY:&_startY];
            [self.writerManager activeNotebookIdDidChange:noteId withPageNumber:pageId];
        }
        NSArray *strokeSaved = (NSArray *)[offlineStrokes objectForKey:@"strokes"] ;
        for (int i = 0; i < [strokeSaved count]; i++) {
            NJStroke *a_stroke = strokeSaved[i];
            [self.activePageDocument.page insertStrokeByTimestamp:a_stroke];
        }
        [self.writerManager saveCurrentPageWithEventlog:YES andEvernote:YES andLastStrokeTime:[NSDate dateWithTimeIntervalSince1970:(self.offlineLastStrokeStartTime / 1000.0)]];
        if (hasPageBackup && noteIdBackup > 0) {
            [self.paperInfo getPaperDotcodeStartForNotebook:(int)noteIdBackup startX:&_startX startY:&_startY];
            [self.writerManager activeNotebookIdDidChange:noteIdBackup withPageNumber:pageIdBackup];
        }
        if (self.strokeHandler) {
            [self.strokeHandler notifyDataUpdating:NO];
        }
        NSLog(@"dispatch_semaphore_signal");
        dispatch_semaphore_signal(semaphore);
    });
    NSLog(@"dispatch_semaphore_wait start");
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    NSLog(@"dispatch_semaphore_wait end");
    return YES;
}
- (void) parseOfflineDots:(NSData *)penData startAt:(int)position withFileHeader:(OffLineDataFileHeaderStruct *)pFileHeader
          andStrokeHeader:(OffLineDataStrokeHeaderStruct *)pStrokeHeader toArray:(NSMutableArray *)strokes
{
    OffLineDataDotStruct dot;
    float pressure, x, y;
    NSRange range = {position, sizeof(OffLineDataDotStruct)};
    int dotCount = MIN(MAX_NODE_NUMBER, pStrokeHeader->nDotCount);
    float *point_x_buff = malloc(sizeof(float)* dotCount);
    float *point_y_buff = malloc(sizeof(float)* dotCount);
    float *point_p_buff = malloc(sizeof(float)* dotCount);
    int *time_diff_buff = malloc(sizeof(int)* dotCount);
    int point_index = 0;
    
    startTime = pStrokeHeader->nStrokeStartTime;
    //    NSLog(@"offline time %llu", startTime);
#ifdef HAS_LINE_COLOR
    UInt32 color = pStrokeHeader->nLineColor;
    if ((color & 0x00FFFFFF) != 0x00FFFFFF && (color & 0x00FFFFFF) != 0x00000000) {
        offlinePenColor = color | 0xFF000000; // set Alpha to 255
    }
    else
        offlinePenColor = 0;
#else
    offlinePenColor = 0;
#endif
    offlinePenColor = penColor; // 2015-01-28 add for maintaining color feature
    NSLog(@"offlinePenColor 0x%x", (unsigned int)offlinePenColor);
    float paperStartX, paperStartY;
    float paperSizeX, paperSizeY;
    [self.paperInfo getPaperDotcodeStartForNotebook:(int)pFileHeader->nNoteId startX:&paperStartX startY:&paperStartY];
    [self.paperInfo getPaperDotcodeRangeForNotebook:(int)pFileHeader->nNoteId Xmax:&paperSizeX Ymax:&paperSizeY];
    float normalizeScale = MAX(paperSizeX, paperSizeY);
    for (int i =0; i < pStrokeHeader->nDotCount; i++) {
        [penData getBytes:&dot range:range];
        x = (float)dot.x + (float)dot.fx * 0.01f;
        y = (float)dot.y + (float)dot.fy * 0.01f;
        pressure = [self processPressure:(float)dot.force];
        point_x_buff[point_index] = x - paperStartX;
        point_y_buff[point_index] = y - paperStartY;
        point_p_buff[point_index] = pressure;
        time_diff_buff[point_index] = dot.nTimeDelta;
        point_index++;
        //        NSLog(@"x %f, y %f, pressure %f, o_p %f", x, y, pressure, (float)dot.force);
        if(point_index >= MAX_NODE_NUMBER){
            NJStroke *stroke = [[NJStroke alloc] initWithRawDataX:point_x_buff Y:point_y_buff pressure:point_p_buff time_diff:time_diff_buff
                                                         penColor:offlinePenColor penThickness:_penThickness startTime:startTime size:point_index normalizer:normalizeScale];
            [strokes addObject:stroke];
            point_index = 0;
        }
        position += sizeof(OffLineDataDotStruct);
        range.location = position;
    }
    NJStroke *stroke = [[NJStroke alloc] initWithRawDataX:point_x_buff Y:point_y_buff pressure:point_p_buff time_diff:time_diff_buff
                                                 penColor:offlinePenColor penThickness:_penThickness startTime:startTime size:point_index normalizer:normalizeScale];
    [strokes addObject:stroke];
    free(point_x_buff);
    free(point_y_buff);
    free(point_p_buff);
    free(time_diff_buff);
}
#endif
- (void) notifyOfflineDataStatus:(OFFLINE_DATA_STATUS)status percent:(float)percent
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.offlineDataDelegate offlineDataReceiveStatus:status percent:percent];
    });
}
- (void) notifyOfflineDataFileListDidReceive
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.offlineDataDelegate offlineDataDidReceiveNoteList:_offlineFileList];
    });
}
- (void) parseRequestUpdateFile:(unsigned char *)data withLength:(int) length
{
    RequestUpdateFileStruct *request = (RequestUpdateFileStruct *)data;
    if (!_cancelFWUpdate) {
        [self sendUpdateFileDataAt:request->index];
    }
}
- (void) parseUpdateFileStatus:(unsigned char *)data withLength:(int) length
{
    UpdateFileStatusStruct *status = (UpdateFileStatusStruct *)data;
    
    if (status->status == 1) {
        [self notifyFWUpdateStatus:FW_UPDATE_DATA_RECEIVE_END percent:100];
    }else if(status->status == 0){
        [self notifyFWUpdateStatus:FW_UPDATE_DATA_RECEIVE_FAIL percent:0.0f];
    }else if(status->status == 3){
        NSLog(@"out of pen memory space");
    }
    
    NSLog(@"parseUpdateFileStatus status %d", status->status);
}

- (void) notifyFWUpdateStatus:(FW_UPDATE_DATA_STATUS)status percent:(float)percent
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.fwUpdateDelegate fwUpdateDataReceiveStatus:status percent:percent];
    });
}

- (void) parseReadyExchangeDataRequest:(unsigned char *)data withLength:(int) length
{
    ReadyExchangeDataRequestStruct *request = (ReadyExchangeDataRequestStruct *)data;
    if (request->ready == 0) {
        _isReadyExchangeSent = NO;
        NSLog(@"2AB5 was sent to App because a pen was turned off by itself.");
    }
    if (_isReadyExchangeSent) {
        NSLog(@"2AB4 was already sent to Pen. So, 2AB5 request is not proceeded again");
        return;
    }
    self.penExchangeDataReady = (request->ready == 1);
}

- (void) parsePenPasswordRequest:(unsigned char *)data withLength:(int) length
{
    PenPasswordRequestStruct *request = (PenPasswordRequestStruct *)data;

    if (_penCommIdDataReady && _penCommStrokeDataReady && _penCommUpDownDataReady && _penExchangeDataReady){
        dispatch_async(dispatch_get_main_queue(), ^{
        [self.penPasswordDelegate penPasswordRequest:request];
        });
    }
}

- (void) parsePenPasswordChangeResponse:(unsigned char *)data withLength:(int) length
{
    PenPasswordChangeResponseStruct *response = (PenPasswordChangeResponseStruct *)data;
    if (response->passwordState == 0x00) {
        NSLog(@"password change success");
        _commManager.hasPenPassword = YES;
    }else if(response->passwordState == 0x01){
        NSLog(@"password change fail");
    }
    BOOL PasswordChangeResult = (response->passwordState)? NO : YES;
    NSDictionary *info = @{@"result":[NSNumber numberWithBool:PasswordChangeResult]};
    dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:NJPenCommParserPenPasswordSutupSuccess object:nil userInfo:info];
    });
}

- (void) parseFWVersion:(unsigned char *)data withLength:(int) length
{
    self.fwVersion = [[NSString alloc] initWithBytes:data length:length encoding:NSUTF8StringEncoding];
    
}

#pragma mark - Send data
- (void)setPenState
{
    NSTimeInterval timeInMiliseconds = [[NSDate date] timeIntervalSince1970]*1000;
    NSTimeZone *localTimeZone = [NSTimeZone localTimeZone];
    NSInteger millisecondsFromGMT = 1000 * [localTimeZone secondsFromGMT] + [localTimeZone daylightSavingTimeOffset]*1000;
    SetPenStateStruct setPenStateData;
    setPenStateData.timeTick=(UInt64)timeInMiliseconds;
    setPenStateData.timezoneOffset=(int32_t)millisecondsFromGMT;
    NSLog(@"set timezoneOffset %d, timeTick %llu", setPenStateData.timezoneOffset, setPenStateData.timeTick);
    if (self.penStatus) {
        UInt32 color = self.penStatus->colorState;
        setPenStateData.colorState = (color & 0x00FFFFFF) | (0x01000000);
        setPenStateData.usePenTipOnOff = self.penStatus->usePenTipOnOff;
        setPenStateData.useAccelerator = self.penStatus->useAccelerator;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = self.penStatus->beepOnOff;
        setPenStateData.autoPwrOnTime = self.penStatus->autoPwrOffTime;
        setPenStateData.penPressure = self.penStatus->penPressure;
        
    } else {

        UIColor *color = nil;
        if (color != nil) {
            CGFloat r, g, b, a;
            [color getRed:&r green:&g blue:&b alpha:&a];
            UInt32 ir=(UInt32)(r*255);UInt32 ig=(UInt32)(g*255);
            UInt32 ib=(UInt32)(b*255);UInt32 ia=(UInt32)(a*255);
            setPenStateData.colorState=(ia<<24)|(ir<<16)|(ig<<8)|(ib);
        }
        else
            setPenStateData.colorState = 0;
        setPenStateData.usePenTipOnOff = 1;
        setPenStateData.useAccelerator = 1;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = 1;
        
    }
    NSData *data = [NSData dataWithBytes:&setPenStateData length:sizeof(setPenStateData)];
    [_commManager writeSetPenState:data];
}

- (void)setPenStateWithTimeTick
{
    NSTimeInterval timeInMiliseconds = [[NSDate date] timeIntervalSince1970]*1000;
    NSTimeZone *localTimeZone = [NSTimeZone localTimeZone];
    NSInteger millisecondsFromGMT = 1000 * [localTimeZone secondsFromGMT] + [localTimeZone daylightSavingTimeOffset]*1000;
    SetPenStateStruct setPenStateData;
    setPenStateData.timeTick=(UInt64)timeInMiliseconds;
    setPenStateData.timezoneOffset=(int32_t)millisecondsFromGMT;
    NSLog(@"set timezoneOffset %d, timeTick %llu", setPenStateData.timezoneOffset, setPenStateData.timeTick);
    
    if (self.penStatus) {
        UInt32 color = self.penStatus->colorState;
        setPenStateData.colorState = (color & 0x00FFFFFF) | (0x01000000);
        setPenStateData.usePenTipOnOff = self.penStatus->usePenTipOnOff;
        setPenStateData.useAccelerator = self.penStatus->useAccelerator;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = self.penStatus->beepOnOff;
        setPenStateData.autoPwrOnTime = self.penStatus->autoPwrOffTime;
        setPenStateData.penPressure = self.penStatus->penPressure;
    
        NSData *data = [NSData dataWithBytes:&setPenStateData length:sizeof(setPenStateData)];
        [_commManager writeSetPenState:data];
    }else{
        NSLog(@"setPenStateWithTimeTick, self.penStatus : nil");
    }
}

- (void)setPenStateWithPenPressure:(UInt16)penPressure
{
    NSTimeInterval timeInMiliseconds = [[NSDate date] timeIntervalSince1970]*1000;
    NSTimeZone *localTimeZone = [NSTimeZone localTimeZone];
    NSInteger millisecondsFromGMT = 1000 * [localTimeZone secondsFromGMT] + [localTimeZone daylightSavingTimeOffset]*1000;
    SetPenStateStruct setPenStateData;
    setPenStateData.timeTick=(UInt64)timeInMiliseconds;
    setPenStateData.timezoneOffset=(int32_t)millisecondsFromGMT;
    NSLog(@"set timezoneOffset %d, timeTick %llu", setPenStateData.timezoneOffset, setPenStateData.timeTick);
    
    if (self.penStatus) {
        UInt32 color = self.penStatus->colorState;
        setPenStateData.colorState = (color & 0x00FFFFFF) | (0x01000000);
        setPenStateData.usePenTipOnOff = self.penStatus->usePenTipOnOff;
        setPenStateData.useAccelerator = self.penStatus->useAccelerator;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = self.penStatus->beepOnOff;
        setPenStateData.autoPwrOnTime = self.penStatus->autoPwrOffTime;
    }
    setPenStateData.penPressure = penPressure;
    
    NSData *data = [NSData dataWithBytes:&setPenStateData length:sizeof(setPenStateData)];
    [_commManager writeSetPenState:data];
}

- (void)setPenStateWithAutoPwrOffTime:(UInt16)autoPwrOff
{
    NSTimeInterval timeInMiliseconds = [[NSDate date] timeIntervalSince1970]*1000;
    NSTimeZone *localTimeZone = [NSTimeZone localTimeZone];
    NSInteger millisecondsFromGMT = 1000 * [localTimeZone secondsFromGMT] + [localTimeZone daylightSavingTimeOffset]*1000;
    SetPenStateStruct setPenStateData;
    setPenStateData.timeTick=(UInt64)timeInMiliseconds;
    setPenStateData.timezoneOffset=(int32_t)millisecondsFromGMT;
    NSLog(@"set timezoneOffset %d, timeTick %llu", setPenStateData.timezoneOffset, setPenStateData.timeTick);
    
    if (self.penStatus) {
        UInt32 color = self.penStatus->colorState;
        setPenStateData.colorState = (color & 0x00FFFFFF) | (0x01000000);
        setPenStateData.usePenTipOnOff = self.penStatus->usePenTipOnOff;
        setPenStateData.useAccelerator = self.penStatus->useAccelerator;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = self.penStatus->beepOnOff;
        setPenStateData.penPressure = self.penStatus->penPressure;
    }
    setPenStateData.autoPwrOnTime = autoPwrOff;
    
    NSData *data = [NSData dataWithBytes:&setPenStateData length:sizeof(setPenStateData)];
    [_commManager writeSetPenState:data];
}

- (void)setPenStateAutoPower:(unsigned char)autoPower Sound:(unsigned char)sound
{
    NSTimeInterval timeInMiliseconds = [[NSDate date] timeIntervalSince1970]*1000;
    NSTimeZone *localTimeZone = [NSTimeZone localTimeZone];
    NSInteger millisecondsFromGMT = 1000 * [localTimeZone secondsFromGMT] + [localTimeZone daylightSavingTimeOffset]*1000;
    SetPenStateStruct setPenStateData;
    setPenStateData.timeTick=(UInt64)timeInMiliseconds;
    setPenStateData.timezoneOffset=(int32_t)millisecondsFromGMT;
    NSLog(@"set timezoneOffset %d, timeTick %llu", setPenStateData.timezoneOffset, setPenStateData.timeTick);
    
    if (self.penStatus) {
        UInt32 color = self.penStatus->colorState;
        setPenStateData.colorState = (color & 0x00FFFFFF) | (0x01000000);
        setPenStateData.usePenTipOnOff = autoPower;
        setPenStateData.useAccelerator = self.penStatus->useAccelerator;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = sound;
        setPenStateData.autoPwrOnTime = self.penStatus->autoPwrOffTime;
        setPenStateData.penPressure = self.penStatus->penPressure;
        
    }else{
        
        UIColor *color = nil;
        if (color != nil) {
            CGFloat r, g, b, a;
            [color getRed:&r green:&g blue:&b alpha:&a];
            UInt32 ir=(UInt32)(r*255);UInt32 ig=(UInt32)(g*255);
            UInt32 ib=(UInt32)(b*255);UInt32 ia=(UInt32)(a*255);
            setPenStateData.colorState=(ia<<24)|(ir<<16)|(ig<<8)|(ib);
        }
        else
            setPenStateData.colorState = 0;
        setPenStateData.usePenTipOnOff = autoPower;
        setPenStateData.useAccelerator = 1;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = sound;
        setPenStateData.autoPwrOnTime = 15;
        setPenStateData.penPressure = 20;
    }
    
    NSData *data = [NSData dataWithBytes:&setPenStateData length:sizeof(setPenStateData)];
    [_commManager writeSetPenState:data];

}

- (void)setPenStateWithRGB:(UInt32)color
{
    NSTimeInterval timeInMiliseconds = [[NSDate date] timeIntervalSince1970]*1000;
    NSTimeZone *localTimeZone = [NSTimeZone localTimeZone];
    NSInteger millisecondsFromGMT = 1000 * [localTimeZone secondsFromGMT] + [localTimeZone daylightSavingTimeOffset]*1000;
    SetPenStateStruct setPenStateData;
    setPenStateData.timeTick=(UInt64)timeInMiliseconds;
    setPenStateData.timezoneOffset=(int32_t)millisecondsFromGMT;
    NSLog(@"set timezoneOffset %d, timeTick %llu", setPenStateData.timezoneOffset, setPenStateData.timeTick);
    
    if (self.penStatus) {
        NSLog(@"setPenStateWithRGB color 0x%x", (unsigned int)color);
        setPenStateData.colorState = (color & 0x00FFFFFF) | (0x01000000);
        setPenStateData.usePenTipOnOff = self.penStatus->usePenTipOnOff;
        setPenStateData.useAccelerator = self.penStatus->useAccelerator;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = self.penStatus->beepOnOff;
        setPenStateData.autoPwrOnTime = self.penStatus->autoPwrOffTime;
        setPenStateData.penPressure = self.penStatus->penPressure;
    }else{
        NSLog(@"setPenStateWithRGB color 0x%x", (unsigned int)color);
        setPenStateData.colorState = (color & 0x00FFFFFF) | (0x01000000);
        setPenStateData.usePenTipOnOff = 1;
        setPenStateData.useAccelerator = 1;
        setPenStateData.useHover = 2;
        setPenStateData.beepOnOff = 1;
        setPenStateData.autoPwrOnTime = 15;
        setPenStateData.penPressure = 20;
    }
    
    NSData *data = [NSData dataWithBytes:&setPenStateData length:sizeof(setPenStateData)];
    [_commManager writeSetPenState:data];

}

- (void)setPenStateWithHover:(UInt16)useHover
{
    NSTimeInterval timeInMiliseconds = [[NSDate date] timeIntervalSince1970]*1000;
    NSTimeZone *localTimeZone = [NSTimeZone localTimeZone];
    NSInteger millisecondsFromGMT = 1000 * [localTimeZone secondsFromGMT] + [localTimeZone daylightSavingTimeOffset]*1000;
    SetPenStateStruct setPenStateData;
    setPenStateData.timeTick=(UInt64)timeInMiliseconds;
    setPenStateData.timezoneOffset=(int32_t)millisecondsFromGMT;
    NSLog(@"set timezoneOffset %d, timeTick %llu", setPenStateData.timezoneOffset, setPenStateData.timeTick);
    
    if (self.penStatus) {
        UInt32 color = self.penStatus->colorState;
        setPenStateData.colorState = (color & 0x00FFFFFF) | (0x01000000);
        setPenStateData.usePenTipOnOff = self.penStatus->usePenTipOnOff;
        setPenStateData.useAccelerator = self.penStatus->useAccelerator;
        setPenStateData.beepOnOff = self.penStatus->beepOnOff;
        setPenStateData.autoPwrOnTime = self.penStatus->autoPwrOffTime;
        setPenStateData.penPressure = self.penStatus->penPressure;
    }
    
    setPenStateData.useHover = useHover;
    
    NSData *data = [NSData dataWithBytes:&setPenStateData length:sizeof(setPenStateData)];
    [_commManager writeSetPenState:data];
}

- (UIColor *)convertRGBToUIColor:(UInt32)penTipColor
{
    UInt8 red = (UInt8)(penTipColor >> 16) & 0xFF;
    UInt8 green = (UInt8)(penTipColor >> 8) & 0xFF;
    UInt8 blue = (UInt8)penTipColor & 0xFF;
    
    UIColor *color = [UIColor colorWithRed:red/255 green:green/255 blue:blue/255 alpha:1.0];
    
    return color;
}

- (void)setNoteIdList
{
    
    if (self.canvasStartDelegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.canvasStartDelegate setPenCommNoteIdList];
            
            
        });
    }
}

- (void)setAllNoteIdList
{
    SetNoteIdListStruct noteIdList;
    NSData *data;

//NISDK -
    noteIdList.type = 3;
    int index = 0;

    noteIdList.count = index;
    data = [NSData dataWithBytes:&noteIdList length:sizeof(noteIdList)];
    [self.commManager writeNoteIdList:data];
}

- (void)setNoteIdListFromPList
{
    
    SetNoteIdListStruct noteIdList;
    NSData *data;
    unsigned char section_id;
    UInt32 owner_id;
    NSArray *noteIds;
    NJNotebookPaperInfo *noteInfo = [NJNotebookPaperInfo sharedInstance];
    NSArray *notesSupported = [noteInfo notesSupported];
    noteIdList.type = 1; // Note Id
    for (NSDictionary *note in notesSupported) {
        section_id = [(NSNumber *)[note objectForKey:@"section"] unsignedCharValue];
        owner_id = (UInt32)[(NSNumber *)[note objectForKey:@"owner"] unsignedIntegerValue];
        noteIds = (NSArray *)[note objectForKey:@"noteIds"];
        noteIdList.params[0] = (section_id << 24) | owner_id;
        int noteIdCount = (int)[noteIds count];
        int index = 0;
        for (int i = 0; i < noteIdCount; i++) {
            noteIdList.params[index+1] = (UInt32)[(NSNumber *)[noteIds objectAtIndex:i] unsignedIntegerValue];
            NSLog(@"note id at %d : %d", i, (unsigned int)noteIdList.params[index+1]);
            index++;
            if (index == (NOTE_ID_LIST_SIZE-1)) {
                noteIdList.count = index;
                data = [NSData dataWithBytes:&noteIdList length:sizeof(noteIdList)];
                [_commManager writeNoteIdList:data];
                index = 0;
            }
        }
        if (index != 0) {
            noteIdList.count = index;
            data = [NSData dataWithBytes:&noteIdList length:sizeof(noteIdList)];
            [_commManager writeNoteIdList:data];
        }
    }
    //Season note
    noteIdList.type = 1; // Note Id
    section_id = 0;
    owner_id = 19;
    noteIdList.params[0] = (section_id << 24) | owner_id;;
    noteIdList.params[1] = 1;
    noteIdList.count = 1;
    data = [NSData dataWithBytes:&noteIdList length:sizeof(noteIdList)];
    [_commManager writeNoteIdList:data];

    // To get Seal ID
    noteIdList.type = 2;
    UInt32 noteId;
    for (NSDictionary *note in notesSupported) {
        section_id = SEAL_SECTION_ID; // Fixed for seal
        noteIds = (NSArray *)[note objectForKey:@"noteIds"];
        int noteIdCount = (int)[noteIds count];
        int index = 0;
        for (int i = 0; i < noteIdCount; i++) {
            noteId = (UInt32)[(NSNumber *)[noteIds objectAtIndex:i] unsignedIntegerValue];
            noteIdList.params[index] = (section_id << 24) | noteId;
            index++;
            if (index == (NOTE_ID_LIST_SIZE)) {
                noteIdList.count = index;
                NSData *data = [NSData dataWithBytes:&noteIdList length:sizeof(noteIdList)];
                [_commManager writeNoteIdList:data];
                index = 0;
            }
        }
        if (index != 0) {
            noteIdList.count = index;
            data = [NSData dataWithBytes:&noteIdList length:sizeof(noteIdList)];
            [_commManager writeNoteIdList:data];
        }
    }
    
}

- (void)setNoteIdListSectionOwnerFromPList
{
    SetNoteIdListStruct noteIdList;
    NSData *data;
    unsigned char section_id;
    UInt32 owner_id;
    NJNotebookPaperInfo *noteInfo = [NJNotebookPaperInfo sharedInstance];
    NSArray *notesSupported = [noteInfo notesSupported];

    noteIdList.type = 2;
    int index = 0;
    
    for (NSDictionary *note in notesSupported) {
        section_id = [(NSNumber *)[note objectForKey:@"section"] unsignedCharValue];
        owner_id = (UInt32)[(NSNumber *)[note objectForKey:@"owner"] unsignedIntegerValue];
        noteIdList.params[index++] = (section_id << 24) | owner_id;
    }
    noteIdList.count = index;
    data = [NSData dataWithBytes:&noteIdList length:sizeof(noteIdList)];
    [_commManager writeNoteIdList:data];
}


- (void) changePasswordFrom:(NSString *)curNumber To:(NSString *)pinNumber
{
    PenPasswordChangeRequestStruct request;
    
    NSData *stringData = [curNumber dataUsingEncoding:NSUTF8StringEncoding];
    memcpy(request.prevPassword, [stringData bytes], sizeof(stringData));
    
    NSData *newData = [pinNumber dataUsingEncoding:NSUTF8StringEncoding];
    memcpy(request.newPassword, [newData bytes], sizeof(newData));
    
    for(int i = 0 ; i < 12 ; i++)
    {
        request.prevPassword[i+4] = (unsigned char)NULL;
        request.newPassword[i+4] = (unsigned char)NULL;
    }
    
    NSData *data = [NSData dataWithBytes:&request length:sizeof(PenPasswordChangeRequestStruct)];
    [_commManager writeSetPasswordData:data];
    
}

- (void) setBTComparePassword:(NSString *)pinNumber
{
    PenPasswordResponseStruct response;
    NSData *stringData = [pinNumber dataUsingEncoding:NSUTF8StringEncoding];
    memcpy(response.password, [stringData bytes], sizeof(stringData));    
    for(int i = 0 ; i < 12 ; i++)
    {
        response.password[i+4] = (unsigned char)NULL;
    }
    NSData *data = [NSData dataWithBytes:&response length:sizeof(PenPasswordResponseStruct)];
    [_commManager writePenPasswordResponseData:data];
}

- (void) writeReadyExchangeData:(BOOL)ready
{
    ReadyExchangeDataStruct request;
    request.ready = ready ? 1 : 0;
    NSData *data = [NSData dataWithBytes:&request length:sizeof(ReadyExchangeDataStruct)];
    [_commManager writeReadyExchangeData:data];
    if (ready == YES) {
        //flag should be YES when 2AB4 (response App ready)
        _isReadyExchangeSent = YES;
        NSLog(@"isReadyExchangeSent set into YES because it is sent to Pen");
    } else if (ready == NO){
        [self resetDataReady];
        NSLog(@"isReadyExchangeSent set into NO because of disconnected signal");
    }

}

- (void) resetDataReady
{
    //reset isReadyExchangeSent flag when disconnected
    _isReadyExchangeSent = NO;
    _penExchangeDataReady = NO;
    _penCommUpDownDataReady = NO;
    _penCommIdDataReady = NO;
    _penCommStrokeDataReady = NO;
    
    NSLog(@"resetDataReady is performed because of disconnected signal");
}

- (BOOL) requestOfflineFileList
{
    if (_offlineFileProcessing) {
        return NO;
    }
    _offlineFileList = [[NSMutableDictionary alloc] init];
    _offlineFileParsedList = [[NSMutableDictionary alloc] init];
    RequestOfflineFileListStruct request;
    request.status = 0x00;
    NSData *data = [NSData dataWithBytes:&request length:sizeof(request)];
    [_commManager writeRequestOfflineFileList:data];
    return YES;
}
- (BOOL) requestDelOfflineFile:(UInt32)sectionOwnerId
{
    RequestDelOfflineFileStruct request;
    request.sectionOwnerId = sectionOwnerId;
    NSData *data = [NSData dataWithBytes:&request length:sizeof(request)];
    [_commManager writeRequestDelOfflineFile:data ];
    return YES;
}
- (BOOL) requestOfflineDataWithOwnerId:(UInt32)ownerId noteId:(UInt32)noteId
{
    NSArray *noteList = [_offlineFileList objectForKey:[NSNumber numberWithUnsignedInt:ownerId]];
    if (noteList == nil) return NO;
    if ([noteList indexOfObject:[NSNumber numberWithUnsignedInt:noteId]] == NSNotFound) return NO;
    
    RequestOfflineFileStruct request;
    request.sectionOwnerId = ownerId;
    request.noteCount = 1;
    request.noteId[0] = noteId;
    NSData *data = [NSData dataWithBytes:&request length:sizeof(request)];
    [_commManager writeRequestOfflineFile:data];
    return YES;
}
- (void) offlineFileAckForType:(unsigned char)type index:(unsigned char)index
{
    OfflineFileAckStruct fileAck;
    fileAck.type = type;
    fileAck.index = index;
    NSData *data = [NSData dataWithBytes:&fileAck length:sizeof(fileAck)];
    [_commManager writeOfflineFileAck:data];
}
- (void) sendUpdateFileInfoAtUrl:(NSURL *)fileUrl
{
    [self readUpdateDataFromUrl:fileUrl];
    UpdateFileInfoStruct fileInfo;
    char *fileName = "\\Update.zip";
    memset(fileInfo.filePath, 0, sizeof(fileInfo.filePath));
    memcpy(fileInfo.filePath, fileName, strlen(fileName));
    fileInfo.fileSize = (UInt32)[self.updateFileData length];
    float size = (float)fileInfo.fileSize / UPDATE_DATA_PACKET_SIZE;
    fileInfo.packetCount = ceilf(size);
    fileInfo.packetSize = UPDATE_DATA_PACKET_SIZE;
    NSData *data = [NSData dataWithBytes:&fileInfo length:sizeof(fileInfo)];
    [_commManager writeUpdateFileInfo:data];
}
- (void) sendUpdateFileDataAt:(UInt16)index
{
    NSLog(@"sendUpdateFileDataAt %d", index);
    UpdateFileDataStruct updateData;
    updateData.index = index;
    NSRange range;
    range.location = index*UPDATE_DATA_PACKET_SIZE;
    if ((range.location + UPDATE_DATA_PACKET_SIZE) > self.updateFileData.length ){
        range.length = self.updateFileData.length - range.location;
    }
    else {
        range.length = UPDATE_DATA_PACKET_SIZE;
    }
    if (range.length > 0) {
        [self.updateFileData getBytes:updateData.fileData range:range];
        NSData *data = [NSData dataWithBytes:&updateData length:(sizeof(updateData.index) + range.length)];
        [_commManager writeUpdateFileData:data];
    }
    float progress_percent = (((float)index)/((float)self.packetCount))*100.0f;
    [self notifyFWUpdateStatus:FW_UPDATE_DATA_RECEIVE_PROGRESSING percent:progress_percent];

}
- (void) readUpdateDataFromUrl:(NSURL *)fileUrl
{
    self.updateFileData = [NSData dataWithContentsOfURL:fileUrl];
    self.updateFilePosition = 0;
}

- (void) sendUpdateFileInfoAtUrlToPen:(NSURL *)fileUrl
{
    self.cancelFWUpdate = NO;
    
    [self readUpdateDataFromUrl:fileUrl];
    UpdateFileInfoStruct fileInfo;
    //char *fileName = "\\Update.zip";
    NSString *fileNameString = [NSString stringWithFormat:@"\\%@",[[fileUrl path] lastPathComponent]];
    const char *fileName = [fileNameString UTF8String];
    
    memset(fileInfo.filePath, 0, sizeof(fileInfo.filePath));
    memcpy(fileInfo.filePath, fileName, strlen(fileName));
    fileInfo.fileSize = (UInt32)[self.updateFileData length];
    float size = (float)fileInfo.fileSize / UPDATE_DATA_PACKET_SIZE;
    fileInfo.packetCount = ceilf(size);
    fileInfo.packetSize = UPDATE_DATA_PACKET_SIZE;
    self.packetCount = fileInfo.packetCount;
    NSData *data = [NSData dataWithBytes:&fileInfo length:sizeof(fileInfo)];
    [_commManager writeUpdateFileInfo:data];
    [self notifyFWUpdateStatus:FW_UPDATE_DATA_RECEIVE_START percent:0.0f];    
    
}

#pragma mark - Page data
- (void)pageOpened:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        for (int i=0; i < [self.strokeArray count]; i++) {
            NJStroke *stroke = (NJStroke *)[self.strokeArray objectAtIndex:i];
            [stroke normalize:self.activePageDocument.page.inputScale];
            [self.activePageDocument.page addStrokes:stroke];
        }
        if([_strokeArray count] > 0) {
            if (self.strokeHandler != nil) {
                //To draw on canvas
                NSNumber *timeNumber = [NSNumber numberWithLongLong:0];
                NSString *status = @"up";
                NSDictionary *strokeData = [NSDictionary dictionaryWithObjectsAndKeys:
                                            @"updown", @"type",
                                            timeNumber, @"time",
                                            status, @"status",
                                            nil];
                [self.strokeHandler processStroke:strokeData];
            }

            [[NSNotificationCenter defaultCenter]
             postNotificationName:NJPageChangedNotification
             object:self.activePageDocument.page userInfo:nil];
            [self.strokeArray removeAllObjects];
        }
    });
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NJNoteBookPageDocumentOpenedNotification object:self.writerManager];
}
- (float) getDotScale
{
    if(_mDotToScreenScale == 0)
        return 1;
    
    return _mDotToScreenScale;
}

- (void) calcDotScaleScreenW:(float)screenW screenH:(float)screenH
{
    float dotWidth = 600;
    float dotHeight = 900;
    
    float widthScale = screenW / dotWidth;
    float heightScale = screenH / dotHeight;
    
    float dotToScreenScale = widthScale > heightScale ? heightScale : widthScale;
    _mDotToScreenScale = dotToScreenScale;
}

- (float) dotcode2PixelX:(int) dot Y:(int)fdot
{
    float doScale = [self getDotScale];
    return (dot * doScale + (float)(fdot * doScale * 0.01f));
}

- (void) dotChecker:(dotDataStruct *)aDot
{
    if (dotCheckState == DOT_CHECK_NORMAL) {
        if ([self dotCheckerForMiddle:aDot]) {
            [self dotAppend:&dotData2];
            dotData0 = dotData1;
            dotData1 = dotData2;
        }
        else {
            NSLog(@"dotChecker error : middle");
        }
        dotData2 = *aDot;
    }
    else if(dotCheckState == DOT_CHECK_FIRST) {
        dotData0 = *aDot;
        dotData1 = *aDot;
        dotData2 = *aDot;
        dotCheckState = DOT_CHECK_SECOND;
    }
    else if(dotCheckState == DOT_CHECK_SECOND) {
        dotData2 = *aDot;
        dotCheckState = DOT_CHECK_THIRD;
    }
    else if(dotCheckState == DOT_CHECK_THIRD) {
        if ([self dotCheckerForStart:aDot]) {
            [self dotAppend:&dotData1];
            if ([self dotCheckerForMiddle:aDot]) {
                [self dotAppend:&dotData2];
                dotData0 = dotData1;
                dotData1 = dotData2;
            }
            else {
                NSLog(@"dotChecker error : middle2");
            }
        }
        else {
            dotData1 = dotData2;
            NSLog(@"dotChecker error : start");
        }
        dotData2 = *aDot;
        dotCheckState = DOT_CHECK_NORMAL;
    }
}
- (void) dotCheckerLast
{
    if ([self dotCheckerForEnd]) {
        [self dotAppend:&dotData2];
        dotData2.x = 0.0f;
        dotData2.y = 0.0f;
    }
    else {
        NSLog(@"dotChecker error : end");
    }
}
- (BOOL) dotCheckerForStart:(dotDataStruct *)aDot
{
    static const float delta = 2.0f;
    if (dotData1.x > 150 || dotData1.x < 1) return NO;
    if (dotData1.y > 150 || dotData1.y < 1) return NO;
    if ((aDot->x - dotData1.x) * (dotData2.x - dotData1.x) > 0 && ABS(aDot->x - dotData1.x) > delta && ABS(dotData1.x - dotData2.x) > delta)
    {
        return NO;
    }
    if ((aDot->y - dotData1.y) * (dotData2.y - dotData1.y) > 0 && ABS(aDot->y - dotData1.y) > delta && ABS(dotData1.y - dotData2.y) > delta)
    {
        return NO;
    }
    return YES;
}
- (BOOL) dotCheckerForMiddle:(dotDataStruct *)aDot
{
    static const float delta = 2.0f;
    if (dotData2.x > 150 || dotData2.x < 1) return NO;
    if (dotData2.y > 150 || dotData2.y < 1) return NO;
    if ((dotData1.x - dotData2.x) * (aDot->x - dotData2.x) > 0 && ABS(dotData1.x - dotData2.x) > delta && ABS(aDot->x - dotData2.x) > delta)
    {
        return NO;
    }
    if ((dotData1.y - dotData2.y) * (aDot->y - dotData2.y) > 0 && ABS(dotData1.y - dotData2.y) > delta && ABS(aDot->y - dotData2.y) > delta)
    {
        return NO;
    }

    return YES;
}
- (BOOL) dotCheckerForEnd
{
    static const float delta = 2.0f;
    if (dotData2.x > 150 || dotData2.x < 1) return NO;
    if (dotData2.y > 150 || dotData2.y < 1) return NO;
    if ((dotData2.x - dotData0.x) * (dotData2.x - dotData1.x) > 0 && ABS(dotData2.x - dotData0.x) > delta && ABS(dotData2.x - dotData1.x) > delta)
    {
        return NO;
    }
    if ((dotData2.y - dotData0.y) * (dotData2.y - dotData1.y) > 0 && ABS(dotData2.y - dotData0.y) > delta && ABS(dotData2.y - dotData1.y) > delta)
    {
        return NO;
    }
    return YES;
}
- (void) dotAppend:(dotDataStruct *)aDot
{
    float pressure = [self processPressure:aDot->pressure];
    point_x[point_count] = aDot->x;
    point_y[point_count] = aDot->y;
    point_p[point_count] = pressure;
    time_diff[point_count] = aDot->diff_time;
    point_count++;
    node_count++;
//    NSLog(@"time %d, x %f, y %f, pressure %f", aDot->diff_time, aDot->x, aDot->y, pressure);
    if(point_count >= MAX_NODE_NUMBER){
        // call _penDown setter
        self.penDown = NO;
        self.penDown = YES;
    }
    NJNode *node = [[NJNode alloc] initWithPointX:aDot->x poinY:aDot->y pressure:pressure];
    //requested
    node.timeDiff = aDot->diff_time;
    NSDictionary *new_node = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"stroke", @"type",
                              node, @"node",
                              nil];
    if (self.strokeHandler != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.strokeHandler processStroke:new_node];
        });
    }
}
@end
