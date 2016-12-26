//
//  NoodleLineNumberView.m
//  NoodleKit
//
//  Created by Paul Kim on 9/28/08.
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

#import "NoodleLineNumberView.h"
#import "NoodleLineNumberMarker.h"
#import <tgmath.h>

#define DEFAULT_THICKNESS	22.0
#define RULER_MARGIN		5.0


@interface NoodleLineNumberView ()

@property (readonly, retain) NSDictionary *textAttributes;
@property (readonly, retain) NSDictionary *markerTextAttributes;

@end


@interface NoodleLineNumberView (Private)

- (NSFont *)defaultFont;
- (NSColor *)defaultTextColor;
- (NSColor *)defaultAlternateTextColor;
- (NSMutableArray *)lineIndices;
- (void)invalidateLineIndicesFromCharacterIndex:(NSUInteger)charIndex;
- (void)calculateLines;
- (NSUInteger)lineNumberForCharacterIndex:(NSUInteger)index;
- (CGFloat)calculateRuleThickness;

@end

@implementation NoodleLineNumberView

@synthesize font = _font;
@synthesize textColor = _textColor;
@synthesize alternateTextColor = _alternateTextColor;
@synthesize backgroundColor = _backgroundColor;
@synthesize textAttributes = _textAttributes;
@synthesize markerTextAttributes = _markerTextAttributes;

- (id)initWithScrollView:(NSScrollView *)aScrollView
{
    if ((self = [super initWithScrollView:aScrollView orientation:NSVerticalRuler]) != nil)
    {
        _lineIndices = [[NSMutableArray alloc] init];
		_linesToMarkers = [[NSMutableDictionary alloc] init];
		
        [self setClientView:[aScrollView documentView]];
    }
    return self;
}

- (void)awakeFromNib
{
    _lineIndices = [[NSMutableArray alloc] init];
	_linesToMarkers = [[NSMutableDictionary alloc] init];
	[self setClientView:[[self scrollView] documentView]];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
#if !__has_feature(objc_arc)
    [_lineIndices release];
	[_linesToMarkers release];
    [_font release];
    [_textColor release];
    [_alternateTextColor release];
    [_backgroundColor release];
    [_textAttributes release];
    [_markerTextAttributes release];
    
    [super dealloc];
#endif
}

- (NSFont *)defaultFont
{
    return [NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]];
}

- (NSColor *)defaultTextColor
{
    return [NSColor colorWithCalibratedWhite:0.42 alpha:1.0];
}

- (NSColor *)defaultAlternateTextColor
{
    return [NSColor whiteColor];
}

- (void)setClientView:(NSView *)aView
{
	id		oldClientView;
	
	oldClientView = [self clientView];
	
    if ((oldClientView != aView) && [oldClientView isKindOfClass:[NSTextView class]])
    {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextStorageDidProcessEditingNotification object:[(NSTextView *)oldClientView textStorage]];
    }
    [super setClientView:aView];
    if ((aView != nil) && [aView isKindOfClass:[NSTextView class]])
    {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textStorageDidProcessEditing:) name:NSTextStorageDidProcessEditingNotification object:[(NSTextView *)aView textStorage]];

		[self invalidateLineIndicesFromCharacterIndex:0];
    }
}

- (NSMutableArray *)lineIndices
{
	if (_invalidCharacterIndex < NSUIntegerMax)
	{
		[self calculateLines];
	}
	return _lineIndices;
}

// Forces recalculation of line indicies starting from the given index
- (void)invalidateLineIndicesFromCharacterIndex:(NSUInteger)charIndex
{
    _invalidCharacterIndex = MIN(charIndex, _invalidCharacterIndex);
}

- (void)textStorageDidProcessEditing:(NSNotification *)notification
{
    NSTextStorage       *storage;
    NSRange             range;
    
    storage = [notification object];

    // Invalidate the line indices. They will be recalculated and re-cached on demand.
    range = [storage editedRange];
    if (range.location != NSNotFound)
    {
        [self invalidateLineIndicesFromCharacterIndex:range.location];
        [self setNeedsDisplay:YES];
    }
}

