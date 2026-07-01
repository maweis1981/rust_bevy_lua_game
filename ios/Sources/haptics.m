// Haptic feedback bridge for iOS. Rust calls `hl_haptic(style)` (see
// src/script.rs); this maps the style to a UIKit feedback generator. On
// non-iOS platforms the Rust side stubs the call out, so this file is only
// ever compiled into the iOS app target.
#import <UIKit/UIKit.h>

// style: 0 = light, 1 = medium, 2 = heavy impact, 3 = "success" notification.
void hl_haptic(int style) {
    if (@available(iOS 10.0, *)) {
        // UIKit feedback generators must be used on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (style == 3) {
                UINotificationFeedbackGenerator *g =
                    [[UINotificationFeedbackGenerator alloc] init];
                [g prepare];
                [g notificationOccurred:UINotificationFeedbackTypeSuccess];
            } else {
                UIImpactFeedbackStyle s = UIImpactFeedbackStyleLight;
                if (style == 1) s = UIImpactFeedbackStyleMedium;
                else if (style >= 2) s = UIImpactFeedbackStyleHeavy;
                UIImpactFeedbackGenerator *g =
                    [[UIImpactFeedbackGenerator alloc] initWithStyle:s];
                [g prepare];
                [g impactOccurred];
            }
        });
    }
}
