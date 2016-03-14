//
//  NJNotebookManager.h
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "configure.h"



@class NJPageDocument;
@class NJNotebook;
@class NJNotebookDocument;
@class NJNotebook;

typedef enum {
    kNotebookPageSortByName=0,
    kNotebookPageSortByDate,
} NotebookPageSortRule;

@interface NJNotebookManager : NSObject
@property (strong, nonatomic) NSMutableDictionary *notebookPages;
@property (strong, nonatomic) NSString *activeNotebookUuid;
@property (strong, nonatomic) NJPageDocument *activePageDocument;
@property (nonatomic) NSUInteger activeNoteBookId;
@property (nonatomic) NSUInteger activePageNumber;
@property (strong, nonatomic) NSArray *notebookList;
@property (strong, nonatomic) NSArray *digitalNotebookList;
@property (strong, nonatomic) NSArray *archivesNotebookList;
@property (strong, nonatomic) NSArray *totalNotebookList;
@property (nonatomic) BOOL documentOpend;
@property (nonatomic) BOOL newPage;
@property (nonatomic, strong) NJNotebook *notebook;
@property (nonatomic, strong) NJNotebookDocument * notebookDocument;
//Page related
- (NSString *) notebookPathForId:(NSUInteger) notebookId;
- (NSString *) pageNameFromNumber:(NSUInteger)number;
- (NSURL *) urlForName:(NSString *)name;
- (NSArray *) notebookPagesSortedBy:(NotebookPageSortRule)rule;
- (NSDictionary *) pageInfoForPageNumber:(NSUInteger) number;
- (void) activeNotebookIdDidChange:(NSUInteger)notebookId
                        withPageNumber:(NSUInteger)pageNumber;
- (BOOL) openNotebookInfoData:(NSUInteger)noteId;
- (void)removeAllObjectsFromChangedPages:(NSUInteger)nId;
- (void)setNotebookTitle:(NSString *)title;
- (void)setNotebookGuid:(NSString *)guid;
- (void)setNotebookCTime:(NSDate *)cTime;
- (void)setNotebookMTime:(NSDate *)mTime;
- (NSArray *) filterPages:(NSArray *)pages;
- (void)setNotebookArchivesLocked:(BOOL)locked nId:(NSUInteger)nId;
- (void)setNotebookArchivesTime:(NSDate *)aTime nId:(NSUInteger)nId;
- (void) syncSetActivePageNumber:(NSUInteger)activePageNumber;
-(void) syncReload;
- (NSDictionary *)notebookInfo:(NSUInteger)notebookId;
- (NSDate *) getCurrentTime;
- (void)setNotebookInit:(NSUInteger)nId;
- (void)setNotebookTitle:(NSString *)title nId:(NSUInteger)nId;
- (NSString *) convertNSDateToNSString:(NSDate *)time;
- (void)setNotebookImageName:(NSString *)imageName nId:(NSUInteger)nId;
- (void) setNotebookImage:(UIImage *)image index:(NSUInteger)index;
- (void) setImagefromAlbum:(BOOL)pickfromAlbum index:(NSUInteger)index;
- (void) setImagefromAlbumInitIndex:(NSUInteger)index;
- (BOOL)imageFromAlbumFlag:(NSUInteger)index;
- (UIImage *)imageFromAlbum:(NSUInteger)index;
- (NSUInteger) totalNotebookCount;

- (NSArray *)getPagesForNotebookId:(NSUInteger)notebookId;
- (NJPageDocument *) getPageDocument:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId;
- (NSString *)getPagePath:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId;
- (BOOL)checkIfNoteExists:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId;

- (void) saveNotebook:(NSUInteger)noteId;
- (void) openNotebook:(NSUInteger)noteId;

- (void) closeCurrentNotebook;
@end
