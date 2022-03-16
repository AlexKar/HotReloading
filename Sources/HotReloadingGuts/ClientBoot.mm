//
//  ClientBoot.mm
//  InjectionIII
//
//  Created by John Holdsworth on 02/24/2021.
//  Copyright © 2021 John Holdsworth. All rights reserved.
//
//  $Id: //depot/HotReloading/Sources/HotReloadingGuts/ClientBoot.mm#44 $
//
//  Initiate connection to server side of InjectionIII/HotReloading.
//

#import "InjectionClient.h"
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "SimpleSocket.h"
#import <dlfcn.h>

#ifndef INJECTION_III_APP
NSString *INJECTION_KEY = @__FILE__;
#endif

#if defined(DEBUG) || defined(INJECTION_III_APP)
@interface BundleInjection: NSObject
@end
@implementation BundleInjection

+ (void)load {
    if (Class clientClass = objc_getClass("InjectionClient"))
        [self performSelectorInBackground:@selector(tryConnect:)
                               withObject:clientClass];
}

static SimpleSocket *injectionClient;
NSString *injectionHost = @"127.0.0.1";

+ (void)tryConnect:(Class)clientClass {
#if TARGET_IPHONE_SIMULATOR
    if (!getenv("INJECTION_DAEMON"))
        if (Class stanalone = objc_getClass("InjectionStandalone")) {
            [[stanalone new] run];
            return;
        }
#endif
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR && !defined(INJECTION_III_APP)
    #ifdef DEVELOPER_HOST
    if (!isdigit(DEVELOPER_HOST[0]))
        printf(APP_PREFIX"Sending multicast packet to connect to your development host.\n"
               APP_PREFIX"If this fails, hardcode your Mac's IP address in HotReloading/Package.swift\n");
    #endif
    injectionHost = [NSString stringWithUTF8String:[clientClass
        getMulticastService:HOTRELOADING_MULTICAST port:HOTRELOADING_PORT
                    message:APP_PREFIX"Connecting to %s (%s)...\n"]];
    NSString *socketAddr = [injectionHost stringByAppendingString:@INJECTION_ADDRESS];
#else
    NSString *socketAddr = @INJECTION_ADDRESS;
#endif
    for (int retry=0, retrys=3; retry<retrys; retry++) {
        if (retry)
            [NSThread sleepForTimeInterval:1.0];
        if ((injectionClient = [clientClass connectTo:socketAddr])) {
            [injectionClient run];
            return;
        }
    }

    if (dlsym(RTLD_DEFAULT, VAPOUR_SYMBOL)) {
       printf(APP_PREFIX"Unable to connect to HotReloading server, please run %s/start_daemon.sh\n",
              @__FILE__.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent
              .stringByDeletingLastPathComponent.UTF8String);
       return;
    }
#ifdef INJECTION_III_APP
    printf(APP_PREFIX"⚠️ Injection bundle loaded but could not connect. Is InjectionIII.app running?\n");
#else
    printf(APP_PREFIX"⚠️ HotReloading loaded but could not connect to %s. Is injectiond running? ⚠️\n"
       APP_PREFIX"Have you added the following \"Run Script\" build phase to your project to start injectiond?\n"
        "if [ -d $SYMROOT/../../SourcePackages ]; then\n"
        "    $SYMROOT/../../SourcePackages/checkouts/HotReloading/start_daemon.sh\n"
        "elif [ -d \"$SYMROOT\"/../../../../../SourcePackages ]; then\n"
        "    \"$SYMROOT\"/../../../../../SourcePackages/checkouts/HotReloading/fix_previews.sh\n"
        "fi\n", injectionHost.UTF8String);
#endif
#ifndef __IPHONE_OS_VERSION_MIN_REQUIRED
    printf(APP_PREFIX"⚠️ For a macOS app you need to turn off the sandbox to connect. ⚠️\n");
#elif !TARGET_IPHONE_SIMULATOR
    printf(APP_PREFIX"⚠️ For iOS, HotReloading used to only work in the simulator. ⚠️\n");
#endif
}

+ (const char *)connectedAddress {
    return injectionHost.UTF8String;
}
@end

#if DEBUG && !defined(INJECTION_III_APP)
@implementation NSObject(InjectionTester)
- (void)swiftTraceInjectionTest:(NSString * _Nonnull)sourceFile
                         source:(NSString * _Nonnull)source {
    if (!injectionClient)
        NSLog(@"swiftTraceInjectionTest: Too early.");
    [injectionClient writeCommand:InjectionTestInjection
                           withString:sourceFile];
    [injectionClient writeString:source];
}
@end
#endif

@implementation NSObject (RunXCTestCase)
+ (void)runXCTestCase:(Class)aTestCase {
    Class _XCTestSuite = objc_getClass("XCTestSuite");
    XCTestSuite *suite0 = [_XCTestSuite testSuiteWithName: @"InjectedTest"];
    XCTestSuite *suite = [_XCTestSuite testSuiteForTestCaseClass: aTestCase];
    Class _XCTestSuiteRun = objc_getClass("XCTestSuiteRun");
    XCTestSuiteRun *tr = [_XCTestSuiteRun testRunWithTest: suite];
    [suite0 addTest:suite];
    [suite0 performTest:tr];
}
@end
#endif

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
@interface UIViewController (StoryboardInjection)
- (void)_loadViewFromNibNamed:(NSString *)a0 bundle:(NSBundle *)a1;
@end
@implementation UIViewController (iOS14StoryboardInjection)
- (void)iOS14LoadViewFromNibNamed:(NSString *)nibName bundle:(NSBundle *)bundle {
    if ([self respondsToSelector:@selector(_loadViewFromNibNamed:bundle:)])
        [self _loadViewFromNibNamed:nibName bundle:bundle];
    else {
        size_t vcSize = class_getInstanceSize([UIViewController class]);
        size_t mySize = class_getInstanceSize([self class]);
        char *extra = (char *)(__bridge void *)self + vcSize;
        NSData *ivars = [NSData dataWithBytes:extra length:mySize-vcSize];
        (void)[self initWithNibName:nibName bundle:bundle];
        memcpy(extra, ivars.bytes, ivars.length);
        [self loadView];
    }
}
@end

