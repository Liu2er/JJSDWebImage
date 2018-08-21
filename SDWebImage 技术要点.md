[TOC]

## SDWebImage 执行流程

### 接口调用

最常见的用法如下：

```objective-c
#import "UIImageView+WebCache.h"

[imageView sd_setImageWithURL:[NSURL URLWithString:@"https://www.dpfile.com/sc/eleconfig/contenttopicoperation/201803141901422.jpg"]];
```

但是 SDWebImage 还提供了一系列的调用接口，只是传入的参数不同，最终都会调用到这个全能方法：

```objective-c
- (void)sd_setImageWithPreviousCachedImageWithURL:(nullable NSURL *)url
                                 placeholderImage:(nullable UIImage *)placeholder
                                          options:(SDWebImageOptions)options
                                         progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                        completed:(nullable SDExternalCompletionBlock)completedBlock);
```

继续研究发现，最终都会调用到 `UIView+WebCache` 的方法：

```objective-c
- (void)sd_internalSetImageWithURL:(nullable NSURL *)url
                  placeholderImage:(nullable UIImage *)placeholder
                           options:(SDWebImageOptions)options
                      operationKey:(nullable NSString *)operationKey
                     setImageBlock:(nullable SDSetImageBlock)setImageBlock
                          progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                         completed:(nullable SDExternalCompletionBlock)completedBlock
                           context:(nullable NSDictionary<NSString *, id> *)context;
```

### 实现流程

1. 先取消正在进行的operation 
2. 根据需要设置展位图
3. 根据需要创建加载指示器 
4. 创建SDWebImageManager，并调用SDWebImageManager的loadImageWithURL:options:progress:completed:方法
5. load成功后通过sd_setImage:imageData:basedOnClassOrViaCustomSetImageBlock:transition:cacheType:imageURL:方法回到主线程中设置图片
6. load操作结束后，为UIView绑定新的operation，因为之前把UIView上的操作取消了 

## SDWebImage 核心方法

### sd_cancelImageLoadOperationWithKey 操作

在 sd_internalSetImageWithURL 的实现里，每次执行 sd_internalSetImageWithURL 方法时先执行 cancel operation的方法：

```objective-c
[self sd_cancelImageLoadOperationWithKey:validOperationKey];
```

loadImageWithURL 结束后又执行 set operation 的方法：

```objective-c
[self sd_setImageLoadOperation:operation forKey:validOperationKey];
```

如果没有传入自定义的 key，那么 validOperationKey 就是调用 sd_internalSetImageWithURL 对象的类型的字符串，例如 @"UIImageView"、@"UIButton"、@"NSButton"、@"UIView"。

#### sd_cancelImageLoadOperationWithKey: 

核心操作：

```objective-c
// operationDictionary是通过Associate为UIView添加了一个NSMapTable类型的属性
// 该operationDictionary里的key是@"UIImageView"、@"UIButton"、@"NSButton"、@"UIView"等，value是遵守了SDWebImageOperation协议的id类型的operation，该协议只有一个cancel方法
SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];

// operation是每次调用loadImageWithURL:options:progress:completed:方法返回的SDWebImageCombinedOperation类型的对象
// SDWebImageCombinedOperation是SDWebImageManager的私有类，是对每一个下载任务的封装（cancelled、downloadToken、cacheOperation、manager），遵守了SDWebImageOperation协议，它仅提供了一个取消功能
operation = [operationDictionary objectForKey:key];

// 实际执行了如下操作：
// 1、[cacheOperation cancel];
// 2、[imageDownloader cancel:downloadToken];
// 3、manager.runningOperations移除opration
[operation cancel];

// 取消operation的执行后，再将该operation从operationDictionary中移除
[operationDictionary removeObjectForKey:key];
```

#### sd_setImageLoadOperation:

核心操作：

```objective-c
// 添加前先移除
[self sd_cancelImageLoadOperationWithKey:key];

// 获得通过Associate为UIView添加了一个NSMapTable类型的属性operationDictionary
SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];

// 将以validOperationKey为key，以operation为value，保存到operationDictionary里
[operationDictionary setObject:operation forKey:key];
```



### 将图片设置到视图上

将图片设置到视图上调用的核心方法是：

