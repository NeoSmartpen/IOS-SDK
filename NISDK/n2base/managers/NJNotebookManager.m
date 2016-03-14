//
//  NJNotebookManager.m
//  NeoJournal
//
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import "NJNotebookManager.h"
#import "NJPageDocument.h"
#import "NJNotebookDocument.h"
#import "NJNotebook.h"
#import "NJNotebookIdStore.h"
#import "configure.h"
#import "NJCommon.h"



#import <Foundation/NSSortDescriptor.h>

#define PAGE_NUMBER_MAX 9999

#define NOTEBOOK_DATA_FILE

NSString *NJNoteBookExtension = @"notebook_store";
NSString *NJNoteBookPageExtension = @"page_store";
NSString * NJPageChangeNotification = @"NJPageChangeNotification";
NSString * NJPageStrokeAddedNotification = @"NJPageStrokeAddedNotification";

@interface NJNotebookManager (Private)
- (void) createDefaultDirectories_;
@end

@interface NJNotebookManager()

@end
@implementation NJNotebookManager
@synthesize activePageDocument = _activePageDocument;

- (id) init
{
    self = [super init];
    if(!self) {
        return nil;
    }
    [self createDefaultDirectories_];
    self.documentOpend=NO;    

    self.activeNoteBookId = 898;
    self.activePageNumber = 0;
    self.newPage = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addedChangedPage:) name:NJPageStrokeAddedNotification object:nil];
    return self;
}
- (void) setActiveNoteBookId:(NSUInteger)activeNoteBookId
{
    if ((_activeNoteBookId == activeNoteBookId) && (self.newPage == NO)){
        return;
    }
    self.newPage = NO;
    [self closeActiveDocument];
    _activePageNumber = -1;
    _activeNoteBookId = activeNoteBookId;
    // load pages in notebook directory
    NSFileManager *fm = [NSFileManager defaultManager];
    // Find folders for pages. Actual paths look like below for notebook id 10.
    // ..../Documents/NeoNoteBooks/00010.notebook_store/0000.page_store/
    // ..../Documents/NeoNoteBooks/00010.notebook_store/0001.page_store/
    NSArray *pageFiles = [fm contentsOfDirectoryAtPath:[self notebookPath] error:NULL];
    
    pageFiles = [self filterPages:pageFiles];
    //pageFiles looks like ["0000", "0001".....]
    [self.notebookPages removeAllObjects];
    for (NSString *pageName in pageFiles){
        NSDictionary *pageInfo = [self pageInfoForPageName:pageName];
        [self.notebookPages setObject:pageInfo
                               forKey:[NSNumber numberWithInt:[pageName intValue]]];
    }
}
- (void) setActivePageNumber:(NSUInteger)activePageNumber
{
    if (_activePageNumber == activePageNumber) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NJNoteBookPageDocumentOpenedNotification object:self userInfo:nil];
        return;
    }
    NJPageDocument *pageDocument = [self pageDocumentAtNumber:activePageNumber];
    self.activePageDocument = pageDocument;
    _activePageNumber=activePageNumber;
}
- (NSArray *) notebookList
{
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSArray * list = [fm contentsOfDirectoryAtPath:[self bookshelfPath] error:NULL];
    list = [self filterNotebooks:list];
    
    NSArray * dList = [fm contentsOfDirectoryAtPath:[self digitalBookshelfPath] error:NULL];
    dList = [self filterNotebooks:dList];
    if ([dList count]) {
        list = [list arrayByAddingObjectsFromArray:dList];
    }
    
    return list;
}
- (NSArray *) digitalNotebookList
{
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSArray * list = [fm contentsOfDirectoryAtPath:[self digitalBookshelfPath] error:NULL];
    list = [self filterNotebooks:list];
    
    return list;
}
- (NSArray *) totalNotebookList
{
    NSArray *list = [self notebookList];
    NSArray *dList = [self digitalNotebookList];
    NSArray *mergedNotebookList = [list arrayByAddingObjectsFromArray:dList];
    
    return mergedNotebookList;
}
- (NSUInteger) totalNotebookCount
{
    NSUInteger notebookCount = [[self notebookList] count];
    NSUInteger digitalNotebookCount = [[self digitalNotebookList] count];
    
    return notebookCount + digitalNotebookCount;
}
- (NSMutableDictionary *) notebookPages
{
    if (_notebookPages == nil) {
        _notebookPages = [[NSMutableDictionary alloc] init];
    }
    return _notebookPages;
}
- (void) activeNotebookIdDidChange:(NSUInteger)notebookId withPageNumber:(NSUInteger)pageNumber
{
    if (self.activeNoteBookId == notebookId && self.activePageNumber == pageNumber) {
        return;
    }
    [self setActiveNoteBookId:notebookId];
    [self setActivePageNumber:pageNumber];
}

