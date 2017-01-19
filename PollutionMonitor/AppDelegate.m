//
//  AppDelegate.m
//  PollutionMonitor
//
//  Created by Demian Turner on 13/12/2016.
//  Copyright © 2016 Seagull Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "TestImage.h"
#import "PopoverViewController.h"
#import "NSString+Sha1.h"
#import "Reachability.h"
#import "PLMCityList.h"
#import "MyView.h"

static NSString* const kLastSelectedCityId = @"LastSelectedCityId";
static int const kBeijingCityId = 1451;

typedef enum
{
    kPLMMenuItemLastUpdated,
    kPLMMenuItemChangeCity,
    kPLMMenuItemViewOnWeb,
    kPLMMenuItemAbout,
    kPLMMenuItemQuit,
} PLMMenuItem;

@interface AppDelegate()

//@property (weak, nonatomic) IBOutlet NSWindow *window;
//@property (strong, nonatomic) id popoverTransiencyMonitor;
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTimer *timer;
@property (weak) IBOutlet MyView *menuItemView;
@property (weak) IBOutlet NSTextField *lastRequestedLabel;
@property (weak) IBOutlet NSTextField *lastUpdatedLabel;

@end

@implementation AppDelegate



#pragma mark - Application Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    
    // update every 5 mins
    float intervalInSeconds = 60.0 * 5;
//    float intervalInSeconds = 10;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:intervalInSeconds
                                     target:self
                                   selector:@selector(timerFired:cityCode:)
                                   userInfo:nil
                                    repeats:YES];
    
    // update reading when Mac wakes
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(timerFired:cityCode:)
                                                               name:NSWorkspaceDidWakeNotification object:NULL];
    
    [self initializeStatusBarItem];
    
    NSString *lastUpdatedItem = @"Updating ...";
    NSString *viewOnWebTitle = @"View on Website";
    NSString *aboutTitle = @"About Pollution Monitor";
    NSString *quitTitle = @"Quit";
				
    NSDictionary *one = @{lastUpdatedItem : [NSValue valueWithPointer:nil]};
    NSDictionary *two = @{viewOnWebTitle : [NSValue valueWithPointer:@selector(viewOnWebsiteSelected:)]};
    NSDictionary *three = @{aboutTitle : [NSValue valueWithPointer:@selector(aboutSelected:)]};
    NSDictionary *four = @{quitTitle : [NSValue valueWithPointer:@selector(terminate:)]};
    NSArray *menuItemsArray = @[one, two, three, four];
    
    self.statusItem.menu = [self initializeStatusBarMenu:menuItemsArray];
    [self addCityItemsToStatusBarMenu:[PLMCityList cities]];
    
    // invoke first call, rest done by timer
    [self timerFired:self.timer cityCode:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    
    [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
    self.statusItem = nil;
}

#pragma mark - Menu Bar


- (NSMenu *)initializeStatusBarMenu:(NSArray *)menuItemsArray
{
    NSMenu *menu = [[NSMenu alloc] init];
    
    for (NSDictionary *menuItems in menuItemsArray) {
        [menuItems enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSValue *val, BOOL *stop) {
            SEL action = nil;
            [val getValue:&action];
            [menu addItemWithTitle:key action:action keyEquivalent:@""];
        }];
    }
    
    return menu;
}

- (void)addCityItemsToStatusBarMenu:(NSArray *)menuItemsArray
{
    NSMenuItem *cityItem = [[NSMenuItem alloc] initWithTitle:@"Choose City" action:nil keyEquivalent:@""];
    
    NSMenu *submenu = [[NSMenu alloc] init];
    
    for (NSDictionary *menuItems in menuItemsArray) {
        [menuItems enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *cityCode, BOOL *stop) {
            
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:key action:@selector(citySelected:) keyEquivalent:@""];
            [item setTarget:self];
            [item setRepresentedObject:cityCode];
            [submenu addItem:item];
        }];
    }
    
    [cityItem setSubmenu:submenu];
    [self.statusItem.menu insertItem:cityItem atIndex:kPLMMenuItemChangeCity];
}

- (void)updateStatusItemWithReading:(int)reading updatedAt:(NSString *)updatedString
{
    NSImage *image = [TestImage imageOfMyImage:reading];
    [self.statusItem setImage:image];
    
    // local update time
    NSLocale *formatterLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_GB"];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    [dateFormatter setLocale:formatterLocale];
    NSString *stringDate = [dateFormatter stringFromDate:[NSDate date]];
    NSString *lastUpdatedLocal = [@"Last Requested: " stringByAppendingString:stringDate];
    
    self.lastRequestedLabel.stringValue = lastUpdatedLocal;

    // server update time
    NSMenuItem *lastUpdatedMenuItem = [self.statusItem.menu itemAtIndex:kPLMMenuItemLastUpdated];
    NSString *lastUpdatedServer = [@"Last Updated: " stringByAppendingString:updatedString];
    self.lastUpdatedLabel.stringValue = lastUpdatedServer;
    [lastUpdatedMenuItem setEnabled:NO];    
    [lastUpdatedMenuItem setView:self.menuItemView];
    
    NSLog(@"timer fired");
    NSLog(@"Server Last Updated %@", updatedString);
    NSLog(@"reading %d", reading);
}

- (void)initializeStatusBarItem
{
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.highlightMode = YES;
    NSStatusBarButton *button = self.statusItem.button;
    button.action = @selector(buttonClicked:);
}

