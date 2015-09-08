//
//  RWSearchFormViewController.m
//  TwitterInstant
//
//  Created by Colin Eberhardt on 02/12/2013.
//  Copyright (c) 2013 Colin Eberhardt. All rights reserved.
//

#import "RWSearchFormViewController.h"
#import "RWSearchResultsViewController.h"
#import "ReactiveCocoa.h"
#import "RACEXTScope.h"
#import <Accounts/Accounts.h>
#import <Social/Social.h>
#import "RWTweet.h"
#import "NSArray+LinqExtensions.h"

typedef NS_ENUM(NSInteger, RWTwitterInstantError) {
    RWTwitterInstantErrorAccessDenied,
    RWTwitterInstantErrorNoTwitterAccounts,
    RWTwitterInstantErrorInvalidResponse
};

static NSString * const RWTwitterInstantDomain = @"TwitterInstant";

@interface RWSearchFormViewController ()

@property (weak, nonatomic) IBOutlet UITextField *searchText;

@property (strong, nonatomic) RWSearchResultsViewController *resultsViewController;

@property (strong, nonatomic) ACAccountStore *accountStore;
@property (strong, nonatomic) ACAccountType *twitterAccountType;

@end

@implementation RWSearchFormViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
  
    self.title = @"Twitter Instant";
  
    [self styleTextField:self.searchText];
  
    self.resultsViewController = self.splitViewController.viewControllers[1];
    
    // 监听输入框内容改变背景色
    RAC(self.searchText, backgroundColor) =
    [self.searchText.rac_textSignal
     map:^id(NSString *text) {
       return [self isValidSearchText:text] ? [UIColor whiteColor] : [UIColor yellowColor];
    }];
    
    // 社会化分享设置
    self.accountStore = [[ACAccountStore alloc] init];
    self.twitterAccountType = [self.accountStore
                               accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    @weakify(self)
    [[[[[[[self requestAccessToTwitterSignal]
     then:^RACSignal *{// 订阅别的信号，监听textfield的text改变
         @strongify(self)
         return self.searchText.rac_textSignal;
     }]
     filter:^BOOL(NSString *text) {// 过滤信号
         return [self isValidSearchText:text];
     }]
     flattenMap:^RACStream *(NSString *text) {// 映射到一个新的signal
         @strongify(self)
         return [self signalForSearchWithText:text];
     }]
      throttle:0.5]// 当停止输入超过500毫秒后执行block
     deliverOn:[RACScheduler mainThreadScheduler]]// 在主线程更新UI
     subscribeNext:^(NSDictionary *jsonSearchResult) {
         NSArray *statuses = jsonSearchResult[@"statuses"];
         // 遍历字典数组，转成RWTweet对象
         NSArray *tweets = [statuses linq_select:^id(id tweet) {
             return [RWTweet tweetWithStatus:tweet];
         }];
         // 显示到分屏
         [self.resultsViewController displayTweets:tweets];
     } error:^(NSError *error) {
         NSLog(@"An error occurred: %@", error);
     }];
}

/**
 *  获取社会化分享权限
 *
 */
- (RACSignal *)requestAccessToTwitterSignal {
    // 1 - 自定义错误
    NSError *accessError = [NSError errorWithDomain:RWTwitterInstantDomain
                                               code:RWTwitterInstantErrorAccessDenied
                                           userInfo:nil];
    
    // 2 - 创建信号
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id subscriber) {
        // 3 - 请求Twitter访问权限
        @strongify(self)
        [self.accountStore requestAccessToAccountsWithType:self.twitterAccountType
                                                   options:nil
                                                completion:^(BOOL granted, NSError *error) {
                                                    // 4 - 处理响应
                                                    if (!granted) {// 不同意，返回错误
                                                        [subscriber sendError:accessError];
                                                    } else {// 同意
                                                        [subscriber sendNext:nil]; 
                                                        [subscriber sendCompleted]; 
                                                    } 
                                                }]; 
        return nil; 
    }]; 
}

/**
 *  发送获取微博请求
 *
 */
- (RACSignal *)signalForSearchWithText:(NSString *)text {
    // 1 - 自定义错误
    NSError *noAccountsError = [NSError errorWithDomain:RWTwitterInstantDomain
                                                   code:RWTwitterInstantErrorNoTwitterAccounts
                                               userInfo:nil];
    NSError *invalidResponseError = [NSError errorWithDomain:RWTwitterInstantDomain
                                                        code:RWTwitterInstantErrorInvalidResponse
                                                    userInfo:nil];
    // 2 - 创建信号
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self);
        
        // 3 - create the request
        SLRequest *request = [self requestforTwitterSearchWithText:text];
        
        // 4 - supply a twitter account
        NSArray *twitterAccounts = [self.accountStore accountsWithAccountType:self.twitterAccountType];
        
        if (twitterAccounts.count == 0) {// 未输入账号
            [subscriber sendError:noAccountsError];
        } else {
            [request setAccount:[twitterAccounts lastObject]];
            
            // 5 - perform the request
            [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
                if (urlResponse.statusCode == 200) {
                    // 6 - on success, parse the response
                    NSDictionary *timelineData = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingAllowFragments error:nil];
                    [subscriber sendNext:timelineData];
                    [subscriber sendCompleted];
                } else {
                    // 7 - send an error on failure
                    [subscriber sendError:invalidResponseError];
                }
            }];
        }
        
        return nil;
    }];
}

/**
 *  封装请求
 *
 */
- (SLRequest *)requestforTwitterSearchWithText:(NSString *)text {
    NSURL *url = [NSURL URLWithString:@"https://api.twitter.com/1.1/search/tweets.json"];
    NSDictionary *params = @{@"q" : text};
    SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeTwitter
                                            requestMethod:SLRequestMethodGET
                                                      URL:url
                                               parameters:params];
    return request; 
}

- (BOOL)isValidSearchText:(NSString *)text {
    return text.length > 2;
}

- (void)styleTextField:(UITextField *)textField {
  CALayer *textFieldLayer = textField.layer;
  textFieldLayer.borderColor = [UIColor grayColor].CGColor;
  textFieldLayer.borderWidth = 2.0f;
  textFieldLayer.cornerRadius = 0.0f;
}

@end