@interface NSObject (Remapped)
+ (void)addMappingFromIdentifier:(NSString *)identifier toObject:(id)object forCoder:(id)coder;
+ (id)mappedObjectForCoder:(id)decoder withIdentifier:(NSString *)identifier;
@end

@implementation NSObject (Remapper)

static struct {
    NSMutableDictionary *inputIndexes;
    NSMutableArray *output, *order;
    int orderIndex;
} remapper;

+ (void)my_addMappingFromIdentifier:(NSString *)identifier toObject:(id)object forCoder:(id)coder {
    //NSLog(@"Map %@ = %@", identifier, object);
    if(remapper.output && [identifier hasPrefix:@"UpstreamPlaceholder-"]) {
        if (remapper.inputIndexes)
            remapper.inputIndexes[identifier] = @([remapper.inputIndexes count]);
        else
            [remapper.output addObject:object];
    }
    [self my_addMappingFromIdentifier:identifier toObject:object forCoder:coder];
}

+ (id)my_mappedObjectForCoder:(id)decoder withIdentifier:(NSString *)identifier {
    //NSLog(@"Mapped? %@", identifier);
    if(remapper.output && [identifier hasPrefix:@"UpstreamPlaceholder-"]) {
        if (remapper.inputIndexes)
            [remapper.order addObject:remapper.inputIndexes[identifier] ?: @""];
        else
            return remapper.output[[remapper.order[remapper.orderIndex++] intValue]];
    }
    return [self my_mappedObjectForCoder:decoder withIdentifier:identifier];
}

+ (BOOL)injectUI:(NSString *)changed {
    static NSMutableDictionary *allOrder;
    static dispatch_once_t once;
    printf(APP_PREFIX"Waiting for rebuild of %s\n", changed.UTF8String);

    dispatch_once(&once, ^{
        Class proxyClass = objc_getClass("UIProxyObject");
        method_exchangeImplementations(
           class_getClassMethod(proxyClass,
                                @selector(my_addMappingFromIdentifier:toObject:forCoder:)),
           class_getClassMethod(proxyClass,
                                @selector(addMappingFromIdentifier:toObject:forCoder:)));
        method_exchangeImplementations(
           class_getClassMethod(proxyClass,
                                @selector(my_mappedObjectForCoder:withIdentifier:)),
           class_getClassMethod(proxyClass,
                                @selector(mappedObjectForCoder:withIdentifier:)));
        allOrder = [NSMutableDictionary new];
    });

    @try {
        UIViewController *rootViewController = [UIApplication sharedApplication].windows.firstObject.rootViewController;
        UINavigationController *navigationController = (UINavigationController*)rootViewController;
        UIViewController *visibleVC = rootViewController;

        if (UIViewController *child =
            visibleVC.childViewControllers.firstObject)
            visibleVC = child;
        if ([visibleVC respondsToSelector:@selector(viewControllers)])
            visibleVC = [(UISplitViewController *)visibleVC
                         viewControllers].lastObject;

        if ([visibleVC respondsToSelector:@selector(visibleViewController)])
            visibleVC = [(UINavigationController *)visibleVC
                         visibleViewController];
        if (!visibleVC.nibName && [navigationController respondsToSelector:@selector(topViewController)]) {
          visibleVC = [navigationController topViewController];
        }

        NSString *nibName = visibleVC.nibName;

        if (!(remapper.order = allOrder[nibName])) {
            remapper.inputIndexes = [NSMutableDictionary new];
            remapper.output = [NSMutableArray new];
            allOrder[nibName] = remapper.order = [NSMutableArray new];

            [visibleVC iOS14LoadViewFromNibNamed:visibleVC.nibName
                                          bundle:visibleVC.nibBundle];

            remapper.inputIndexes = nil;
            remapper.output = nil;
        }

        Class SwiftEval = objc_getClass("SwiftEval"),
         SwiftInjection = objc_getClass("SwiftInjection");

        NSError *err = nil;
        [[SwiftEval sharedInstance] rebuildWithStoryboard:changed error:&err];
        if (err)
            return FALSE;

        void (^resetRemapper)(void) = ^{
            remapper.output = [NSMutableArray new];
            remapper.orderIndex = 0;
        };

        resetRemapper();

        [visibleVC iOS14LoadViewFromNibNamed:visibleVC.nibName
                                      bundle:visibleVC.nibBundle];

        if ([[SwiftEval sharedInstance] vaccineEnabled] == YES) {
            resetRemapper();
            [SwiftInjection vaccine:visibleVC];
        } else {
            [visibleVC viewDidLoad];
            [visibleVC viewWillAppear:NO];
            [visibleVC viewDidAppear:NO];

            [SwiftInjection flash:visibleVC];
        }
    }
    @catch(NSException *e) {
        printf("Problem reloading nib: %s\n", e.reason.UTF8String);
    }

    remapper.output = nil;
    return true;
}
@end
#endif
