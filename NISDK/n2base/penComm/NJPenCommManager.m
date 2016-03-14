//
//  NJPenCommManager.m
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJPenCommManager.h"
#import "NeoPenService.h"
#import "NJCommon.h"

#define kPenCommMan_Pen_Register @"penRegister"
#define kPenCommMan_Pen_Reg_UUID @"regUuid"
#define kPenCommMan_Pen_Name     @"penName"

extern NSString *NJPenCommManagerWriteIdleNotification;

NSString * NJPenCommManagerPageChangedNotification = @"NJPenCommManagerPageChangedNotification";
NSString * NJPenBatteryLowWarningNotification = @"NJPenBatteryLowWarningNotification";

@interface NJPenCommManager() <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (strong, nonatomic) CBPeripheral          *connectedPeripheral;
@property (strong, nonatomic) NSMutableData         *data;
@property (strong, nonatomic) NSString *penConnectionStatusMsg;
// Pen Servce
@property (strong, nonatomic) CBUUID *neoPenServiceUuid;
@property (strong, nonatomic) CBUUID *strokeDataUuid;
@property (strong, nonatomic) CBUUID *updownDataUuid;
@property (strong, nonatomic) CBUUID *idDataUuid;
@property (strong, nonatomic) NSArray *penCharacteristics;
@property (strong, nonatomic) CBService *penService;

// Offline data service
@property (strong, nonatomic) CBUUID *neoOfflineDataServiceUuid;
@property (strong, nonatomic) CBUUID *neoOffline2DataServiceUuid;
@property (strong, nonatomic) CBUUID *offlineFileInfoUuid;
@property (strong, nonatomic) CBUUID *offlineFileDataUuid;
@property (strong, nonatomic) CBUUID *offlineFileListInfoUuid;
@property (strong, nonatomic) CBUUID *requestOfflineFileUuid;
@property (strong, nonatomic) CBUUID *offlineFileStatusUuid;
@property (strong, nonatomic) CBUUID *requestOfflineFileListUuid;
@property (strong, nonatomic) CBUUID *offlineFileListUuid;
@property (strong, nonatomic) CBUUID *requestDelOfflineFileUuid;
@property (strong, nonatomic) CBUUID *offline2FileAckUuid;
@property (strong, nonatomic) NSArray *offlineCharacteristics;
@property (strong, nonatomic) NSArray *offline2Characteristics;
@property (strong, nonatomic) CBService *offlineService;
@property (strong, nonatomic) CBService *offline2Service;
@property (strong, nonatomic) CBCharacteristic *requestDelOfflineFileCharacteristic;
@property (strong, nonatomic) CBCharacteristic *requestOfflineFileCharacteristic;
@property (strong, nonatomic) CBCharacteristic *requestOfflineFileListCharacteristic;
@property (strong, nonatomic) CBCharacteristic *offline2FileAckCharacteristic;
@property (nonatomic) BOOL needRequestOfflineFileList;

// Update Service
@property (strong, nonatomic) CBUUID *neoUpdateServiceUuid;
@property (strong, nonatomic) CBUUID *updateFileInfoUuid;
@property (strong, nonatomic) CBUUID *requestUpdateUuid;
@property (strong, nonatomic) CBUUID *updateFileDataUuid;
@property (strong, nonatomic) CBUUID *updateFileStatusUuid;
@property (strong, nonatomic) NSArray *updateCharacteristics;
@property (strong, nonatomic) CBService *updateService;
@property (strong, nonatomic) CBCharacteristic *sendUpdateFileInfoCharacteristic;
@property (strong, nonatomic) CBCharacteristic *updateFileDataCharacteristic;

// System Service
@property (strong, nonatomic) CBUUID *neoSystemServiceUuid;
@property (strong, nonatomic) CBUUID *penStateDataUuid;
@property (strong, nonatomic) CBUUID *setPenStateUuid;
@property (strong, nonatomic) CBUUID *setNoteIdListUuid;
@property (strong, nonatomic) CBUUID *readyExchangeDataUuid;
@property (strong, nonatomic) CBUUID *readyExchangeDataRequestUuid;
@property (strong, nonatomic) NSArray *systemCharacteristics;
@property (strong, nonatomic) CBService *systemService;
@property (strong, nonatomic) CBCharacteristic *setPenStateCharacteristic;
@property (strong, nonatomic) CBCharacteristic *setNoteIdListCharacteristic;
@property (strong, nonatomic) CBCharacteristic *readyExchangeDataCharacteristic;

// System2 Service
@property (strong, nonatomic) CBUUID *neoSystem2ServiceUuid;
@property (strong, nonatomic) CBUUID *penPasswordRequestUuid;
@property (strong, nonatomic) CBUUID *penPasswordResponseUuid;
@property (strong, nonatomic) CBUUID *penPasswordChangeRequestUuid;
@property (strong, nonatomic) CBUUID *penPasswordChangeResponseUuid;
@property (strong, nonatomic) NSArray *system2Characteristics;
@property (strong, nonatomic) CBService *system2Service;
@property (strong, nonatomic) CBCharacteristic *penPasswordResponseCharacteristic;
@property (strong, nonatomic) CBCharacteristic *penPasswordChangeRequestCharacteristic;

@property (strong, nonatomic) NSArray *supportedServices;

// Device Information Service
@property (strong, nonatomic) CBUUID *neoDeviceInfoServiceUuid;
@property (strong, nonatomic) CBUUID *fwVersionUuid;
@property (strong, nonatomic) NSArray *deviceInfoCharacteristics;
@property (strong, nonatomic) CBService *deviceInfoService;

@property (strong, nonatomic) CBCharacteristic *setRtcCharacteristic;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) NSTimer *regiTimer;
@property (nonatomic) NSInteger rssiIndex;
@property (nonatomic) NSMutableArray *rssiArray;
@property (nonatomic) NSDictionary *peripheralInfo;
@property (nonatomic) BOOL hasStrokeHandler;

@property (nonatomic) BOOL initBTConnect;
@property (nonatomic) BOOL initDisConnect;

@property (nonatomic) BOOL penRegister;
@property (nonatomic) BOOL firstPenStatus;
@property (nonatomic) BOOL initialConnect;
@property (nonatomic) BOOL disconnectedByUser;
@property (nonatomic) BOOL setAutoPowerOn;
@end

@implementation NJPenCommManager{
    dispatch_queue_t bt_write_dispatch_queue;
}
+ (NJPenCommManager *) sharedInstance
{
    static NJPenCommManager *shared = nil;
    @synchronized(self) {
        if(!shared){
            shared = [[NJPenCommManager alloc] init];
        }
    }
    return shared;
}

