//
//  NJNotebookInfoStore.m
//  NeoJournal
//
//  Created by NamSSan on 10/08/2014.
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJNotebookInfoStore.h"
#import "NJNotebookInfo.h"
#import "configure.h"

#import "NJNotebook.h"
#import "NJNotebookDocument.h"
#import "NJNotebookReaderManager.h"

#define kNOTEBOOK_INFO_FILE_NAME    @"notebook.info"
#define kNOTEBOOK_INFO_KEY          @"notebook_info"
#define kMAX_NOTE_ID   1000

@implementation NJNotebookInfoStore



+ (NJNotebookInfoStore *)sharedStore
{
    static NJNotebookInfoStore *sharedStore = nil;
    
    @synchronized(self) {
        
        if(!sharedStore) {
            sharedStore = [[super allocWithZone:nil] init];
            
        }
    }
    
    return sharedStore;
}




- (id)init
{
    self = [super init];
    
    if(self) {
        
        [self _findMaxDigitalNoteNumber];
    }
    
    return self;
}



- (void)dealloc
{
    

    
}



- (void)_findMaxDigitalNoteNumber
{
    NJNotebookReaderManager *reader = [NJNotebookReaderManager sharedInstance];
    
    NSArray *activieNotebookList = [reader totalNotebookList];
    NSArray *archivedNotebookList = [reader archivesNotebookList];
    
    NSArray *allNotebookList = [activieNotebookList arrayByAddingObjectsFromArray:archivedNotebookList];
    
    _curDigitalNoteId = kNOTEBOOK_ID_START_DIGITAL;
    
    for(int i=0; i < allNotebookList.count; i++) {
        
        NSUInteger noteId = [[allNotebookList objectAtIndex:i] integerValue];
        
        if(noteId < kNOTEBOOK_ID_START_DIGITAL) continue;
        
        if(noteId > _curDigitalNoteId)
            _curDigitalNoteId = noteId;
    }
    
    NSLog(@"NJNotebookInfoStore]]] current max notebook Id is %d",(int)_curDigitalNoteId);
}



- (NSString *)_getNotebookInfoPath:(NSUInteger)notebookId
{
    NJNotebookReaderManager *reader = [NJNotebookReaderManager sharedInstance];
    NSString *notebookPath = [reader notebookPathForId:notebookId];
    
    notebookPath = [notebookPath stringByAppendingPathComponent:kNOTEBOOK_INFO_FILE_NAME];
    return notebookPath;
}




- (NJNotebookInfo *)_readNotebookInfo:(NSUInteger)notebookId
{
    
    NSString* path = [self _getNotebookInfoPath:notebookId];
    
    NJNotebookInfo *noteInfo = nil;
    
	if ([[NSFileManager defaultManager] fileExistsAtPath:path])
	{
		NSData* data = [[NSData alloc] initWithContentsOfFile:path];
		NSKeyedUnarchiver* unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        
        noteInfo = [unarchiver decodeObjectForKey:kNOTEBOOK_INFO_KEY];
		[unarchiver finishDecoding];
        
    } else {

        
	}
    
    return noteInfo;
}



- (BOOL)_writeNotebookInfo:(NJNotebookInfo *)notebookInfo
{
    NSLog(@"Writing Notebook Info...");

    NSMutableData* data = [[NSMutableData alloc] init];
    
	NSKeyedArchiver* archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    
    [archiver encodeObject:notebookInfo forKey:kNOTEBOOK_INFO_KEY];
    [archiver finishEncoding];
    
    BOOL success = [data writeToFile:[self _getNotebookInfoPath:notebookInfo.notebookId] atomically:YES];

    // temporarily added
    
    NJNotebookReaderManager *reader = [NJNotebookReaderManager sharedInstance];
    
    BOOL result = [reader openNotebookInfoData:notebookInfo.notebookId];
    
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    
    reader.notebookDocument.notebook.title = notebookInfo.notebookTitle;
    reader.notebookDocument.notebook.cTime = notebookInfo.createdDate;
    reader.notebookDocument.notebook.mTime = notebookInfo.lastModifiedDate;
    
    [reader saveNotebook:notebookInfo.notebookId];
    
    return success;
}


- (NJNotebookInfo *)_createNotebookDefaultInfo:(NSUInteger)noteId shouldCreateNew:(BOOL)new
{
    
    NJNotebookInfo *noteInfo = [[NJNotebookInfo alloc] init];
    

    NSUInteger notebookId = noteId;
    
    if(new)
        notebookId = _curDigitalNoteId;
        
    noteInfo.notebookId = notebookId;
    noteInfo.createdDate = [NSDate date];
    noteInfo.lastModifiedDate = [NSDate date];
    
    if ([self _writeNotebookInfo:noteInfo] == NO)
        return nil;
    
    if(new)
        _curDigitalNoteId++;
    
    return noteInfo;
}




- (NJNotebookInfo *)createNewNotebookInfo
{
    
    return [self _createNotebookDefaultInfo:0 shouldCreateNew:YES];
}



- (NJNotebookInfo *)getNotebookInfo:(NSUInteger)notebookId
{
    
    if(notebookId <= 0 || notebookId > kMAX_NOTE_ID) return nil;
    
    
    NJNotebookInfo *noteInfo = [self _readNotebookInfo:notebookId];
    
    if(isEmpty(noteInfo))
        // file not exist at the moment so we create default one for user
        noteInfo = [self _createNotebookDefaultInfo:notebookId shouldCreateNew:NO];

    NJNotebookReaderManager *reader = [NJNotebookReaderManager sharedInstance];
    
    
    
    BOOL result = [reader openNotebookInfoData:notebookId];
    
    if (!result) {
        
        NSLog(@"notebook info reading fail");
    }
    
    
    //NSLog(@"I read from document ----> %@",reader.notebookDocument.notebook.title);
    noteInfo.notebookTitle = reader.notebookDocument.notebook.title;

    
    
    return noteInfo;
}



- (BOOL)updateNotebookInfo:(NJNotebookInfo *)notebookInfo
{

    if(isEmpty(notebookInfo)) return NO;
    if(notebookInfo.notebookId <= 0 || notebookInfo.notebookId > kMAX_NOTE_ID) return NO;
    
    
    return [self _writeNotebookInfo:notebookInfo];
    
}


//- updateNotebook:(NSUInteger)notebookId forTitle:(NSString *)string;




@end
