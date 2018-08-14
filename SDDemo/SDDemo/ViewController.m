//
//  ViewController.m
//  SDDemo
//
//  Created by 刘佳杰 on 2018/8/13.
//  Copyright © 2018年 Jiajie.Liu. All rights reserved.
//

#import "ViewController.h"
#import "UIImageView+WebCache.h"

@interface ViewController ()

@property (nonatomic, strong) UIImageView *imageView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    CGFloat top = 50;
    CGFloat left = 10;
    CGFloat width = [UIScreen mainScreen].bounds.size.width - left * 2;
    CGFloat height = [UIScreen mainScreen].bounds.size.height - top * 2;
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(left, top, width, height)];
    imageView.backgroundColor = [UIColor lightGrayColor];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:imageView];
    self.imageView = imageView;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.imageView.image = nil;
    [self addImage];
}

- (void)addImage {
//    NSURL *url = [NSURL URLWithString:@"https://pic.qqtn.com/up/2016-4/201604281819303646024.png"];
//    NSURL *url = [NSURL URLWithString:@"http://pic.netbian.com/uploads/allimg/180128/113416-1517110456633d.jpg"];
    NSURL *url = [NSURL URLWithString:@"https://www.dpfile.com/sc/eleconfig/contenttopicoperation/201803141901422.jpg"];
    [self.imageView sd_setImageWithURL:url placeholderImage:nil completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
        NSLog(@"\nLiujiajie2: image = %@", image);
        NSLog(@"\nLiujiajie2:");
        NSLog(@"\nLiujiajie2: error = %@", error);
        NSLog(@"\nLiujiajie2:");
        NSLog(@"\nLiujiajie2: cacheType = %@", @(cacheType));
        NSLog(@"\nLiujiajie2:");
        NSLog(@"\nLiujiajie2: imageURL = %@", imageURL);
        NSLog(@"\nLiujiajie2:");
    }];
}

@end