- (void)calculateLines
{
    id              view;

    view = [self clientView];
    
    if ([view isKindOfClass:[NSTextView class]])
    {
        NSUInteger      charIndex, stringLength, lineEnd, contentEnd, count, lineIndex;
        NSString        *text;
        
        text = [view string];
        stringLength = [text length];
        count = [_lineIndices count];

        charIndex = 0;
        lineIndex = [self lineNumberForCharacterIndex:_invalidCharacterIndex];
        if (count > 0)
        {
            charIndex = [[_lineIndices objectAtIndex:lineIndex] unsignedIntegerValue];
        }
        
        do
        {
            if (lineIndex < count)
            {
                [_lineIndices replaceObjectAtIndex:lineIndex withObject:[NSNumber numberWithUnsignedInteger:charIndex]];
            }
            else
            {
                [_lineIndices addObject:[NSNumber numberWithUnsignedInteger:charIndex]];
            }
            
            charIndex = NSMaxRange([text lineRangeForRange:NSMakeRange(charIndex, 0)]);
            lineIndex++;
        }
        while (charIndex < stringLength);
        
        if (lineIndex < count)
        {
            [_lineIndices removeObjectsInRange:NSMakeRange(lineIndex, count - lineIndex)];
        }
        _invalidCharacterIndex = NSUIntegerMax;

        // Check if text ends with a new line.
        [text getLineStart:NULL end:&lineEnd contentsEnd:&contentEnd forRange:NSMakeRange([[_lineIndices lastObject] unsignedIntegerValue], 0)];
        if (contentEnd < lineEnd)
        {
            [_lineIndices addObject:[NSNumber numberWithUnsignedInteger:charIndex]];
        }

        // See if we need to adjust the width of the view
        CGFloat oldThickness = [self ruleThickness];
        CGFloat newThickness = [self calculateRuleThickness];
        if (oldThickness != newThickness)
        {
			NSInvocation			*invocation;
			
			// Not a good idea to resize the view during calculations (which can happen during
			// display). Do a delayed perform (using NSInvocation since arg is a float).
            // ...or do it via KVO, so the Notification Center perform the delayed resize...
            // Observe the key "lineIndices.@count" for adjusting the thickness
			invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(setRuleThickness:)]];
			[invocation setSelector:@selector(setRuleThickness:)];
			[invocation setTarget:self];
			[invocation setArgument:&newThickness atIndex:2];
			
			[invocation performSelector:@selector(invoke) withObject:nil afterDelay:0.0];
        }
	}
}

/* This not returns a line number as the name promise, it is a line index number */
- (NSUInteger)lineNumberForCharacterIndex:(NSUInteger)charIndex
{
    NSUInteger			left, right, mid, lineStart;

    // Binary search
    left = 0;
    right = [_lineIndices count];

    while ((right - left) > 1)
    {
        mid = (right + left) / 2;
        lineStart = [[_lineIndices objectAtIndex:mid] unsignedIntegerValue];
        
        if (charIndex < lineStart)
        {
            right = mid;
        }
        else if (charIndex > lineStart)
        {
            left = mid;
        }
        else
        {
            return mid;
        }
    }
    return left;
}

- (NSDictionary *)textAttributes
{
    if (nil == _textAttributes) {
        NSFont  *font;
        NSColor *color;

        font = [self font];
        if (font == nil)
        {
            font = [self defaultFont];
        }

        color = [self textColor];
        if (color == nil)
        {
            color = [self defaultTextColor];
        }

        _textAttributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, color, NSForegroundColorAttributeName, nil];
#if !__has_feature(objc_arc)
        [_textAttributes retain];
#endif
    }
    return _textAttributes;
}