- (void) setPenCommParserStrokeHandler:(id<NJPenCommParserStrokeHandler>)strokeHandler
{
    [self.penCommParser setStrokeHandler:strokeHandler];
    if (strokeHandler == nil)
        self.hasStrokeHandler = NO;
    else
        self.hasStrokeHandler = YES;

}
- (void) setPenCommParserCommandHandler:(id<NJPenCommParserCommandHandler>)commandHandler
{
    [self.penCommParser setCommandHandler:commandHandler];
}
- (void) setPenCommParserPasswordDelegate:(id<NJPenCommParserPasswordDelegate>)delegate
{
    [self.penCommParser setPasswordDelegate:delegate];
}
- (void) setPenCommParserStartDelegate:(id<NJPenCommParserStartDelegate>)delegate
{
    [self.penCommParser setCanvasStartDelegate:delegate];
}

- (instancetype)init
{
    self=[super init];
    if (!self) return nil;
    self.neoPenServiceUuid = [CBUUID UUIDWithString:NEO_PEN_SERVICE_UUID];
    self.strokeDataUuid = [CBUUID UUIDWithString:STROKE_DATA_UUID];
    self.updownDataUuid = [CBUUID UUIDWithString:UPDOWN_DATA_UUID];
    self.idDataUuid = [CBUUID UUIDWithString:ID_DATA_UUID];
    self.penCharacteristics = @[self.strokeDataUuid, self.updownDataUuid, self.idDataUuid];
    
    // Offline data Service
    self.neoOfflineDataServiceUuid = [CBUUID UUIDWithString:NEO_OFFLINE_SERVICE_UUID];
    self.offlineFileListUuid = [CBUUID UUIDWithString:OFFLINE_FILE_LIST_UUID];
    self.requestOfflineFileListUuid = [CBUUID UUIDWithString:REQUEST_OFFLINE_FILE_LIST_UUID];
    self.requestDelOfflineFileUuid = [CBUUID UUIDWithString:REQUEST_DEL_OFFLINE_FILE_UUID];
    self.offlineCharacteristics = @[self.offlineFileListUuid, self.requestOfflineFileListUuid, _requestDelOfflineFileUuid];
    
    // Offline2 data Service
    self.neoOffline2DataServiceUuid = [CBUUID UUIDWithString:NEO_OFFLINE2_SERVICE_UUID];
    self.offlineFileInfoUuid = [CBUUID UUIDWithString:OFFLINE2_FILE_INFO_UUID];
    self.offlineFileDataUuid = [CBUUID UUIDWithString:OFFLINE2_FILE_DATA_UUID];
    self.offlineFileListInfoUuid = [CBUUID UUIDWithString:OFFLINE2_FILE_LIST_INFO_UUID];
    self.requestOfflineFileUuid = [CBUUID UUIDWithString:REQUEST_OFFLINE2_FILE_UUID];
    self.offlineFileStatusUuid = [CBUUID UUIDWithString:OFFLINE2_FILE_STATUS_UUID];
    self.offline2FileAckUuid = [CBUUID UUIDWithString:OFFLINE2_FILE_ACK_UUID];
    self.offline2Characteristics = @[self.offlineFileInfoUuid, self.offlineFileDataUuid, self.offlineFileListInfoUuid,
                                     self.requestOfflineFileUuid, self.offlineFileStatusUuid, self.offline2FileAckUuid];
    
    // Update Service
    self.neoUpdateServiceUuid = [CBUUID UUIDWithString:NEO_UPDATE_SERVICE_UUID];
    self.updateFileInfoUuid = [CBUUID UUIDWithString:UPDATE_FILE_INFO_UUID];
    self.requestUpdateUuid = [CBUUID UUIDWithString:REQUEST_UPDATE_FILE_UUID];
    self.updateFileDataUuid = [CBUUID UUIDWithString:UPDATE_FILE_DATA_UUID];
    self.updateFileStatusUuid = [CBUUID UUIDWithString:UPDATE_FILE_STATUS_UUID];
    self.updateCharacteristics = @[self.updateFileInfoUuid, self.requestUpdateUuid, self.updateFileDataUuid,
                                   self.updateFileStatusUuid];
    
    // System Service
    self.neoSystemServiceUuid = [CBUUID UUIDWithString:NEO_SYSTEM_SERVICE_UUID];
    self.penStateDataUuid = [CBUUID UUIDWithString:PEN_STATE_UUID];
    self.setPenStateUuid = [CBUUID UUIDWithString:SET_PEN_STATE_UUID];
    self.setNoteIdListUuid = [CBUUID UUIDWithString:SET_NOTE_ID_LIST_UUID];
    self.readyExchangeDataUuid = [CBUUID UUIDWithString:READY_EXCHANGE_DATA_UUID];
    self.readyExchangeDataRequestUuid = [CBUUID UUIDWithString:READY_EXCHANGE_DATA_REQUEST_UUID];
    self.systemCharacteristics = @[self.penStateDataUuid, self.setPenStateUuid, self.setNoteIdListUuid , self.readyExchangeDataUuid, self.readyExchangeDataRequestUuid];
    
    // System2 Service
    self.neoSystem2ServiceUuid = [CBUUID UUIDWithString:NEO_SYSTEM2_SERVICE_UUID];
    self.penPasswordRequestUuid = [CBUUID UUIDWithString:PEN_PASSWORD_REQUEST_UUID];
    self.penPasswordResponseUuid = [CBUUID UUIDWithString:PEN_PASSWORD_RESPONSE_UUID];
    self.penPasswordChangeRequestUuid = [CBUUID UUIDWithString:PEN_PASSWORD_CHANGE_REQUEST_UUID];
    self.penPasswordChangeResponseUuid = [CBUUID UUIDWithString:PEN_PASSWORD_CHANGE_RESPONSE_UUID];
    self.system2Characteristics = @[self.penPasswordRequestUuid, self.penPasswordResponseUuid, self.penPasswordChangeRequestUuid, self.penPasswordChangeResponseUuid];
    
    // Device Information Service
    self.neoDeviceInfoServiceUuid = [CBUUID UUIDWithString:NEO_DEVICE_INFO_SERVICE_UUID];
    self.fwVersionUuid = [CBUUID UUIDWithString:FW_VERSION_UUID];
    self.deviceInfoCharacteristics = @[self.fwVersionUuid];
    
    self.supportedServices = @[self.neoPenServiceUuid, self.neoSystemServiceUuid, self.neoOfflineDataServiceUuid, self.neoOffline2DataServiceUuid, self.
                               neoUpdateServiceUuid, self.neoDeviceInfoServiceUuid, self.neoSystem2ServiceUuid];
    
    self.selectedIndex = -1;
    self.hasStrokeHandler = NO;
    self.writeActiveState = NO;
    self.setAutoPowerOn = NO;
    
    
    _initialConnect = NO;
    _penConnectionStatus = NJPenCommManPenConnectionStatusNone;
    bt_write_dispatch_queue = dispatch_queue_create("bt_write_dispatch_queue", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (CBCentralManager *) centralManager
{
    if (_centralManager == nil) {
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue: (dispatch_queue_create("kr.neolab.penBT", NULL)) options:@{CBCentralManagerOptionShowPowerAlertKey:@YES}];
    }
    return _centralManager;
}

- (NSMutableData *) data
{
    if (_data == nil) {
        _data = [[NSMutableData alloc] init];
    }
    return _data;
}

- (NSMutableArray *) discoveredPeripherals
{
    if (_discoveredPeripherals == nil) {
        _discoveredPeripherals = [[NSMutableArray alloc] init];
    }
    return _discoveredPeripherals;
}
- (NSMutableArray *) rssiArray
{
    if (_rssiArray == nil) {
        _rssiArray = [[NSMutableArray alloc] init];
    }
    return _rssiArray;
}
- (NSMutableArray *) macArray
{
    if (_macArray == nil) {
        _macArray = [[NSMutableArray alloc] init];
    }
    return _macArray;
}
- (NJPenCommParser *) penCommParser
{
    if (_penCommParser == nil) {
        _penCommParser = [[NJPenCommParser alloc] initWithPenCommManager:self];
    }
    return _penCommParser;
}
- (BOOL)isPenConnected
{
    return (_penConnectionStatus == NJPenCommManPenConnectionStatusConnected);
}
- (void)setPenConnectionStatus:(NJPenCommManPenConnectionStatus)penConnectionStatus
{
    if(_penConnectionStatus != penConnectionStatus) {
        
        _penConnectionStatus = penConnectionStatus;
        if(_penConnectionStatus == NJPenCommManPenConnectionStatusConnected) {
            
        } else if (_penConnectionStatus == NJPenCommManPenConnectionStatusDisconnected) {
            self.penCommParser.passwdCounter = 0;
            _initialConnect = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                NJNotebookWriterManager *writer = [NJNotebookWriterManager sharedInstance];
                [writer saveCurrentPage];
                [writer closeCurrentNotebook];
            });
        }
        
        NSDictionary *info = @{@"info":[NSNumber numberWithInteger:penConnectionStatus],@"msg":_penConnectionStatusMsg};
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NJPenCommManagerPenConnectionStatusChangeNotification object:nil userInfo:info];
        });
    }
}
- (BOOL)hasPenRegistered
{
    if(![[[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys] containsObject:kPenCommMan_Pen_Register])
        return NO;
    
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPenCommMan_Pen_Register];
}
- (void)setHasPenRegistered:(BOOL)hasPenRegistered
{
    if(!hasPenRegistered) {
        [MyFunctions saveIntoKeyChainWithPasswd:nil];
    }
    self.penCommParser.passwdCounter = 0;
    [[NSUserDefaults standardUserDefaults] setBool:hasPenRegistered forKey:kPenCommMan_Pen_Register];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (NSString *)regUuid
{
    if(![[[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys] containsObject:kPenCommMan_Pen_Reg_UUID])
        return @"";
    
    return [[NSUserDefaults standardUserDefaults] objectForKey:kPenCommMan_Pen_Reg_UUID];
}
- (void)setRegUuid:(NSString *)regUuid
{
    [[NSUserDefaults standardUserDefaults] setObject:regUuid forKey:kPenCommMan_Pen_Reg_UUID];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (NSString *)penName
{
    if(![[[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys] containsObject:kPenCommMan_Pen_Name])
        return @"";
    
    return [[NSUserDefaults standardUserDefaults] objectForKey:kPenCommMan_Pen_Name];
}
- (void)setPenName:(NSString *)penName
{
    [[NSUserDefaults standardUserDefaults] setObject:penName forKey:kPenCommMan_Pen_Name];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)resetPenRegistration
{
    [self disConnect];
    self.hasPenRegistered = NO;
    [[NSUserDefaults standardUserDefaults]setObject:@"" forKey:kPenCommMan_Pen_Reg_UUID];
}
- (void) setOfflineDataDelegate:(id<NJOfflineDataDelegate>)offlineDataDelegate
{
    [self.penCommParser setOfflineDataDelegate: offlineDataDelegate];
    if (offlineDataDelegate == nil) return;
    if(_requestOfflineFileListCharacteristic != nil){
        [self.penCommParser requestOfflineFileList];
        _needRequestOfflineFileList = YES;
    }
    else
        _needRequestOfflineFileList = YES;
}
- (void) setPenCalibrationDelegate:(id<NJPenCalibrationDelegate>)penCalibration
{
    [self.penCommParser setPenCalibrationDelegate:penCalibration];
}
- (void) setFWUpdateDelegate:(id<NJFWUpdateDelegate>)fwUpdateDelegate;
{
    [self.penCommParser setFWUpdateDelegate:fwUpdateDelegate];
}

//NISDK -
- (void) setPenPasswordDelegate:(id<NJPenPasswordDelegate>)penPasswordDelegate
{
    [self.penCommParser setPenPasswordDelegate:penPasswordDelegate];
}
- (void)requestWritingStartNotification
{
    self.penCommParser.shouldSendPageChangeNotification = YES;
}

- (void) setPenStatusDelegate:(id<NJPenStatusDelegate>)penStatusDelegate
{
    [self.penCommParser setPenStatusDelegate:penStatusDelegate];
}

- (void) btStart
{
    NSArray *connectedPeripherals;
    if(self.centralManager.state == CBCentralManagerStatePoweredOn) {
        if((self.penConnectionStatus == NJPenCommManPenConnectionStatusNone) || (self.penConnectionStatus == NJPenCommManPenConnectionStatusDisconnected)) {
            self.penConnectionStatus = NJPenCommManPenConnectionStatusNone;
            connectedPeripherals = [self.centralManager retrieveConnectedPeripheralsWithServices:@[self.neoPenServiceUuid, self.neoSystemServiceUuid]];
            if ([connectedPeripherals count] == 0) {
                [self scan];
            } else {
                if(!isEmpty(self.penCommParser.commandHandler)){
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        [self.penCommParser.commandHandler penConnectedByOtherApp:YES];
                    });
                }
            }
        }
    }
}

- (void) btStartForPeripheralsList
{
    NSArray *connectedPeripherals;
    if(self.centralManager.state == CBCentralManagerStatePoweredOn) {
        if((self.penConnectionStatus == NJPenCommManPenConnectionStatusNone) || (self.penConnectionStatus == NJPenCommManPenConnectionStatusDisconnected)) {
            self.penConnectionStatus = NJPenCommManPenConnectionStatusNone;
            connectedPeripherals = [self.centralManager retrieveConnectedPeripheralsWithServices:@[self.neoPenServiceUuid, self.neoSystemServiceUuid]];
            if ([connectedPeripherals count] == 0) {
                [self scanForPeripheralsList];
            } else {
                if(!isEmpty(self.penCommParser.commandHandler)){
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        [self.penCommParser.commandHandler penConnectedByOtherApp:YES];
                    });
                }
            }
        }
    }
}

