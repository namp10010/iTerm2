//
//  iTermBadgeEditorWindowController.h
//  iTerm2
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermBadgeEditorWindowController;

@protocol iTermBadgeEditorDelegate <NSObject>
- (void)badgeEditor:(iTermBadgeEditorWindowController *)editor
    didCommitFormat:(NSString *)format;
@end

@interface iTermBadgeEditorWindowController : NSWindowController

@property (nonatomic, weak) id<iTermBadgeEditorDelegate> delegate;

- (instancetype)initWithCurrentFormat:(NSString *)format;
- (void)showCenteredInWindowRect:(NSRect)windowRect;

@end

NS_ASSUME_NONNULL_END
