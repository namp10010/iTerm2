#import "iTermTabGroup.h"
#import "iTermAdvancedSettingsModel.h"
#import "PTYTab.h"
#import "NSColor+iTerm.h"

NSArray<NSColor *> *iTermTabGroupPresetColors(void) {
    NSString *hexString = [iTermAdvancedSettingsModel tabColorMenuOptions];
    NSMutableArray<NSColor *> *colors = [NSMutableArray array];
    for (NSString *component in [hexString componentsSeparatedByString:@" "]) {
        NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }
        NSColor *color = [NSColor colorFromHexString:trimmed];
        if (color) {
            [colors addObject:color];
        }
    }
    return colors;
}

@implementation iTermTabGroup {
    NSMutableArray<PTYTab *> *_tabs;
}

- (instancetype)initWithColor:(NSColor *)color {
    return [self initWithColor:color name:nil];
}

- (instancetype)initWithColor:(NSColor *)color name:(NSString *)name {
    self = [super init];
    if (self) {
        _identifier = [[NSUUID UUID] UUIDString];
        _color = color;
        _name = [name copy];
        _tabs = [NSMutableArray array];
    }
    return self;
}

- (NSArray<PTYTab *> *)tabs {
    return _tabs;
}

- (void)addTab:(PTYTab *)tab {
    if (![_tabs containsObject:tab]) {
        [_tabs addObject:tab];
        tab.tabGroup = self;
    }
}

- (void)insertTab:(PTYTab *)tab atIndex:(NSUInteger)index {
    if ([_tabs containsObject:tab]) {
        return;
    }
    if (index > _tabs.count) {
        index = _tabs.count;
    }
    [_tabs insertObject:tab atIndex:index];
    tab.tabGroup = self;
}

- (void)removeTab:(PTYTab *)tab {
    [_tabs removeObject:tab];
    if (tab.tabGroup == self) {
        tab.tabGroup = nil;
    }
}

- (BOOL)containsTab:(PTYTab *)tab {
    return [_tabs containsObject:tab];
}

- (BOOL)isEmpty {
    return _tabs.count == 0;
}

@end
