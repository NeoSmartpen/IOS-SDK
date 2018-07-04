//
//  PDFPageRenderer.m
//
//  Created by Sorin Nistor on 3/21/11.
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

#import "PDFPageRenderer.h"


@implementation PDFPageRenderer

+ (void) renderPage: (CGPDFPageRef) page inContext: (CGContextRef) context{
	[PDFPageRenderer renderPage:page inContext:context atPoint:CGPointMake(0, 0)];
}
	 
+ (void) renderPage: (CGPDFPageRef) page inContext: (CGContextRef) context atPoint:(CGPoint) point{
	[PDFPageRenderer renderPage:page inContext:context atPoint:point withZoom:100];
}

+ (void) renderPage: (CGPDFPageRef) page inContext: (CGContextRef) context atPoint: (CGPoint) point withZoom: (float) zoom{
	
	CGRect cropBox = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
	int rotate = CGPDFPageGetRotationAngle(page);
	
	CGContextSaveGState(context);
	
	// Setup the coordinate system.
	// Top left corner of the displayed page must be located at the point specified by the 'point' parameter.
	CGContextTranslateCTM(context, point.x, point.y);
	
	// Scale the page to desired zoom level.
	CGContextScaleCTM(context, zoom / 100, zoom / 100);
	
	// The coordinate system must be set to match the PDF coordinate system.
	switch (rotate) {
		case 0:
			CGContextTranslateCTM(context, 0, cropBox.size.height);
			CGContextScaleCTM(context, 1, -1);
			break;
		case 90:
			CGContextScaleCTM(context, 1, -1);
			CGContextRotateCTM(context, -M_PI / 2);
			break;
		case 180:
		case -180:
			CGContextScaleCTM(context, 1, -1);
			CGContextTranslateCTM(context, cropBox.size.width, 0);
			CGContextRotateCTM(context, M_PI);
			break;
		case 270:
		case -90:
			CGContextTranslateCTM(context, cropBox.size.height, cropBox.size.width);
			CGContextRotateCTM(context, M_PI / 2);
			CGContextScaleCTM(context, -1, 1);
			break;
	}
	
	// The CropBox defines the page visible area, clip everything outside it.
	CGRect clipRect = CGRectMake(0, 0, cropBox.size.width, cropBox.size.height);
	CGContextAddRect(context, clipRect);
	CGContextClip(context);
	
	CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
	CGContextFillRect(context, clipRect);
	
	CGContextTranslateCTM(context, -cropBox.origin.x, -cropBox.origin.y);
	
	CGContextDrawPDFPage(context, page);
	
	CGContextRestoreGState(context);
}

+ (void) renderPage: (CGPDFPageRef) page inContext: (CGContextRef) context inRectangle: (CGRect) displayRectangle {
    if ((displayRectangle.size.width == 0) || (displayRectangle.size.height == 0)) {
        return;
    }
    
    CGRect cropBox = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
	int pageRotation = CGPDFPageGetRotationAngle(page);
	
	CGSize pageVisibleSize = CGSizeMake(cropBox.size.width, cropBox.size.height);
	if ((pageRotation == 90) || (pageRotation == 270) ||(pageRotation == -90)) {
		pageVisibleSize = CGSizeMake(cropBox.size.height, cropBox.size.width);
	}
    
    float scaleX = displayRectangle.size.width / pageVisibleSize.width;
    float scaleY = displayRectangle.size.height / pageVisibleSize.height;
    float scale = scaleX < scaleY ? scaleX : scaleY;
    
    // Offset relative to top left corner of rectangle where the page will be displayed
    float offsetX = 0;
    float offsetY = 0;
    
    float rectangleAspectRatio = displayRectangle.size.width / displayRectangle.size.height;
    float pageAspectRatio = pageVisibleSize.width / pageVisibleSize.height;
    
    if (pageAspectRatio < rectangleAspectRatio) {
        // The page is narrower than the rectangle, we place it at center on the horizontal
        offsetX = (displayRectangle.size.width - pageVisibleSize.width * scale) / 2;
    }
    else { 
        // The page is wider than the rectangle, we place it at center on the vertical
        offsetY = (displayRectangle.size.height - pageVisibleSize.height * scale) / 2;
    }
    
    CGPoint topLeftPage = CGPointMake(displayRectangle.origin.x + offsetX, displayRectangle.origin.y + offsetY);
    
    [PDFPageRenderer renderPage:page inContext:context atPoint:topLeftPage withZoom:scale * 100];
}

@end
