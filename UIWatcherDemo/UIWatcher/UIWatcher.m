//
//  UIWatcher.m
//  JSBridge
//
//  Created by Golder on 2017/9/19.
//  Copyright © 2017年 Golder. All rights reserved.
//

#import "UIWatcher.h"
#import <mach/message.h>
#import <pthread.h>
#import <signal.h>
#import <QuartzCore/QuartzCore.h>

#define MainThreadReportPortKey @"UIWatcher_main_thread_report_port_key"
#define WorkThreadListenPortKey @"UIWatcher_work_thread_listen_port_key"

#define CALLSTACK_SIG SIGUSR1

@interface JSWeakProxy : NSProxy
@property (nonatomic, weak) id target;
+ (instancetype)proxyWithWeakTarget:(id)target;
@end

@implementation JSWeakProxy

+ (instancetype)proxyWithWeakTarget:(id)target {
    return [[self alloc] initWithTarget:target];
}

- (instancetype)initWithTarget:(id)target {
    _target = target;
    return self;
}

- (BOOL)isProxy {
    return YES;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [self.target respondsToSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:self.target];
}

- (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [self.target methodSignatureForSelector:sel];
}

@end

@interface UIWatcher () <NSMachPortDelegate>

@property (nonatomic, strong) NSThread *workThread;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, strong) NSTimer *workTimer;

@property (nonatomic, assign) CFTimeInterval start;
@property (nonatomic, assign) CFTimeInterval end;

@end

@implementation UIWatcher

pthread_t mainThreadID;

dispatch_queue_t global_queue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
}

void main_thread_call_stack(int sig) {
    if (sig != CALLSTACK_SIG) {
        return;
    }
    
    NSArray *callStack = [NSThread callStackSymbols];
    printf("UIWatcher slow call stack symbols: \n");
    for (NSString *symbol in callStack) {
        printf("%s\n", symbol.UTF8String);
    }
    
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *time = [format stringFromDate:[NSDate date]];
    
    NSArray *stackSymbols = [NSThread callStackSymbols];
    NSString *record = @"\n\n";
    record = [record stringByAppendingString:[NSString stringWithFormat:@"%@\n", time]];
    record = [record stringByAppendingString:[stackSymbols componentsJoinedByString:@"\n"]];
    
    dispatch_async(global_queue(), ^{
        [UIWatcher storeSlowRecord:record];
    });
}

+ (NSString *)watchFilePath {
    NSString *path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    path = [path stringByAppendingPathComponent:@"watchslow.txt"];
    return path;
}

+ (void)storeSlowRecord:(NSString *)record {
    NSString *path = [UIWatcher watchFilePath];
    
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:path]) {
        NSData *old = [NSData dataWithContentsOfFile:path];
        NSString *newRecord = [[[NSString alloc] initWithData:old encoding:NSUTF8StringEncoding] stringByAppendingString:record];
        record = newRecord;
    }
    NSData *data = [record dataUsingEncoding:NSUTF8StringEncoding];
    [data writeToFile:path atomically:YES];
}

+ (NSString *)watchRecords {
    NSString *path = [UIWatcher watchFilePath];
    NSString *records = nil;
    
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:path]) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        records = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return records;
}

+ (void)cleanRecords {
    NSString *path = [UIWatcher watchFilePath];
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:path]) {
        [manager removeItemAtPath:path error:NULL];
    }
}

+ (instancetype)shareInstance {
    static UIWatcher *watcher;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        watcher = [UIWatcher new];
    });
    return watcher;
}

