#import <Cocoa/Cocoa.h>

@class PTYTab;

NS_ASSUME_NONNULL_BEGIN

// Default preset colours for tab groups (indices into tabColorMenuOptions).
// When a group is created, the next unused colour from this palette is assigned.
extern NSArray<NSColor *> *iTermTabGroupPresetColors(void);

@interface iTermTabGroup : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, getter=isCollapsed) BOOL collapsed;
@property (nonatomic, readonly) NSArray<PTYTab *> *tabs;

- (instancetype)initWithColor:(NSColor *)color;
- (instancetype)initWithColor:(NSColor *)color name:(nullable NSString *)name;
- (instancetype)initWithIdentifier:(NSString *)identifier
                             color:(NSColor *)color
                              name:(nullable NSString *)name;

- (void)addTab:(PTYTab *)tab;
- (void)insertTab:(PTYTab *)tab atIndex:(NSUInteger)index;
- (void)removeTab:(PTYTab *)tab;
- (BOOL)containsTab:(PTYTab *)tab;
- (BOOL)isEmpty;

@end

NS_ASSUME_NONNULL_END
