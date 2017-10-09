//
//  UIWatcher.h
//  JSBridge
//
//  Created by Golder on 2017/9/19.
//  Copyright © 2017年 Golder. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface UIWatcher : NSObject

+ (instancetype)shareInstance;

- (void)startWatch;
- (void)stopWatch;

+ (NSString *)watchRecords;
+ (void)cleanRecords;

@end