#pragma mark - Page Document
- (NJPageDocument *) activePageDocument
{
    if (_activePageDocument == nil) {
        // TODO : temporary implemented to return page 0 document.
        // Need to implement UI for no page saved state.
        NJPageDocument *doc = [self pageDocumentAtNumber:15];
        self.activePageDocument = doc;
        //return nil;
    }
    return _activePageDocument;
}

- (void) setActivePageDocument:(NJPageDocument *)activePageDocument
{
    if (_activePageDocument != activePageDocument) {
        [self closeActiveDocument];
        _activePageDocument.page = nil;  // To remove notification
        _activePageDocument = activePageDocument;
        self.documentOpend=NO;
        [_activePageDocument openWithCompletionHandler:^(BOOL success) {
            if (success) {
                if (_activePageDocument.page != nil) {
                    self.documentOpend=YES;
                    [[NSNotificationCenter defaultCenter] postNotificationName:NJNoteBookPageDocumentOpenedNotification object:self userInfo:nil];
                    NSLog(@"open document success");
                }
            }
            else {
                self.documentOpend=NO;
                NSLog(@"open document fail");
            }
        }];
    }
}
- (void) syncSetActivePageNumber:(NSUInteger)activePageNumber
{
    if (_activePageNumber == activePageNumber) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NJNoteBookPageDocumentOpenedNotification object:self userInfo:nil];
        return;
    }
    NJPageDocument *pageDocument = [self pageDocumentAtNumber:activePageNumber];
    _activePageNumber=activePageNumber;
    [self syncSetActivePageDocument :pageDocument];
}
- (void) syncSetActivePageDocument:(NJPageDocument *)activePageDocument
{
    if (_activePageDocument != activePageDocument) {
        [self closeActiveDocument];
        _activePageDocument.page = nil;  // To remove notification
        _activePageDocument = activePageDocument;
        NSString *name = [self pageNameFromNumber:self.activePageNumber];
        if (!name) return;
        NSURL *url = [self urlForName:name];
        [_activePageDocument readFromURL:url error:NULL];
        if (_activePageDocument.page != nil) {
            self.documentOpend=YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:NJNoteBookPageDocumentOpenedNotification object:self userInfo:nil];
            NSLog(@"open document success synchronously");
        }
    }
    
}
-(void) syncReload
{
    NSUInteger pageNumber = _activePageNumber;
    _activePageNumber = 0;
    _activePageDocument = nil;
    [self syncSetActivePageNumber:pageNumber];
}

- (void) closeActiveDocument
{
    if(_activePageDocument) {
        [_activePageDocument closeWithCompletionHandler:nil];
        _activePageDocument = nil;
        self.documentOpend=NO;
    }
}
-(void)closeCurrentNotebook
{
    [self closeActiveDocument];
    _activeNoteBookId = -1;
    _activePageNumber = -1;
    _activeNotebookUuid = nil;
}
#pragma mark - File path related
- (NSString *) documentDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDirectory = paths[0];
    return documentDirectory;
}

- (NSString *) bookshelfPath
{
    NSString *bookshelfPath = [[self documentDirectory] stringByAppendingPathComponent:@"NeoNoteBooks"];
    return bookshelfPath;
}

