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
//@property (nonatomic) NSUInteger activePageNumber;
//@property (strong, nonatomic) NJPageDocument *activePageDocument;

+ (NJNotebookWriterManager *) sharedInstance;
- (void) saveCurrentPage;
- (void) saveCurrentPage:(BOOL)force withInitialCall:(BOOL)initial;
- (void) syncOpenNotebook:(NSUInteger)notebookId withPageNumber:(NSUInteger)pageNumber;

- (NSArray *) copyPages:(NSArray *)pageArray fromNotebook:(NSUInteger)fNotebookId toNotebook:(NSUInteger)tNotebookId;
- (NSArray *) deletePages:(NSArray *)pageArray fromNotebook:(NSUInteger)fNotebookId;

@end
