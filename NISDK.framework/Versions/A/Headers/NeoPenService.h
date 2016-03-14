
/* Pen Service UUID
 */
#define NEO_PEN_SERVICE_UUID    @"18F1"
#define STROKE_DATA_UUID        @"2AA0"
#define ID_DATA_UUID            @"2AA1"
#define UPDOWN_DATA_UUID        @"2AA2"
#define SET_RTC_UUID            @"2AB1"

/* OFFLINE Data Service UUID
 */
#define NEO_OFFLINE_SERVICE_UUID @"18F2"
#define REQUEST_OFFLINE_FILE_LIST_UUID @"2AC1"
#define OFFLINE_FILE_LIST_UUID @"2AC2"
#define REQUEST_DEL_OFFLINE_FILE_UUID @"2AC3"

/* OFFLINE2 Data Service UUID
 */
#define NEO_OFFLINE2_SERVICE_UUID @"18F3"
#define REQUEST_OFFLINE2_FILE_UUID        @"2AC7"
#define OFFLINE2_FILE_LIST_INFO_UUID @"2AC8"
#define OFFLINE2_FILE_INFO_UUID   @"2AC9"
#define OFFLINE2_FILE_DATA_UUID   @"2ACA"
#define OFFLINE2_FILE_ACK_UUID   @"2ACB"
#define OFFLINE2_FILE_STATUS_UUID      @"2ACC"

/* Update Service UUID
 */
#define NEO_UPDATE_SERVICE_UUID         @"18F4"
#define UPDATE_FILE_INFO_UUID           @"2AD1"
#define REQUEST_UPDATE_FILE_UUID   @"2AD2"
#define UPDATE_FILE_DATA_UUID           @"2AD3"
#define UPDATE_FILE_STATUS_UUID         @"2AD4"

/* System Service UUID
 */
#define NEO_SYSTEM_SERVICE_UUID @"18F5"
#define PEN_STATE_UUID          @"2AB0"
#define SET_PEN_STATE_UUID      @"2AB1"
#define SET_NOTE_ID_LIST_UUID   @"2AB2"
#define READY_EXCHANGE_DATA_UUID   @"2AB4"
#define READY_EXCHANGE_DATA_REQUEST_UUID   @"2AB5"

/* System2 Service UUID
 */
#define NEO_SYSTEM2_SERVICE_UUID @"18F6"
#define PEN_PASSWORD_REQUEST_UUID   @"2AB7"
#define PEN_PASSWORD_RESPONSE_UUID  @"2AB8"
#define PEN_PASSWORD_CHANGE_REQUEST_UUID    @"2AB9"
#define PEN_PASSWORD_CHANGE_RESPONSE_UUID   @"2ABA"

/* device information Service UUID
 */
#define NEO_DEVICE_INFO_SERVICE_UUID @"180A"
#define FW_VERSION_UUID          @"2A26"

#define HAS_LINE_COLOR

typedef struct __attribute__((packed)){
	unsigned char diff_time;
	unsigned short x;
	unsigned short y;
	unsigned char f_x;
	unsigned char f_y;
	unsigned char force;
} COMM_WRITE_DATA;
typedef struct __attribute__((packed)){
	UInt32 owner_id;
	UInt32 note_id;
	UInt32 page_id;
} COMM_CHANGEDID2_DATA;
typedef struct __attribute__((packed)){
	UInt64 time;
	unsigned char upDown;
    UInt32 penColor;
} COMM_PENUP_DATA;

// Offline File Data
typedef struct  __attribute__((packed)){
    unsigned char status;
} RequestOfflineFileListStruct; //Ox2AC1
typedef struct  __attribute__((packed)){
    unsigned char status;
    UInt32 sectionOwnerId;
    unsigned char noteCount;
    UInt32 noteId[10];
} OfflineFileListStruct; //0x2AC2
typedef struct  __attribute__((packed)){
    UInt32 sectionOwnerId;
    UInt64 noteId;
} RequestDelOfflineFileStruct; //0x2AC3

