//
//  iTermHotkeyPreferencesModel.h
//  iTerm2
//
//  Created by George Nachman on 7/7/16.
//
//

#import <Foundation/Foundation.h>
#import "iTermShortcut.h"

@interface iTermHotkeyPreferencesModel : NSObject

@property(nonatomic, retain) iTermShortcut *primaryShortcut;

@property(nonatomic, assign) BOOL hasModifierActivation;
@property(nonatomic, assign) iTermHotKeyModifierActivation modifierActivation;

@property(nonatomic, assign) BOOL autoHide;
@property(nonatomic, assign) BOOL showAutoHiddenWindowOnAppActivation;
@property(nonatomic, assign) BOOL animate;
@property(nonatomic, assign) BOOL floats;
@property(nonatomic, retain) NSArray<iTermShortcut *> *alternateShortcuts;
@property(nonatomic, retain) NSArray<NSDictionary *> *alternateShortcutDictionaries;

// Radio buttons
@property(nonatomic, assign) iTermHotKeyDockPreference dockPreference;

// Tab-bar position for the hotkey window. -1 means follow the global setting;
// otherwise a TAB_POSITION_* value (top/bottom/left).
@property(nonatomic, assign) NSInteger tabBarPositionOverride;


@property(nonatomic, readonly) BOOL hotKeyAssigned;
@property(nonatomic, readonly) NSDictionary<NSString *, id> *dictionaryValue;

@end