- (NSString *) digitalBookshelfPath
{
    NSString *bookshelfPath = [[self documentDirectory] stringByAppendingPathComponent:@"NeoDigitalNoteBooks"];
    return bookshelfPath;
}

- (NSString *) notebookPathForUuid:(NSString *)uuid
{
    NSString *notebookPath=[[self bookshelfPath] stringByAppendingPathComponent:uuid];
    return notebookPath;
}

// ---> have to change notebookPathForNoteType // physical notes only
- (NSString *) notebookPathForId:(NSUInteger) notebookId
{
    NSString *notebookPath;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSString *notebookIdName = [[NSString stringWithFormat:@"%05d", (int)notebookId] stringByAppendingPathExtension:NJNoteBookExtension];
    
    if (notebookId >= kNOTEBOOK_ID_START_DIGITAL) {

        notebookPath=[[self digitalBookshelfPath] stringByAppendingPathComponent:notebookIdName];

        if(![fm fileExistsAtPath:notebookPath]) {
            [fm createDirectoryAtPath:notebookPath withIntermediateDirectories:NO attributes:nil error:NULL];
        }
    } else {
        notebookPath=[[self bookshelfPath] stringByAppendingPathComponent:notebookIdName];
    }
    return notebookPath;
}


// ---> have to change notebookPathForNoteID
- (NSString *) notebookPathForUUID:(NSString *) uuid
{
    NSString *notebookPath;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSString *notebookIdName = [[NSString stringWithFormat:@"%@",uuid] stringByAppendingPathExtension:NJNoteBookExtension];
    
    if ([NJNotebookIdStore isDigitalNote:uuid])
        notebookPath=[[self digitalBookshelfPath] stringByAppendingPathComponent:notebookIdName];
    else
        notebookPath=[[self bookshelfPath] stringByAppendingPathComponent:notebookIdName];
    
    if(![fm fileExistsAtPath:notebookPath])
        [fm createDirectoryAtPath:notebookPath withIntermediateDirectories:NO attributes:nil error:NULL];
    
    return notebookPath;
}


- (NSString *) notebookPath
{
    NSString *notebookPath = [self notebookPathForId:self.activeNoteBookId];
    return notebookPath;
}

