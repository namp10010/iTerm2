//
//  iTermBadgeLabel.m
//  iTerm2
//
//  Created by George Nachman on 7/7/15.
//
//

#import "iTermBadgeLabel.h"
#import "DebugLogging.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"

@interface iTermBadgeLabel()
@property(nonatomic, retain) NSImage *image;
@end

static const CGFloat kHudHPad          = 10.0;
static const CGFloat kHudVPad          = 6.0;
static const CGFloat kHudStepW         = 16.0;
static const CGFloat kHudOuterWidth    = 1.5;
static const CGFloat kHudInnerWidth    = 1.0;
static const CGFloat kHudInnerInset    = 3.5;
static const CGFloat kHudGlowRadius   = 7.0;

@implementation iTermBadgeLabel {
    NSMutableDictionary<NSString *, NSImage *> *_images;
    BOOL _dirty;
    NSMutableParagraphStyle *_paragraphStyle;
    NSMutableParagraphStyle *_hudParagraphStyle;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        _paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        _paragraphStyle.alignment = NSTextAlignmentRight;
        _hudParagraphStyle = [[NSMutableParagraphStyle alloc] init];
        _hudParagraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        _hudParagraphStyle.alignment = NSTextAlignmentLeft;
        _minimumPointSize = 4;
        _maximumPointSize = 100;
        _images = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setFillColor:(NSColor *)fillColor {
    if ([fillColor isEqual:_fillColor] || fillColor == _fillColor) {
        return;
    }
    _fillColor = fillColor;
    [self setDirty:YES];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    if ([backgroundColor isEqual:_backgroundColor] || backgroundColor == _backgroundColor) {
        return;
    }
    _backgroundColor = backgroundColor;
    [self setDirty:YES];
}

- (void)setHudBackgroundColor:(NSColor *)hudBackgroundColor {
    if ([hudBackgroundColor isEqual:_hudBackgroundColor] || hudBackgroundColor == _hudBackgroundColor) {
        return;
    }
    _hudBackgroundColor = hudBackgroundColor;
    [self setDirty:YES];
}

- (void)setStringValue:(NSString *)stringValue {
    if ([stringValue isEqual:_stringValue] || stringValue == _stringValue) {
        return;
    }
    _stringValue = [stringValue copy];
    [self setDirty:YES];
}

- (void)setViewSize:(NSSize)viewSize {
    if (NSEqualSizes(_viewSize, viewSize)) {
        return;
    }
    _viewSize = viewSize;
    [self setDirty:YES];
}

- (NSImage *)image {
    if (!_image) {
        _image = [self freshlyComputedImage];
    }
    return _image;
}

#pragma mark - HUD rendering

// 8-vertex right-angle polygon with notches cut from the top-left and bottom-right corners.
// In NSImage coords (y=0 at bottom) the Metal shader flips the image vertically, so
// "bottom" in image space appears at the top on screen — which is where the title strip sits.
- (NSBezierPath *)hudPathForW:(CGFloat)W H:(CGFloat)H stepW:(CGFloat)sw stepH:(CGFloat)sh {
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(sw, 0)];
    [p lineToPoint:NSMakePoint(W, 0)];
    [p lineToPoint:NSMakePoint(W, H - sh)];
    [p lineToPoint:NSMakePoint(W - sw, H - sh)];
    [p lineToPoint:NSMakePoint(W - sw, H)];
    [p lineToPoint:NSMakePoint(0, H)];
    [p lineToPoint:NSMakePoint(0, sh)];
    [p lineToPoint:NSMakePoint(sw, sh)];
    [p closePath];
    return p;
}

// Same path but inset uniformly by |s| on all edges.
- (NSBezierPath *)hudPathInsetBy:(CGFloat)s W:(CGFloat)W H:(CGFloat)H stepW:(CGFloat)sw stepH:(CGFloat)sh {
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(sw + s, s)];
    [p lineToPoint:NSMakePoint(W - s, s)];
    [p lineToPoint:NSMakePoint(W - s, H - sh - s)];
    [p lineToPoint:NSMakePoint(W - sw - s, H - sh - s)];
    [p lineToPoint:NSMakePoint(W - sw - s, H - s)];
    [p lineToPoint:NSMakePoint(s, H - s)];
    [p lineToPoint:NSMakePoint(s, sh + s)];
    [p lineToPoint:NSMakePoint(sw + s, sh + s)];
    [p closePath];
    return p;
}

