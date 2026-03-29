//
//  iTermAboutWindowController.m
//  iTerm2
//
//  Created by George Nachman on 9/21/14.
//
//

#import "iTermAboutWindowController.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermController.h"
#import "iTermLaunchExperienceController.h"
#import "iTermPreferences.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "PTYWindow.h"
#import "PseudoTerminal.h"

static NSString *iTermAboutWindowControllerWhatsNewURLString = @"iterm2://whats-new/";

@interface iTermAboutWindowContentView : NSVisualEffectView
- (void)configureForDark:(BOOL)dark;
@end

@interface iTermSponsor: NSObject
@property (nonatomic) NSTextField *textField;
@property (nonatomic) NSTrackingArea *trackingArea;
@property (nonatomic) NSView *view;
@property (nonatomic, copy) NSString *url;

+ (instancetype)sponsorWithView:(NSView *)view textField:(NSTextField *)textField container:(NSView *)container url:(NSString *)url;
@end

@implementation iTermSponsor
+ (instancetype)sponsorWithView:(NSView *)view textField:(NSTextField *)textField container:(NSView *)container url:(NSString *)url {
    iTermSponsor *sponsor = [[iTermSponsor alloc] init];
    sponsor.view = view;
    sponsor.textField = textField;
    sponsor.url = url;

    // Create a tracking area for the sponsor's view
    sponsor.trackingArea = [[NSTrackingArea alloc] initWithRect:view.frame
                                                        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                          owner:container
                                                       userInfo:nil];
    [view addTrackingArea:sponsor.trackingArea];
    if (textField) {
        NSDictionary *attrs = @{
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
        };
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:[textField stringValue] attributes:attrs];
        [textField setAttributedStringValue:attributedString];
    }
    return sponsor;
}

- (void)updateTrackingAreaForContainer:(NSView *)container {
    [container removeTrackingArea:self.trackingArea];
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.view.frame
                                                    options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                      owner:container
                                                   userInfo:nil];
    [container addTrackingArea:self.trackingArea];
}
@end

@implementation iTermAboutWindowContentView {
    IBOutlet NSScrollView *_bottomAlignedScrollView;
    IBOutlet NSTextView *_sponsorsHeading;

    IBOutlet NSView *_whitebox;

    IBOutlet NSView *_codeRabbit;
    IBOutlet NSView *_serpApi;

    NSArray<iTermSponsor *> *_sponsors;
    NSView *_sponsorWrapper;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self updateLayout];
}

