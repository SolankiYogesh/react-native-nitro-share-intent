//
//  NitroShareIntentAppDelegateHook.m
//
//  Removes the need for consumers to add any code to their AppDelegate.
//
//  `+load` runs before `main()`, so this class swizzles
//  `-[UIApplication setDelegate:]` and installs an
//  `application:openURL:options:` implementation on the app delegate the
//  moment it is assigned (inside `UIApplicationMain`, before any launch or
//  open-URL callback) - but ONLY when the app doesn't implement it itself.
//  Apps that already implement it (their own deep linking, RCTLinkingManager
//  forwarding, or the legacy manual NitroShareIntent snippet) are left
//  completely untouched; those flows are picked up by the Swift module via
//  RCTOpenURLNotification / the legacy "ShareIntentReceived" notification.
//
//  Installing this early matters: UIKit checks the delegate for
//  `application:openURL:options:` while the launch is still in flight, and an
//  app declaring `LSSupportsOpeningDocumentsInPlace` (any app that accepts
//  "Open in..." shares) is *hard asserted* out of existence if the method is
//  missing at that point. Waiting for
//  UIApplicationDidFinishLaunchingNotification was too late.
//
//  URLs can arrive before the Nitro module instance exists (cold-start
//  custom-scheme opens), so they are buffered here and replayed once the
//  Swift side posts "NitroShareIntentReady".
//
//  Opt out by setting `NitroShareIntentAppDelegateProxyEnabled` to NO in
//  the app's Info.plist.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kShareIntentReceivedNotification = @"ShareIntentReceived";
static NSString *const kModuleReadyNotification = @"NitroShareIntentReady";
static NSString *const kProxyEnabledPlistKey = @"NitroShareIntentAppDelegateProxyEnabled";

static NSMutableArray<NSURL *> *gPendingURLs = nil;
static BOOL gModuleReady = NO;

static BOOL NitroShareIntentProxyEnabled(void)
{
  NSNumber *enabled = [[NSBundle mainBundle] objectForInfoDictionaryKey:kProxyEnabledPlistKey];
  return enabled == nil || enabled.boolValue;
}

static void NitroShareIntentDeliverURL(NSURL *url)
{
  if (url == nil) {
    return;
  }
  if (gModuleReady) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kShareIntentReceivedNotification
                                                        object:nil
                                                      userInfo:@{@"url" : url}];
  } else {
    if (gPendingURLs == nil) {
      gPendingURLs = [NSMutableArray new];
    }
    [gPendingURLs addObject:url];
  }
}

/// Adds `application:openURL:options:` to the delegate's class when it has no
/// implementation of its own. Safe to call more than once - the second call
/// sees the method we added and bails out.
static void NitroShareIntentInstallOnDelegate(id<UIApplicationDelegate> delegate)
{
  if (delegate == nil || !NitroShareIntentProxyEnabled()) {
    return;
  }

  SEL selector = @selector(application:openURL:options:);
  if ([delegate respondsToSelector:selector]) {
    // The app (or a superclass like Expo's delegate wrapper) already
    // handles URL opens - don't interfere. Those setups reach us through
    // RCTOpenURLNotification or the legacy manual notification instead.
    return;
  }

  IMP imp = imp_implementationWithBlock(^BOOL(id _self, UIApplication *app, NSURL *url, NSDictionary *options) {
    NitroShareIntentDeliverURL(url);
    return YES;
  });
  class_addMethod([delegate class], selector, imp, "B@:@@@");
}

@interface NitroShareIntentAppDelegateHook : NSObject
@end

@implementation NitroShareIntentAppDelegateHook

+ (void)load
{
  [self installDelegateSetterHook];

  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

  // `queue:nil` delivers synchronously on the posting thread - a queued block
  // would run after the launch sequence has already finished.
  [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                      object:nil
                       queue:nil
                  usingBlock:^(NSNotification *note) {
                    [self handleDidFinishLaunchingWithOptions:note.userInfo];
                  }];

  [center addObserverForName:kModuleReadyNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:^(NSNotification *note) {
                    gModuleReady = YES;
                    NSArray<NSURL *> *pending = [gPendingURLs copy];
                    [gPendingURLs removeAllObjects];
                    for (NSURL *url in pending) {
                      NitroShareIntentDeliverURL(url);
                    }
                  }];
}

/// Swizzles `-[UIApplication setDelegate:]` so the open-URL handler is in
/// place before UIKit ever inspects the delegate.
+ (void)installDelegateSetterHook
{
  if (!NitroShareIntentProxyEnabled()) {
    return;
  }

  Method method = class_getInstanceMethod([UIApplication class], @selector(setDelegate:));
  if (method == NULL) {
    return;
  }

  __block IMP original = NULL;
  IMP replacement = imp_implementationWithBlock(^(UIApplication *app, id<UIApplicationDelegate> delegate) {
    // Install *before* calling through: `setDelegate:` caches which optional
    // delegate methods exist in an internal bitmask, and UIKit consults that
    // cache - not `respondsToSelector:` - when it later decides whether the
    // app can handle an open-URL action. Adding the method afterwards would
    // be invisible to that cache.
    NitroShareIntentInstallOnDelegate(delegate);
    if (original != NULL) {
      ((void (*)(id, SEL, id))original)(app, @selector(setDelegate:), delegate);
    }
  });
  original = method_setImplementation(method, replacement);
}

+ (void)handleDidFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  // Fallback for the (unexpected) case where the `setDelegate:` hook didn't
  // run - e.g. a delegate installed through some other path.
  NitroShareIntentInstallOnDelegate([UIApplication sharedApplication].delegate);

  if (!NitroShareIntentProxyEnabled()) {
    return;
  }

  // A cold start via a custom URL scheme delivers the URL in the launch
  // options - capture it here too, since a delegate that implements
  // `application:openURL:options:` itself may never forward it to us. The
  // Swift side dedupes if the same URL also arrives through another source.
  // Deprecated in favor of UIScene, but React Native apps use the classic
  // UIApplicationDelegate lifecycle where this key is still delivered.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  id launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
#pragma clang diagnostic pop
  if ([launchURL isKindOfClass:[NSURL class]]) {
    NitroShareIntentDeliverURL(launchURL);
  }
}

@end