//NISDK -
- (void) btStop
{
    if (self.centralManager.state == CBCentralManagerStatePoweredOn) {
        if (self.penConnectionStatus == NJPenCommManPenConnectionStatusScanStarted) {
            [self.centralManager stopScan];
        }
    }
    
}
- (void) disConnect
{
    [self.penCommParser writeReadyExchangeData:NO];
    _disconnectedByUser = YES;
    // Give some time to pen, before actual disconnect.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500*NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self disConnectInternal];
    });
}
- (void) disConnectInternal
{
    NSLog(@"current peripheral %@", self.connectedPeripheral);
    if (self.connectedPeripheral) {
        [self.centralManager cancelPeripheralConnection:self.connectedPeripheral];
        self.connectedPeripheral = nil;
        self.penConnectionStatus = NJPenCommManPenConnectionStatusDisconnected;
    
    }
    
#ifdef AUDIO_BACKGROUND_FOR_BT
    NJAppDelegate *delegate = (NJAppDelegate *)[[UIApplication sharedApplication] delegate];
    [delegate.audioController stop];
#endif
    self.writeActiveState = NO;
    
}
- (void) connectPeripheralAt:(NSInteger)index
{
    if (index >= [self.discoveredPeripherals count] ) return;
    CBPeripheral *peripheral = [self.discoveredPeripherals objectAtIndex:index];
    
    // Ok, it's in range - have we already seen it?
    if (self.connectedPeripheral != peripheral) {
        
        NSLog(@"Connecting to peripheral %@", peripheral);
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
    
}
- (CBPeripheral *) peripheralAt:(NSInteger)index
{
    if (index < [self.discoveredPeripherals count] ) {
        return [self.discoveredPeripherals objectAtIndex:index];
    }
    return nil;
}
#pragma mark - CBCentralManagerDelegate
/** centralManagerDidUpdateState is a required protocol method.
 *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
 *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
 *  the Central is ready to be used.
 */
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state == CBCentralManagerStatePoweredOn) {
        // The state must be CBCentralManagerStatePoweredOn...
        // ... so start scanning
        if(!isEmpty(self.handleNewPeripheral)){
            [self btStartForPeripheralsList];
        }else{
            [self btStart];
        }
    } else if(central.state == CBCentralManagerStatePoweredOff) {
        [self disConnect];
    }
}