// Offline2 File Data
typedef struct __attribute__((packed)){
	UInt32 sectionOwnerId;
    unsigned char noteCount;
    UInt32 noteId[10];
} RequestOfflineFileStruct; //0x2AC7
typedef struct __attribute__((packed)){
	UInt32 fileCount;
	UInt32 fileSize;
} OfflineFileListInfoStruct; //0x2AC8
typedef struct __attribute__((packed)){
	unsigned char type;
    UInt32 file_size;
	UInt16 packet_count;
    UInt16 packet_size;
	UInt16 slice_count;
    UInt16 slice_size;
} OFFLINE_FILE_INFO_DATA; //0x2AC9
typedef struct __attribute__((packed)){
	UInt16 index;
	unsigned char slice_index;
	unsigned char data;
} OFFLINE_FILE_DATA; //0x2ACA
typedef struct __attribute__((packed)){
    unsigned char type;
    unsigned char index;  //packet index
} OfflineFileAckStruct; //0x2ACB
typedef struct __attribute__((packed)){
    unsigned char status;
} OfflineFileStatusStruct; //0x2ACC

// Offline File Format
typedef struct __attribute__((packed)){ //64 bytes
	unsigned char abVersion[5];
	unsigned char isActive;
	UInt32 nOwnerId;
	UInt32 nNoteId;
	UInt32 nPageId;
	UInt32 nSubId;
	UInt32 nNumOfStrokes;
	UInt32 cbDataSize; //header 크기를 제외한 값
	unsigned char abReserved[33];
	unsigned char nCheckSum;
}  OffLineDataFileHeaderStruct ;

typedef struct __attribute__((packed)){
	UInt64 nStrokeStartTime;
	UInt64 nStrokeEndTime;
	UInt32 nDotCount;
	unsigned char cbDotStructSize;
#ifdef HAS_LINE_COLOR
	UInt32 nLineColor;
#endif
	unsigned char nCheckSum;
} OffLineDataStrokeHeaderStruct;

typedef struct __attribute__((packed)){
	unsigned char nTimeDelta;
	UInt16 x, y;
	unsigned char fx, fy;
	unsigned char force;
} OffLineDataDotStruct;

/* Update Service Data Structure
 */
typedef struct __attribute__((packed)){
	unsigned char filePath[52];
    UInt32 fileSize;
    UInt16 packetCount;
    UInt16 packetSize;
} UpdateFileInfoStruct; //0x2AD1
typedef struct __attribute__((packed)){
    UInt16 index;
} RequestUpdateFileStruct; //0x2AD2
#define UPDATE_DATA_PACKET_SIZE 112
typedef struct __attribute__((packed)){
    UInt16 index;
	unsigned char fileData[UPDATE_DATA_PACKET_SIZE];
} UpdateFileDataStruct; //0x2AD3
typedef struct __attribute__((packed)){
    UInt16 status;
} UpdateFileStatusStruct; //0x2AD4

/* System Service Data Structure
 */
typedef struct __attribute__((packed)){
    unsigned char version;
    unsigned char penStatus;
	int32_t timezoneOffset;
	UInt64 timeTick;
    unsigned char pressureMax;
    unsigned char battLevel;
    unsigned char memoryUsed;
    UInt32 colorState;
	unsigned char usePenTipOnOff;
    unsigned char useAccelerator;
    unsigned char useHover;
    unsigned char beepOnOff;
    UInt16 autoPwrOffTime;
    UInt16 penPressure;
    unsigned char reserved[11];
} PenStateStruct;
typedef struct __attribute__((packed)){
	int32_t timezoneOffset;
	UInt64 timeTick;
    UInt32 colorState;
	unsigned char usePenTipOnOff;
    unsigned char useAccelerator;
    unsigned char useHover;
    unsigned char beepOnOff;
    UInt16 autoPwrOnTime;
    UInt16 penPressure;
    unsigned char reserved[16];
} SetPenStateStruct;
#define NOTE_ID_LIST_SIZE 10
typedef struct __attribute__((packed)){
    unsigned char type;
	unsigned char count;
    UInt32 params[NOTE_ID_LIST_SIZE + 1];
} SetNoteIdListStruct; //ox2AB2

typedef struct __attribute__((packed)){
    unsigned char ready;
} ReadyExchangeDataStruct; //0x2AB4
typedef struct __attribute__((packed)){
    unsigned char ready;
} ReadyExchangeDataRequestStruct; //0x2AB5

typedef struct __attribute__((packed)){
    unsigned char retryCount;
    unsigned char resetCount;
} PenPasswordRequestStruct; //0x2AB7
typedef struct __attribute__((packed)){
    unsigned char password[16];
} PenPasswordResponseStruct; //0x2AB8

typedef struct __attribute__((packed)){
    unsigned char prevPassword[16];
    unsigned char newPassword[16];
} PenPasswordChangeRequestStruct; //0x2AB9
typedef struct __attribute__((packed)){
    unsigned char passwordState;
} PenPasswordChangeResponseStruct; //0x2ABA