- (void)updateLayout {
    if (!_sponsorWrapper) {
        return;
    }

    // Sponsor logos are top-pinned (NSViewMinYMargin) in the XIB.
    // Their Y origin moves with the window height. Find the bottom-most Y origin.
    CGFloat sponsorLogoMinY = MIN(MIN(_whitebox.frame.origin.y, _codeRabbit.frame.origin.y),
                                  _serpApi.frame.origin.y);
    CGFloat headingTop = NSMaxY(_sponsorsHeading.frame);

    // Guard: logos and heading haven't been positioned yet (frame.origin is zero).
    if (sponsorLogoMinY == 0 || headingTop == 0) {
        return;
    }

    // Sponsor wrapper: encloses logos + heading with generous padding on each side.
    const CGFloat kWrapperInset = 16;
    const CGFloat kWrapperGap = 12;
    CGFloat wrapperY = sponsorLogoMinY - kWrapperGap;
    CGFloat wrapperHeight = (headingTop + kWrapperGap) - wrapperY;
    _sponsorWrapper.frame = NSMakeRect(kWrapperInset,
                                       wrapperY,
                                       self.frame.size.width - kWrapperInset * 2,
                                       wrapperHeight);

    // Patron scroll view: bottom-pinned at kBottomMargin, fills up to the sponsor wrapper.
    const CGFloat kBottomMargin = 16;
    const CGFloat kScrollGap = 20;
    CGFloat scrollHeight = wrapperY - kScrollGap - kBottomMargin;
    NSRect scrollFrame = NSMakeRect(kWrapperInset,
                                    kBottomMargin,
                                    self.frame.size.width - kWrapperInset * 2,
                                    MAX(scrollHeight, 40));
    _bottomAlignedScrollView.frame = scrollFrame;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.material = NSVisualEffectMaterialHUDWindow;
    self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.state = NSVisualEffectStateActive;

    _bottomAlignedScrollView.drawsBackground = NO;

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    _sponsorsHeading.selectable = YES;
    _sponsorsHeading.editable = NO;
    [_sponsorsHeading.textStorage setAttributedString:[NSAttributedString attributedStringWithHTML:_sponsorsHeading.textStorage.string
                                                                                              font:_sponsorsHeading.font
                                                                                    paragraphStyle:paragraphStyle]];

    // HTML parsing injects explicit blue NSForegroundColorAttributeName on link ranges.
    // linkTextAttributes can't override stored attributes in a non-editable NSTextView,
    // so we patch the storage directly.
    NSDictionary *subtleLinkAttributes = @{
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSCursorAttributeName: [NSCursor pointingHandCursor]
    };
    _sponsorsHeading.linkTextAttributes = subtleLinkAttributes;
    [_sponsorsHeading.textStorage enumerateAttribute:NSLinkAttributeName
                                             inRange:NSMakeRange(0, _sponsorsHeading.textStorage.length)
                                             options:0
                                          usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) {
            [_sponsorsHeading.textStorage addAttributes:subtleLinkAttributes range:range];
        }
    }];

    // The SVG is a white+orange logo designed for dark backgrounds.
    // Load it programmatically so NSImage's bundle lookup finds it by path,
    // bypassing the XIB image-name resolution which is unreliable for SVG.
    NSString *svgPath = [[NSBundle mainBundle] pathForResource:@"coderabbitai" ofType:@"svg"];
    if (svgPath) {
        NSImage *svgLogo = [[NSImage alloc] initWithContentsOfFile:svgPath];
        if (svgLogo) {
            [(NSImageView *)_codeRabbit setImage:svgLogo];
        }
    }

    _sponsors = @[ [iTermSponsor sponsorWithView:_whitebox
                                       textField:nil
                                       container:self
                                             url:@"https://whitebox.so/?utm_source=iTerm2"],
                   [iTermSponsor sponsorWithView:_codeRabbit
                                       textField:nil
                                       container:self
                                             url:@"https://coderabbit.ai/"],
                   [iTermSponsor sponsorWithView:_serpApi
                                       textField:nil
                                       container:self
                                             url:@"https://serpapi.com/?utm_source=iterm"]];
}

- (void)configureForDark:(BOOL)dark {
    self.material = NSVisualEffectMaterialHUDWindow;
    self.blendingMode = NSVisualEffectBlendingModeBehindWindow;

    // Patron scroll: single rounded box — background on the scroll view itself.
    // masksToBounds clips content to the rounded rect; the overlay scroller auto-hides
    // so its brief clipping at the corners is imperceptible.
    // textContainerInset=12pt keeps text clear of the 10pt corner radius.
    _bottomAlignedScrollView.drawsBackground = NO;
    _bottomAlignedScrollView.contentView.drawsBackground = NO;
    _bottomAlignedScrollView.hasVerticalScroller = YES;
    _bottomAlignedScrollView.autohidesScrollers = YES;
    _bottomAlignedScrollView.wantsLayer = YES;
    _bottomAlignedScrollView.layer.cornerRadius = 10;
    _bottomAlignedScrollView.layer.masksToBounds = YES;
    _bottomAlignedScrollView.layer.backgroundColor = dark
        ? [NSColor colorWithWhite:0 alpha:0.18].CGColor
        : [NSColor colorWithWhite:1 alpha:0.22].CGColor;

    // Sponsor wrapper: subtle inner grouping behind heading + logos.
    // Frame is set dynamically by updateLayout.
    const CGFloat kWrapperInset = 16;
    _sponsorWrapper = [[NSView alloc] initWithFrame:NSMakeRect(kWrapperInset, 0,
                                                                self.frame.size.width - kWrapperInset * 2,
                                                                80)];
    _sponsorWrapper.wantsLayer = YES;
    _sponsorWrapper.layer.cornerRadius = 8;
    _sponsorWrapper.layer.backgroundColor = dark
        ? [NSColor colorWithWhite:1 alpha:0.07].CGColor
        : [NSColor colorWithWhite:0 alpha:0.05].CGColor;
    _sponsorWrapper.autoresizingMask = NSViewNotSizable;
    [self addSubview:_sponsorWrapper positioned:NSWindowBelow relativeTo:nil];

    [self updateLayout];
}