- (NSImage *)hudImageWithBodyPointSize:(CGFloat)bodyPts {
    NSRange nl = [_stringValue rangeOfString:@"\n"];
    NSString *titleLine = [_stringValue substringToIndex:nl.location];
    NSString *bodyText = [_stringValue substringFromIndex:nl.location + 1];

    CGFloat titlePts = MAX(self.minimumPointSize, bodyPts - 2);
    NSFont *titleFont = [self.delegate badgeLabelFontOfSize:titlePts];
    NSFont *bodyFont  = [self.delegate badgeLabelFontOfSize:bodyPts];

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: [_fillColor colorWithAlphaComponent:1.0],
        NSParagraphStyleAttributeName: _hudParagraphStyle,
    };
    NSDictionary *bodyAttrs = @{
        NSFontAttributeName: bodyFont,
        NSForegroundColorAttributeName: _fillColor,
        NSParagraphStyleAttributeName: _hudParagraphStyle,
        NSStrokeWidthAttributeName: @-2,
        NSStrokeColorAttributeName: [_backgroundColor colorWithAlphaComponent:1],
    };

    NSSize maxSize = self.maxSize;
    CGFloat maxBodyW = maxSize.width - 2 * kHudHPad;
    BOOL truncated;
    NSSize titleSize = [titleLine it_boundingRectWithSize:NSMakeSize(maxBodyW, CGFLOAT_MAX)
                                              attributes:titleAttrs
                                               truncated:&truncated].size;
    NSSize bodySize  = [bodyText it_boundingRectWithSize:NSMakeSize(maxBodyW, CGFLOAT_MAX)
                                             attributes:bodyAttrs
                                              truncated:&truncated].size;

    CGFloat stepH = titleSize.height + 2 * kHudVPad;
    CGFloat W = MIN(maxSize.width,
                    MAX(bodySize.width, titleSize.width + kHudStepW) + 2 * kHudHPad);
    CGFloat H = MIN(maxSize.height,
                    stepH + bodySize.height + 3 * kHudVPad);

    if (W <= 0 || H <= 0) {
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(W, H)];
    [image lockFocus];

    NSBezierPath *outer = [self hudPathForW:W H:H stepW:kHudStepW stepH:stepH];
    NSBezierPath *inner = [self hudPathInsetBy:kHudInnerInset W:W H:H stepW:kHudStepW stepH:stepH];

    // Background fill
    NSColor *bg = _hudBackgroundColor
        ?: [NSColor colorWithCalibratedRed:0.03 green:0.08 blue:0.19 alpha:0.82];
    [bg setFill];
    [outer fill];

    // Outer border with glow
    [NSGraphicsContext saveGraphicsState];
    NSShadow *glow = [[NSShadow alloc] init];
    glow.shadowColor = [_fillColor colorWithAlphaComponent:0.75];
    glow.shadowBlurRadius = kHudGlowRadius;
    glow.shadowOffset = NSZeroSize;
    [glow set];
    [[_fillColor colorWithAlphaComponent:0.9] setStroke];
    [outer setLineWidth:kHudOuterWidth];
    [outer stroke];
    [NSGraphicsContext restoreGraphicsState];
    // Inner border (no glow, dimmer)
    [[_fillColor colorWithAlphaComponent:0.45] setStroke];
    [inner setLineWidth:kHudInnerWidth];
    [inner stroke];

    // Title — in image coords, y=0..stepH is at the bottom of the image
    // but the Metal shader flips the texture, so it appears at the TOP on screen.
    NSRect titleRect = NSMakeRect(kHudStepW + kHudHPad,
                                  kHudVPad,
                                  W - kHudStepW - 2 * kHudHPad,
                                  stepH - 2 * kHudVPad);
    [titleLine it_drawInRect:titleRect attributes:titleAttrs];

    // Body — above the title strip in image coords → appears below title on screen.
    NSRect bodyRect = NSMakeRect(kHudHPad,
                                 stepH + kHudVPad,
                                 W - 2 * kHudHPad,
                                 H - stepH - 2 * kHudVPad);
    [bodyText it_drawInRect:bodyRect attributes:bodyAttrs];

    [image unlockFocus];
    return image;
}