- (NSDictionary *)markerTextAttributes
{
    if (nil == _markerTextAttributes) {
        NSFont  *font;
        NSColor *color;

        font = [self font];
        if (font == nil)
        {
            font = [self defaultFont];
        }

        color = [self alternateTextColor];
        if (color == nil)
        {
            color = [self defaultAlternateTextColor];
        }

        _markerTextAttributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, color, NSForegroundColorAttributeName, nil];
#if !__has_feature(objc_arc)
        [_markerTextAttributes retain];
#endif
    }
    return _markerTextAttributes;
}

- (CGFloat)calculateRuleThickness
{
    NSUInteger			lineCount, digits;
    NSSize              stringSize;
    
    lineCount = [[self lineIndices] count];
    digits = 1;
    if (lineCount > 0)
    {
        digits = (NSUInteger)log10(lineCount) + 1;
    }
    // Use "8" since it is one of the fatter numbers. Anything but "1"
    // will probably be ok here. I could be pedantic and actually find the fattest
    // number for the current font but nah.
    stringSize = [@"8" sizeWithAttributes:[self textAttributes]];

	// Round up the value. There is a bug on 10.4 where the display gets all wonky when scrolling if you don't
	// return an integral value here.
    return ceil(MAX(DEFAULT_THICKNESS, stringSize.width * digits + RULER_MARGIN * 2));
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)aRect
{
	NSRect bounds = [self bounds];

	if (nil != _backgroundColor) {
		[_backgroundColor set];
		NSRectFill(bounds);
		
		[[NSColor colorWithCalibratedWhite:0.58 alpha:1.0] set];
		[NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(bounds) - 0.5, NSMinY(bounds))
                                  toPoint:NSMakePoint(NSMaxX(bounds) - 0.5, NSMaxY(bounds))];
	}

    id view = [self clientView];
	
    if (nil != view && [view isKindOfClass:[NSTextView class]]) {
        NSLayoutManager *layoutManager = [view layoutManager];
        NSTextContainer *container = [view textContainer];
		
		CGFloat yinset = [view textContainerInset].height;
        NSRect visibleRect = [[[self scrollView] contentView] bounds];

        // Find the characters that are currently visible
        NSRange glyphRange = [layoutManager glyphRangeForBoundingRect:visibleRect inTextContainer:container];

#if MAC_OS_X_VERSION_MIN_REQUIRED >= 101100
        // Not tested adequate, there are still some quirks
        if (_invalidCharacterIndex < NSUIntegerMax) {
            [self calculateLines];
        }
        __block NSUInteger lastLine = NSUIntegerMax;
        glyphRange.length++;
        [layoutManager enumerateLineFragmentsForGlyphRange:glyphRange usingBlock:^(NSRect rect, NSRect usedRect, NSTextContainer * _Nonnull textContainer, NSRange glyphRange, BOOL * _Nonnull stop) {
            NSRange range = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
            const NSUInteger lineNumber = [self lineNumberForCharacterIndex:range.location];
            if (lineNumber == lastLine) {
                return;
            }
            lastLine = lineNumber;
            CGFloat ypos = yinset + NSMinY(rect) - NSMinY(visibleRect);
            [self drawLabelInRect:NSMakeRect(0.0, ypos, NSWidth(bounds), NSHeight(rect)) atLineNumber:lineNumber];
        }];
#else
        NSRange range = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
        
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1060
        NSArray *lines = [self lineIndices];
        NSUInteger firstLineNumber = [self lineNumberForCharacterIndex:range.location];
        NSUInteger lastLineNumber = [self lineNumberForCharacterIndex:NSMaxRange(range)]+1;
        NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:(NSRange){firstLineNumber, lastLineNumber - firstLineNumber}];
        [lines enumerateObjectsAtIndexes:indexes options:0 usingBlock:^(id  _Nonnull obj, NSUInteger line, BOOL * _Nonnull stop) {
            NSUInteger rectCount = 0;
            NSRange characterRange = (NSRange){[obj unsignedIntegerValue], 0};

            NSRectArray rects = [layoutManager rectArrayForCharacterRange:characterRange
                                             withinSelectedCharacterRange:characterRange
                                                          inTextContainer:container
                                                                rectCount:&rectCount];
            if (0 < rectCount) {
                // Note that the ruler view is only as tall as the visible
                // portion. Need to compensate for the clipview's coordinates.
                CGFloat ypos = yinset + NSMinY(rects[0]) - NSMinY(visibleRect);
                [self drawLabelAndMarkerInRect:NSMakeRect(0.0, ypos, NSWidth(bounds), NSHeight(rects[0])) atLineNumber:line];
            }
        }];