- (NSArray *) filterPages:(NSArray *)pages
{
    NSMutableArray *filtered = [[NSMutableArray alloc] init];
    
    for(NSString *page in pages) {
        if([[page pathExtension] compare:NJNoteBookPageExtension
                                 options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            [filtered addObject:[page stringByDeletingPathExtension]];
        }
    }
    return filtered;
}

- (NSArray *) filterNotebooks:(NSArray *)notebookList
{
    NSMutableArray *filtered = [[NSMutableArray alloc] init];
    
    for(NSString *notebook in notebookList) {
        if([[notebook pathExtension] compare:NJNoteBookExtension
                                 options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            
            NSString *notebookId = [notebook stringByDeletingPathExtension];
            NSCharacterSet* nonNumbers = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            NSRange r = [notebookId rangeOfCharacterFromSet: nonNumbers];
            
            if(r.location == NSNotFound)
                [filtered addObject:notebookId];
        }
    }
    return filtered;
}


- (NSString *) pathForName:(NSString *)name;
{
    NSString *path = [[[self notebookPath] stringByAppendingPathComponent:name] stringByAppendingPathExtension:NJNoteBookPageExtension];
    
    return path;
}

- (NSURL *) urlForName:(NSString *)name
{
    NSURL *url = [NSURL fileURLWithPath:[self pathForName:name]];
    
    return url;
}


#pragma mark - Page information
- (NSString *) pageNameFromNumber:(NSUInteger)number
{
    if (number > PAGE_NUMBER_MAX) {
        return nil;
    }
    return [NSString stringWithFormat:@"%04d", (int)number];
}

- (NSArray *)getPagesForNotebookId:(NSUInteger)notebookId
{
    
    NSArray * pages;
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *notebookPath = [self notebookPathForId:notebookId];
    
    pages = [fm contentsOfDirectoryAtPath:notebookPath error:NULL];
    NSArray *fiteredPages = [self filterPages:pages];
    
    NSSortDescriptor *sd = [[NSSortDescriptor alloc] initWithKey:nil ascending:YES];
    NSArray *sortedPages = [fiteredPages sortedArrayUsingDescriptors:@[sd]];
    
    return sortedPages;
}
- (NSString *)getPagePath:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId
{
    
    NSString *notebookPath = [self notebookPathForId:notebookId];
    
    NSString *pageName = [self pageNameFromNumber:pageNum];
    NSString *pagePath = [[notebookPath stringByAppendingPathComponent:pageName] stringByAppendingPathExtension:NJNoteBookPageExtension];
    
    return pagePath;
}
- (NJPageDocument *)getPageDocument:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId
{
    
    NSString *pagePath = [self getPagePath:pageNum forNotebookId:notebookId];
    NSURL *pageUrl = [NSURL fileURLWithPath:pagePath];
    
    NJPageDocument *doc = [[NJPageDocument alloc] initWithFileURL:pageUrl withBookId:notebookId andPageNumber:pageNum];
    
    return doc;
    
}
- (BOOL)checkIfNoteExists:(NSUInteger)pageNum forNotebookId:(NSUInteger)notebookId
{
    
    NSString *pagePath = [self getPagePath:pageNum forNotebookId:notebookId];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSString *dataPath = [pagePath stringByAppendingPathComponent:@"page.data"];
    NSString *thumbPath = [pagePath stringByAppendingPathComponent:@"thumb.jpg"];
    NSString *imgPath = [pagePath stringByAppendingPathComponent:@"image.jpg"];
    
    if (![fm fileExistsAtPath:dataPath] || ![fm fileExistsAtPath:thumbPath] || ![fm fileExistsAtPath:imgPath]) return NO;
    
    return YES;
}

- (void)setNotebookInit:(NSUInteger)nId
{
#ifdef NOTEBOOK_DATA_FILE
    BOOL result = [self openNotebookInfoData:nId];
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    self.notebook = [[NJNotebook alloc] initWithNoteId:nId];
    
    self.notebookDocument.notebook = self.notebook;
    
    [self saveNotebook:nId];
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger notebookId = nId;
    
    NSString *notebookIdName = [NSString stringWithFormat:@"%d", (int)notebookId];
    NSString *notebookTitle = title;
    NSDate *notebookCTime = cTime;
    NSDate *notebookMTime = mTime;
    NSString *notebookImageName = imageName;
    NSNumber *nLocked = [NSNumber numberWithBool:NO];
    NSDate *notebookATime = mTime;
    
    NSDictionary *writeNotebookDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       notebookTitle, @"title", notebookCTime, @"cTime", notebookMTime, @"mTime"
                                       ,notebookImageName, @"image", nLocked, @"nLocked",notebookATime, @"aTime", nil];
    [defaults setObject:writeNotebookDict forKey:notebookIdName];
    [defaults synchronize];
    
    
#endif
}

- (void)setNotebookTitle:(NSString *)title nId:(NSUInteger)nId
{
#ifdef NOTEBOOK_DATA_FILE
    BOOL result = [self openNotebookInfoData:nId];
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    self.notebookDocument.notebook.title = title;
    [self saveNotebook:nId];
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger notebookId = nId;
    
    NSString *notebookIdName = [NSString stringWithFormat:@"%d", (int)notebookId];
    NSDictionary *readNotebookDict = [defaults objectForKey:notebookIdName];
    NSString *notebookTitle = title;
    NSDate *notebookCTime = [readNotebookDict objectForKey:@"cTime"];
    NSDate *notebookMTime = [readNotebookDict objectForKey:@"mTime"];
    NSString *notebookImageName = [readNotebookDict objectForKey:@"image"];
    NSNumber *nLocked = [readNotebookDict objectForKey:@"nLocked"];
    NSDate *notebookATime = [readNotebookDict objectForKey:@"aTime"];
    
    NSDictionary *writeNotebookDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       notebookTitle, @"title", notebookCTime, @"cTime", notebookMTime, @"mTime",notebookImageName, @"image", nLocked, @"nLocked",notebookATime, @"aTime", nil];
    [defaults setObject:writeNotebookDict forKey:notebookIdName];
    [defaults synchronize];
#endif
    
    
}

