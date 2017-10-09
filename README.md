# UIWatcher
iOS平台UI卡顿检测组件，简单超实用

# UIWatcher能干什么
  UIWatcher是一个监控UI卡顿的组件，当iOS系统不能做到60FPS的刷新时，记录哪些函数的执行影响了界面的刷新，是提升App性能的绝佳工具

# 如何使用

- 下载工程Demo文件，拷贝UIWatcher.h与UIWatcher.m文件到需要的工程
- 在App启动时插入 [[UIWatcher shareInstance] startWatch]; 即可

开启监控
AppDelegate.m
``` object-c
#import "UIWatcher.h"
@implementation
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    [[UIWatcher shareInstance] startWatch];
    return YES;
}
@end
```

查看卡顿记录
```object-c
NSString *records = [[UIWatcher shareInstance] watchRecords];
```

# 实现原理
    iOS中UI刷新的频率是60FPS，主线程在每次Runloop中执行代码的时间不能超过16.6ms，否则会掉帧
    UIWatcher建立了一个work线程定时向main线程发送消息，如果work线程不能在16.6ms内收到main线程的回复，则记录main线程的调用栈

# Sorry
- 在Xcode连接状态下不可用，因为Xcode会捕获signal信号
