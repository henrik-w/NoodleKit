//
//  NoodleLineNumberMarker.m
//  NoodleKit
//
//  Created by Paul Kim on 9/30/08.
//  Copyright (c) 2008 Noodlesoft, LLC. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//

#import "NoodleLineNumberMarker.h"

#import "NoodleLineNumberView.h"


@interface NoodleLineNumberMarker ()

@property (readonly, retain) NSDictionary *textAttributes;

@end


@implementation NoodleLineNumberMarker

@synthesize textAttributes = _textAttributes;

- (instancetype)initWithRulerView:(NSRulerView *)aRulerView lineNumber:(CGFloat)line image:(NSImage *)anImage imageOrigin:(NSPoint)imageOrigin
{
	return [self initWithRulerView:(NoodleLineNumberView *)aRulerView markerLocation:0.0 image:anImage imageOrigin:imageOrigin];
}


- (instancetype)initWithRulerView:(NoodleLineNumberView *)ruler markerLocation:(CGFloat)location image:(NSImage *)image imageOrigin:(NSPoint)imageOrigin
{
    self = [super initWithRulerView:ruler markerLocation:location image:image imageOrigin:imageOrigin];
    if (nil == self) {
        return nil;
    }

    NSRect visibleRect = [[[ruler scrollView] contentView] bounds];
    if ([ruler orientation] == NSVerticalRuler) {
        location -= NSMinY(visibleRect) + imageOrigin.y;
    } else {
        location -= NSMinX(visibleRect) - imageOrigin.x;
    }
    _lineNumber = [ruler lineNumberForLocation:location];

    _textAttributes = nil;

    return self;
}


- (void)dealloc
{
#if !__has_feature(objc_arc)
    [_textAttributes release];
    
    [super dealloc];
#endif
}


- (NSRect)imageRectInRuler
{
    NSRect r = [super imageRectInRuler];
    return r;
}

- (CGFloat)XXthicknessRequiredInRuler
{
    // TODO: Fix bug. This result increases by two with each call
    CGFloat s_thickness = [super thicknessRequiredInRuler];
    CGFloat thickness = [_image size].width;
    return thickness;
}


- (void)drawRect:(NSRect)rect
{
    if (nil == _image || nil == _ruler || nil == [_ruler clientView]) {
        return;
    }

    // All drawings here is designed only for vertical rulers!

    NSRect visibleRect = [[[_ruler scrollView] contentView] bounds];
    id view = [_ruler clientView];
    if ([view isKindOfClass:[NSTextView class]]) {
        // draw image
        CGFloat linePos = -1;
        NSRect extraLineRect = [[view layoutManager] extraLineFragmentRect];
        if (0 < extraLineRect.origin.y && NSPointInRect((NSPoint){0, [self markerLocation]}, extraLineRect)) {
            // there is an extra line fragment and the location point onto it
            linePos = extraLineRect.origin.y;
        } else {
            NSUInteger characterIndexForLocation = [[view layoutManager] characterIndexForPoint:(NSPoint){0, [self markerLocation]}
                                                                                inTextContainer:[view textContainer]
                                                       fractionOfDistanceBetweenInsertionPoints:NULL];
            NSRange effectiveRange = [[[view textStorage] string] paragraphRangeForRange:(NSRange){characterIndexForLocation, 0}];
            NSUInteger rectCount = 0;
            NSRectArray rects = [[view layoutManager] rectArrayForCharacterRange:effectiveRange
                                                    withinSelectedCharacterRange:(NSRange){NSNotFound, 0}
                                                                 inTextContainer:[view textContainer]
                                                                       rectCount:&rectCount];
            if (0 < rectCount) {
                linePos = rects[0].origin.y;
            }
        }

        NSRect markerRect;
        markerRect.size = [_image size];
        markerRect.origin.x = visibleRect.origin.x + [_ruler baselineLocation] - _imageOrigin.x;
        markerRect.origin.y = linePos - visibleRect.origin.y - _imageOrigin.y + markerRect.size.height/2;

        [_image drawInRect:markerRect fromRect:(NSRect){{0, 0}, [_image size]}
                 operation:NSCompositeSourceOver fraction:1.0];

        // draw label (in this case a linenumber) above the image
        NSString *labelText = [NSString stringWithFormat:@"%jd", (uintmax_t)_lineNumber];

        NSDictionary *currentTextAttributes = [self textAttributes];
        NSSize stringSize = [labelText sizeWithAttributes:currentTextAttributes];

        // Draw string flush right, centered vertically within the line
        NSRect labelRect;
        labelRect.size = markerRect.size;
        labelRect.origin.x = rect.origin.x + labelRect.size.width - stringSize.width - _imageOrigin.x / 2.0;
        labelRect.origin.y = markerRect.origin.y + (labelRect.size.height - stringSize.height) / 2.0;
        [labelText drawInRect:labelRect withAttributes:currentTextAttributes];
    }
}

#pragma mark private methods

- (NSDictionary *)textAttributes
{
    if (nil == _textAttributes) {
        NSFont  *font;
        NSColor *color;

        font = [(NoodleLineNumberView *)_ruler font];
        if (font == nil) {
            font = [NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]];
        }

        color = [(NoodleLineNumberView *)_ruler alternateTextColor];
        if (color == nil) {
            color = [NSColor whiteColor];
        }

        _textAttributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, color, NSForegroundColorAttributeName, nil];
#if !__has_feature(objc_arc)
        [_textAttributes retain];
#endif
    }
    return _textAttributes;
}

#pragma mark NSCoding methods

#define NOODLE_LINE_CODING_KEY		@"line"

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder]) != nil)
	{
		if ([decoder allowsKeyedCoding])
		{
			_lineNumber = [[decoder decodeObjectForKey:NOODLE_LINE_CODING_KEY] unsignedIntegerValue];
		}
		else
		{
			_lineNumber = [[decoder decodeObject] unsignedIntegerValue];
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[super encodeWithCoder:encoder];
	
	if ([encoder allowsKeyedCoding])
	{
		[encoder encodeObject:[NSNumber numberWithUnsignedInteger:_lineNumber] forKey:NOODLE_LINE_CODING_KEY];
	}
	else
	{
		[encoder encodeObject:[NSNumber numberWithUnsignedInteger:_lineNumber]];
	}
}


#pragma mark NSCopying methods

- (id)copyWithZone:(NSZone *)zone
{
	id		copy;
	
	copy = [super copyWithZone:zone];
	[copy setLineNumber:_lineNumber];
	
	return copy;
}


@end