- (void)setNotebookTitle:(NSString *)title
{
#ifdef NOTEBOOK_DATA_FILE
    BOOL result = [self openNotebookInfoData:self.activeNoteBookId];
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    self.notebookDocument.notebook.title = title;
    [self saveNotebook:self.activeNoteBookId];
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger notebookId = self.activeNoteBookId;
    
    NSString *notebookIdName = [NSString stringWithFormat:@"%d", (int)notebookId];
    NSDictionary *readNotebookDict = [defaults objectForKey:notebookIdName];
    NSString *notebookTitle = title;
    NSDate *notebookCTime = [readNotebookDict objectForKey:@"cTime"];
    NSDate *notebookMTime = [readNotebookDict objectForKey:@"mTime"];
    NSString *notebookImageName = [readNotebookDict objectForKey:@"image"];
    NSNumber *nLocked = [readNotebookDict objectForKey:@"nLocked"];
    NSDate *notebookATime = [readNotebookDict objectForKey:@"aTime"];
    
    NSDictionary *writeNotebookDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       notebookTitle, @"title", notebookCTime, @"cTime", notebookMTime, @"mTime",notebookImageName, @"image", nLocked, @"nLocked",notebookATime, @"aTime", nil];
    [defaults setObject:writeNotebookDict forKey:notebookIdName];
    [defaults synchronize];
#endif
    
}

- (void)setNotebookGuid:(NSString *)guid
{
    BOOL result = [self openNotebookInfoData:self.activeNoteBookId];
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    self.notebookDocument.notebook.guid = guid;
    [self saveNotebook:self.activeNoteBookId];
    
}

- (void)setNotebookCTime:(NSDate *)cTime
{
#ifdef NOTEBOOK_DATA_FILE
    
    BOOL result = [self openNotebookInfoData:self.activeNoteBookId];
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    self.notebookDocument.notebook.cTime = cTime;
    [self saveNotebook:self.activeNoteBookId];
    
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger notebookId = self.activeNoteBookId;
    
    NSString *notebookIdName = [NSString stringWithFormat:@"%d", (int)notebookId];
    NSDictionary *readNotebookDict = [defaults objectForKey:notebookIdName];
    NSString *notebookTitle = [readNotebookDict objectForKey:@"title"];
    NSDate *notebookCTime = cTime;
    NSDate *notebookMTime = cTime;
    NSString *notebookImageName = [readNotebookDict objectForKey:@"image"];
    NSNumber *nLocked = [readNotebookDict objectForKey:@"nLocked"];
    NSDate *notebookATime = [readNotebookDict objectForKey:@"aTime"];
    
    NSDictionary *writeNotebookDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       notebookTitle, @"title", notebookCTime, @"cTime", notebookMTime, @"mTime",notebookImageName, @"image", nLocked, @"nLocked",notebookATime, @"aTime", nil];
    [defaults setObject:writeNotebookDict forKey:notebookIdName];
    [defaults synchronize];
#endif
}

- (void)setNotebookMTime:(NSDate *)mTime
{
#ifdef NOTEBOOK_DATA_FILE
    BOOL result = [self openNotebookInfoData:self.activeNoteBookId];
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    self.notebookDocument.notebook.mTime = mTime;
    [self saveNotebook:self.activeNoteBookId];
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger notebookId = self.activeNoteBookId;
    
    NSString *notebookIdName = [NSString stringWithFormat:@"%d", (int)notebookId];
    NSDictionary *readNotebookDict = [defaults objectForKey:notebookIdName];
    NSString *notebookTitle = [readNotebookDict objectForKey:@"title"];;
    NSDate *notebookCTime = [readNotebookDict objectForKey:@"cTime"];
    NSDate *notebookMTime = mTime;
    NSString *notebookImageName = [readNotebookDict objectForKey:@"image"];
    NSNumber *nLocked = [readNotebookDict objectForKey:@"nLocked"];
    NSDate *notebookATime = [readNotebookDict objectForKey:@"aTime"];
    
    NSDictionary *writeNotebookDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       notebookTitle, @"title", notebookCTime, @"cTime", notebookMTime, @"mTime",notebookImageName, @"image", nLocked, @"nLocked",notebookATime, @"aTime", nil];
    [defaults setObject:writeNotebookDict forKey:notebookIdName];
    [defaults synchronize];