```objective-c
- (void)sd_setImage:(UIImage *)image 
          imageData:(NSData *)imageData 
basedOnClassOrViaCustomSetImageBlock:(SDSetImageBlock)setImageBlock 
          transition:(SDWebImageTransition *)transition 
           cacheType:(SDImageCacheType)cacheType 
            imageURL:(NSURL *)imageURL
```

其实现流程是：

1. 判断调用本方法的对象的实际类型，如果是UIImageView类型，则调用imageView的set方法设置图片`imageView.image = setImage;`，如果是UIButton类型，则执行`[button setImage:setImage forState:UIControlStateNormal];`
2. 如果设置了过渡动画，则执行过渡动画



### 几种 cancel 总结

#### sd_cancelImageLoadOperationWithKey:

核心操作：

```objective-c
// operationDictionary是通过Associate为UIView添加了一个NSMapTable类型的属性
// 该operationDictionary里的key是@"UIImageView"、@"UIButton"、@"NSButton"、@"UIView"等，value是遵守了SDWebImageOperation协议的id类型的operation，该协议只有一个cancel方法
SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];

// operation是每次调用loadImageWithURL:options:progress:completed:方法返回的SDWebImageCombinedOperation类型的对象
// SDWebImageCombinedOperation是SDWebImageManager的私有类，是对每一个下载任务的封装（cancelled、downloadToken、cacheOperation、manager），遵守了SDWebImageOperation协议，它仅提供了一个取消功能
operation = [operationDictionary objectForKey:key];

// 实际执行了如下操作：
// 1、[cacheOperation cancel];
// 2、[imageDownloader cancel:downloadToken];
// 3、manager.runningOperations移除opration
[operation cancel];

// 取消operation的执行后，再将该operation从operationDictionary中移除
[operationDictionary removeObjectForKey:key];
```

#### SDWebImageCombinedOperation 的 cancel

核心操作：

```objective-c
- (void)cancel {
    @synchronized(self) {
        // 1、将self.cancelled值为YES
        self.cancelled = YES;
        if (self.cacheOperation) {
            // 2、执行cacheOperation的cancel操作，并将self.cacheOperation值为nil
            [self.cacheOperation cancel];
            self.cacheOperation = nil;
        }
        if (self.downloadToken) {
            // 3、执行imageDownloader的cancel:操作
            [self.manager.imageDownloader cancel:self.downloadToken];
        }
        // 3、将SDWebImageCombinedOperation对象从self.manager.runningOperations中移除
        [self.manager safelyRemoveOperationFromRunning:self];
    }
}
```

#### cacheOperation 的 cancel

self.cacheOperation 是 NSOperation 对象，用来停止查询缓存，执行的 cancel 是 NSOperation 类默认的 cancel 方法：

```objective-c
// 本cancel方法相当于只是将cacheOperation.isCancelled设置为YES，用来取消磁盘的查询操作，并无其他作用
[self.cacheOperation cancel];
```

其中 cacheOperation 是 SDImageCache 对象的 queryCacheOperationForKey:options:done: 方法返回的 NSOperation 类型的对象。

```objective-c
// 如果外面有调用了本方法返回的operation的cancel方法，那么再次查询的时候会终止查询磁盘
- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key options:(SDImageCacheOptions)options done:(nullable SDCacheQueryCompletedBlock)doneBlock {
    // 1、如果只需要查询内存
    doneBlock(image, nil, SDImageCacheTypeMemory);
    
    // 2、满足在“内存中找到了图片仍去磁盘中查找”或“没在内存中找到图片”两种情况就执行下面的操作
    NSOperation *operation = [NSOperation new];
    void(^queryDiskBlock)(void) =  ^{
        if (operation.isCancelled) {
            return;
        }        
        // 3、查询磁盘
    };
    
    // 4、执行queryDiskBlock
    
    // 5、返回operation
    return operation;
}
```

#### SDWebImageDownloader 的 cancel:

SDWebImageDownloader 的 cancel: 方法传入的是 SDWebImageDownloadToken 类型的 token
SDWebImageDownloaderOperation 的 cancel: 方法传入的是 SDCallbacksDictionary 类型的 token