/** Scan for peripherals - specifically for our service's 128bit CBUUID
 */
- (void)scan
{
    [self.discoveredPeripherals removeAllObjects];
    [self.rssiArray removeAllObjects];
    [self.macArray removeAllObjects];
    
    self.penCommParser.passwdCounter = 0;
    _initialConnect = NO;
    _disconnectedByUser = NO;
    _penConnectionStatusMsg = @"";
    
    NSLog(@"Scanning started");
    [self.centralManager stopScan];
    
    if (self.hasPenRegistered) {
        [self.centralManager scanForPeripheralsWithServices:@[self.neoPenServiceUuid]
                                                    options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES }];
        [self startScanTimer:3.0f];
    }else{
        [self.centralManager scanForPeripheralsWithServices:@[self.neoSystemServiceUuid]
                                                    options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES }];
        [self startScanTimer:7.0f];
    }
}

- (void)scanForPeripheralsList
{
    [self.discoveredPeripherals removeAllObjects];
    [self.rssiArray removeAllObjects];
    [self.macArray removeAllObjects];
    
    self.penCommParser.passwdCounter = 0;
    _initialConnect = NO;
    _disconnectedByUser = NO;
    _penConnectionStatusMsg = @"";
    
    NSLog(@"Scanning started for peripherals list");
    [self.centralManager stopScan];
    
    self.hasPenRegistered = YES;
    
    [self.centralManager scanForPeripheralsWithServices:@[self.neoPenServiceUuid]
                                                options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES }];
}

- (NSString *)getMacAddrFromString:(NSData *)data
{
    NSString *macAddrStr =[NSString stringWithFormat:@"%@",data];
    macAddrStr = [macAddrStr stringByReplacingOccurrencesOfString:@"<" withString:@""];
    macAddrStr = [macAddrStr stringByReplacingOccurrencesOfString:@">" withString:@""];
    macAddrStr = [macAddrStr stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    return macAddrStr;
}
/** This callback comes whenever a peripheral that is advertising the NEO_PEN_SERVICE_UUID is discovered.
 *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
 *  we start the connection process
 */
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    // Reject any where the value is above reasonable range
    if (RSSI.integerValue > -15) {
        NSLog(@"Too Strong %@ at %@", peripheral.name, RSSI);
        //return;
    }
    self.penConnectionStatus = NJPenCommManPenConnectionStatusScanStarted;
    
    NSLog(@"Discovered %@ at %@", peripheral.name, RSSI);
    NSLog(@"advertisement.localname %@", [advertisementData objectForKey:@"kCBAdvDataLocalName"]);
    
    NSString *macAddrStr = nil;
    if([[advertisementData allKeys] containsObject:@"kCBAdvDataManufacturerData"])
        macAddrStr = [self getMacAddrFromString:[advertisementData objectForKey:@"kCBAdvDataManufacturerData"]];
    
    NSLog(@"advertisement.manufactureData %@",macAddrStr);
    NSArray *serviceUUIDs = [advertisementData objectForKey:@"kCBAdvDataServiceUUIDs"];
    NSLog(@"advertisement.serviceUUIDs %@", serviceUUIDs);
    
    if(self.hasPenRegistered) {
        
        // if the peripheral has no pen service --> ignore the peripheral
        if(![serviceUUIDs containsObject:self.neoPenServiceUuid]) return;
        
        NSLog(@"found service 18F1");
        if (![self.discoveredPeripherals containsObject:peripheral]) {
            [self.discoveredPeripherals addObject:peripheral];
            [self.rssiArray addObject:RSSI];
            [self.macArray addObject:(macAddrStr == nil)? @"":macAddrStr];
            NSLog(@"new discoveredPeripherals, rssi %@",RSSI);
        }
        
        
    } else {
        // if the peripheral has no pen service --> ignore the peripheral
        if(![serviceUUIDs containsObject:self.neoSystemServiceUuid]) return;
        
        NSLog(@"found service 18F5");
        if (![self.discoveredPeripherals containsObject:peripheral]) {
            [self.discoveredPeripherals addObject:peripheral];
            [self.rssiArray addObject:RSSI];
            [self.macArray addObject:(macAddrStr == nil)? @"":macAddrStr];
            NSLog(@"new discoveredPeripherals, rssi %@",RSSI);
        }
    }
    
}