#pragma mark - Private

- (void)setDirty:(BOOL)dirty {
    _dirty = dirty;
    if (dirty) {
        self.image = nil;
    }
}

// Compute the best point size and return a new image of the badge. Returns nil if the badge
// is empty or zero pixels.r
- (NSImage *)freshlyComputedImage {
    DLog(@"Recompute badge self=%p, label=“%@”, color=%@, view size=%@. Called from:\n%@",
         self,
         _stringValue,
         _fillColor,
         NSStringFromSize(_viewSize),
         [NSThread callStackSymbols]);

    if (![_stringValue length]) {
        return nil;
    }
    if ([_stringValue containsString:@"\n"]) {
        return [self hudImageWithBodyPointSize:self.idealPointSize];
    }
    return [self imageWithPointSize:self.idealPointSize];
}

// Returns an image from the current text with the given |attributes|, or nil if the image would
// have 0 pixels.
- (NSImage *)imageWithPointSize:(CGFloat)pointSize {
    NSDictionary *attributes = [self attributesWithPointSize:pointSize];
    NSMutableDictionary *temp = [attributes mutableCopy];
    temp[NSStrokeColorAttributeName] = [_backgroundColor colorWithAlphaComponent:1];
    BOOL truncated;
    NSSize sizeWithFont = [self sizeWithAttributes:temp truncated:&truncated];
    if (sizeWithFont.width <= 0 || sizeWithFont.height <= 0) {
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithSize:sizeWithFont];
    [image lockFocus];

    [_stringValue it_drawInRect:NSMakeRect(0, 0, sizeWithFont.width, sizeWithFont.height)
                     attributes:temp
                          alpha:_fillColor.alphaComponent];

    [image unlockFocus];
    return image;
}

// Attributed string attributes for a given font point size.
- (NSDictionary *)attributesWithPointSize:(CGFloat)pointSize {
    NSDictionary *attributes = @{ NSFontAttributeName: [self.delegate badgeLabelFontOfSize:pointSize],
                                  NSForegroundColorAttributeName: _fillColor,
                                  NSParagraphStyleAttributeName: _paragraphStyle,
                                  NSStrokeWidthAttributeName: @-2 };
    return attributes;
}

// Size of the image resulting from drawing an attributed string with |attributes|.
- (NSSize)sizeWithAttributes:(NSDictionary *)attributes truncated:(BOOL *)truncated {
    NSSize size = self.maxSize;
    size.height = CGFLOAT_MAX;
    NSRect bounds = [_stringValue it_boundingRectWithSize:self.maxSize
                                               attributes:attributes
                                                truncated:truncated];
    return bounds.size;
}

// Max size of image in points within the containing view.
- (NSSize)maxSize {
    const NSSize fractions = [self.delegate badgeLabelSizeFraction];
    double maxWidth = MIN(1.0, MAX(0.01, fractions.width));
    double maxHeight = MIN(1.0, MAX(0.0, fractions.height));
    NSSize maxSize = _viewSize;
    maxSize.width *= maxWidth;
    maxSize.height *= maxHeight;
    return maxSize;
}

- (CGFloat)idealPointSize {
    DLog(@"Computing ideal point size for badge");
    NSSize maxSize = self.maxSize;

    // Perform a binary search for the point size that best fits |maxSize|.
    CGFloat min = self.minimumPointSize;
    CGFloat max = self.maximumPointSize;
    int points = (min + max) / 2;
    int prevPoints = -1;
    NSSize sizeWithFont = NSZeroSize;
    while (points != prevPoints) {
        BOOL truncated;
        sizeWithFont = [self sizeWithAttributes:[self attributesWithPointSize:points] truncated:&truncated];
        DLog(@"Point size of %@ gives label size of %@", @(points), NSStringFromSize(sizeWithFont));
        if (truncated ||
            sizeWithFont.width > maxSize.width ||
            sizeWithFont.height > maxSize.height) {
            max = points;
        } else if (sizeWithFont.width < maxSize.width &&
                   sizeWithFont.height < maxSize.height) {
            min = points;
        }
        prevPoints = points;
        points = (min + max) / 2;
    }
    DLog(@"Using point size %@", @(points));
    return points;
}

@end
