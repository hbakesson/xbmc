/*
 *  Copyright (C) 2010-2018 Team Kodi
 *  This file is part of Kodi - https://kodi.tv
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 *  See LICENSES/README.md for more information.
 */

#import "platform/darwin/tvos/XBMCApplication.h"

#import "platform/darwin/NSLogDebugHelpers.h"
#import "platform/darwin/tvos/PreflightHandler.h"
#import "platform/darwin/tvos/TVOSTopShelf.h"
#import "platform/darwin/tvos/XBMCController.h"

#import <AVFoundation/AVFoundation.h>

@implementation XBMCApplicationDelegate

- (void)applicationWillTerminate:(UIApplication*)application
{
  auto sceneDelegate =
      static_cast<XBMCSceneDelegate*>(application.connectedScenes.anyObject.delegate);
  [sceneDelegate.xbmcController stopAnimation];
}

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
  // check if apple removed our Cache folder first
  // this will trigger the restore if there is a backup available
  CPreflightHandler::CheckForRemovedCacheFolder();

  // This needs to run before anything does any CLog::Log calls
  // as they will directly cause guisetting to get accessed/created
  // via debug log settings.
  CPreflightHandler::MigrateUserdataXMLToNSUserDefaults();

  // audio session setup
  auto audioSession = AVAudioSession.sharedInstance;
  NSError* err = nil;
  if (![audioSession setCategory:AVAudioSessionCategoryPlayback error:&err])
    NSLog(@"audioSession setCategory failed: %@", err);

  err = nil;
  if (![audioSession setMode:AVAudioSessionModeMoviePlayback error:&err])
    NSLog(@"audioSession setMode failed: %@", err);

  err = nil;
  if (![audioSession setActive:YES error:&err])
    NSLog(@"audioSession setActive failed: %@", err);

  return YES;
}
@end

@implementation XBMCSceneDelegate
{
  BOOL m_didEnterBackground;
}

- (XBMCController*)xbmcController
{
  return static_cast<XBMCController*>(self.window.rootViewController);
}

#pragma mark - Shutdown Procedures

- (void)sceneWillResignActive:(UIScene*)scene
{
  // Occurs when Kodi is interrupted by something
  // (e.g. Siri triggered by user, Control center opened by user, Mutlitask opened by user ...)
}

- (void)sceneDidEnterBackground:(UIScene*)scene
{
  // Occurs when Kodi has been backgrounded
  // (e.g. when user uses remote to go to tvOS homescreen)
  // sceneWillResignActive() will always be called before this method
  m_didEnterBackground = YES;
  if (scene.activationState == UISceneActivationStateBackground)
  {
    // the app is turn into background, not in by screen lock which has app state inactive.
    [self.xbmcController pauseAnimation];
    [self.xbmcController enterBackground];
  }
}

#pragma mark - Startup Procedures

- (void)sceneDidBecomeActive:(UIScene*)scene
{
  // This function occurs:
  //  * on the first start of Kodi
  //  * when Kodi has been activated after being suspended by sceneWillResignActive()
  //  * when Kodi has been foregrounded after sceneDidEnterBackground()
}

- (void)sceneWillEnterForeground:(UIScene*)scene
{
  // Occurs after a sceneDidEnterBackground(), but also on first start
  // before Kodi is running
  if (!m_didEnterBackground)
    return;
  m_didEnterBackground = NO;

  [self.xbmcController resumeAnimation];
  [self.xbmcController enterForeground];
}

- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions
{
  // UI setup
  self.window = [[UIWindow alloc] initWithWindowScene:static_cast<UIWindowScene*>(scene)];
  self.window.rootViewController = [XBMCController new];
  [self.window makeKeyAndVisible];
  [self.xbmcController startAnimation];

  [self scene:scene openURLContexts:connectionOptions.URLContexts];
}

- (void)scene:(UIScene*)scene openURLContexts:(NSSet<UIOpenURLContext*>*)URLContexts
{
  for (UIOpenURLContext* context in URLContexts)
  {
    NSURL* url = context.URL;
    NSArray* urlComponents = [url.absoluteString componentsSeparatedByString:@"/"];
    NSString* action = urlComponents[2];
    if ([action isEqualToString:@"display"] || [action isEqualToString:@"play"])
      CTVOSTopShelf::GetInstance().HandleTopShelfUrl(url.absoluteString.UTF8String, true);
  }
}
@end

static void SigPipeHandler(int s)
{
  NSLog(@"We Got a Pipe Signal: %d____________", s);
}

int main(int argc, char* argv[])
{
  @autoreleasepool
  {
    signal(SIGPIPE, SigPipeHandler);

    int retVal = 0;
    @try
    {
      retVal =
          UIApplicationMain(argc, argv, nil, NSStringFromClass([XBMCApplicationDelegate class]));
    }
    @catch (id theException)
    {
      ELOG(@"%@", theException);
    }
    @finally
    {
      ILOG(@"This always happens.");
    }

    return retVal;
  }
}
