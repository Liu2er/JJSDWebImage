[TOC]

## 概述

本文为笔者在阅读 [SDWebImage](https://github.com/rs/SDWebImage#author) 时的笔记，帮助自己加深印象，让学习一步一个脚印，也希望能帮到其他人。

### 流程图

学习 SDWebImage 就不得不看官方提供的流程图和 UML 图：

<img src="./MDImages/SDWebImageSequenceDiagram.png"/>

<img src="./MDImages/SDWebImageClassDiagram.png"/>

阅读源码之前，首先通过对源文件进行分组来查看源码的文件结构，分组方式1（[SDWebImage 源码解析](https://zhuanlan.zhihu.com/p/27456754)）：

<img src="./MDImages/SDWebImage 01.jpg" width="250px" />

分组方式2：

<img src="./MDImages/SDWebImage 02.png" width="400px" />

或参考以下 Workflow（[搬好小板凳看SDWebImage源码解析（一）](http://www.cocoachina.com/ios/20171218/21566.html)）：

<img src="./MDImages/SDWebImage 03.png" width="500px" />

再来看一个框架的调用流程图（[SDWebImage源码解析](https://www.jianshu.com/p/93696717b4a3)）：

<img src="./MDImages/SDWebImage 04.png" width="500px" />

### 源码阅读

`UIImageView +WebCache` 暴露了很多调用灵活的接口，其最终都会调用到 `UIView+WebCache` 分类的如下方法中：

```objective-c
- (void)sd_internalSetImageWithURL:(nullable NSURL *)url
                  placeholderImage:(nullable UIImage *)placeholder
                           options:(SDWebImageOptions)options
                      operationKey:(nullable NSString *)operationKey
                     setImageBlock:(nullable SDSetImageBlock)setImageBlock
                          progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                         completed:(nullable SDExternalCompletionBlock)completedBlock;
```

因为 SDWebImage 框架也支持 UIButton 的下载图片等方法，所以需要在它们的父类 `UIView` 里面统一一个下载方法（[SDWebImage源码解析](https://www.jianshu.com/p/93696717b4a3)）。

<img src="./MDImages/SDWebImage 05.png" width="650px" />

该方法里执行了如下操作：

- 先取消正在进行的operation
- options ！= SDWebImageDelayPlaceholder 就先展示占位图
- url存在：
  - 创建加载指示器菊花
  - 获取manager
  - 调用manager的loadImage:::方法，并返回operation，loadImage:::结束的回调里执行如下步骤：
    - 停掉加载指示器（菊花）
    - 根据需要标记为progress的完成状态
    - 不需要设置图片的情况：
      - 如果需要调用completedBlock回调，就在主线程中执行completedBlock回调
    - 需要设置图片的情况：
      - 图片存在，且没有设置SDWebImageAvoidAutoSetImage：targetImage = image, targetData = data;
      - 图片不存在，且设置了延迟展示占位图：targetImage = placeholder, targetData = nil;
      - 加载结束 且 （options为图片强制转场 或 cacheType为None），就设置transition = sself.sd_imageTransition;
      - 回到主线程中设置图片：即调用sd_setImage:imageData:basedOnClassOrViaCustomSetImageBlock:transition:cacheType:imageURL:方法，如果group存在，则设置图片和完成回调的的操作需要加入group，不存在group则直接调用设置图片的方法，最后主线程调用回调block
  - load操作结束后，为UIView绑定新的operation，因为之前把UIView上的操作取消了
- url不存在：
  - 停掉加载指示器（菊花）
  - 调用completedBlock回调，在其中返回错误信息

## 参考

- [SDWebImage 源码解析](https://zhuanlan.zhihu.com/p/27456754)
- [搬好小板凳看SDWebImage源码解析（一）](http://www.cocoachina.com/ios/20171218/21566.html)
- [SDWebImage源码解析](https://www.jianshu.com/p/93696717b4a3)