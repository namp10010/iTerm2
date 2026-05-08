//
//  iTermBadgeEditorWindowController.m
//  iTerm2
//

#import "iTermBadgeEditorWindowController.h"

static const CGFloat kPanelWidth = 420.0;
static const CGFloat kPanelHeight = 90.0;
static const CGFloat kCornerRadius = 10.0;
static const CGFloat kPad = 10.0;

@interface iTermBadgeEditorPanel : NSPanel
@end

@implementation iTermBadgeEditorPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

@end

@protocol iTermBadgeTextViewDelegate <NSObject>
- (void)badgeTextViewDidCommit:(NSTextView *)textView;
- (void)badgeTextViewDidCancel:(NSTextView *)textView;
@end

@interface iTermBadgeTextView : NSTextView
@property (nonatomic, weak) id<iTermBadgeTextViewDelegate> badgeDelegate;
@end

@implementation iTermBadgeTextView

- (void)keyDown:(NSEvent *)event {
    // CMD+Return → commit
    if ((event.modifierFlags & NSEventModifierFlagCommand) &&
        (event.keyCode == 36 || event.keyCode == 76)) {
        [self.badgeDelegate badgeTextViewDidCommit:self];
        return;
    }
    // Escape → cancel
    if (event.keyCode == 53) {
        [self.badgeDelegate badgeTextViewDidCancel:self];
        return;
    }
    [super keyDown:event];
}

@end

@implementation iTermBadgeEditorWindowController {
    iTermBadgeTextView *_textView;
    NSString *_currentFormat;
}

- (instancetype)initWithCurrentFormat:(NSString *)format {
    NSRect frame = NSMakeRect(0, 0, kPanelWidth, kPanelHeight);
    iTermBadgeEditorPanel *panel =
        [[iTermBadgeEditorPanel alloc]
            initWithContentRect:frame
                      styleMask:(NSWindowStyleMaskNonactivatingPanel |
                                 NSWindowStyleMaskBorderless)
                        backing:NSBackingStoreBuffered
                          defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = YES;
    panel.level = NSFloatingWindowLevel;
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = YES;

    self = [super initWithWindow:panel];
    if (self) {
        _currentFormat = [format copy];
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    NSVisualEffectView *blur = [[NSVisualEffectView alloc] initWithFrame:content.bounds];
    blur.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    blur.material = NSVisualEffectMaterialHUDWindow;
    blur.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    blur.state = NSVisualEffectStateActive;
    blur.wantsLayer = YES;
    blur.layer.cornerRadius = kCornerRadius;
    blur.layer.masksToBounds = YES;
    [content addSubview:blur];

    NSRect scrollFrame = NSMakeRect(kPad, kPad,
                                    kPanelWidth - 2 * kPad,
                                    kPanelHeight - 2 * kPad);
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:scrollFrame];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;

    _textView = [[iTermBadgeTextView alloc] initWithFrame:scrollView.bounds];
    _textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _textView.font = [NSFont fontWithName:@"Menlo" size:11];
    _textView.textColor = [NSColor textColor];
    _textView.insertionPointColor = [NSColor textColor];
    _textView.drawsBackground = NO;
    _textView.richText = NO;
    _textView.allowsUndo = YES;
    _textView.automaticQuoteSubstitutionEnabled = NO;
    _textView.automaticDashSubstitutionEnabled = NO;
    _textView.automaticSpellingCorrectionEnabled = NO;
    _textView.continuousSpellCheckingEnabled = NO;
    _textView.string = [self displayStringFromFormat:_currentFormat];
    _textView.badgeDelegate = self;

    scrollView.documentView = _textView;
    [content addSubview:scrollView];
}

- (NSString *)displayStringFromFormat:(NSString *)format {
    return [format stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
}

- (NSString *)formatFromDisplayString:(NSString *)display {
    return [display stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
}

- (void)showCenteredInWindowRect:(NSRect)windowRect {
    CGFloat x = NSMidX(windowRect) - kPanelWidth / 2.0;
    CGFloat y = NSMaxY(windowRect) - 120.0 - kPanelHeight;
    [self.window setFrameOrigin:NSMakePoint(x, y)];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:_textView];
    [_textView selectAll:nil];
}

#pragma mark - iTermBadgeTextViewDelegate

- (void)badgeTextViewDidCommit:(NSTextView *)textView {
    NSString *newFormat = [self formatFromDisplayString:_textView.string];
    [self.delegate badgeEditor:self didCommitFormat:newFormat];
    [self.window orderOut:nil];
}

- (void)badgeTextViewDidCancel:(NSTextView *)textView {
    [self.window orderOut:nil];
}

@end