- (void)mouseEntered:(NSEvent *)theEvent {
    [NSCursor.pointingHandCursor set];
}

- (void)mouseExited:(NSEvent *)theEvent {
    [NSCursor.arrowCursor set];
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (theEvent.clickCount == 1) {
        NSPoint locationInView = [self convertPoint:theEvent.locationInWindow fromView:nil];
        [_sponsors enumerateObjectsUsingBlock:^(iTermSponsor * _Nonnull sponsor, NSUInteger idx, BOOL * _Nonnull stop) {
            if (NSPointInRect(locationInView, sponsor.view.frame)) {
                // Open the link
                [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:sponsor.url]];
            }
        }];
    }
}

// Don't forget to update the tracking area when the view resizes
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    [_sponsors enumerateObjectsUsingBlock:^(iTermSponsor * _Nonnull sponsor, NSUInteger idx, BOOL * _Nonnull stop) {
        [sponsor updateTrackingAreaForContainer:self];
    }];
}

@end

@interface iTermAboutWindowController()<NSTextViewDelegate>
@end

@implementation iTermAboutWindowController {
    IBOutlet NSTextView *_dynamicText;
    IBOutlet NSTextView *_patronsTextView;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super initWithWindowNibName:@"AboutWindow"];
    if (self) {
        NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
        NSString *const versionNumber = myDict[(NSString *)kCFBundleVersionKey];
        NSString *versionString = [NSString stringWithFormat: @"Build %@\n", versionNumber];
        NSAttributedString *whatsNew = nil;
        if ([versionNumber hasPrefix:@"3.6."] || [versionString isEqualToString:@"unknown"]) {
            whatsNew = [self attributedStringWithLinkToURL:iTermAboutWindowControllerWhatsNewURLString
                                                     title:@"What’s New in 3.6?\n"];
        }

        NSAttributedString *webAString = [self attributedStringWithLinkToURL:@"https://iterm2.com/"
                                                                       title:@"Home Page"];
        NSAttributedString *bugsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/bugs"
                                              title:@"Report a bug"];
        NSAttributedString *creditsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/credits"
                                              title:@"Credits"];

        // Force IBOutlets to be bound by creating window.
        [self window];

        iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        BOOL isDark = NO;
        if (preferredStyle == TAB_STYLE_DARK || preferredStyle == TAB_STYLE_DARK_HIGH_CONTRAST) {
            isDark = YES;
        } else if (preferredStyle == TAB_STYLE_MINIMAL) {
            PseudoTerminal *terminal = [[iTermController sharedInstance] currentTerminal];
            NSColor *bgColor = [terminal.ptyWindow it_terminalWindowDecorationBackgroundColor];
            isDark = bgColor.perceivedBrightness < 0.5;
        }

        // Always transparent — frosted glass over the desktop.
        // VibrantDark makes the HUDWindow material render as a dark tint; default (nil) renders light.
        self.window.backgroundColor = [NSColor clearColor];
        if (isDark) {
            self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        }

        // Resize to 75% of the screen height before configuring the content view,
        // so configureForDark: sees the final window dimensions.
        NSScreen *screen = [NSScreen mainScreen] ?: self.window.screen;
        if (screen) {
            CGFloat targetHeight = screen.visibleFrame.size.height * 0.75;
            NSRect windowFrame = self.window.frame;
            CGFloat delta = targetHeight - windowFrame.size.height;
            windowFrame.size.height = targetHeight;
            windowFrame.origin.y -= delta;
            [self.window setFrame:windowFrame display:NO];
        }

        [(iTermAboutWindowContentView *)self.window.contentView configureForDark:isDark];

        NSDictionary *versionAttributes = @{
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium]
        };
        NSAttributedString *bullet = [[NSAttributedString alloc] initWithString:@" ∙ "
                                                                     attributes:versionAttributes];
        [_dynamicText setLinkTextAttributes:self.linkTextViewAttributes];
        [[_dynamicText textStorage] deleteCharactersInRange:NSMakeRange(0, [[_dynamicText textStorage] length])];
        [[_dynamicText textStorage] appendAttributedString:[[NSAttributedString alloc] initWithString:versionString
                                                                                            attributes:versionAttributes]];
        if (whatsNew) {
            [[_dynamicText textStorage] appendAttributedString:whatsNew];
        }
        [[_dynamicText textStorage] appendAttributedString:webAString];
        [[_dynamicText textStorage] appendAttributedString:bullet];
        [[_dynamicText textStorage] appendAttributedString:bugsAString];
        [[_dynamicText textStorage] appendAttributedString:bullet];
        [[_dynamicText textStorage] appendAttributedString:creditsAString];
        [_dynamicText setAlignment:NSTextAlignmentCenter
                             range:NSMakeRange(0, [[_dynamicText textStorage] length])];

        [self setPatronsString:[self defaultPatronsString] animate:NO];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURL *url = [NSURL URLWithString:@"https://iterm2.com/patrons.txt"];
            NSData *data = [NSData dataWithContentsOfURL:url];
            NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSArray<NSString *> *patronNames = string.length > 0 ? [string componentsSeparatedByString:@"\n"] : nil;
            patronNames = [patronNames filteredArrayUsingBlock:^BOOL(NSString *name) {
                return name.length > 0;
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setPatrons:patronNames];
            });
        });
    }
    return self;
}