- (void)startScanTimer:(CGFloat)duration
{
    if (!_timer)
    {
        _timer = [NSTimer timerWithTimeInterval:duration
                                         target:self
                                       selector:@selector(selectRSSI)
                                       userInfo:nil
                                        repeats:NO];
        
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];
    }
}

- (void)stopScanTimer
{
    [_timer invalidate];
    _timer = nil;
}
- (void) selectRSSI
{
    NSLog(@"[selectRSSI] slectRSSI started....");
    [self.centralManager stopScan];
    [self stopScanTimer];
    
    NSInteger noPeripherals = [self.discoveredPeripherals count];
    if (noPeripherals == 0) {
        NSLog(@"[selectRSSI] no peripherals found....");
        // we have not any discovered peripherals
        self.penConnectionStatus = NJPenCommManPenConnectionStatusDisconnected;
    }
    
    
    _rssiIndex = -1;
    if (self.hasPenRegistered) {
        // we have registration
        // check if stored regUuid is MAC or UUID
        NSLog(@"[selectRSSI] already registred now trying to connect to pen....");
        if(self.regUuid.length <= 15) {
            // 1. MAC address --> try new method
            for (int i = 0; i < noPeripherals; i++) {
                NSString *uid = [self.macArray objectAtIndex:i];
                if ([self.regUuid isEqualToString:uid]) {
                    NSLog(@"[selectRSSI] connecting pen by using MAC....");
                    [self connectPeripheralAt:i];
                    return;
                }
            }
        } else {
            // 2. UUID --> try old method
            NSLog(@"[selectRSSI] connecting pen by using UUID....");
            for (int i = 0; i < noPeripherals; i++) {
                CBPeripheral *foundPeripheral = self.discoveredPeripherals[i];
                NSString *uid = [foundPeripheral.identifier UUIDString];
                
                if ([self.regUuid isEqualToString:uid]) {
                    [self connectPeripheralAt:i];
                    return;
                }
            }
        }
    } else {
        
        NSInteger noRssi = [self.rssiArray count];
        NSNumber *foundRssi;
        NSInteger max= -90, current;
        
        for (int i = 0; i < noRssi; i++) {
            foundRssi = self.rssiArray[i];
            current = [foundRssi integerValue];
            if (current > max){
                max = current;
                _rssiIndex = i;
            }
        }
        
        CBPeripheral *foundPeripheral;
        
        if ((self.connectedPeripheral == nil) && (_rssiIndex != -1)){
            
            // 1.try macAddr first
            foundPeripheral = self.discoveredPeripherals[_rssiIndex];
            NSString *uid = [self.macArray objectAtIndex:_rssiIndex];
            if(isEmpty(uid)) {
                // 2.if no macAddr (backwards-compatibility) try uuid
                uid = [foundPeripheral.identifier UUIDString];
            }
            self.regUuid = uid;
            self.hasPenRegistered = YES;
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"penAutoPower"];
            self.penName = foundPeripheral.name;
            [self connectPeripheralAt:_rssiIndex];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:NJPenRegistrationNotification object:nil userInfo:nil];
            return;
        }
    }
    
    // if we reached here --> we failed, and try the scan again
    NSLog(@"[selectRSSI] not found any eligible peripheral....");
    _penConnectionStatusMsg = @"This pen is not registered.";
    self.penConnectionStatus = NJPenCommManPenConnectionStatusDisconnected;
}
/** If the connection fails for whatever reason, we need to deal with it.
 */
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    self.penConnectionStatus = NJPenCommManPenConnectionStatusDisconnected;
    
    
    if(!isEmpty(self.handleNewPeripheral)){
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.handleNewPeripheral connectionResult:NO];
        });
    }
    
    NSLog(@"Failed to connect to %@. (%@)", peripheral, [error localizedDescription]);
    [self cleanup];
}


/** We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
 */
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    
    NSLog(@"Peripheral Connected");
    
    // Clear the data that we may already have
    [self.data setLength:0];
    
    self.connectedPeripheral = peripheral;
    // Make sure we get the discovery callbacks
    peripheral.delegate = self;
    
    // Search only for services that match our UUID
    [peripheral discoverServices:self.supportedServices];
#ifdef AUDIO_BACKGROUND_FOR_BT
    NJAppDelegate *delegate = (NJAppDelegate *)[[UIApplication sharedApplication] delegate];
    [delegate.audioController start:NULL];
#endif
    if(!isEmpty(self.handleNewPeripheral)){
        dispatch_async(dispatch_get_main_queue(), ^{
            
                [self.handleNewPeripheral connectionResult:YES];
        });
    }

}


