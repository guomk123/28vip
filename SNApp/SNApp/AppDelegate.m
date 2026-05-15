//
//  AppDelegate.m
//  SNApp
//
//  Created by Guomk1 on 2026/4/24.
//

#import "AppDelegate.h"
#import <Flutter/Flutter.h>
#import <FlutterPluginRegistrant/GeneratedPluginRegistrant.h>
@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    static FlutterEngine *flutterEngine = nil;
      if (!flutterEngine) {
          flutterEngine = [[FlutterEngine alloc] initWithName:@"my_flutter_engine"];
          [flutterEngine runWithEntrypoint:nil];
          [GeneratedPluginRegistrant registerWithRegistry:flutterEngine];
      }
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [self.window makeKeyAndVisible];
    
    FlutterViewController *flutterViewController = [[FlutterViewController alloc] initWithEngine:flutterEngine nibName:nil bundle:nil];
    self.window.rootViewController = flutterViewController;
    
    return YES;
}

@end