#else
        // Fudge the range a tad in case there is an extra new line at end.
        // It doesn't show up in the glyphs so would not be accounted for.
        range.length++;

        NSRange nullRange = NSMakeRange(NSNotFound, 0);
        NSArray *lines = [self lineIndices];
        NSUInteger count = [lines count];

        for (NSUInteger line = [self lineNumberForCharacterIndex:range.location]; line < count; line++)
        {
            NSUInteger index = [[lines objectAtIndex:line] unsignedIntegerValue];

            if (NSLocationInRange(index, range))
            {
                NSUInteger rectCount = 0;
                NSRectArray rects = [layoutManager rectArrayForCharacterRange:NSMakeRange(index, 0)
                                                 withinSelectedCharacterRange:nullRange
                                                              inTextContainer:container
                                                                    rectCount:&rectCount];

                if (rectCount > 0)
                {
                    // Note that the ruler view is only as tall as the visible
                    // portion. Need to compensate for the clipview's coordinates.
                    CGFloat ypos = yinset + NSMinY(rects[0]) - NSMinY(visibleRect);
                    [self drawLabelAndMarkerInRect:NSMakeRect(0.0, ypos, NSWidth(bounds), NSHeight(rects[0])) atLineNumber:line];
                }
            }
            if (index > NSMaxRange(range))
            {
                break;
            }
        }
#endif
#endif
    }
}


- (void)drawLabelAndMarkerInRect:(NSRect)rect atLineNumber:(NSUInteger)line
{
    // TODO: refactoring necessary
    // Markers should be drawn with drawMarkersInRect:(NSRect)rect
    NoodleLineNumberMarker *marker = [_linesToMarkers objectForKey:[NSNumber numberWithUnsignedInteger:line]];
    if (nil != marker) {
        NSImage *markerImage = [marker image];
        NSRect markerRect;
        markerRect.size = [markerImage size];

        // Marker is flush right and centered vertically within the line.
        markerRect.origin.x = rect.size.width - [markerImage size].width;
        markerRect.origin.y = rect.origin.y + rect.size.height / 2.0 - [marker imageOrigin].y;

        [markerImage drawInRect:markerRect fromRect:NSMakeRect(0, 0, markerRect.size.width, markerRect.size.height) operation:NSCompositeSourceOver fraction:1.0];
    }

    // Line numbers are internally stored starting at 0
    NSString *labelText = [NSString stringWithFormat:@"%jd", (intmax_t)line + 1];

    NSDictionary *currentTextAttributes = (nil == marker)? [self textAttributes] : [self markerTextAttributes];
    NSSize stringSize = [labelText sizeWithAttributes:currentTextAttributes];

    // Draw string flush right, centered vertically within the line
    [labelText drawInRect:NSMakeRect(rect.size.width - RULER_MARGIN - stringSize.width,
                                     rect.origin.y + (rect.size.height - stringSize.height) / 2.0,
                                     rect.size.width - RULER_MARGIN * 2.0, rect.size.height)
           withAttributes:currentTextAttributes];
}