```objective-c
// 实际上是执行SDWebImageDownloaderOperation的cancel:操作
// 传入的token是保存在SDWebImageCombinedOperation里的downloadToken，其类型是SDWebImageDownloadToken
- (void)cancel:(nullable SDWebImageDownloadToken *)token {
    NSURL *url = token.url;
    if (!url) {
        return;
    }
    LOCK(self.operationsLock);
    SDWebImageDownloaderOperation *operation = [self.URLOperations objectForKey:url];
    if (operation) {
        // 1、执行SDWebImageDownloaderOperation的cancel:
        BOOL canceled = [operation cancel:token.downloadOperationCancelToken];
        if (canceled) {
            // 2、将url从self.URLOperations中移除
            [self.URLOperations removeObjectForKey:url];
        }
    }
    UNLOCK(self.operationsLock);
}
```

#### SDWebImageDownloaderOperation 的 cancel:

传入的 token 是一个保存了 progressBlock 和 completedBlock 的**回调块字典**，本方法时从 operation.callbackBlocks 中移除某个 token，当 callbackBlocks 中的回调块字典全部被删除了才会真正取消任务

```objective-c
- (BOOL)cancel:(nullable id)token {
    BOOL shouldCancel = NO;
    LOCK(self.callbacksLock);
    // 1、从self.callbackBlocks移除传入的token
    [self.callbackBlocks removeObjectIdenticalTo:token];
    
    if (self.callbackBlocks.count == 0) {
        shouldCancel = YES;
    }
    UNLOCK(self.callbacksLock);

    if (shouldCancel) {
        // 2、self.callbackBlocks中的回调块删除完了就执行真正的取消操作
        [self cancel];
    }
    return shouldCancel;
}

// SDWebImageOperation协议的cancel方法，取消任务
- (void)cancel {
    @synchronized (self) {
        [self cancelInternal];
    }
}

//真正取消下载任务的方法
- (void)cancelInternal {
    if (self.isFinished) return;
    // 1、调用NSOperation类的cancel方法，即，将isCancelled属性置为YES
    [super cancel];

    if (self.dataTask) {
        // 2、执行NSURLSessionTask的cancel方法
        [self.dataTask cancel];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            // 3、发送DownloadStop的通知
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:weakSelf];
        });

        // 4、重置各self.executing和self.finished的状态
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    }

    [self reset];
}

- (void)reset {
    LOCK(self.callbacksLock);
    [self.callbackBlocks removeAllObjects];
    UNLOCK(self.callbacksLock);
    self.dataTask = nil;
    
    //如果ownedSession存在，就需要我们手动调用invalidateAndCancel方法打破循环引用
    if (self.ownedSession) {
        [self.ownedSession invalidateAndCancel];
        self.ownedSession = nil;
    }
}
```

## 易混淆类分析

### 两种 token

#### SDWebImageDownloadToken 和 SDCallbacksDictionary

SDWebImageDownloadToken 是一个继承自 NSObject 的类，遵守了 SDWebImageOperation 协议，它与每一个下载任务相绑定（绑定了url、CancelToken字典、operation），用于取消下载任务（根据token获得url，根据url从dowloader.URLOperations里获得operation，再根据operation和token里的cancelToken来执行取消任务[operation cancel:cancelToken] ）。

SDCallbacksDictionary 是一个包含了通过对外暴露的sd_setImage方法传入的progressBlock和completedBlock的字典，这个字典要保存在SDWebImageDownloadToken里（token.downloadOperationCancelToken）。

SDWebImageDownloaderOperation.callbackBlocks 中保存了很多SDCallbacksDictionary对象，当callbackBlocks中的回调块删除完了就执行真正的取消操作。

```objective-c
- (nullable SDWebImageDownloadToken *)downloadImageWithURL:(nullable NSURL *)url
                                                   options:(SDWebImageDownloaderOptions)options
                                                  progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                                 completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock {

    return [self addProgressCallback:progressBlock completedBlock:completedBlock forURL:url createCallback:^SDWebImageDownloaderOperation *{
        
        //创建operation
        SDWebImageDownloaderOperation *operation = [[sself.operationClass alloc] initWithRequest:request inSession:sself.session options:options];

        //返回operation
        return operation;
    }];
}

- (nullable SDWebImageDownloadToken *)addProgressCallback:(SDWebImageDownloaderProgressBlock)progressBlock
                                           completedBlock:(SDWebImageDownloaderCompletedBlock)completedBlock
                                                   forURL:(nullable NSURL *)url
                                           createCallback:(SDWebImageDownloaderOperation *(^)(void))createCallback {
    
	// 1、获取SDWebImageDownloaderOperation对象
    SDWebImageDownloaderOperation *operation = createCallback();
        
    // 2、将operation添加到并发队列里
    [self.downloadQueue addOperation:operation];

    // 3、创建downloadOperationCancelToken
    id downloadOperationCancelToken = [operation addHandlersForProgress:progressBlock completed:completedBlock];
    
    // 4、创建SDWebImageDownloadToken对象
    SDWebImageDownloadToken *token = [SDWebImageDownloadToken new];
    token.downloadOperation = operation;
    token.url = url;
    token.downloadOperationCancelToken = downloadOperationCancelToken;

	// 5、返回token
    return token;
}
```



