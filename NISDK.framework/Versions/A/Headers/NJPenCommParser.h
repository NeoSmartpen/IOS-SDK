//
//  NJPenCommParser.h
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "NeoPenService.h"

#define SEAL_SECTION_ID 4


@protocol NJPenCommParserStrokeHandler <NSObject>
- (void) processStroke:(NSDictionary *)stroke;
- (void) activeNoteId:(int)noteId pageNum:(int)pageNumber sectionId:(int)section AndOwnderId:(int)owner;
- (void) notifyPageChanging;
- (void) didColorChangedFromPen:(UIColor *)color;
@optional
// This is for offline data. 
- (void) notifyDataUpdating:(BOOL)updating;
- (UInt32)setPenColor;

@end

@protocol NJPenCommParserPasswordDelegate
- (void) performComparePassword:(PenPasswordRequestStruct *)request;
@end

@class NJPenCommManager;
@class NJPageDocument;
@protocol NJOfflineDataDelegate;
@protocol NJPenCalibrationDelegate;
@protocol NJFWUpdateDelegate;
@protocol NJPenStatusDelegate;
@protocol NJPenPasswordDelegate;

@interface NJPenCommParser : NSObject
@property (weak, nonatomic) id <NJPenCommParserStrokeHandler> strokeHandler;
@property (nonatomic) BOOL shouldSendPageChangeNotification;
@property (weak, nonatomic) id <NJPenCommParserPasswordDelegate> passwordDelegate;


@property (strong, nonatomic) NSMutableDictionary *offlineFileList;
@property (nonatomic) unsigned char batteryLevel;
@property (nonatomic) unsigned char memoryUsed;
@property (nonatomic) NSUInteger penThickness;
@property (nonatomic, strong) NSString *fwVersion;
// Pen data related BTLE characteristics.
@property (nonatomic) BOOL penCommIdDataReady;
@property (nonatomic) BOOL penCommUpDownDataReady;
@property (nonatomic) BOOL penCommStrokeDataReady;
@property (nonatomic) BOOL penExchangeDataReady;
@property (nonatomic) BOOL penPasswordResponse;
@property (nonatomic) BOOL cancelFWUpdate;
@property (strong, nonatomic) NJPageDocument *activePageDocument;
@property (nonatomic) float startX;
@property (nonatomic) float startY;

- (id) initWithPenCommManager:(NJPenCommManager *)manager;
- (void) parsePenStrokeData:(unsigned char *)data withLength:(int) length;
- (void) parsePenUpDowneData:(unsigned char *)data withLength:(int) length;
- (void) parsePenNewIdData:(unsigned char *)data withLength:(int) length;
- (void) parsePenStatusData:(unsigned char *)data withLength:(int) length;
- (void) parseOfflineFileList:(unsigned char *)data withLength:(int) length;
- (void) parseOfflineFileListInfo:(unsigned char *)data withLength:(int) length;
- (void) parseOfflineFileInfoData:(unsigned char *)data withLength:(int) length;
- (void) parseOfflineFileData:(unsigned char *)data withLength:(int) length;
- (void) parseOfflineFileStatus:(unsigned char *)data withLength:(int) length;
- (void) parseRequestUpdateFile:(unsigned char *)data withLength:(int) length;
- (void) parseUpdateFileStatus:(unsigned char *)data withLength:(int) length;
- (void) parseFWVersion:(unsigned char *)data withLength:(int) length;
- (void) parseReadyExchangeDataRequest:(unsigned char *)data withLength:(int) length;
- (void) parsePenPasswordRequest:(unsigned char *)data withLength:(int) length;
- (void) parsePenPasswordChangeResponse:(unsigned char *)data withLength:(int) length;
- (BOOL) requestOfflineFileList;
- (void) setPenState;
- (void)setPenStateWithPenPressure:(UInt16)penPressure;
- (void)setPenStateWithAutoPwrOffTime:(UInt16)autoPwrOff;
- (void)setPenStateAutoPower:(unsigned char)autoPower Sound:(unsigned char)sound;
- (void)setPenStateWithRGB:(UInt32)color;
- (void)setPenStateWithTimeTick;
- (void) setNoteIdList;
- (void) changePasswordFrom:(NSString *)curNumber To:(NSString *)pinNumber;
- (void) setBTComparePassword:(NSString *)pinNumber;
- (void) writeReadyExchangeData:(BOOL)ready;
- (BOOL) requestOfflineDataWithOwnerId:(UInt32)onwerId noteId:(UInt32)noteId;
- (void) offlineFileAckForType:(unsigned char)type index:(unsigned char)index;

- (void) calcDotScaleScreenW:(float)screenW screenH:(float)screenH;
- (BOOL) requestNextOfflineNote;
- (void) setOfflineDataDelegate:(id<NJOfflineDataDelegate>)offlineDataDelegate;
- (void) setPenCalibrationDelegate:(id<NJPenCalibrationDelegate>)penCalibrationDelegate;
- (void) setFWUpdateDelegate:(id<NJFWUpdateDelegate>)fwUpdateDelegate;
- (void) setPenStatusDelegate:(id<NJPenStatusDelegate>)penStatusDelegate;
- (void) setPenPasswordDelegate:(id<NJPenStatusDelegate>)penPasswordDelegate;
- (void) sendUpdateFileInfoAtUrlToPen:(NSURL *)fileUrl;
- (float) processPressure:(float)pressure;

@end
