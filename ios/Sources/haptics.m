// Haptic feedback bridge for iOS. Rust calls `hl_haptic(style)` (see
// src/script.rs); this maps the style to a UIKit feedback generator. On
// non-iOS platforms the Rust side stubs the call out, so this file is only
// ever compiled into the iOS app target.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// winit owns the root view controller, so we can't subclass it to hide the
// home-indicator. Instead, override UIViewController's
// -prefersHomeIndicatorAutoHidden to return YES app-wide (this is the only VC),
// which lets iOS fade the bottom swipe-up indicator out during play.
static BOOL hl_prefers_home_hidden(id self, SEL _cmd) { return YES; }

__attribute__((constructor))
static void hl_home_indicator_setup(void) {
    Method m = class_getInstanceMethod(UIViewController.class,
                                       @selector(prefersHomeIndicatorAutoHidden));
    if (m) method_setImplementation(m, (IMP)hl_prefers_home_hidden);
}

// Fill the safe-area strips the Bevy/winit Metal view doesn't cover (top notch /
// bottom home indicator) with a theme-matched colour, so they read as the
// background continuing rather than a black bar. We ONLY set the window (and
// root-view) backgroundColor, which sits *behind* the Metal content — we never
// add a subview (that risks covering the game) or resize winit's view (that
// shifts touch coordinates).
static float g_sr = 0.14f, g_sg = 0.28f, g_sb = 0.32f;

static NSArray<UIWindow *> *hl_windows(void) {
    NSMutableArray *wins = [NSMutableArray array];
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]])
            [wins addObjectsFromArray:((UIWindowScene *)s).windows];
    if (wins.count == 0)
        [wins addObjectsFromArray:UIApplication.sharedApplication.windows];
    return wins;
}

static const NSInteger HL_BOT_TAG = 0x6249;

static void hl_fill_screen(void) {
    UIColor *c = [UIColor colorWithRed:g_sr green:g_sg blue:g_sb alpha:1.0];
    for (UIWindow *w in hl_windows()) {
        w.backgroundColor = c;
        UIViewController *vc = w.rootViewController;
        UIView *host = vc.view ?: w;
        if (vc) [vc setNeedsUpdateOfHomeIndicatorAutoHidden];
        // The Metal drawable is inset above the bottom home-indicator strip, so
        // that strip renders black. Cover ONLY that strip with a theme-coloured
        // view (it sits outside all game content, so it can never hide the game).
        CGFloat bottom = w.safeAreaInsets.bottom;
        UIView *strip = [host viewWithTag:HL_BOT_TAG];
        if (bottom > 0.5) {
            CGRect f = CGRectMake(0, host.bounds.size.height - bottom, host.bounds.size.width, bottom);
            if (!strip) {
                strip = [[UIView alloc] initWithFrame:f];
                strip.tag = HL_BOT_TAG;
                strip.userInteractionEnabled = NO;
                strip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
                [host addSubview:strip];
            } else {
                strip.frame = f;
            }
            strip.backgroundColor = c;
            [host bringSubviewToFront:strip];
        }
    }
}

// Theme colour for the safe-area strips, driven from Rust (src/background.rs).
void hl_safe_color(float r, float g, float b) {
    g_sr = r; g_sg = g; g_sb = b;
    dispatch_async(dispatch_get_main_queue(), ^{ hl_fill_screen(); });
}

__attribute__((constructor))
static void hl_window_bg_setup(void) {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *_note) {
        hl_fill_screen();
        for (double d = 0.4; d <= 2.0; d += 0.6) {   // re-apply once winit is fully up
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ hl_fill_screen(); });
        }
    }];
}

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