/** The Service was discovered
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering services: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    // Discover the characteristic we want...
    
    // Loop through the newly filled peripheral.services array, just in case there's more than one.
    for (CBService *service in peripheral.services) {
        NSLog(@"Service UUID : %@", [[service UUID] UUIDString]);
        if ([[[service UUID] UUIDString] isEqualToString:NEO_SYSTEM_SERVICE_UUID]) {
            self.systemService = service;
            [peripheral discoverCharacteristics:self.systemCharacteristics forService:service];
        }
        else if ([[[service UUID] UUIDString] isEqualToString:NEO_SYSTEM2_SERVICE_UUID]) {
            self.system2Service = service;
            [peripheral discoverCharacteristics:self.system2Characteristics forService:service];
        }
        else if ([[[service UUID] UUIDString] isEqualToString:NEO_PEN_SERVICE_UUID]) {
            self.penService = service;
            // Initialize some value.
            [self.penCommParser setPenCommIdDataReady:NO];
            [self.penCommParser setPenCommStrokeDataReady:NO];
            [self.penCommParser setPenCommUpDownDataReady:NO];
            
            [peripheral discoverCharacteristics:self.penCharacteristics forService:service];
        }
        else if ([[[service UUID] UUIDString] isEqualToString:NEO_OFFLINE_SERVICE_UUID]) {
            self.offlineService = service;
            [peripheral discoverCharacteristics:self.offlineCharacteristics forService:service];
        }
        else if ([[[service UUID] UUIDString] isEqualToString:NEO_OFFLINE2_SERVICE_UUID]) {
            self.offline2Service = service;
            [peripheral discoverCharacteristics:self.offline2Characteristics forService:service];
        }
        else if ([[[service UUID] UUIDString] isEqualToString:NEO_UPDATE_SERVICE_UUID]) {
            self.updateService = service;
            [peripheral discoverCharacteristics:self.updateCharacteristics forService:service];
        }
        else if ([[[service UUID] UUIDString] isEqualToString:NEO_DEVICE_INFO_SERVICE_UUID]) {
            self.deviceInfoService = service;
            [peripheral discoverCharacteristics:self.deviceInfoCharacteristics forService:service];
        }
    }
}


/** The Transfer characteristic was discovered.
 *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    // Deal with errors (if any)
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    if (service == self.penService) {
        // Again, we loop through the array, just in case.
        for (CBCharacteristic *characteristic in service.characteristics) {
            // And check if it's the right one
            if ([self.penCharacteristics containsObject:characteristic.UUID]) {
                if ([[characteristic UUID] isEqual:self.strokeDataUuid]) {
                    NSLog(@"strokeDataUuid");
                    [self.penCommParser setPenCommStrokeDataReady:YES];
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if ([[characteristic UUID] isEqual:self.updownDataUuid]) {
                    NSLog(@"updownDataUuid");
                    [self.penCommParser setPenCommUpDownDataReady:YES];
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if ([[characteristic UUID] isEqual:self.idDataUuid]) {
                    NSLog(@"idDataUuid");
                    [self.penCommParser setPenCommIdDataReady:YES];
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.offlineFileInfoUuid]) {
                    NSLog(@"offlineFileInfoUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.offlineFileDataUuid]) {
                    NSLog(@"offlineFileDataUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
            }
            else {
                NSLog(@"Unknown characteristic %@ for service %@", service.UUID, characteristic.UUID);
            }
        }
    }
    else if (service == self.systemService) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            // And check if it's the right one
            if ([self.systemCharacteristics containsObject:characteristic.UUID]) {
                if ([[characteristic UUID] isEqual:self.penStateDataUuid]) {
                    NSLog(@"penStateDataUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.setPenStateUuid]) {
                    NSLog(@"setPenStateUuid");
                    self.setPenStateCharacteristic = characteristic;
                }
                else if([[characteristic UUID] isEqual:self.setNoteIdListUuid]) {
                    NSLog(@"setNoteIdListUuid");
                    self.setNoteIdListCharacteristic = characteristic;
                    [self.penCommParser setNoteIdList];
                }
                else if([[characteristic UUID] isEqual:_readyExchangeDataUuid]) {
                    NSLog(@"readyExchangeDataUuid");
                    _readyExchangeDataCharacteristic = characteristic;
                }
                else if([[characteristic UUID] isEqual:_readyExchangeDataRequestUuid]) {
                    NSLog(@"readyExchangeDataRequestUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
            }
            else {
                NSLog(@"Unknown characteristic %@ for service %@", service.UUID, characteristic.UUID);
            }
        }
    }
    else if (service == self.system2Service) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            // And check if it's the right one
            if ([self.system2Characteristics containsObject:characteristic.UUID]) {
                if ([[characteristic UUID] isEqual:_penPasswordRequestUuid]) {
                    NSLog(@"penPasswordRequestUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:_penPasswordResponseUuid]) {
                    NSLog(@"penPasswordResponseUuid");
                    _penPasswordResponseCharacteristic = characteristic;
                }
                else if([[characteristic UUID] isEqual:_penPasswordChangeRequestUuid]) {
                    NSLog(@"penPasswordChangeRequestUuid");
                    _penPasswordChangeRequestCharacteristic = characteristic;
                }
                else if([[characteristic UUID] isEqual:_penPasswordChangeResponseUuid]) {
                    NSLog(@"penPasswordChangeResponseUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                
            }
            else {
                NSLog(@"Unknown characteristic %@ for service %@", service.UUID, characteristic.UUID);
            }
        }
        
    }
    else if (service == self.offline2Service) {
        // Again, we loop through the array, just in case.
        for (CBCharacteristic *characteristic in service.characteristics) {
            // And check if it's the right one
            if ([self.offline2Characteristics containsObject:characteristic.UUID]) {
                if([[characteristic UUID] isEqual:self.offlineFileInfoUuid]) {
                    NSLog(@"offlineFileInfoUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.offlineFileDataUuid]) {
                    NSLog(@"offlineFileDataUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.offlineFileListInfoUuid]) {
                    NSLog(@"offlineFileListInfoUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.requestOfflineFileUuid]) {
                    NSLog(@"requestOfflineFileUuid");
                    self.requestOfflineFileCharacteristic = characteristic;
                }
                else if([[characteristic UUID] isEqual:self.offlineFileStatusUuid]) {
                    NSLog(@"offlineFileStatusUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.offline2FileAckUuid]) {
                    NSLog(@"offline2FileAckUuid");
                    self.offline2FileAckCharacteristic = characteristic;
                }
                else {
                    NSLog(@"Unhandled characteristic %@ for service %@", service.UUID, characteristic.UUID);
                }
                
            }
            else {
                NSLog(@"Unknown characteristic %@ for service %@", service.UUID, characteristic.UUID);
            }
        }
        
    }
    else if (service == self.offlineService) {
        // Again, we loop through the array, just in case.
        for (CBCharacteristic *characteristic in service.characteristics) {
            // And check if it's the right one
            if ([self.offlineCharacteristics containsObject:characteristic.UUID]) {
                if([[characteristic UUID] isEqual:self.requestOfflineFileListUuid]) {
                    NSLog(@"requestOfflineFileListUuid");
                    self.requestOfflineFileListCharacteristic = characteristic;
                }
                else if([[characteristic UUID] isEqual:self.offlineFileListUuid]) {
                    NSLog(@"offlineFileListUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.requestDelOfflineFileUuid]) {
                    NSLog(@"requestDelOfflineFileUuid");
                    _requestDelOfflineFileCharacteristic = characteristic;
                }
                else {
                    NSLog(@"Unhandled characteristic %@ for service %@", service.UUID, characteristic.UUID);
                }
                
            }
            else {
                NSLog(@"Unknown characteristic %@ for service %@", service.UUID, characteristic.UUID);
            }
        }
        
    }
    else if (service == self.updateService) {
        // Again, we loop through the array, just in case.
        for (CBCharacteristic *characteristic in service.characteristics) {
            // And check if it's the right one
            if ([self.updateCharacteristics containsObject:characteristic.UUID]) {
                if([[characteristic UUID] isEqual:self.updateFileInfoUuid]) {
                    NSLog(@"updateFileInfoUuid");
                    self.sendUpdateFileInfoCharacteristic = characteristic;
                }
                else if([[characteristic UUID] isEqual:self.requestUpdateUuid]) {
                    NSLog(@"requestUpdateFileInfoUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if([[characteristic UUID] isEqual:self.updateFileDataUuid]) {
                    NSLog(@"updateFileDataUuid");
                    self.updateFileDataCharacteristic = characteristic;
                }
                else if([[characteristic UUID] isEqual:self.updateFileStatusUuid]) {
                    NSLog(@"updateFileStatusUuid");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
                else {
                    NSLog(@"Unhandled characteristic %@ for service %@", service.UUID, characteristic.UUID);
                }
                
            }
            else {
                NSLog(@"Unknown characteristic %@ for service %@", service.UUID, characteristic.UUID);
            }
        }
        
    }
    else if (service == self.deviceInfoService) {
        // Again, we loop through the array, just in case.
        for (CBCharacteristic *characteristic in service.characteristics) {
            // And check if it's the right one
            if ([self.deviceInfoCharacteristics containsObject:characteristic.UUID]) {
                if([[characteristic UUID] isEqual:self.fwVersionUuid]) {
                    NSLog(@"fwVersionUuid");
                    [peripheral readValueForCharacteristic:characteristic];
                }
            }
            else {
               NSLog(@"Unknown characteristic %@ for service %@", service.UUID, characteristic.UUID);
           }
       }
        
   }
    // Once this is complete, we just need to wait for the data to come in.
}


/** This callback lets us know more data has arrived via notification on the characteristic
 */
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        return;
    }
    
    NSData* received_data = characteristic.value;
    int dataLength = (int)[received_data length];
    unsigned char *packet = (unsigned char *) [received_data bytes];
    if([ characteristic.UUID isEqual: self.strokeDataUuid] )
    {
        [self.penCommParser parsePenStrokeData:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.updownDataUuid] )
    {
        NSLog(@"Received: updown");
        self.writeActiveState = YES;
        [self.penCommParser parsePenUpDowneData:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.idDataUuid] )
    {
        NSLog(@"Received: id data");
        [self.penCommParser parsePenNewIdData:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.offlineFileDataUuid] ){
//        NSLog(@"Received: offline file data");
        [self.penCommParser parseOfflineFileData:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.offlineFileInfoUuid] ) {
        NSLog(@"Received: offline file info data");
        [self.penCommParser parseOfflineFileInfoData:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.penStateDataUuid] ) {
        NSLog(@"Received: pen status data");
        if (!_initialConnect) {
            self.penConnectionStatus = NJPenCommManPenConnectionStatusConnected;
            _initialConnect = YES;
        }
        [self.penCommParser parsePenStatusData:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.offlineFileListUuid] ) {
        NSLog(@"Received: offline File list");
        [self.penCommParser parseOfflineFileList:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.offlineFileListInfoUuid] ) {
        NSLog(@"Received: offline File List info");
        [self.penCommParser parseOfflineFileListInfo:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.offlineFileStatusUuid] ) {
        NSLog(@"Received: offline File Status");
        [self.penCommParser parseOfflineFileStatus:packet withLength:dataLength];
    }
    // Update FW
    else if([ characteristic.UUID isEqual: self.requestUpdateUuid] ) {
        NSLog(@"Received: request update file");
        [self.penCommParser parseRequestUpdateFile:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.updateFileStatusUuid] ) {
        NSLog(@"Received: update file status ");
        [self.penCommParser parseUpdateFileStatus:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: _readyExchangeDataRequestUuid] ) {
        NSLog(@"Received: readyExchangeDataRequestUuid");
        [self.penCommParser parseReadyExchangeDataRequest:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: _penPasswordRequestUuid] ) {
        NSLog(@"Received: penPasswordRequestUuid");
        [self.penCommParser parsePenPasswordRequest:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: _penPasswordChangeResponseUuid] ) {
        NSLog(@"Received: penPasswordResponseUuid");
        [self.penCommParser parsePenPasswordChangeResponse:packet withLength:dataLength];
    }
    else if([ characteristic.UUID isEqual: self.fwVersionUuid] ) {
        NSLog(@"Received: FW version");
        [self.penCommParser parseFWVersion:packet withLength:dataLength];
    }
    else {
        NSLog(@"Un-handled data characteristic.UUID %@", [characteristic.UUID UUIDString]);
        return;
    }
}