- (void)startWatch {
    NSAssert([NSThread isMainThread], @"UIWatcher: UIWatch must launch in main thread!");
    
    mainThreadID = pthread_self();
    signal(CALLSTACK_SIG, main_thread_call_stack);
    
    NSThread *mainThread = [NSThread mainThread];
    
    NSPort *reportPort = [NSMachPort port];
    [reportPort setDelegate:self];
    [reportPort scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    [NSThread detachNewThreadSelector:@selector(launchListenThreadWithPort:) toTarget:self withObject:reportPort];
    
    [mainThread.threadDictionary setValue:reportPort forKey:MainThreadReportPortKey];
}

- (void)stopWatch {
    if (_timeoutTimer) {
        [_timeoutTimer invalidate];
        _timeoutTimer = nil;
    }
    
    if (_workTimer) {
        [_workTimer invalidate];
        _workTimer = nil;
    }
    
    NSThread *main = [NSThread mainThread];
    NSPort *reportPort = [main.threadDictionary valueForKey:MainThreadReportPortKey];
    [[NSRunLoop mainRunLoop] removePort:reportPort forMode:NSRunLoopCommonModes];
    [main.threadDictionary removeObjectForKey:MainThreadReportPortKey];
    
    if (self.workThread) {
        [self performSelector:@selector(exitWorkThread) onThread:self.workThread withObject:nil waitUntilDone:YES];
        self.workThread = nil;
    }
}

- (void)exitWorkThread {
    NSThread *workThread = [NSThread currentThread];
    NSPort *workPort = [workThread.threadDictionary valueForKey:WorkThreadListenPortKey];
    [[NSRunLoop currentRunLoop] removePort:workPort forMode:NSRunLoopCommonModes];
    [workThread.threadDictionary removeObjectForKey:WorkThreadListenPortKey];
}

- (void)launchListenThreadWithPort:(NSMachPort *)reportPort { @autoreleasepool {
    NSAssert(![NSThread isMainThread], @"UIWatcher: listen thread can not be main thread");
    
    if (self.workThread) {
        return;
    }
    
    NSThread *workThread = [NSThread currentThread];
    workThread.qualityOfService = NSQualityOfServiceUserInteractive;
    workThread.name = @"UIWatch_work_thread";
    self.workThread = workThread;
    
    NSPort *listenPort = [NSMachPort port];
    [listenPort setDelegate:self];
    [workThread.threadDictionary setValue:listenPort forKey:WorkThreadListenPortKey];
    
    NSTimer *workTimer = [NSTimer timerWithTimeInterval:1.0 target:[JSWeakProxy proxyWithWeakTarget:self] selector:@selector(pingMainThread:) userInfo:nil repeats:YES];
    NSRunLoop *listenRunLoop = [NSRunLoop currentRunLoop];
    [listenRunLoop addPort:listenPort forMode:NSRunLoopCommonModes];
    [listenRunLoop addTimer:workTimer forMode:NSRunLoopCommonModes];
    [listenRunLoop run];
    _workTimer = workTimer;
} }

- (void)pingMainThread:(NSTimer *)timer {
    NSAssert(![NSThread isMainThread], @"UIWatcher: ping action must occur on secondary thread!");
    
    NSThread *mainThread = [NSThread mainThread];
    NSMachPort *reportPort = mainThread.threadDictionary[MainThreadReportPortKey];
    
    if (!reportPort) {
        return;
    }

    NSUInteger msgID = arc4random() % 100000;
    NSMachPort *listenPort = self.workThread.threadDictionary[WorkThreadListenPortKey];
    
    // 设置超时计时器
    NSTimer *timeoutTimer = [NSTimer timerWithTimeInterval:0.02 target:[JSWeakProxy proxyWithWeakTarget:self] selector:@selector(pingTimeout:) userInfo:@{@"msgid": @(msgID)} repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:timeoutTimer forMode:NSRunLoopCommonModes];
    _timeoutTimer = timeoutTimer;
    
    _start = CACurrentMediaTime();
    [reportPort sendBeforeDate:[NSDate date] msgid:msgID components:nil from:listenPort reserved:1];
}

- (void)pongWorkThread:(NSNumber *)msgID {
    NSAssert([NSThread isMainThread], @"UIWatcher: pong action must occur on main thread!");
    
    NSThread *workThread = self.workThread;
    NSMachPort *listenPort = workThread.threadDictionary[WorkThreadListenPortKey];
    
    if (!listenPort) {
        return;
    }
    
    NSMachPort *reportPort = [NSThread mainThread].threadDictionary[MainThreadReportPortKey];
    [listenPort sendBeforeDate:[NSDate date] msgid:msgID.longLongValue+1 components:nil from:reportPort reserved:1];
}

- (void)pingTimeout:(NSTimer *)timer {
    
    _end = CACurrentMediaTime();
    CFTimeInterval inteval = _end - _start;
    
    NSString *log = [NSString stringWithFormat:@"%@ timeout %.3lf\n", [NSThread currentThread], inteval];
    printf("🆘🆘🆘🆘🆘🆘🆘🆘🆘\n");
    [self printLog:log];
    
    pthread_kill(mainThreadID, CALLSTACK_SIG);
    
    
    [timer invalidate];
    self.timeoutTimer = nil;
}

- (void)printCallStack {
    main_thread_call_stack(CALLSTACK_SIG);
}

- (void)printLog:(NSString *)log {
    printf("======== UIWatcher Start ========\n");
    printf("%s", log.UTF8String);
    printf("======== UIWatcher End ========\n");
}

#pragma mark - NSMachPortDelegate

- (void)handleMachMessage:(void *)msg {
    
    mach_msg_header_t *mach_msg = (mach_msg_header_t *)msg;
    if ([NSThread isMainThread]) {
        // 主线程收到ping，立刻回复pong
        [self performSelectorOnMainThread:@selector(pongWorkThread:) withObject:@(mach_msg->msgh_id) waitUntilDone:NO];
    } else {
        if (self.timeoutTimer) {
            [self.timeoutTimer invalidate];
            self.timeoutTimer = nil;
        }
    }
}

@end