- (NSDictionary *)linkTextViewAttributes {
    return @{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
              NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
              NSCursorAttributeName: [NSCursor pointingHandCursor] };
}

- (void)setPatronsString:(NSAttributedString *)patronsAttributedString animate:(BOOL)animate {
    [_patronsTextView setLinkTextAttributes:self.linkTextViewAttributes];
    [[_patronsTextView textStorage] setAttributedString:patronsAttributedString];
    [_patronsTextView setAlignment:NSTextAlignmentLeft
                         range:NSMakeRange(0, [[_patronsTextView textStorage] length])];
    _patronsTextView.horizontallyResizable = NO;
    // Re-apply after every content change: setAlignment: triggers a layout pass
    // that can restore the text view's default insets.
    _patronsTextView.textContainerInset = NSMakeSize(12, 0);
    _patronsTextView.textContainer.lineFragmentPadding = 0;
}

- (NSAttributedString *)defaultPatronsString {
    NSString *string = [NSString stringWithFormat:@"Loading supporters…"];
    NSMutableAttributedString *attributedString =
        [[NSMutableAttributedString alloc] initWithString:string
                                               attributes:self.attributes];
    return attributedString;
}

- (NSDictionary *)attributes {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    [style setLineSpacing:5];
    return @{ NSForegroundColorAttributeName: [NSColor labelColor],
              NSParagraphStyleAttributeName: style,
              NSFontAttributeName: [NSFont systemFontOfSize:13]
    };
}

- (void)setPatrons:(NSArray *)patronNames {
    if (!patronNames.count) {
        [self setPatronsString:[[NSAttributedString alloc] initWithString:@"Error loading patrons :("
                                                                attributes:[self attributes]]
                       animate:NO];
        return;
    }

    NSArray *sortedNames = [patronNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString *string = [sortedNames componentsJoinedWithOxfordComma];
    NSDictionary *attributes = [self attributes];
    NSMutableAttributedString *attributedString =
        [[NSMutableAttributedString alloc] initWithString:string
                                               attributes:attributes];
    NSAttributedString *period = [[NSAttributedString alloc] initWithString:@"."];
    [attributedString appendAttributedString:period];

    [self setPatronsString:attributedString animate:YES];
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSString *)urlString title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    NSString *localizedTitle = title;
    return [[NSAttributedString alloc] initWithString:localizedTitle
                                            attributes:linkAttributes];
}

#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    NSURL *url = [NSURL castFrom:link];
    if ([url.absoluteString isEqualToString:iTermAboutWindowControllerWhatsNewURLString]) {
        [iTermLaunchExperienceController forceShowWhatsNew];
        return YES;
    }
    return NO;
}

@end
