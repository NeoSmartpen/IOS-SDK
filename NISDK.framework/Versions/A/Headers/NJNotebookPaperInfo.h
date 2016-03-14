//
//  NJNotebookPaperInfo.h
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NJNotebookPaperInfo : NSObject
@property (nonatomic) int noteListLength;
+ (NJNotebookPaperInfo *) sharedInstance;
- (BOOL) hasInfoForNotebookId:(int)notebookId;
- (BOOL) getPaperDotcodeRangeForNotebook:(int)notebookId Xmax:(float *)x Ymax:(float *)y;
- (BOOL) getPaperDotcodeStartForNotebook:(int)notebookId startX:(float *)x startY:(float *)y;

/* Deprecated : This function should not be used. BG has been replaced by dpf. */
- (NSString *) backgroundImageNameForNotebook:(int)notebookId atPage:(int)pageNumber;
- (UInt32) noteIdAt:(int)index;
- (UInt32) sectionOwnerIdAt:(int)index;
- (NSArray *) notesSupported;
/* Return background pdf file name. */
- (NSString *) backgroundFileNameForSection:(int)section owner:(UInt32)onwerId note:(UInt32)noteId;\
/* Return difference in page number between pdf and note. */
- (int) pdfPageOffsetForSection:(int)sectionId owner:(UInt32)onwerId note:(UInt32)noteId;
@end
