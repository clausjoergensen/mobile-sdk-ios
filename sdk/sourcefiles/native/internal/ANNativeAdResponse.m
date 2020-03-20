/*   Copyright 2014 APPNEXUS INC
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "ANNativeAdResponse.h"
#import "ANLogging.h"
#import "UIView+ANNativeAdCategory.h"
#import "ANGlobal.h"
#import "ANAdProtocol.h"
#import "ANOMIDImplementation.h"
#import "ANVerificationScriptResource.h"

NSString * const  kANNativeElementObject                                   = @"ELEMENT";


#pragma mark - ANNativeAdResponseGestureRecognizerRecord

@interface ANNativeAdResponseGestureRecognizerRecord : NSObject

@property (nonatomic, weak) UIView *viewWithTracking;
@property (nonatomic, weak) UIGestureRecognizer *gestureRecognizer;

@end


@implementation ANNativeAdResponseGestureRecognizerRecord

@end




#pragma mark - ANNativeAdResponse

@interface ANNativeAdResponse()

@property (nonatomic, readwrite, strong) UIView *viewForTracking;
@property (nonatomic, readwrite, strong) NSMutableArray *gestureRecognizerRecords;
@property (nonatomic, readwrite, weak) UIViewController *rootViewController;
@property (nonatomic, readwrite, assign, getter=hasExpired) BOOL expired;
@property (nonatomic, readwrite, assign) ANNativeAdNetworkCode networkCode;
@property (nonatomic, readwrite, strong) OMIDAppnexusAdSession *omidAdSession;
@property (nonatomic, readwrite, strong) ANVerificationScriptResource *verificationScriptResource;
@property (nonatomic, readwrite, strong)  ANAdResponseInfo *adResponseInfo;
@property (nonatomic, readwrite, strong, nullable) NSMutableArray<UIView *> *obstructionView;

@end




@implementation ANNativeAdResponse

@synthesize  clickThroughAction             = _clickThroughAction;
@synthesize  landingPageLoadsInBackground   = _landingPageLoadsInBackground;


#pragma mark - Lifecycle.

- (instancetype) init
{
    self = [super init];
    if (!self)  { return nil; }

    //
    self.clickThroughAction = ANClickThroughActionOpenSDKBrowser;

    return  self;
}

#pragma mark - Getters/setters.

- (void)setClickThroughAction:(ANClickThroughAction)clickThroughAction
{
    _clickThroughAction = clickThroughAction;
}

#pragma mark - Registration

- (BOOL)registerViewForTracking:(nonnull UIView *)view
         withRootViewController:(nonnull UIViewController *)controller
                 clickableViews:(nullable NSArray *)clickableViews
                          error:(NSError *__nullable*__nullable)error {
    if (!view) {
        ANLogError(@"native_invalid_view");
        if (error) {
            *error = ANError(@"native_invalid_view", ANNativeAdRegisterErrorCodeInvalidView);
        }
        return NO;
    }
    if (!controller) {
        ANLogError(@"native_invalid_rvc");
        if (error) {
            *error = ANError(@"native_invalid_rvc", ANNativeAdRegisterErrorCodeInvalidRootViewController);
        }
        return NO;
    }
    if (self.hasExpired) {
        ANLogError(@"native_expired_response");
        if (error) {
            *error = ANError(@"native_expired_response", ANNativeAdRegisterErrorCodeExpiredResponse);
        }
        return NO;
    }
    
    ANNativeAdResponse *response = [view anNativeAdResponse];
    if (response) {
        ANLogDebug(@"Unregistering view from another response");
        [response unregisterViewFromTracking];
    }
    
    BOOL successfulResponseRegistration = [self registerResponseInstanceWithNativeView:view
                                                                    rootViewController:controller
                                                                        clickableViews:clickableViews
                                                                                 error:error];
    
    if (successfulResponseRegistration) {
        self.viewForTracking = view;
        [view setAnNativeAdResponse:self];
        self.rootViewController = controller;
        self.expired = YES;
        [self registerOMID];
        return YES;
    }
    
    return NO;
}

- (BOOL)registerResponseInstanceWithNativeView:(UIView *)view
                            rootViewController:(UIViewController *)controller
                                clickableViews:(NSArray *)clickableViews
                                         error:(NSError *__autoreleasing*)error {
    // Abstract method, to be implemented by subclass
    return NO;
}

- (void)unregisterViewFromTracking {
    [self detachAllGestureRecognizers];
    [self.viewForTracking setAnNativeAdResponse:nil];
    self.viewForTracking = nil;
    if(self.omidAdSession != nil){
        [[ANOMIDImplementation sharedInstance] stopOMIDAdSession:self.omidAdSession];
    }
}


- (void)registerOMID{
    NSMutableArray *scripts = [NSMutableArray new];
    NSURL *url = [NSURL URLWithString:self.verificationScriptResource.url];
    NSString *vendorKey = self.verificationScriptResource.vendorKey;
    NSString *params = self.verificationScriptResource.params;
    [scripts addObject:[[OMIDAppnexusVerificationScriptResource alloc] initWithURL:url vendorKey:vendorKey  parameters:params]];
    self.omidAdSession = [[ANOMIDImplementation sharedInstance] createOMIDAdSessionforNative:self.viewForTracking withScript:scripts];
    [[ANOMIDImplementation sharedInstance] addFriendlyObstruction:self.obstructionView.firstObject toOMIDAdSession:self.omidAdSession];
}




#pragma mark - Click handling

- (void)attachGestureRecognizersToNativeView:(UIView *)nativeView
                          withClickableViews:(NSArray *)clickableViews
{
    if (clickableViews.count) {
        [clickableViews enumerateObjectsUsingBlock:^(id clickableView, NSUInteger idx, BOOL *stop) {
            if ([clickableView isKindOfClass:[UIView class]]) {
                [self attachGestureRecognizerToView:clickableView];
            } else {
                ANLogWarn(@"native_invalid_clickable_views");
            }
        }];
    } else {
        [self attachGestureRecognizerToView:nativeView];
    }
}

- (void)attachGestureRecognizerToView:(UIView *)view
{
    view.userInteractionEnabled = YES;
    
    ANNativeAdResponseGestureRecognizerRecord *record = [[ANNativeAdResponseGestureRecognizerRecord alloc] init];
    record.viewWithTracking = view;
    
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        [button addTarget:self
                   action:@selector(handleClick)
         forControlEvents:UIControlEventTouchUpInside];
    } else {
        UITapGestureRecognizer *clickRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handleClick)];
        [view addGestureRecognizer:clickRecognizer];
        record.gestureRecognizer = clickRecognizer;
    }
    
    [self.gestureRecognizerRecords addObject:record];
}

- (void)detachAllGestureRecognizers {
    [self.gestureRecognizerRecords enumerateObjectsUsingBlock:^(ANNativeAdResponseGestureRecognizerRecord *record, NSUInteger idx, BOOL *stop) {
        UIView *view = record.viewWithTracking;
        if (view) {
            if ([view isKindOfClass:[UIButton class]]) {
                [(UIButton *)view removeTarget:self
                                        action:@selector(handleClick)
                              forControlEvents:UIControlEventTouchUpInside];
            } else if (record.gestureRecognizer) {
                [view removeGestureRecognizer:record.gestureRecognizer];
            }
        }
    }];
    
    [self.gestureRecognizerRecords removeAllObjects];
}

- (NSMutableArray *)gestureRecognizerRecords {
    if (!_gestureRecognizerRecords) _gestureRecognizerRecords = [[NSMutableArray alloc] init];
    return _gestureRecognizerRecords;
}

- (void)handleClick {
    // Abstract method, to be implemented by subclass
}

- (void)dealloc {
    [self unregisterViewFromTracking];
}




# pragma mark - ANNativeAdDelegate

- (void)adWasClicked {
    if ([self.delegate respondsToSelector:@selector(adWasClicked:)]) {
        [self.delegate adWasClicked:self];
    }
}

- (void)adWasClickedWithURL:(NSString *)clickURLString fallbackURL:(NSString *)clickFallbackURLString
{
    if ([self.delegate respondsToSelector:@selector(adWasClicked:withURL:fallbackURL:)]) {
        [self.delegate adWasClicked: self
                            withURL: clickURLString
                        fallbackURL: clickFallbackURLString];
    }
}

- (void)willPresentAd {
    if ([self.delegate respondsToSelector:@selector(adWillPresent:)]) {
        [self.delegate adWillPresent:self];
    }
}

- (void)didPresentAd {
    if ([self.delegate respondsToSelector:@selector(adDidPresent:)]) {
        [self.delegate adDidPresent:self];
    }
}

- (void)willCloseAd {
    if ([self.delegate respondsToSelector:@selector(adWillClose:)]) {
        [self.delegate adWillClose:self];
    }
}

- (void)didCloseAd {
    if ([self.delegate respondsToSelector:@selector(adDidClose:)]) {
        [self.delegate adDidClose:self];
    }
}

- (void)willLeaveApplication {
    if ([self.delegate respondsToSelector:@selector(adWillLeaveApplication:)]) {
        [self.delegate adWillLeaveApplication:self];
    }
}



- (void)removeFriendlyObstruction:(nullable UIView*)obstructionView{
    if([self.obstructionView containsObject:obstructionView]){
        [self removeView:obstructionView];
    }
}
- (void)removeAllFriendlyObstructions{
    [self.obstructionView removeAllObjects];
    self.obstructionView = nil;
}


-(void)removeView:(UIView *)view{
    NSLog(@"Ab - %@",view);
    [self.obstructionView removeObject:view];
    
    for (UIView *obsView in view.subviews){
        if([obsView isKindOfClass:[UIView class]]){
            [self removeView:obsView];
        }
    }
    
}



-(void)addView:(UIView *)view{
    if(view.alpha == 0.0 && view.opaque){
        NSLog(@"Ab - %@",view);
        [self.obstructionView addObject:view];
    }
    
    for (UIView *obsView in view.subviews){
        if([obsView isKindOfClass:[UIView class]]){
            [self addView:obsView];
        }
    }
    
}



- (void)addFriendlyObstruction:(nullable UIView *)obstructionView{
    if(self.obstructionView == nil){
        self.obstructionView = [[NSMutableArray alloc] init];
    }
    [self addView:obstructionView];
    
}



@end
