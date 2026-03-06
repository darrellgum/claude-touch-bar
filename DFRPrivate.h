// Bridging header for private DFRFoundation / TouchBar APIs
// These symbols exist in the DFRFoundation private framework on Touch Bar Macs.

#import <AppKit/AppKit.h>

typedef NS_ENUM(long long, DFRElementType) {
    DFRElementTypeStandard = 1,
    DFRElementTypeSystem = 2,
};

extern void DFRElementSetControlStripPresenceForIdentifier(NSString *identifier, BOOL present);
extern void DFRSystemStatusItemSetEnabled(NSString *identifier, BOOL enabled);

@interface NSTouchBarItem (PrivateDFR)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (PrivateDFR)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
          systemTrayItemIdentifier:(NSString *)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
@end