#endif
}

- (void)setNotebookImageName:(NSString *)imageName nId:(NSUInteger)nId
{
#ifdef NOTEBOOK_DATA_FILE
    BOOL result = [self openNotebookInfoData:nId];
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    self.notebookDocument.notebook.imageName = imageName;
    [self saveNotebook:nId];
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger notebookId = nId;
    
    NSString *notebookIdName = [NSString stringWithFormat:@"%d", (int)notebookId];
    NSDictionary *readNotebookDict = [defaults objectForKey:notebookIdName];
    NSString *notebookTitle = [readNotebookDict objectForKey:@"title"];;
    NSDate *notebookCTime = [readNotebookDict objectForKey:@"cTime"];
    NSDate *notebookMTime = [readNotebookDict objectForKey:@"mTime"];;
    NSString *notebookImageName = imageName;
    NSNumber *nLocked = [readNotebookDict objectForKey:@"nLocked"];
    NSDate *notebookATime = [readNotebookDict objectForKey:@"aTime"];
    
    NSDictionary *writeNotebookDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       notebookTitle, @"title", notebookCTime, @"cTime", notebookMTime, @"mTime",notebookImageName, @"image", nLocked, @"nLocked",notebookATime, @"aTime", nil];
    [defaults setObject:writeNotebookDict forKey:notebookIdName];
    [defaults synchronize];
#endif
}


- (NSDictionary *)notebookInfo:(NSUInteger)notebookId
{
#ifdef NOTEBOOK_DATA_FILE
    BOOL result = [self openNotebookInfoData:notebookId];
    
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    
    NSString *notebookPathForId = [self notebookPathForId:notebookId];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:notebookPathForId]) {
        [self setNotebookInit:notebookId];
    }
    
    NSString *notebookTitle = self.notebook.title;
    NSDate *notebookCTime = self.notebook.cTime;
    NSDate *notebookMTime = self.notebook.mTime;
    NSString *notebookImageName = self.notebook.imageName;
    NSNumber *nLocked = [NSNumber numberWithBool:1];
    NSDate *notebookATime = self.notebook.aTime;
    NSString *notebookGuid = self.notebook.guid;
    
    NSDictionary *writeNotebookDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       notebookTitle, @"title", notebookCTime, @"cTime", notebookMTime, @"mTime",notebookImageName, @"image", nLocked, @"nLocked",notebookATime, @"aTime",
                                       notebookGuid, @"guid",nil];
    
    
    return writeNotebookDict;
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSString *notebookIdName = [NSString stringWithFormat:@"%d", (int)notebookId];
    NSDictionary *readNotebookDict = [defaults objectForKey:notebookIdName];
    return readNotebookDict;
#endif
}

- (NSDate *) getCurrentTime
{
    NSDate* sourceDate = [NSDate date];

    return sourceDate;
}

- (NSString *) convertNSDateToNSString:(NSDate *)time
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"dd MMM yyyy"];
    NSString *strDate = [dateFormatter stringFromDate:time];
    return strDate;
}

- (void) setNotebookImage:(UIImage *)image index:(NSUInteger)index
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger noteIndex = index;
    
    
    NSString *notebookIndexName = [NSString stringWithFormat:@"%03d", (int)noteIndex];
    UIImage *resizedImage = [self createThumbnailImage:image];
    UIImage *notebookImage = resizedImage;
    NSData *imageData = UIImageJPEGRepresentation(notebookImage, 1.0);
    
    [defaults setObject:imageData forKey:notebookIndexName];
    [defaults synchronize];
    
}

