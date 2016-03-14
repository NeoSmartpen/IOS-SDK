//
//  NJNotebookReaderManager.h
//  NeoJournal
//
//  Created by Ken on 14/02/2014.
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJNotebookManager.h"

@class NJPage;
@interface NJNotebookReaderManager : NJNotebookManager

@property (nonatomic, strong) NSMutableDictionary *booksData;
@property (nonatomic, strong) NSMutableDictionary *pagesData;

+ (NJNotebookReaderManager *) sharedInstance;
- (void) initializeFromFile;

- (NJPage *)getPageData:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId;
- (NSArray *)getLargeSizePageImage:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId;
- (NSArray *)getSmallSizePageImage:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId;
@end
