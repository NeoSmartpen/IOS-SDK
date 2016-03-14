//
//  NJNotebookInfoStore.h
//  NeoJournal
//
//  Created by NamSSan on 10/08/2014.
//  Copyright (c) 2014 Neolab. All rights reserved.
//

#import <Foundation/Foundation.h>

@class NJNotebookInfo;
@interface NJNotebookInfoStore : NSObject
{
    
    NSUInteger _curDigitalNoteId;
}


+ (NJNotebookInfoStore *)sharedStore;
- (NJNotebookInfo *)createNewNotebookInfo;
- (NJNotebookInfo *)getNotebookInfo:(NSUInteger)notebookId;
- (BOOL)updateNotebookInfo:(NJNotebookInfo *)notebookInfo;

@end