/** The peripheral letting us know whether our subscribe/unsubscribe happened or not
 */
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error changing notification state: %@ characteristic : %@", error.localizedDescription, characteristic.UUID);
    }
    
   
    // Notification has started
    if (characteristic.isNotifying) {
        NSLog(@"Notification began on %@", characteristic);
    }
    // Notification has stopped
    else {
        // so disconnect from the peripheral
        NSLog(@"Notification stopped on %@.  Disconnecting", characteristic);
        [self.centralManager cancelPeripheralConnection:peripheral];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error WriteValueForCharacteristic: %@ characteristic : %@", error.localizedDescription, characteristic.UUID);
        return;
    }
    if (characteristic == self.setPenStateCharacteristic) {
        NSLog(@"Set Pen Status successful");
    }
    else if (characteristic == self.requestOfflineFileListCharacteristic) {
        NSLog(@"requestOfflineFileList successful");
    }
    else if (characteristic == self.sendUpdateFileInfoCharacteristic) {
        NSLog(@"sendUpdateFileInfoCharacteristic successful");
    }
    else if (characteristic == self.updateFileDataCharacteristic) {
        NSLog(@"updateFileDataCharacteristic successful");
    }
    else if (characteristic == self.offline2FileAckCharacteristic) {
        NSLog(@"offline2FileAckCharacteristic successful");
    }
    else if (characteristic == self.setNoteIdListCharacteristic) {
        NSLog(@"setNoteIdListCharacteristic successful");
    }
    else if (characteristic == self.requestOfflineFileCharacteristic) {
        NSLog(@"requestOfflineFileCharacteristic successful");
    }
    else if (characteristic == self.requestDelOfflineFileCharacteristic) {
        NSLog(@"requestDelOfflineFileCharacteristic successful");
    }
    else {
        NSLog(@"Unknown characteristic %@ didWriteValueForCharacteristic successful", characteristic.UUID);
    }
}
/** Once the disconnection happens, we need to clean up our local copy of the peripheral
 */
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Peripheral Disconnected");
    self.connectedPeripheral = nil;
    
    self.selectedIndex = -1;
    [self.penCommParser resetDataReady];
    self.penConnectionStatus = NJPenCommManPenConnectionStatusDisconnected;
    
#ifdef AUDIO_BACKGROUND_FOR_BT
    NJAppDelegate *delegate = (NJAppDelegate *)[[UIApplication sharedApplication] delegate];
    [delegate.audioController stop];
#endif
    self.writeActiveState = NO;
    
    if(!isEmpty(self.handleNewPeripheral)){
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.handleNewPeripheral connectionResult:NO];
        });
    }
}


/** Call this when things either go wrong, or you're done with the connection.
 *  This cancels any subscriptions if there are any, or straight disconnects if not.
 *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
 */
