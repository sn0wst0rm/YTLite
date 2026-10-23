#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// YouTube 21.42.4 moved the content response to contentPlayerResponse.
// Restore the old getter only when absent, for YTLite 5.2b4 callers.
static id legacyPlayerResponse(id self, SEL cmd) {
    return ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("contentPlayerResponse"));
}
__attribute__((constructor)) static void installCompatibility(void) {
    @autoreleasepool {
        Class cls = objc_getClass("YTPlayerViewController");
        SEL legacy = sel_registerName("playerResponse");
        Method modern = class_getInstanceMethod(cls, sel_registerName("contentPlayerResponse"));
        if (cls && modern && !class_getInstanceMethod(cls, legacy)) {
            BOOL added = class_addMethod(cls, legacy, (IMP)legacyPlayerResponse, method_getTypeEncoding(modern));
            NSLog(@"YTCompatibility: playerResponse bridge installed=%d", added);
        }
    }
}

#import <UIKit/UIKit.h>

static __weak id activePlayer;
static id (*responseBridge)(id, SEL);
static id trackedResponse(id self, SEL cmd) {
    activePlayer = self;
    return responseBridge(self, cmd);
}

@interface YTCompatibilityMenu : NSObject
@property(nonatomic, weak) UINavigationController *settingsNavigation;
+ (instancetype)shared;
- (void)install;
- (void)open:(UIButton *)sender;
- (void)close:(UIBarButtonItem *)sender;
@end

@implementation YTCompatibilityMenu
+ (instancetype)shared {
    static YTCompatibilityMenu *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; });
    return value;
}
- (UIViewController *)presenter:(UIWindow *)window {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed)
        vc = vc.presentedViewController;
    return vc;
}
- (void)install {}
- (void)close:(UIBarButtonItem *)sender {
    [self.settingsNavigation dismissViewControllerAnimated:YES completion:nil];
}
- (void)message:(NSString *)message window:(UIWindow *)window {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"YouTube Plus" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [[self presenter:window] presentViewController:alert animated:YES completion:nil];
}
- (void)open:(UIButton *)sender {
    UIWindow *window = sender.window;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"YouTube Plus" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Impostazioni YouTube Plus" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIViewController *settings = [NSClassFromString(@"SettingsViewController") new];
        if (!settings) return;
        settings.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
        self.settingsNavigation = navigation;
        [[self presenter:window] presentViewController:navigation animated:YES completion:nil];
    }]];
    id player = activePlayer;
    BOOL hasVideo = player && [player respondsToSelector:sel_registerName("currentVideoID")] && ((id(*)(id,SEL))objc_msgSend)(player, sel_registerName("currentVideoID"));
    UIAlertAction *download = [UIAlertAction actionWithTitle:@"Scarica video o audio" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        Class helper = NSClassFromString(@"DownloadMenuHelper");
        SEL selector = sel_registerName("showDownloadSheet:withSender:");
        if (![helper respondsToSelector:selector]) return;
        @try { ((void(*)(id,SEL,id,id))objc_msgSend)(helper, selector, player, sender); }
        @catch (NSException *exception) { NSLog(@"YTCompatibility download: %@", exception.reason); [self message:@"Il menu download non è compatibile con questo video." window:window]; }
    }];
    download.enabled = hasVideo; [menu addAction:download];
    UIAlertAction *speed = [UIAlertAction actionWithTitle:@"Velocità di riproduzione" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *rates = [UIAlertController alertControllerWithTitle:@"Velocità" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *rate in @[@0.25, @0.5, @0.75, @1, @1.25, @1.5, @1.75, @2, @2.5, @3]) {
            [rates addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@×", rate] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                ((void(*)(id,SEL,float))objc_msgSend)(player, sel_registerName("setPlaybackRate:"), rate.floatValue);
            }]];
        }
        [rates addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
        rates.popoverPresentationController.sourceView = sender;
        rates.popoverPresentationController.sourceRect = sender.bounds;
        [[self presenter:window] presentViewController:rates animated:YES completion:nil];
    }];
    speed.enabled = hasVideo && [player respondsToSelector:sel_registerName("setPlaybackRate:")]; [menu addAction:speed];
    UIAlertAction *pip = [UIAlertAction actionWithTitle:@"Picture-in-Picture" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        ((void(*)(id,SEL))objc_msgSend)(player, sel_registerName("switchToPip"));
    }];
    pip.enabled = hasVideo && [player respondsToSelector:sel_registerName("switchToPip")]; [menu addAction:pip];
    [menu addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = sender;
    menu.popoverPresentationController.sourceRect = sender.bounds;
    [[self presenter:window] presentViewController:menu animated:YES completion:nil];
}
@end

