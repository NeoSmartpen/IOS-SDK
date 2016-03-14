//
//  NJNotebookWriterManager.h
//  NeoJournal
//
//  Created by Ken on 14/02/2014.
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJNotebookManager.h"
#import "NJPageDocument.h"

@interface NJNotebookWriterManager : NJNotebookManager

+ (NJNotebookWriterManager *) sharedInstance;
- (void) saveCurrentPage;
- (void) saveCurrentPage:(BOOL)force withInitialCall:(BOOL)initial;
- (void) saveCurrentPage:(BOOL)force completionHandler:(void (^)(BOOL success))completionHandler;
- (void) saveEventlog:(BOOL)log andEvernote:(BOOL)evernote andLastStrokeTime:(NSDate *)lastStrokeTime;
- (void) syncOpenNotebook:(NSUInteger)notebookId withPageNumber:(NSUInteger)pageNumber;
- (void) syncOpenNotebook:(NSUInteger)notebookId withPageNumber:(NSUInteger)pageNumber saveNow:(BOOL)saveNow;

- (NSArray *) copyPages:(NSArray *)pageArray fromNotebook:(NSUInteger)fNotebookId toNotebook:(NSUInteger)tNotebookId;
- (NSArray *) deletePages:(NSArray *)pageArray fromNotebook:(NSUInteger)fNotebookId;

@end