- (void)cleanup
{
    // Don't do anything if we're not connected
    if (self.connectedPeripheral.state != CBPeripheralStateConnected) {
        return;
    }
    
    // See if we are subscribed to a characteristic on the peripheral
    if (self.connectedPeripheral.services != nil) {
        for (CBService *service in self.connectedPeripheral.services) {
            if (service.characteristics != nil) {
                for (CBCharacteristic *characteristic in service.characteristics) {
                    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:STROKE_DATA_UUID]]) {
                        if (characteristic.isNotifying) {
                            // It is notifying, so unsubscribe
                            [self.connectedPeripheral setNotifyValue:NO forCharacteristic:characteristic];
                            
                            // And we're done.
                            self.penConnectionStatus = NJPenCommManPenConnectionStatusDisconnected;
                            return;
                        }
                    }
                }
            }
        }
    }
    
    // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
    [self.centralManager cancelPeripheralConnection:self.connectedPeripheral];
}
#pragma mark - Write to Pen

- (void)writeData:(NSData *)data to:(CBCharacteristic *)characteristic
{
    dispatch_async(bt_write_dispatch_queue, ^{
        [self.connectedPeripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
    });
}
- (void)writeSetPenState:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        NSLog(@"gethere 3");
        [self.connectedPeripheral writeValue:data forCharacteristic:self.setPenStateCharacteristic type:CBCharacteristicWriteWithResponse];
    });
}
- (void)writeNoteIdList:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        [self.connectedPeripheral writeValue:data forCharacteristic:self.setNoteIdListCharacteristic type:CBCharacteristicWriteWithResponse];
    });
}

- (void)writeReadyExchangeData:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        if (_readyExchangeDataCharacteristic) {
            [self.connectedPeripheral writeValue:data forCharacteristic:_readyExchangeDataCharacteristic type:CBCharacteristicWriteWithResponse];
        }
    });
}
- (void)writePenPasswordResponseData:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        if (_penPasswordResponseCharacteristic) {
            [self.connectedPeripheral writeValue:data forCharacteristic:_penPasswordResponseCharacteristic type:CBCharacteristicWriteWithResponse];
        }
    });
}

- (void)writeSetPasswordData:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        if (_penPasswordChangeRequestCharacteristic) {
            [self.connectedPeripheral writeValue:data forCharacteristic:_penPasswordChangeRequestCharacteristic type:CBCharacteristicWriteWithResponse];
        }
    });
}

- (void)writeRequestOfflineFileList:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        [self.connectedPeripheral writeValue:data forCharacteristic:self.requestOfflineFileListCharacteristic type:CBCharacteristicWriteWithResponse];
    });
}
- (void)writeRequestDelOfflineFile:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        [self.connectedPeripheral writeValue:data forCharacteristic:self.requestDelOfflineFileCharacteristic type:CBCharacteristicWriteWithResponse];
    });
}
- (void)writeRequestOfflineFile:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        [self.connectedPeripheral writeValue:data forCharacteristic:self.requestOfflineFileCharacteristic type:CBCharacteristicWriteWithResponse];
    });
}
- (void)writeOfflineFileAck:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        [self.connectedPeripheral writeValue:data forCharacteristic:self.offline2FileAckCharacteristic type:CBCharacteristicWriteWithResponse];
    });
}
- (void)writeUpdateFileData:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        [self.connectedPeripheral writeValue:data forCharacteristic:self.updateFileDataCharacteristic type:CBCharacteristicWriteWithResponse];
    });
}
- (void)writeUpdateFileInfo:(NSData *)data
{
    dispatch_async(bt_write_dispatch_queue, ^{
        [self.connectedPeripheral writeValue:data forCharacteristic:self.sendUpdateFileInfoCharacteristic type:CBCharacteristicWriteWithResponse];
    });
}
#pragma mark - Public API

- (void)setPenStateWithRGB:(UInt32)color
{
    [self.penCommParser setPenStateWithRGB:color];
}

- (void)setPenStateWithPenPressure:(UInt16)penPressure
{
    [self.penCommParser setPenStateWithPenPressure:penPressure];
}

- (void)setPenStateWithAutoPwrOffTime:(UInt16)autoPwrOff
{
    [self.penCommParser setPenStateWithAutoPwrOffTime:autoPwrOff];
}

- (void)setPenStateAutoPower:(unsigned char)autoPower Sound:(unsigned char)sound
{
    [self.penCommParser setPenStateAutoPower:autoPower Sound:sound];
}

- (void)setPenStateWithHover:(UInt16)useHover
{
    [self.penCommParser setPenStateWithHover:useHover];
}

//NISDK -
- (void)setPenStateWithTimeTick
{
    [self.penCommParser setPenStateWithTimeTick];
}

- (unsigned char)getPenStateWithBatteryLevel
{
    return [self.penCommParser batteryLevel];
}

- (unsigned char)getPenStateWithMemoryUsed
{
    return [self.penCommParser memoryUsed];
}

- (NSString *)getFWVersion
{
    return [self.penCommParser fwVersion];
}

- (BOOL) requestOfflineDataWithOwnerId:(UInt32)ownerId noteId:(UInt32)noteId
{
    return [self.penCommParser requestOfflineDataWithOwnerId:ownerId noteId:noteId];
}

- (void)setPenThickness:(NSUInteger)thickness
{
    [self.penCommParser setPenThickness:thickness];
}

- (void) changePasswordFrom:(NSString *)curNumber To:(NSString *)pinNumber
{
    [self.penCommParser changePasswordFrom:curNumber To:pinNumber];
}
- (void) setBTComparePassword:(NSString *)pinNumber
{
    [self.penCommParser setBTComparePassword:pinNumber];
}

- (void) sendUpdateFileInfoAtUrlToPen:(NSURL *)fileUrl
{
    [self.penCommParser sendUpdateFileInfoAtUrlToPen:(NSURL *)fileUrl];
}

- (void) setCancelFWUpdate:(BOOL)cancelFWUpdate
{
    [self.penCommParser setCancelFWUpdate:cancelFWUpdate];
}

- (void) getPenBattLevelAndMemoryUsedSize:(void (^)(unsigned char remainedBattery, unsigned char usedMemory))completionBlock
{
    self.penCommParser.battMemoryBlock = completionBlock;
    [self.penCommParser setPenStateWithTimeTick];
}

//NISDK -
- (void) setPenState
{
    [self.penCommParser setPenState];
}

- (void) setNoteIdList
{
    [self.penCommParser setNoteIdList];
}

- (void) setNoteIdListFromPList
{
    [self.penCommParser setNoteIdListFromPList];
}

- (void) setAllNoteIdList
{
    [self.penCommParser setAllNoteIdList];
}

- (void) setNoteIdListSectionOwnerFromPList
{
    [self.penCommParser setNoteIdListSectionOwnerFromPList];
}

- (float) processPressure:(float)pressure
{
    return [self.penCommParser processPressure:pressure];
}

- (NJPageDocument *) activePageDocument
{
    return [self.penCommParser activePageDocument];
}

- (float) startX
{
    return [self.penCommParser startX];
}
- (float) startY
{
    return [self.penCommParser startY];
}

@end
