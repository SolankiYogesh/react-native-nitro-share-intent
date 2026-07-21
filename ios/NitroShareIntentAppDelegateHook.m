//
//  NitroShareIntentAppDelegateHook.m
//
//  Removes the need for consumers to add any code to their AppDelegate.
//
//  `+load` runs before `main()`, so this class can watch for
//  UIApplicationDidFinishLaunchingNotification and then install an
//  `application:openURL:options:` implementation on the app delegate at
//  runtime - but ONLY when the app doesn't implement it itself. Apps that
//  already implement it (their own deep linking, RCTLinkingManager
//  forwarding, or the legacy manual NitroShareIntent snippet) are left
//  completely untouched; those flows are picked up by the Swift module via
//  RCTOpenURLNotification / the legacy "ShareIntentReceived" notification.
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

@interface NitroShareIntentAppDelegateHook : NSObject
@end

@implementation NitroShareIntentAppDelegateHook

+ (void)load
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

  [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:^(NSNotification *note) {
                    [self installWithLaunchOptions:note.userInfo];
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

+ (void)installWithLaunchOptions:(NSDictionary *)launchOptions
{
  NSNumber *enabled = [[NSBundle mainBundle] objectForInfoDictionaryKey:kProxyEnabledPlistKey];
  if (enabled != nil && !enabled.boolValue) {
    return;
  }

  // A cold start via a custom URL scheme delivers the URL in the launch
  // options - capture it here since `application:openURL:options:` may not
  // exist yet at that point. The Swift side dedupes if the system also
  // calls the injected method for the same URL.
  // Deprecated in favor of UIScene, but React Native apps use the classic
  // UIApplicationDelegate lifecycle where this key is still delivered.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  id launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
#pragma clang diagnostic pop
  if ([launchURL isKindOfClass:[NSURL class]]) {
    NitroShareIntentDeliverURL(launchURL);
  }

  id<UIApplicationDelegate> delegate = [UIApplication sharedApplication].delegate;
  if (delegate == nil) {
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

@end