- (void) setImagefromAlbum:(BOOL)pickfromAlbum index:(NSUInteger)index
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger noteIndex = index;
    
    NSString *notebookIndexName = [NSString stringWithFormat:@"%02d", (int)noteIndex];
    
    BOOL imageFromAlbum = pickfromAlbum;
    
    [defaults setBool:imageFromAlbum forKey:notebookIndexName];
    [defaults synchronize];
    
}

- (void) setImagefromAlbumInitIndex:(NSUInteger)index
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger noteIndex = index;
    
    NSString *notebookIndexName = [NSString stringWithFormat:@"%02d", (int)noteIndex];
    
    BOOL imageFromAlbum = NO;
    
    [defaults setBool:imageFromAlbum forKey:notebookIndexName];
    [defaults synchronize];
    
}

- (BOOL)imageFromAlbumFlag:(NSUInteger)index
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSString *notebookIndexName = [NSString stringWithFormat:@"%02d", (int)index];
    BOOL imageFromAlbum = [defaults boolForKey:notebookIndexName];
    
    return imageFromAlbum;
}

- (UIImage *)imageFromAlbum:(NSUInteger)index
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSString *notebookIndexName = [NSString stringWithFormat:@"%03d", (int)index];
    NSData *imageData = [defaults objectForKey:notebookIndexName];
    UIImage *image = [UIImage imageWithData:imageData];
    
    return image;
}