### 几种常用类

- **SDWebImageDownloaderOperation：**

  自定义的下载任务，继承自 NSOperation，类似于 NSBlockOperation 和 NSInvocationOperation。当将 SDWebImageDownloaderOperation 加入到队列中后，就会自动启动下载任务，下载任务写在复写的 start 方法里。

- **SDWebImageDownloadToken：**

  继承自 NSObject，遵守了 SDWebImageOperation 协议，它与每一个下载任务相绑定（绑定了url、downloadOperation、downloadOperationCancelToken），用于取消下载任务（仅取消下载）：

  根据token获得url，根据url从dowloader.URLOperations里获得operation，再根据operation和token里的cancelToken来执行取消任务[operation cancel:cancelToken]

  SDWebImageDownloadToken 的 cancel 操作只是 SDWebImageCombinedOperation 的 cancel 操作的一个实现环节。

  SDWebImageDownloadToken 仅用于取消下载的任务，而 SDWebImageCombinedOperation 用于较早地取消所有任务（下载、查找缓存等所有操作）。

- **SDWebImageCombinedOperation：**

  继承自 NSObject，遵守了 SDWebImageOperation 协议，它是对每一个下载任务的封装（封装了cancelled 、downloadToken、cacheOperation、manager），是 SDWebImageManager 的私有类，它仅提供了一个取消功能（取消下载和查找缓存）：

  1. [ _UIView sd_cancelImageLoadOperationWithKey:validOperationKey]; 

  2. [ _SDWebImageCombinedOperation cancel];

  3. [ _SDWebImageCombinedOperation.cacheOperation cancel];

     [ \_SDWebImageCombinedOperation.manager.imageDownloader cancel:\_SDWebImageCombinedOperation.downloadToken];

  4. [ \_SDWebImageDownloaderOperation cancel:\_SDWebImageCombinedOperation.downloadToken.downloadOperationCancelToken];

- **SDWebImageOperation：**

  是一个协议，只有一个 cancel 方法。

- **SDWebImageDownloader：**

  执行下载操作的类，其内有个 `downloadImageWithURL:options:progress:completed:` 方法。



## 其他

### 图片加载和解码

UIIImage 提供了两种加载图片方法，分别是 **imageNamed:** 和 **imageWithContentsOfFile:**。

其中，**imageNamed:** 方法的特点在于**可以缓存已经加载的图片**；使用时，先根据文件名在系统缓存中寻找图片，如果找到了就返回；如果没有，从Bundle内找到该文件，在渲染到屏幕时才**解码**图片，并将解码结果保留到缓存中；当收到内存警告时，缓存会被清空。当频繁加载同一张图片时，使用**imageNamed:** 效果比较好。而**imageWithContentsOfFile：**仅加载图片，不缓存图像数据。

虽然**imageNamed:** 方法利用缓存优化了图片的加载性能，但是第一次加载图片时，只在渲染的时候才在主线程**解码**，性能并不高效，尤其是在列表中加载多张高分辨率的图片（大图），可能会造成卡顿；

优化解码耗时的思路是：**将耗时的解码工作放在子线程中完成**。SDWebImage和FastImageCache就是这么做的。具体的解码工作就是SDWebImageDecoder负责的。

参考 [篇1：SDWebImage源码看图片解码](https://www.jianshu.com/p/728f71b9fe28)

在我们使用 UIImage 的时候，创建的图片通常不会直接加载到内存，而是在渲染的时候再进行解压并加载到内存。这就会导致 UIImage 在渲染的时候效率上不是那么高效。为了提高效率 SDWebImage 通过 `decodedImageWithImage`方法把图片提前解压加载到内存，这样这张新图片就不再需要重复解压了，提高了渲染效率。这是一种空间换时间的做法。

