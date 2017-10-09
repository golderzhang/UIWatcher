//
//  ViewController.m
//  UIWatcherDemo
//
//  Created by Golder on 2017/10/9.
//  Copyright © 2017年 Golder. All rights reserved.
//

#import "ViewController.h"
#import "UIWatcher.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextView *logsView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self doBusyJob];
}

- (void)doBusyJob {
    for (int i = 0; i < 10000; i++) {
        NSLog(@"busy...");
    }
}

- (IBAction)refresh:(id)sender {
    _logsView.text = [UIWatcher watchRecords];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