- (NSUInteger)lineNumberForLocation:(CGFloat)location
{
	id view = [self clientView];
	NSRect visibleRect = [[[self scrollView] contentView] bounds];
	
	if ([view isKindOfClass:[NSTextView class]])
	{
		NSLayoutManager	*layoutManager = [view layoutManager];

        location += NSMinY(visibleRect);
        NSPoint characterPoint = ([self orientation] == NSVerticalRuler)? (NSPoint){0, location} : (NSPoint){location, 0};
        NSUInteger characterIndexForLocation = [layoutManager characterIndexForPoint:characterPoint
                                                                     inTextContainer:[view textContainer]
                                            fractionOfDistanceBetweenInsertionPoints:NULL];
        return [self lineNumberForCharacterIndex:characterIndexForLocation] + 1;
	}
	return NSNotFound;
}

- (NoodleLineNumberMarker *)markerAtLine:(NSUInteger)line
{
	return [_linesToMarkers objectForKey:[NSNumber numberWithUnsignedInteger:line - 1]];
}

- (void)setMarkers:(NSArray *)markers
{
	NSEnumerator		*enumerator;
	NSRulerMarker		*marker;
	
	[_linesToMarkers removeAllObjects];
	[super setMarkers:nil];

	enumerator = [markers objectEnumerator];
	while ((marker = [enumerator nextObject]) != nil)
	{
		[self addMarker:marker];
	}
}

- (void)addMarker:(NSRulerMarker *)aMarker
{
	if ([aMarker isKindOfClass:[NoodleLineNumberMarker class]])
	{
		[_linesToMarkers setObject:aMarker
							forKey:[NSNumber numberWithUnsignedInteger:[(NoodleLineNumberMarker *)aMarker lineNumber] - 1]];
	}
	else
	{
		[super addMarker:aMarker];
	}
}

- (void)removeMarker:(NSRulerMarker *)aMarker
{
	if ([aMarker isKindOfClass:[NoodleLineNumberMarker class]])
	{
		[_linesToMarkers removeObjectForKey:[NSNumber numberWithUnsignedInteger:[(NoodleLineNumberMarker *)aMarker lineNumber] - 1]];
	}
	else
	{
		[super removeMarker:aMarker];
	}
}

#pragma mark NSCoding methods

#define NOODLE_FONT_CODING_KEY				@"font"
#define NOODLE_TEXT_COLOR_CODING_KEY		@"textColor"
#define NOODLE_ALT_TEXT_COLOR_CODING_KEY	@"alternateTextColor"
#define NOODLE_BACKGROUND_COLOR_CODING_KEY	@"backgroundColor"

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder]) != nil)
	{
		if ([decoder allowsKeyedCoding])
		{
			[self setFont:[decoder decodeObjectForKey:NOODLE_FONT_CODING_KEY]];
			[self setTextColor:[decoder decodeObjectForKey:NOODLE_TEXT_COLOR_CODING_KEY]];
			[self setAlternateTextColor:[decoder decodeObjectForKey:NOODLE_ALT_TEXT_COLOR_CODING_KEY]];
			[self setBackgroundColor:[decoder decodeObjectForKey:NOODLE_BACKGROUND_COLOR_CODING_KEY]];
		}
		else
		{
			[self setFont:[decoder decodeObject]];
			[self setTextColor:[decoder decodeObject]];
			[self setAlternateTextColor:[decoder decodeObject]];
			[self setBackgroundColor:[decoder decodeObject]];
		}
		
		_linesToMarkers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[super encodeWithCoder:encoder];
	
	if ([encoder allowsKeyedCoding])
	{
		[encoder encodeObject:_font forKey:NOODLE_FONT_CODING_KEY];
		[encoder encodeObject:_textColor forKey:NOODLE_TEXT_COLOR_CODING_KEY];
		[encoder encodeObject:_alternateTextColor forKey:NOODLE_ALT_TEXT_COLOR_CODING_KEY];
		[encoder encodeObject:_backgroundColor forKey:NOODLE_BACKGROUND_COLOR_CODING_KEY];
	}
	else
	{
		[encoder encodeObject:_font];
		[encoder encodeObject:_textColor];
		[encoder encodeObject:_alternateTextColor];
		[encoder encodeObject:_backgroundColor];
	}
}

@end