static void (*originalSetRenderer)(id, SEL, id);
static void (*originalFloatingRenderer)(id, SEL, id);
static void (*originalClassicRenderer)(id, SEL, id);
static void (*originalDidTap)(id, SEL, id);
static id (*originalSpeedInit)(id, SEL);
static void (*originalPressSpeed)(id, SEL, id);
static void (*originalItemLayout)(id, SEL);
static NSString *const compatibilityPivot = @"FEytplus_compatibility";

static id sendObject(id receiver, const char *selector) {
    SEL sel = sel_registerName(selector);
    return [receiver respondsToSelector:sel] ? ((id(*)(id,SEL))objc_msgSend)(receiver,sel) : nil;
}
static void addCompatibilityItem(id renderer) {
    NSMutableArray *items = [sendObject(renderer, "itemsArray") mutableCopy];
    BOOL exists = NO;
    NSUInteger insertAt = items.count;
    for (NSUInteger i = 0; i < items.count; i++) {
        id item = sendObject(items[i], "pivotBarItemRenderer") ?: sendObject(items[i], "pivotBarIconOnlyItemRenderer");
        NSString *identifier = sendObject(item, "pivotIdentifier");
        if ([identifier isEqual:compatibilityPivot]) exists = YES;
        if ([identifier isEqual:@"FElibrary"] || [identifier isEqual:@"FEyou"]) insertAt = i + 1;
    }
    Class factory = NSClassFromString(@"YTIPivotBarRenderer");
    SEL makeItem = sel_registerName("pivotSupportedRenderersWithBrowseId:title:iconType:");
    if (items && !exists && [factory respondsToSelector:makeItem]) {
        id item = ((id(*)(id,SEL,id,id,int))objc_msgSend)(factory,makeItem,compatibilityPivot,@"YT+",44);
        if (item) {
            id templateItem = sendObject(items.lastObject, "pivotBarItemRenderer");
            id title = [sendObject(templateItem, "title") copy];
            for (id run in sendObject(title, "runsArray")) [run setValue:@"YT+" forKey:@"text"];
            if (title) [sendObject(item, "pivotBarItemRenderer") setValue:title forKey:@"title"];
            [items insertObject:item atIndex:insertAt];
            [renderer setValue:items forKey:@"itemsArray"];
        }
    }
}
static void setPivotRenderer(id self, SEL cmd, id renderer) {
    addCompatibilityItem(renderer);
    originalSetRenderer(self,cmd,renderer);
}
static void setFloatingRenderer(id self, SEL cmd, id renderer) {
    addCompatibilityItem(renderer);
    originalFloatingRenderer(self,cmd,renderer);
}
static void setClassicRenderer(id self, SEL cmd, id renderer) {
    addCompatibilityItem(renderer);
    originalClassicRenderer(self,cmd,renderer);
}
static void didTapPivot(id self, SEL cmd, id renderer) {
    if ([sendObject(renderer, "pivotIdentifier") isEqual:compatibilityPivot]) {
        SEL lookup = sel_registerName("pivotBarItemViewForPivotIdentifier:");
        UIView *anchor = [self respondsToSelector:lookup] ? ((id(*)(id,SEL,id))objc_msgSend)(self,lookup,compatibilityPivot) : nil;
        if (!anchor) anchor = sendObject(self,"view");
        [YTCompatibilityMenu.shared open:(UIButton *)anchor];
        return;
    }
    originalDidTap(self,cmd,renderer);
}
static id speedInit(id self, SEL cmd) {
    id result = originalSpeedInit(self,cmd);
    if (!result) return result;
    @try {
        NSMutableArray *options = [[result valueForKey:@"_options"] mutableCopy];
        Class optionClass = NSClassFromString(@"YTVarispeedSwitchControllerOption");
        for (NSNumber *rate in @[@2.5, @3, @3.5, @4, @5]) {
            BOOL exists = NO;
            for (id option in options) {
                float value = ((float(*)(id,SEL))objc_msgSend)(option,sel_registerName("rate"));
                if (value == rate.floatValue) exists = YES;
            }
            if (!exists) {
                id option = ((id(*)(id,SEL,id,float))objc_msgSend)([optionClass alloc],sel_registerName("initWithTitle:rate:"),[NSString stringWithFormat:@"%@×",rate],rate.floatValue);
                if (option) [options addObject:option];
            }
        }
        if (options) [result setValue:options forKey:@"_options"];
    } @catch (NSException *exception) { NSLog(@"YTCompatibility speed: %@",exception.reason); }
    return result;
}
static void itemLayout(id self, SEL cmd) {
    originalItemLayout(self,cmd);
    if ([sendObject(sendObject(self,"renderer"),"pivotIdentifier") isEqual:compatibilityPivot]) {
        UIButton *button = sendObject(self,"navigationButton");
        static UIImage *icon;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ icon = [[UIImage systemImageNamed:@"gearshape"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]; });
        for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateSelected), @(UIControlStateHighlighted)]) {
            if ([button imageForState:state.unsignedIntegerValue] != icon)
                [button setImage:icon forState:state.unsignedIntegerValue];
        }
        if (button.imageView.image != icon) button.imageView.image = icon;
        button.imageView.hidden = NO;
        button.imageView.alpha = 1;
        button.hidden = NO;
    }
}
static void pressSpeed(id self, SEL cmd, id sender) {
    id controller = sendObject(activePlayer,"varispeedController");
    SEL show = sel_registerName("showMenuFromView:");
    UIView *anchor = [sender isKindOfClass:UIView.class] ? sender : sendObject(self,"view");
    if (controller && anchor && [controller respondsToSelector:show]) {
        ((void(*)(id,SEL,id))objc_msgSend)(controller,show,anchor);
        return;
    }
    originalPressSpeed(self,cmd,sender);
}
__attribute__((constructor)) static void installMenu(void) {
    Class cls = objc_getClass("YTPlayerViewController");
    Method getter = class_getInstanceMethod(cls, sel_registerName("contentPlayerResponse"));
    if (getter) {
        responseBridge = (void *)method_getImplementation(getter);
        method_setImplementation(getter, (IMP)trackedResponse);
    }
    Class pivot = NSClassFromString(@"YTPivotBarViewController");
    Method renderer = class_getInstanceMethod(pivot,sel_registerName("setRenderer:"));
    Method tap = class_getInstanceMethod(pivot,sel_registerName("didTapItemWithRenderer:"));
    if (renderer && tap) {
        originalSetRenderer = (void *)method_setImplementation(renderer,(IMP)setPivotRenderer);
        originalDidTap = (void *)method_setImplementation(tap,(IMP)didTapPivot);
    }
    Method floating = class_getInstanceMethod(NSClassFromString(@"YTFloatingPivotBarView"),sel_registerName("setRenderer:"));
    if (floating) originalFloatingRenderer = (void *)method_setImplementation(floating,(IMP)setFloatingRenderer);
    Method classic = class_getInstanceMethod(NSClassFromString(@"YTPivotBarView"),sel_registerName("setRenderer:"));
    if (classic) originalClassicRenderer = (void *)method_setImplementation(classic,(IMP)setClassicRenderer);
    Method layout = class_getInstanceMethod(NSClassFromString(@"YTPivotBarItemView"),@selector(layoutSubviews));
    if (layout) originalItemLayout = (void *)method_setImplementation(layout,(IMP)itemLayout);
    Method speed = class_getInstanceMethod(NSClassFromString(@"YTVarispeedSwitchControllerImpl"),@selector(init));
    if (speed) originalSpeedInit = (void *)method_setImplementation(speed,(IMP)speedInit);
    Method press = class_getInstanceMethod(NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController"),sel_registerName("didPressVarispeed:"));
    if (press && speed) originalPressSpeed = (void *)method_setImplementation(press,(IMP)pressSpeed);
}
