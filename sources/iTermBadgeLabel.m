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

static const CGFloat kHudHPad        = 10.0;
static const CGFloat kHudVPad        = 6.0;
static const CGFloat kHudCornerRadius = 6.0;
static const CGFloat kHudOuterWidth  = 1.0;
static const CGFloat kHudGlowRadius  = 5.0;

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

- (void)setHudTitlePointSize:(CGFloat)v { if (_hudTitlePointSize == v) return; _hudTitlePointSize = v; [self setDirty:YES]; }
- (void)setHudBodyPointSize:(CGFloat)v  { if (_hudBodyPointSize  == v) return; _hudBodyPointSize  = v; [self setDirty:YES]; }
- (void)setHudTitleAlpha:(CGFloat)v     { if (_hudTitleAlpha     == v) return; _hudTitleAlpha     = v; [self setDirty:YES]; }
- (void)setHudBodyAlpha:(CGFloat)v      { if (_hudBodyAlpha      == v) return; _hudBodyAlpha      = v; [self setDirty:YES]; }

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

- (NSImage *)hudImage {
    NSRange nl = [_stringValue rangeOfString:@"\n"];
    NSString *titleLine = [_stringValue substringToIndex:nl.location];
    NSString *bodyText  = [_stringValue substringFromIndex:nl.location + 1];

    CGFloat titlePts = MAX(self.minimumPointSize, _hudTitlePointSize);
    CGFloat bodyPts  = MAX(self.minimumPointSize, _hudBodyPointSize);
    NSFont *titleFont = [self.delegate badgeLabelFontOfSize:titlePts];
    NSFont *bodyFont  = [self.delegate badgeLabelFontOfSize:bodyPts];

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: [_fillColor colorWithAlphaComponent:_hudTitleAlpha],
        NSParagraphStyleAttributeName: _hudParagraphStyle,
    };
    NSDictionary *bodyAttrs = @{
        NSFontAttributeName: bodyFont,
        NSForegroundColorAttributeName: [_fillColor colorWithAlphaComponent:_hudBodyAlpha],
        NSParagraphStyleAttributeName: _hudParagraphStyle,
    };

    NSSize maxSize = self.maxSize;
    CGFloat maxW = maxSize.width - 2 * kHudHPad;
    BOOL truncated;

    // Step 1: measure title to determine panel width.
    NSSize titleSize = [titleLine it_boundingRectWithSize:NSMakeSize(maxW, CGFLOAT_MAX)
                                              attributes:titleAttrs
                                               truncated:&truncated].size;

    // Panel uses the full allowed width so body text has room and wraps cleanly.
    const CGFloat underlineH = 1.0;
    CGFloat W = maxSize.width;
    CGFloat drawW = W - 2 * kHudHPad;

    // Step 2: measure body at the actual drawing width so wrapping is reflected in H.
    NSSize bodySize = [bodyText it_boundingRectWithSize:NSMakeSize(drawW, CGFLOAT_MAX)
                                            attributes:bodyAttrs
                                             truncated:&truncated].size;

    CGFloat H = 4 * kHudVPad + titleSize.height + underlineH + bodySize.height;

    if (W <= 0 || H <= 0) {
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(W, H)];
    [image lockFocus];

    // All drawing in native NSImage Y-up coordinates (y=0 at bottom, high y = top of badge).
    // drawWithRect:options: places the first text line at the TOP (high-y) of the rect.
    //
    // Layout from bottom to top of image:
    //   kHudVPad | body | kHudVPad | underline | kHudVPad | title | kHudVPad
    //
    // Rect positions (y = bottom of rect, top = y + height):
    //   body:   y=kHudVPad,                                    h=bodySize.height
    //   uline:  y=kHudVPad+bodySize.height+kHudVPad
    //   title:  y=kHudVPad+bodySize.height+kHudVPad+uH+kHudVPad, h=titleSize.height

    NSRect bounds = NSMakeRect(0, 0, W, H);
    NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                          xRadius:kHudCornerRadius
                                                          yRadius:kHudCornerRadius];
    NSColor *bg = _hudBackgroundColor
        ?: [NSColor colorWithCalibratedRed:0.90 green:0.93 blue:0.98 alpha:0.15];
    [bg setFill];
    [frame fill];

    [NSGraphicsContext saveGraphicsState];
    NSShadow *glow = [[NSShadow alloc] init];
    glow.shadowColor = [_fillColor colorWithAlphaComponent:0.6];
    glow.shadowBlurRadius = kHudGlowRadius;
    glow.shadowOffset = NSZeroSize;
    [glow set];
    [[_fillColor colorWithAlphaComponent:0.85] setStroke];
    [frame setLineWidth:kHudOuterWidth];
    [frame stroke];
    [NSGraphicsContext restoreGraphicsState];

    // Underline
    CGFloat underlineY = kHudVPad + bodySize.height + kHudVPad;
    NSBezierPath *ul = [NSBezierPath bezierPath];
    [ul moveToPoint:NSMakePoint(kHudHPad, underlineY)];
    [ul lineToPoint:NSMakePoint(W - kHudHPad, underlineY)];
    [[_fillColor colorWithAlphaComponent:0.5] setStroke];
    [ul setLineWidth:underlineH];
    [ul stroke];

    // Title — rect top (high y) = H - kHudVPad, first line drawn there → top of badge.
    CGFloat titleY = kHudVPad + bodySize.height + kHudVPad + underlineH + kHudVPad;
    NSRect titleRect = NSMakeRect(kHudHPad, titleY, W - 2 * kHudHPad, titleSize.height);
    NSAttributedString *titleStr = [[NSAttributedString alloc] initWithString:titleLine
                                                                   attributes:titleAttrs];
    [titleStr drawWithRect:titleRect options:NSStringDrawingUsesLineFragmentOrigin context:nil];

    // Body — rect top (high y) = kHudVPad + bodySize.height, drawn just below underline.
    NSRect bodyRect = NSMakeRect(kHudHPad, kHudVPad, W - 2 * kHudHPad, bodySize.height);
    NSAttributedString *bodyStr = [[NSAttributedString alloc] initWithString:bodyText
                                                                  attributes:bodyAttrs];
    [bodyStr drawWithRect:bodyRect options:NSStringDrawingUsesLineFragmentOrigin context:nil];

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
        return [self hudImage];
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