#pragma mark - Helpers

- (void)clearSelectionsAtIndex:(NSUInteger)idx
{
    NSMenuItem *chooseCity = [self.statusItem.menu itemAtIndex:kPLMMenuItemChangeCity];
    
    if (chooseCity.hasSubmenu) {
        for (NSMenuItem *menuItem in chooseCity.submenu.itemArray) {
            menuItem.state = NSOffState;
        }
    }
}

- (void)tickSelectedCity:(NSNumber *)cityCode
{
    NSMenuItem *chooseCity = [self.statusItem.menu itemAtIndex:kPLMMenuItemChangeCity];
    
    if (chooseCity.hasSubmenu) {
        for (NSMenuItem *menuItem in chooseCity.submenu.itemArray) {
            NSNumber *code = [menuItem representedObject];
            if (code == cityCode) {
                menuItem.state = NSOnState;
            }
        }
    }
    
}

#pragma mark - Network

- (void)timerFired:(NSTimer *)timer cityCode:(NSNumber *)cityCode
{
    if (! [self hasNetworkConnection]) {
        NSLog(@"no network");
        return;
    }
    
    if (cityCode == nil) {
        // check last selected value in user defaults
        NSNumber *savedCityCode = [[NSUserDefaults standardUserDefaults] objectForKey:kLastSelectedCityId];
        if (savedCityCode) {
            cityCode = savedCityCode;
        } else
            
            // else default to Beijing
        {
            cityCode = @(kBeijingCityId);
        }
    }
    
    [self tickSelectedCity:cityCode];
    
    NSString *feedUrl = @"https://feed.aqicn.org/xservices/refresh";
    NSString *uuidString = [[NSUUID UUID] UUIDString];
    NSString *sha1Hash = [[uuidString sha1Hash] lowercaseString];
    NSString *dataUrl = [NSString stringWithFormat:@"%@:%@?%@", feedUrl, cityCode, sha1Hash];
    // format https://feed.aqicn.org/xservices/refresh:1284?b6928d68172703fe9468ea70e38a330439c3e1a2
    NSURL *url = [NSURL URLWithString:dataUrl];
    
    NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession]
                                          dataTaskWithURL:url
                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                              NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                              NSString *measurement = jsonData[@"aqiv"];
                                              NSString *updateTime = jsonData[@"utime"];
                                              int reading = [measurement intValue];
                                              [self updateStatusItemWithReading:reading updatedAt:updateTime];
                                              NSLog(@"%@", jsonData);
                                          }];
    [downloadTask resume];
}

- (BOOL)hasNetworkConnection
{
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [reachability currentReachabilityStatus];
    return !(networkStatus == NotReachable);
}

#pragma mark - Actions

- (void)citySelected:(id)sender
{
    // untick previous selection
    [self clearSelectionsAtIndex:kPLMMenuItemChangeCity];
    
    // tick selection
    NSMenuItem *item = (NSMenuItem *)sender;
    item.state = NSOnState;
    
    // extract city code
    NSNumber *cityCode = (NSNumber *)[sender representedObject];
    
    // store city code value
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:cityCode forKey:kLastSelectedCityId];
    [defaults synchronize];
    
    [self timerFired:self.timer cityCode:cityCode];
}

- (void)viewOnWebsiteSelected:(id)sender
{
    NSNumber *savedCityCode = [[NSUserDefaults standardUserDefaults] objectForKey:kLastSelectedCityId];
    NSDictionary *cities = [PLMCityList dictionary];
    NSString *cityName = cities[savedCityCode];
    NSString *aqicnUrlString = [NSString stringWithFormat:@"http://aqicn.org/search/#q=%@", cityName];
//    aqicnUrlString = [aqicnUrlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:aqicnUrlString]];
}

- (void)aboutSelected:(id)sender
{
    NSString *aqicnUrlString = @"http://bunchoftext.com/apps/pollution-monitor";
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:aqicnUrlString]];
}

- (IBAction)buttonClicked:(NSStatusBarButton *)sender
{
    NSLog(@"foo"); // never called because menu implemented for statusItem
}


//- (IBAction)buttonClicked:(NSStatusBarButton *)sender
//{
//    // Create view controller
//    PopoverViewController *viewController = [[PopoverViewController alloc] init];
//
//    // Create popover
//    NSPopover *entryPopover = [[NSPopover alloc] init];
//    [entryPopover setContentSize:NSMakeSize(200.0, 200.0)];
//    [entryPopover setBehavior:NSPopoverBehaviorTransient];
//    [entryPopover setAnimates:YES];
//    [entryPopover setContentViewController:viewController];
//
//    // Convert point to main window coordinates
////    NSRect entryRect = [sender convertRect:sender.bounds
////                                    toView:self.statusItem.view];
//
//    // Show popover
//    [entryPopover showRelativeToRect:sender.bounds
//                              ofView:self.statusItem.view
//                       preferredEdge:NSMinYEdge];
//
//    // handle close click
//    if (self.popoverTransiencyMonitor == nil) {
//        self.popoverTransiencyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskKeyUp) handler:^(NSEvent* event) {
//                [NSEvent removeMonitor:self.popoverTransiencyMonitor];
//                self.popoverTransiencyMonitor = nil;
//                [entryPopover close];
//        }];
//    }
//}

@end
