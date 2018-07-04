//
//  PDFPageConverter.m
//
//  Created by Sorin Nistor on 3/23/11.
//  Copyright 2011 iPDFdev.com. All rights reserved.
//
//
//    Copyright (c) 2011 Sorin Nistor. All rights reserved. This software is provided 'as-is',
//    without any express or implied warranty. In no event will the authors be held liable for
//    any damages arising from the use of this software. Permission is granted to anyone to
//    use this software for any purpose, including commercial applications, and to alter it
//    and redistribute it freely, subject to the following restrictions:
//    1. The origin of this software must not be misrepresented; you must not claim that you
//    wrote the original software. If you use this software in a product, an acknowledgment
//    in the product documentation would be appreciated but is not required.
//    2. Altered source versions must be plainly marked as such, and must not be misrepresented
//    as being the original software.
//    3. This notice may not be removed or altered from any source distribution.

#import "PDFPageConverter.h"
#import "PDFPageRenderer.h"

@implementation PDFPageConverter

+ (UIImage *) convertPDFPageToImage: (CGPDFPageRef) page withResolution: (float) resolution {
	
	CGRect cropBox = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
	int pageRotation = CGPDFPageGetRotationAngle(page);
	
	if ((pageRotation == 0) || (pageRotation == 180) ||(pageRotation == -180)) {
		UIGraphicsBeginImageContextWithOptions(cropBox.size, NO, resolution / 72); 
	}
	else {
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(cropBox.size.height, cropBox.size.width), NO, resolution / 72); 
	}
	
	CGContextRef imageContext = UIGraphicsGetCurrentContext();   
	
    [PDFPageRenderer renderPage:page inContext:imageContext];
	
    UIImage *pageImage = UIGraphicsGetImageFromCurrentImageContext();
    CGSize size = [pageImage size];
    NSLog(@"PDF Width %f, height %f", size.width, size.height);
	
    UIGraphicsEndImageContext();
	
	return pageImage;
}

@end
