//
//  NJNotebookReaderManager.m
//  NeoJournal
//
//  Created by Ken on 14/02/2014.
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJPage.h"
#import "NJCommon.h"
#import "MyFunctions.h"
#import "NJPageDocument.h"
#import "NJNotebookReaderManager.h"

extern NSString *NJNoteBookPageExtension;

NSString * NJOneNoteBookCompleteNotification = @"NJOneNoteBookCompleteNotification";
@interface NJNotebookReaderManager()
@property (nonatomic, assign) NSUInteger bookIndex;
@property (nonatomic, assign) NSUInteger bookCount;
@property (nonatomic, assign) NSUInteger pageIndex;
@property (nonatomic, assign) NSUInteger pageCount;
@property (nonatomic, assign) NSUInteger noteType;
@end

@implementation NJNotebookReaderManager
+ (NJNotebookReaderManager *) sharedInstance
{
    static NJNotebookReaderManager *shared = nil;
    
    @synchronized(self) {
        if(!shared){
            shared = [[NJNotebookReaderManager alloc] init];
        }
    }
    
    return shared;
}

- (id) init
{
    self = [super init];
    if(!self) {
        return nil;
    }
     self.booksData = [NSMutableDictionary dictionary];
     self.pagesData = [NSMutableDictionary dictionary];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(initializeNextNotebookFromFile:) name:NJOneNoteBookCompleteNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(initialzePagesFromFile:) name:NJNoteBookPageDocumentOpenedNotification object:nil];
    
    return self;
}

- (void) syncOpenNotebook:(NSUInteger)notebookId withPageNumber:(NSUInteger)pageNumber
{
    if (self.activeNoteBookId == notebookId && self.activePageNumber == pageNumber) {
        return;
    }
    [self setActiveNoteBookId:notebookId];
    [self syncSetActivePageNumber:pageNumber];
}


- (void) initializeFromFile
{
    NSArray *bookList = [self notebookList];
    self.bookCount = [bookList count];
    if (self.bookCount <= 0) return;
    self.bookIndex = 0;
    [self initializeBooksFromFile:self.bookIndex];
}

- (void)initializeNextNotebookFromFile:(NSNotification *)notification
{
    
    self.bookIndex++;
    
    if (self.bookIndex >= self.bookCount) {

        return;
    }

    [self initializeBooksFromFile:self.bookIndex];

}

- (void) initializeBooksFromFile:(NSUInteger)index
{
    NSArray *bookList = [self notebookList];
    self.noteType = [bookList[self.bookIndex] integerValue];
    self.activeNoteBookId = self.noteType;
    
    NSArray *pages = [self notebookPagesSortedBy:kNotebookPageSortByName];
    self.pageCount = [pages count];
    self.pageIndex = 0;
    
    NSUInteger pageNumber = [pages[self.pageIndex] integerValue];
    self.activePageNumber = pageNumber;
}

- (void) initializeNextPagesFromFile:(NSUInteger)index
{
    
    NSArray *pages = [self notebookPagesSortedBy:kNotebookPageSortByName];
    self.pageCount = [pages count];
    self.pageIndex = index;
    
    NSUInteger pageNumber = [pages[self.pageIndex] integerValue];
    self.activePageNumber = pageNumber;
}

- (void) initialzePagesFromFile:(NSNotification *)notification
{
    NJPageDocument *document = ((NJNotebookReaderManager *)notification.object).activePageDocument;
    NJPage *page = document.page;

    [self.pagesData setObject:page forKey:[NSNumber numberWithInt:(int)self.activePageNumber]];

    
    self.pageIndex++;
    
    if (self.pageIndex >= self.pageCount) {
        NSMutableDictionary *pagesDataCopy = [self.pagesData copy];
        [self.booksData setObject:pagesDataCopy forKey:[NSNumber numberWithInt:(int)self.noteType]];
        [self.pagesData removeAllObjects];
        [[NSNotificationCenter defaultCenter] postNotificationName:NJOneNoteBookCompleteNotification object:nil userInfo:nil];
        return;
    }

    [self initializeNextPagesFromFile:self.pageIndex];

}





// following functions.. try to read image / page.data from specified path
// directly / synchronously read from the file

- (NJPage *)getPageData:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId
{
    NSString *pagePath = [self getPagePath:pageNum forNotebookId:notebookId];
    NSURL *pageUrl = [NSURL URLWithString:pagePath];
    NSString *dataPath = [pagePath stringByAppendingPathComponent:@"page.data"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:dataPath]) return nil;
    
    NJPage *aPage = [[NJPage alloc] initWithNotebookId:(int)notebookId andPageNumber:(int)pageNum];
    [aPage readFromURL:pageUrl error:NULL];
    
    if(!isEmpty(aPage) && !isEmpty(aPage.strokes))
        return aPage;
    
    return nil;
}

// return NSArray*
// 0 - UIImage *image
// 1 - NSDictionary *fileAttributes
- (NSArray *)getPageImage:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId imgSize:(BOOL)small
{
    NSString *pagePath = [self getPagePath:pageNum forNotebookId:notebookId];
    
    NSString *thumbPath = [pagePath stringByAppendingPathComponent:@"thumb.jpg"];
    NSString *imgPath = [pagePath stringByAppendingPathComponent:@"image.jpg"];
    
    UIImage *image = nil;
    NSDictionary *attributes = nil;
    
    
    NSString *firstCheck = thumbPath;
    NSString *secondCheck = imgPath;
    
    if(!small) {
        firstCheck = imgPath;
        secondCheck = thumbPath;
    }
    
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:firstCheck]) {
    
        image = [UIImage imageWithContentsOfFile:firstCheck];
        attributes = [fm attributesOfItemAtPath:firstCheck error:nil];
        
    } else {
        
        image = [UIImage imageWithContentsOfFile:secondCheck];
        attributes = [fm attributesOfItemAtPath:secondCheck error:nil];
        
    }
    
    if(isEmpty(image) || isEmpty(attributes)) return nil;
    
    NSArray *retArray = @[image,attributes];
    
    return retArray;
}


- (NSArray *)getLargeSizePageImage:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId
{
    return [self getPageImage:pageNum forNotebookId:notebookId imgSize:NO];

}

- (NSArray *)getSmallSizePageImage:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId
{
    
    return [self getPageImage:pageNum forNotebookId:notebookId imgSize:YES];
}
@end
