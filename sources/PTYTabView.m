/*
 **  PTYTabView.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: NSTabView subclass.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "PTYTabView.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermSwipeTracker.h"

const NSUInteger kAllModifiers = (NSEventModifierFlagControl |
                                  NSEventModifierFlagCommand |
                                  NSEventModifierFlagOption |
                                  NSEventModifierFlagShift);

@interface PTYTabView()<iTermSwipeTrackerDelegate>
@end

@implementation PTYTabView {
    // Holds references to tabs with the most recently used one at index 0 and least recently used
    // in the last position.
    NSMutableArray *_tabViewItemsInMRUOrder;

    // If set, then the user has cycled at least once and has not yet let up the modifier keys used
    // to cycle. If the shortcut for cycling doesn't have modifiers, then this will always be NO.
    BOOL _isCyclingWithModifierPressed;

    // Modifiers that are being used for cycling tabs. Only valid if _isCyclingWithModifierPressed
    // is YES.
    NSUInteger _cycleModifierFlags;

    // For handling swipe outside PTYTextView, such as on pane title bar.
    iTermSwipeTracker *_swipeTracker;
}

@dynamic delegate;

- (instancetype)initWithFrame:(NSRect)aRect {
    self = [super initWithFrame:aRect];
    if (self) {
        _tabViewItemsInMRUOrder = [[NSMutableArray alloc] init];
        _swipeTracker = [[iTermSwipeTracker alloc] init];
        _swipeTracker.delegate = self;
    }

    return self;
}

#pragma mark - NSView

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.drawsBackground) {
        if ([self.window.appearance.name isEqual:NSAppearanceNameVibrantDark]) {
            [[NSColor blackColor] set];
            dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
            NSRectFill(dirtyRect);
        } else {
            [super drawRect:dirtyRect];
        }
    }
}

#pragma mark - NSTabView

- (void)addTabViewItem:(NSTabViewItem *) aTabViewItem {
    // Let our delegate know
    id<PSMTabViewDelegate> delegate = self.delegate;

    if ([delegate conformsToProtocol:@protocol(PSMTabViewDelegate)]) {
        [delegate tabView:self willAddTabViewItem:aTabViewItem];
    }

    [_tabViewItemsInMRUOrder addObject:aTabViewItem];
    [super addTabViewItem:aTabViewItem];
}

- (void)removeTabViewItem:(NSTabViewItem *)tabViewItemToRemove {
    id<PSMTabViewDelegate> delegate = self.delegate;

    // Query for group-aware replacement BEFORE willRemove mutates group state.
    NSTabViewItem *preferredReplacement = nil;
    if (self.selectedTabViewItem == tabViewItemToRemove &&
        [delegate respondsToSelector:@selector(tabView:preferredReplacementForTabViewItem:)]) {
        preferredReplacement = [delegate tabView:self
                preferredReplacementForTabViewItem:tabViewItemToRemove];
    }

    // Let our delegate know.
    if ([delegate conformsToProtocol:@protocol(PSMTabViewDelegate)]) {
        [delegate tabView:self willRemoveTabViewItem:tabViewItemToRemove];
    }

    [_tabViewItemsInMRUOrder removeObject:tabViewItemToRemove];

    if (self.selectedTabViewItem == tabViewItemToRemove) {
        if (preferredReplacement) {
            [self selectTabViewItem:preferredReplacement];
        } else {
            NSArray<NSTabViewItem *> *items = self.tabViewItems;
            NSInteger index = [items indexOfObject:tabViewItemToRemove];
            if (index != NSNotFound) {
                if (![iTermAdvancedSettingsModel moveLeftAfterClosingTab]) {
                    // Select the next tab to the right if possible
                    if (index + 1 < items.count) {
                        [self selectTabViewItem:items[index + 1]];
                    }
                } else {
                    // Select the next tab to the left if possible
                    if (index == 0 && items.count > 1) {
                        [self selectTabViewItem:items[1]];
                    } else if (index > 0) {
                        [self selectTabViewItem:items[index - 1]];
                    }
                }
            }
        }
    }

    // Remove the item.
    [super removeTabViewItem:tabViewItemToRemove];
}

- (void)insertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(NSInteger)theIndex {
    // Let our delegate know
    id<PSMTabViewDelegate> delegate = self.delegate;

    // Check the boundary
    if (theIndex > [self numberOfTabViewItems]) {
        theIndex = [self numberOfTabViewItems];
    }

    if ([delegate conformsToProtocol:@protocol(PSMTabViewDelegate)]) {
        [delegate tabView:self willInsertTabViewItem:tabViewItem atIndex:theIndex];
    }
    [_tabViewItemsInMRUOrder addObject:tabViewItem];

    [super insertTabViewItem:tabViewItem atIndex:theIndex];
}

- (void)selectTabViewItem:(NSTabViewItem *)tabViewItem {
    [super selectTabViewItem:tabViewItem];

    if (!_isCyclingWithModifierPressed) {
        [_tabViewItemsInMRUOrder removeObject:tabViewItem];
        [_tabViewItemsInMRUOrder insertObject:tabViewItem atIndex:0];
    }
}

- (void)selectTab:(id)sender {
    [self selectTabViewItemWithIdentifier:[sender representedObject]];
}

- (BOOL)shouldSkipTabViewItem:(NSTabViewItem *)item {
    id<PSMTabViewDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(tabView:shouldSkipTabViewItem:)]) {
        return [d tabView:self shouldSkipTabViewItem:item];
    }
    return NO;
}

- (void)previousTab:(id)sender {
    NSArray<NSTabViewItem *> *items = self.tabViewItems;
    NSInteger count = items.count;
    if (count == 0) {
        return;
    }
    NSInteger currentIndex = [items indexOfObject:[self selectedTabViewItem]];
    if (currentIndex == NSNotFound) {
        return;
    }
    for (NSInteger i = 1; i <= count; i++) {
        NSInteger candidateIndex = (currentIndex - i + count) % count;
        NSTabViewItem *candidate = items[candidateIndex];
        if (![self shouldSkipTabViewItem:candidate]) {
            [self selectTabViewItem:candidate];
            return;
        }
    }
}

- (void)nextTab:(id)sender {
    NSArray<NSTabViewItem *> *items = self.tabViewItems;
    NSInteger count = items.count;
    if (count == 0) {
        return;
    }
    NSInteger currentIndex = [items indexOfObject:[self selectedTabViewItem]];
    if (currentIndex == NSNotFound) {
        return;
    }
    for (NSInteger i = 1; i <= count; i++) {
        NSInteger candidateIndex = (currentIndex + i) % count;
        NSTabViewItem *candidate = items[candidateIndex];
        if (![self shouldSkipTabViewItem:candidate]) {
            [self selectTabViewItem:candidate];
            return;
        }
    }
}

- (void)cycleForwards:(BOOL)forwards {
    NSInteger count = [_tabViewItemsInMRUOrder count];
    if (count == 0) {
        return;
    }
    NSTabViewItem *current = [self selectedTabViewItem];
    NSInteger theIndex = [_tabViewItemsInMRUOrder indexOfObject:current];
    if (theIndex == NSNotFound) {
        theIndex = 0;
    }
    for (NSInteger i = 0; i < count; i++) {
        if (forwards) {
            theIndex = (theIndex + 1) % count;
        } else {
            theIndex = (theIndex - 1 + count) % count;
        }
        NSTabViewItem *candidate = _tabViewItemsInMRUOrder[theIndex];
        if (![self shouldSkipTabViewItem:candidate]) {
            // The MRU order won't be changed by cycling until you let up the modifier key in
            // cycleFlagsChanged:.
            [self selectTabViewItem:candidate];
            return;
        }
    }
}

- (void)cycleKeyDownWithModifiers:(NSUInteger)modifierFlags forwards:(BOOL)forwards {
    if (!_isCyclingWithModifierPressed) {
        // Initial press; set modifier mask from current modifiers
        _cycleModifierFlags = (modifierFlags & kAllModifiers);
        _isCyclingWithModifierPressed = (_cycleModifierFlags != 0);
    }
    [self cycleForwards:forwards];
}

- (void)cycleFlagsChanged:(NSUInteger)modifierFlags {
    if (_isCyclingWithModifierPressed && ((modifierFlags & _cycleModifierFlags) == 0)) {
        // Modifiers released while cycling.
        _isCyclingWithModifierPressed = NO;
        // While this looks like a no-op, it has the effect of re-ordering the MRU list.
        [self selectTabViewItem:[self selectedTabViewItem]];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    DLog(@"%@", event);
    if (![_swipeTracker handleEvent:event]) {
        [super scrollWheel:event];
    }
}

#pragma mark - iTermSwipeTrackerDelegate

- (iTermSwipeState *)swipeTrackerWillBeginNewSwipe:(iTermSwipeTracker *)tracker {
    if (!self.swipeHandler) {
        return nil;
    }
    return [[iTermSwipeState alloc] initWithSwipeHandler:self.swipeHandler];
}

- (BOOL)swipeTrackerShouldBeginNewSwipe:(iTermSwipeTracker *)tracker {
    return [self.swipeHandler swipeHandlerShouldBeginNewSwipe];
}

@end