- (UIImage *) createThumbnailImage: (UIImage*)image
{
    UIImage *originalImage = image;
    CGSize destinationSize = CGSizeMake(235,351);
    UIGraphicsBeginImageContext(destinationSize);
    [originalImage drawInRect:CGRectMake(0,0,destinationSize.width,destinationSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return newImage;
}


- (void) closeNotebookInfoData
{
    if(self.notebookDocument) {
        [self.notebookDocument closeWithCompletionHandler:nil];
        self.notebookDocument = nil;
    }
}

- (NSDictionary *) pageInfoForPageName:(NSString *) pageName
{
    NSString *image = [[self pathForName:pageName] stringByAppendingPathComponent:@"image.jpg"];
    NSString *thumbnail = [[self pathForName:pageName] stringByAppendingPathComponent:@"thumbnail.jpg"];
    NSDictionary *pageInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              image, @"image",
                              thumbnail, @"thumbnail"
                              , nil];
    NSLog(@"image path : %@",image);
    
    return pageInfo;
}


- (NJPageDocument *) pageDocumentAtNumber:(NSUInteger)number
{
    NSString *pageName = [self pageNameFromNumber:number];
    if (!pageName) return nil;
    if (![self.notebookPages objectForKey:[NSNumber numberWithInt:(int)number]]) {
        [self createNewPageForNumber:number];
    }
    NJPageDocument *doc = [self pageWithName:pageName];
    return doc;
}
- (NJPageDocument *) pageWithName:(NSString *)name
{
    NSURL *url = [self urlForName:name];
    NJPageDocument *doc = [[NJPageDocument alloc] initWithFileURL:url withBookId:self.activeNoteBookId andPageNumber:[name intValue]];
    return doc;
}
- (void) createNewPageForNumber:(NSUInteger)number
{
    NSString *name = [self pageNameFromNumber:number];
    if (!name) return;
    
    NSURL *url = [self urlForName:name];
    
    NJPageDocument * pageDocument = [[NJPageDocument alloc] initWithFileURL:url withBookId:self.activeNoteBookId andPageNumber:[name intValue]];
#ifdef OPEN_NOTEBOOK_SYNC_MODE
    [pageDocument readFromURL:url error:NULL];
    [pageDocument pageSaveToURL:url forSaveOperation:UIDocumentSaveForCreating completionHandler:nil];
#else
    [pageDocument openWithCompletionHandler:^(BOOL success) {
        if (success) {
            [pageDocument pageSaveToURL:url forSaveOperation:UIDocumentSaveForCreating completionHandler:nil];
        } else {
            NSLog(@"saving failure");
        }
        
    }];
#endif
    NSDictionary *pageInfo = [self pageInfoForPageName:name];
    [self.notebookPages setObject:pageInfo forKey:[NSNumber numberWithInt:(int)number]];
    self.newPage = YES;
    
}
- (NSArray *) notebookPagesSortedBy:(NotebookPageSortRule)rule
{
    NSArray *sortedArray = [self.notebookPages allKeys];
    NSSortDescriptor *sd;
    switch (rule) {
        case kNotebookPageSortByName:
            sd = [[NSSortDescriptor alloc] initWithKey:nil ascending:YES];
            sortedArray = [sortedArray sortedArrayUsingDescriptors:@[sd]];
            break;
            
        default:
            break;
    }
    
    return sortedArray;
}
- (NSDictionary *) pageInfoForPageNumber:(NSUInteger) number
{
    NSDictionary * pageInfo = [self.notebookPages objectForKey:[NSNumber numberWithInteger:number]];
    
    return pageInfo;
}

- (void)addedChangedPage:(NSNotification *)notification
{
    NSUInteger nId = [(notification.userInfo)[@"notebookId"] integerValue];
    NSUInteger pageNumber = [(notification.userInfo)[@"page"] integerValue];
    
    if (![self.notebook.pageArray containsObject:[NSNumber numberWithInteger:pageNumber]]) {
        [self.notebook.pageArray addObject:[NSNumber numberWithInteger:pageNumber]];
    }
    self.notebookDocument.notebook.pageArray = self.notebook.pageArray;
    [self saveNotebook:nId];
}

- (void) removeAllObjectsFromChangedPages:(NSUInteger)nId
{
    
    BOOL result = [self openNotebookInfoData:nId];
    if (!result) {
        NSLog(@"notebook info reading fail");
    }
    
    [self.notebook.pageArray removeAllObjects];
    self.notebookDocument.notebook.pageArray = self.notebook.pageArray;
    [self saveNotebook:nId];
    
}

- (void) saveNotebook:(NSUInteger)noteId
{
    NSURL *url = [NSURL fileURLWithPath:[self notebookPathForId:noteId]];
    
    [self.notebookDocument saveToURL:url forSaveOperation:UIDocumentSaveForCreating completionHandler:nil];
    
}

- (BOOL) openNotebookInfoData:(NSUInteger)noteId
{
    [self closeNotebookInfoData];
    NSURL *url = [NSURL fileURLWithPath:[self notebookPathForId:noteId]];
    
    BOOL result = [self.notebookDocument readFromURL:url error:NULL];
    
    if (result) {
        self.notebook = self.notebookDocument.notebook;
    }
    
    return result;
}




@end


























#pragma mark - NJNotebookManager Private
@implementation NJNotebookManager (Private)

- (void) createDefaultDirectories_
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL firstRun = NO;
    
    if((![fm fileExistsAtPath:[self bookshelfPath]]) && (![fm fileExistsAtPath:[self digitalBookshelfPath]])) {
        firstRun = YES;
    }
    
    [fm createDirectoryAtPath:[self bookshelfPath] withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtPath:[self digitalBookshelfPath] withIntermediateDirectories:YES attributes:nil error:NULL];
    //[fm createDirectoryAtPath:[self archivesBookshelfPath] withIntermediateDirectories:YES attributes:nil error:NULL];
    
    if (firstRun) {
        NSString *samplesDirectory = @"preloadNotes";
        NSArray *samplePaths = [[NSBundle mainBundle] pathsForResourcesOfType:@"notebook_store"
                                                                  inDirectory:samplesDirectory];
        for (NSString *path in samplePaths) {
            NSString *documentPath = [[self bookshelfPath] stringByAppendingPathComponent:[path lastPathComponent]];
            [fm copyItemAtPath:path toPath:documentPath error:NULL];
        }
    }
    
}






@end
