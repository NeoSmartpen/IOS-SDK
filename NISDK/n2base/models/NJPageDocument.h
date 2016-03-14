//
//  NJDocument.h
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NJPage.h"

#define OPEN_NOTEBOOK_SYNC_MODE

@class NJNotebookPaperInfo;
@interface NJPageDocument : UIDocument
@property (strong, nonatomic) NJPage *page;
@property (strong, nonatomic) NJNotebookPaperInfo *paperInfo;

- (void) strokeAdded:(NSNotification *)notification;
- (id) initWithFileURL:(NSURL *)url withBookId:(NSUInteger)bookId andPageNumber:(NSUInteger)pageNumber;
- (void) autosaveInBackground;
- (void) pageSaveToURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation completionHandler:(void (^)(BOOL))completionHandler;

- (void)forceDocumentSavingShouldCreating:(BOOL)create completionHandler:(void (^)(BOOL success))completionHandler;
- (void)saveToURLNow;
@end
