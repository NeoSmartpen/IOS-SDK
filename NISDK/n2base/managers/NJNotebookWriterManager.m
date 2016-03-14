//
//  NJNotebookWriterManager.m
//  NeoJournal
//
//  Created by Ken on 14/02/2014.
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJNotebookWriterManager.h"
#import "NJNotebookReaderManager.h"
#import "NJPageDocument.h"
#import "NJNotebookIdStore.h"

extern NSString *NJNoteBookPageExtension;



@implementation NJNotebookWriterManager
+ (NJNotebookWriterManager *) sharedInstance
{
    static NJNotebookWriterManager *shared = nil;
    
    @synchronized(self) {
        if(!shared){
            shared = [[NJNotebookWriterManager alloc] init];
        }
    }
    
    return shared;
}

- (void) saveCurrentPage
{
    
    [self saveCurrentPageWithEventlog:NO andEvernote:NO andLastStrokeTime:nil];
}
- (void) saveCurrentPageWithEventlog:(BOOL)log andEvernote:(BOOL)evernote andLastStrokeTime:(NSDate *)lastStrokeTime
{
    [self saveCurrentPage:YES completionHandler:nil];
}
- (void) saveEventlog:(BOOL)log andEvernote:(BOOL)evernote andLastStrokeTime:(NSDate *)lastStrokeTime
{
    
}
- (void) saveCurrentPage:(BOOL)force completionHandler:(void (^)(BOOL))completionHandler
{
    [self saveCurrentPage:force shouldCreating:NO completionHandler:completionHandler];
}
- (void) saveCurrentPage:(BOOL)force shouldCreating:(BOOL)create completionHandler:(void (^)(BOOL))completionHandler
{
    if(isEmpty(self.activePageDocument)) {
        if(completionHandler)
            completionHandler(NO);
        return;
    }
    if(force)
        [self.activePageDocument forceDocumentSavingShouldCreating:create completionHandler:completionHandler];
    else
        [self.activePageDocument autosaveInBackground];
}

- (void) savePagesData
{
    NSMutableDictionary *booksData = [[NJNotebookReaderManager sharedInstance] booksData];
    NSMutableDictionary *pagesData;
    
    NJPage *page = self.activePageDocument.page;
    
    if (![[booksData allKeys] containsObject:[NSNumber numberWithInt:(int)self.activeNoteBookId]]) {
        pagesData = [NSMutableDictionary dictionary];
        [pagesData setObject:page forKey:[NSNumber numberWithInt:(int)self.activePageNumber]];
        [booksData setObject:pagesData forKey:[NSNumber numberWithInt:(int)self.activeNoteBookId]];
    } else {
        pagesData = [[booksData objectForKey:[NSNumber numberWithInt:(int)self.activeNoteBookId]] mutableCopy];
        [pagesData setObject:page forKey:[NSNumber numberWithInt:(int)self.activePageNumber]];
        [booksData setObject:pagesData forKey:[NSNumber numberWithInt:(int)self.activeNoteBookId]];
    }
    NSLog(@"booksData %@",booksData);
}
- (void) activeNotebookIdDidChange:(NSUInteger)notebookId withPageNumber:(NSUInteger)pageNumber
{
#ifdef OPEN_NOTEBOOK_SYNC_MODE
    [self syncOpenNotebook:notebookId withPageNumber:pageNumber];
#else
    [super activeNotebookIdDidChange:notebookId withPageNumber:pageNumber];
#endif
}
- (void) syncOpenNotebook:(NSUInteger)notebookId withPageNumber:(NSUInteger)pageNumber
{
    [self syncOpenNotebook:notebookId withPageNumber:pageNumber saveNow:NO];
}
- (void) syncOpenNotebook:(NSUInteger)notebookId withPageNumber:(NSUInteger)pageNumber saveNow:(BOOL)saveNow
{
    if (self.activeNoteBookId == notebookId && self.activePageNumber == pageNumber) {
        return;
    }
    if (saveNow) {
        [self.activePageDocument saveToURLNow];
    }
    else
        [self saveCurrentPage];
    [self setActiveNoteBookId:notebookId];
    // 06-Oct-2014 by namSSan currently writer only accessed by penCommManager so pen does not need note uuid.
    // just set it as current activie Uuid
    self.activeNotebookUuid = [[[NJNotebookIdStore sharedStore] notebookIdName:notebookId] copy];
    [self syncSetActivePageNumber:pageNumber];
}

- (NSArray *) copyPages:(NSArray *)pageArray fromNotebook:(NSUInteger)fNotebookId toNotebook:(NSUInteger)tNotebookId
{
    return nil;
}



- (NSArray *) deletePages:(NSArray *)pageArray fromNotebook:(NSUInteger)notebookId
{
    return nil;
}


- (BOOL)_deletePageName:(NSString *)pageName forNotebookId:(NSUInteger)notebookId
{
    return YES;
}


@end
