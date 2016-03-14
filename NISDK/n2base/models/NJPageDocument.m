//
//  NJDocument.m
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJPageDocument.h"
#import "NJPage.h"
#import "NJStroke.h"
#import "NJVoiceMemo.h"
#import "NJNode.h"
#import "NJNotebookReaderManager.h"
#import "NJNotebookPaperInfo.h"

extern NSString * NJPageStrokeAddedNotification;
NSString * NJPageChangedNotification = @"JNPageChangedNotification";

@interface NJPageDocument() {
    NSTimer *_autosavingTimer4Sync;
    dispatch_queue_t document_dispatch_queue;
}
@property (nonatomic) float page_x;
@property (nonatomic) float page_y;
@property (nonatomic) int notebookId;
@property (nonatomic) int pageNumber;
@property (nonatomic) int contentReadPosition;
@property (strong, nonatomic) NSData *contentData;

@end

@implementation NJPageDocument
@synthesize page = _page;

- (id) initWithFileURL:(NSURL *)url withBookId:(NSUInteger)bookId andPageNumber:(NSUInteger)pageNumber
{
    self = [super initWithFileURL:url];
    if(!self) {
        return nil;
    }
    self.paperInfo = [NJNotebookPaperInfo sharedInstance];
    [self.paperInfo getPaperDotcodeRangeForNotebook:(int)bookId PageNumber:(int)pageNumber Xmax:&_page_x Ymax:&_page_y];
    self.notebookId = (int)bookId;
    self.pageNumber = (int)pageNumber;
    self.contentData = nil;
    _autosavingTimer4Sync = nil;
    document_dispatch_queue = dispatch_queue_create("document_dispatch_queue", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void) setPage:(NJPage *)page
{
    if (_page) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NJPageChangedNotification object:_page];
    }
    _page = page;
    if (_page) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(strokeAdded:) name:NJPageChangedNotification object:_page];
    }
}

- (void) strokeAdded:(NSNotification *)notification
{
    NSLog(@"strokeAdded");
#ifdef OPEN_NOTEBOOK_SYNC_MODE
#define AUTOSAVE_TIMER_INTERVAL 10.0f
    if (_autosavingTimer4Sync == nil) {
        _autosavingTimer4Sync = [NSTimer timerWithTimeInterval:AUTOSAVE_TIMER_INTERVAL target:self
                                                      selector:@selector(autoSave4SyncMode:) userInfo:nil repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:_autosavingTimer4Sync forMode:NSDefaultRunLoopMode];
    }
#else
    // to initiate auto-save.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self savePresentedItemChangesWithCompletionHandler:nil];
    });
#endif
}

#ifdef OPEN_NOTEBOOK_SYNC_MODE
- (void)autoSave4SyncMode:(NSTimer *)timer
{
    [self removeAutosaveTimer];
    [self autosaveInBackground];
}

- (void) removeAutosaveTimer
{
    [_autosavingTimer4Sync invalidate];
    _autosavingTimer4Sync = nil;
}
- (void) dealloc
{
    [self removeAutosaveTimer];
}
#endif

- (void) autosaveInBackground
{
    if (self.fileURL == nil) {
        return;
    }
    [self pageSaveToURL:self.fileURL forSaveOperation:UIDocumentSaveForOverwriting completionHandler:nil];
    
}
#define FILE_VERSION 1
- (BOOL) readFromURL:(NSURL *)url error:(NSError *__autoreleasing *)outError
{
    self.page = [[NJPage alloc] initWithNotebookId:self.notebookId andPageNumber:self.pageNumber];

    return [self.page readFromURL:url error:outError];
}

- (void) pageSaveToURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation completionHandler:(void (^)(BOOL))completionHandler
{
    #ifdef OPEN_NOTEBOOK_SYNC_MODE
    [self removeAutosaveTimer];
    #endif
    dispatch_async(document_dispatch_queue, ^{
        if ([self.page saveToURL:url]) {
            
            NSDictionary *info = @{@"notebookId":[NSNumber numberWithInteger:self.page.notebookId],@"page":[NSNumber numberWithInteger:self.page.pageNumber]};
            [[NSNotificationCenter defaultCenter] postNotificationName:NJPageStrokeAddedNotification object:nil userInfo:info];
        }
    });

}


- (void)forceDocumentSavingShouldCreating:(BOOL)create completionHandler:(void (^)(BOOL success))completionHandler
{
    dispatch_async(document_dispatch_queue, ^{
        if(create) self.page.pageHasChanged = YES;
        BOOL success = [self.page saveToURL:self.fileURL];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if(completionHandler)
                completionHandler(success);
            if(success) {

            }
        });
    });
    
}

- (void)saveToURLNow
{
    self.page.pageHasChanged = YES;
    [self.page saveToURL:self.fileURL];
}

@end
