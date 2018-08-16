/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import "NSImage+WebCache.h"
#import <objc/message.h>

#define LOCK(lock) dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
#define UNLOCK(lock) dispatch_semaphore_signal(lock);

//SDWebImageCombinedOperation是对每一个下载任务的封装，是SDWebImageManager的私有类，它仅提供了一个取消功能
@interface SDWebImageCombinedOperation : NSObject <SDWebImageOperation>

@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
@property (strong, nonatomic, nullable) SDWebImageDownloadToken *downloadToken;
@property (strong, nonatomic, nullable) NSOperation *cacheOperation;
@property (weak, nonatomic, nullable) SDWebImageManager *manager;

@end

@interface SDWebImageManager ()

@property (strong, nonatomic, readwrite, nonnull) SDImageCache *imageCache;
@property (strong, nonatomic, readwrite, nonnull) SDWebImageDownloader *imageDownloader;
@property (strong, nonatomic, nonnull) NSMutableSet<NSURL *> *failedURLs;
@property (strong, nonatomic, nonnull) dispatch_semaphore_t failedURLsLock; // a lock to keep the access to `failedURLs` thread-safe
@property (strong, nonatomic, nonnull) NSMutableArray<SDWebImageCombinedOperation *> *runningOperations;
@property (strong, nonatomic, nonnull) dispatch_semaphore_t runningOperationsLock; // a lock to keep the access to `runningOperations` thread-safe

@end

@implementation SDWebImageManager

+ (nonnull instancetype)sharedManager {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (nonnull instancetype)init {
    SDImageCache *cache = [SDImageCache sharedImageCache];
    SDWebImageDownloader *downloader = [SDWebImageDownloader sharedDownloader];
    return [self initWithCache:cache downloader:downloader];
}

- (nonnull instancetype)initWithCache:(nonnull SDImageCache *)cache downloader:(nonnull SDWebImageDownloader *)downloader {
    if ((self = [super init])) {
        _imageCache = cache;
        _imageDownloader = downloader;
        _failedURLs = [NSMutableSet new];
        _failedURLsLock = dispatch_semaphore_create(1);
        _runningOperations = [NSMutableArray new];
        _runningOperationsLock = dispatch_semaphore_create(1);
    }
    return self;
}

// 默认用url.absoluteString作为cache的key，如果自定义了self.cacheKeyFilter就用自定义的方式转换出key
- (nullable NSString *)cacheKeyForURL:(nullable NSURL *)url {
    if (!url) {
        return @"";
    }

    if (self.cacheKeyFilter) {
        return self.cacheKeyFilter(url);
    } else {
        return url.absoluteString;
    }
}

- (nullable UIImage *)scaledImageForKey:(nullable NSString *)key image:(nullable UIImage *)image {
    return SDScaledImageForKey(key, image);
}

// 先去内存中查找，再去磁盘中查找，最后都从completionBlock返回结果
- (void)cachedImageExistsForURL:(nullable NSURL *)url
                     completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    BOOL isInMemoryCache = ([self.imageCache imageFromMemoryCacheForKey:key] != nil);
    
    if (isInMemoryCache) {
        // making sure we call the completion block on the main queue
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(YES);
            }
        });
        return;
    }
    
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];
}

- (void)diskImageExistsForURL:(nullable NSURL *)url
                   completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];
}

/*
 url的类型检查
 创建operation（SDWebImageCombinedOperation类型）
 （如果url不合法，或失败过且失败了也不重试）
     执行一个url不合法的Completion回调，并返回operation
 （接下来为url合法，且失败了重试的情况）
     将operation加入self.runningOperations
     去缓存中查找图片，且返回一个NSOperation对象，保存在operation的cacheOperation属性里
        （接下来为查找结果的回调）
        需要从网络下载图片：
            cachedImage存在且需要刷新cache，则执行回调callCompletionBlockForOperation
            从网络下载图片，返回一个SDWebImageDownloadToken类型的对象，保存在operation的downloadToken属性里
                (下载结束的回调)
                operation被提前释放了，或者operation的任务被取消了，什么都不做
                (如果下载出错了)
                    执行回调callCompletionBlockForOperation，传入错误信息
                    判断是否要把失败的url存入self.failedURLs
                (下载成功了)
                    如果options是失败后重试，则把url从self.failedURLs移除掉
                    将downloadedImage和cacheData存储到缓存中
                    执行成功回调
                    ... ...
        不需要从网络下载图片，且在缓存中找到了图片，执行回调callCompletionBlockForOperation
        不需要从网络下载图片，且没有在缓存中找到图片，执行回调callCompletionBlockForOperation
     返回operation（该operation为SDWebImageCombinedOperation类型，保存了查询队列NSOperation）
 */
- (id <SDWebImageOperation>)loadImageWithURL:(nullable NSURL *)url
                                     options:(SDWebImageOptions)options
                                    progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                   completed:(nullable SDInternalCompletionBlock)completedBlock {
    // Invoking this method without a completedBlock is pointless
    NSAssert(completedBlock != nil, @"If you mean to prefetch the image, use -[SDWebImagePrefetcher prefetchURLs] instead");

    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, Xcode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    //如果传入的url是字符串类型，则将url转换成NSURL类型(容错处理)
    if ([url isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:(NSString *)url];
    }

    // Prevents app crashing on argument type error like sending NSNull instead of NSURL
    //传入的url既不是NSString也不是NSURL时，将其设置为nil，防止crash
    if (![url isKindOfClass:NSURL.class]) {
        url = nil;
    }

    //SDWebImageCombinedOperation继承自NSObject，是SDWebImageManager的私有类，是对每一个下载任务的封装，遵守了SDWebImageOperation协议，它仅提供了一个取消功能
    SDWebImageCombinedOperation *operation = [SDWebImageCombinedOperation new];
    operation.manager = self;

    //如果url下载失败过，就将isFailedUrl置为YES
    BOOL isFailedUrl = NO;
    if (url) {
        LOCK(self.failedURLsLock);
        isFailedUrl = [self.failedURLs containsObject:url];
        UNLOCK(self.failedURLsLock);
    }

    //（如果url长度为0）或者（曾经下载失败过，且options失败后不重试）
    if (url.absoluteString.length == 0 || (!(options & SDWebImageRetryFailed) && isFailedUrl)) {
        //执行一个url不合法的Completion回调
        [self callCompletionBlockForOperation:operation completion:completedBlock error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil] url:url];
        return operation;
    }

    //将operation加入到self.runningOperations数组中，其中存放正在执行的任务
    LOCK(self.runningOperationsLock);
    [self.runningOperations addObject:operation];
    UNLOCK(self.runningOperationsLock);
    //获取由url转换的key（实际上就是url.absoluteString，用户实现了self.cacheKeyFilter(url)则另当别论）
    NSString *key = [self cacheKeyForURL:url];
    
    SDImageCacheOptions cacheOptions = 0;
    if (options & SDWebImageQueryDataWhenInMemory) cacheOptions |= SDImageCacheQueryDataWhenInMemory;
    if (options & SDWebImageQueryDiskSync) cacheOptions |= SDImageCacheQueryDiskSync;
    if (options & SDWebImageScaleDownLargeImages) cacheOptions |= SDImageCacheScaleDownLargeImages;
    
    __weak SDWebImageCombinedOperation *weakOperation = operation;
    //根据key和cacheOptions在缓存中查找图片，且返回一个NSOperation对象，保存在SDWebImageCombinedOperation的实例operation的cacheOperation属性里
    operation.cacheOperation = [self.imageCache queryCacheOperationForKey:key options:cacheOptions done:^(UIImage *cachedImage, NSData *cachedData, SDImageCacheType cacheType) {
        __strong __typeof(weakOperation) strongOperation = weakOperation;
        //如果strongOperation被提前释放了，或者被取消了
        if (!strongOperation || strongOperation.isCancelled) {
            //将strongOperation从self.runningOperations中安全地移除
            [self safelyRemoveOperationFromRunning:strongOperation];
            return;
        }
        
        // Check whether we should download image from network
        //检查是否需要从网络下载图片：（不只从缓存中读取）且 (cachedImage不存在 或者 需要刷新cache) 且 (self.delegate不能响应方法imageManager:shouldDownloadImageForURL: 或者 能响应该方法且返回YES)
        //本options是从block外面截获的自动变量
        // imageManager:shouldDownloadImageForURL:是SDWebImageManagerDelegate协议的代理方法，表示当缓存中没找到图片时，本方法用来控制要不要下载图片，返回NO时不下载
        BOOL shouldDownload = (!(options & SDWebImageFromCacheOnly))
            && (!cachedImage || options & SDWebImageRefreshCached)
            && (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url]);
        
        //如果需要从网络下载图片
        if (shouldDownload) {
            //cachedImage存在 且 需要刷新cache（即从缓存中知道了图片，但是SDWebImageRefreshCached==YES时，依然要重新从网络下载图片）
            if (cachedImage && options & SDWebImageRefreshCached) {
                // If image was found in the cache but SDWebImageRefreshCached is provided, notify about the cached image
                // AND try to re-download it in order to let a chance to NSURLCache to refresh it from server.
                //以下方法其实就是回到主线程安全地执行completedBlock，并把这些参数一并带过去
                [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
            }

            // download if no image or requested to refresh anyway, and download allowed by delegate
            SDWebImageDownloaderOptions downloaderOptions = 0;
            if (options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
            if (options & SDWebImageProgressiveDownload) downloaderOptions |= SDWebImageDownloaderProgressiveDownload;
            if (options & SDWebImageRefreshCached) downloaderOptions |= SDWebImageDownloaderUseNSURLCache;
            if (options & SDWebImageContinueInBackground) downloaderOptions |= SDWebImageDownloaderContinueInBackground;
            if (options & SDWebImageHandleCookies) downloaderOptions |= SDWebImageDownloaderHandleCookies;
            if (options & SDWebImageAllowInvalidSSLCertificates) downloaderOptions |= SDWebImageDownloaderAllowInvalidSSLCertificates;
            if (options & SDWebImageHighPriority) downloaderOptions |= SDWebImageDownloaderHighPriority;
            if (options & SDWebImageScaleDownLargeImages) downloaderOptions |= SDWebImageDownloaderScaleDownLargeImages;
            
            if (cachedImage && options & SDWebImageRefreshCached) {
                // force progressive off if image already cached but forced refreshing
                downloaderOptions &= ~SDWebImageDownloaderProgressiveDownload;
                // ignore image read from NSURLCache if image if cached but force refreshing
                downloaderOptions |= SDWebImageDownloaderIgnoreCachedResponse;
            }
            
            // `SDWebImageCombinedOperation` -> `SDWebImageDownloadToken` -> `downloadOperationCancelToken`, which is a `SDCallbacksDictionary` and retain the completed block below, so we need weak-strong again to avoid retain cycle
            __weak typeof(strongOperation) weakSubOperation = strongOperation;
            //执行下载操作
            strongOperation.downloadToken = [self.imageDownloader downloadImageWithURL:url options:downloaderOptions progress:progressBlock completed:^(UIImage *downloadedImage, NSData *downloadedData, NSError *error, BOOL finished) {
                __strong typeof(weakSubOperation) strongSubOperation = weakSubOperation;
                if (!strongSubOperation || strongSubOperation.isCancelled) {
                    // Do nothing if the operation was cancelled
                    // See #699 for more details
                    // if we would call the completedBlock, there could be a race condition between this block and another completedBlock for the same object, so if this one is called second, we will overwrite the new data
                } else if (error) {
                    [self callCompletionBlockForOperation:strongSubOperation completion:completedBlock error:error url:url];
                    BOOL shouldBlockFailedURL;
                    // Check whether we should block failed url
                    if ([self.delegate respondsToSelector:@selector(imageManager:shouldBlockFailedURL:withError:)]) {
                        shouldBlockFailedURL = [self.delegate imageManager:self shouldBlockFailedURL:url withError:error];
                    } else {
                        shouldBlockFailedURL = (   error.code != NSURLErrorNotConnectedToInternet
                                                && error.code != NSURLErrorCancelled
                                                && error.code != NSURLErrorTimedOut
                                                && error.code != NSURLErrorInternationalRoamingOff
                                                && error.code != NSURLErrorDataNotAllowed
                                                && error.code != NSURLErrorCannotFindHost
                                                && error.code != NSURLErrorCannotConnectToHost
                                                && error.code != NSURLErrorNetworkConnectionLost);
                    }
                    
                    if (shouldBlockFailedURL) {
                        LOCK(self.failedURLsLock);
                        [self.failedURLs addObject:url];
                        UNLOCK(self.failedURLsLock);
                    }
                }
                else {
                    if ((options & SDWebImageRetryFailed)) {
                        LOCK(self.failedURLsLock);
                        [self.failedURLs removeObject:url];
                        UNLOCK(self.failedURLsLock);
                    }
                    
                    BOOL cacheOnDisk = !(options & SDWebImageCacheMemoryOnly);
                    
                    // We've done the scale process in SDWebImageDownloader with the shared manager, this is used for custom manager and avoid extra scale.
                    if (self != [SDWebImageManager sharedManager] && self.cacheKeyFilter && downloadedImage) {
                        downloadedImage = [self scaledImageForKey:key image:downloadedImage];
                    }

                    if (options & SDWebImageRefreshCached && cachedImage && !downloadedImage) {
                        // Image refresh hit the NSURLCache cache, do not call the completion block
                    } else if (downloadedImage && (!downloadedImage.images || (options & SDWebImageTransformAnimatedImage)) && [self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)]) {
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            UIImage *transformedImage = [self.delegate imageManager:self transformDownloadedImage:downloadedImage withURL:url];

                            if (transformedImage && finished) {
                                BOOL imageWasTransformed = ![transformedImage isEqual:downloadedImage];
                                NSData *cacheData;
                                // pass nil if the image was transformed, so we can recalculate the data from the image
                                if (self.cacheSerializer) {
                                    cacheData = self.cacheSerializer(transformedImage, (imageWasTransformed ? nil : downloadedData), url);
                                } else {
                                    cacheData = (imageWasTransformed ? nil : downloadedData);
                                }
                                [self.imageCache storeImage:transformedImage imageData:cacheData forKey:key toDisk:cacheOnDisk completion:nil];
                            }
                            
                            [self callCompletionBlockForOperation:strongSubOperation completion:completedBlock image:transformedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                        });
                    } else {
                        if (downloadedImage && finished) {
                            if (self.cacheSerializer) {
                                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                                    NSData *cacheData = self.cacheSerializer(downloadedImage, downloadedData, url);
                                    [self.imageCache storeImage:downloadedImage imageData:cacheData forKey:key toDisk:cacheOnDisk completion:nil];
                                });
                            } else {
                                [self.imageCache storeImage:downloadedImage imageData:downloadedData forKey:key toDisk:cacheOnDisk completion:nil];
                            }
                        }
                        [self callCompletionBlockForOperation:strongSubOperation completion:completedBlock image:downloadedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                    }
                }

                if (finished) {
                    [self safelyRemoveOperationFromRunning:strongSubOperation];
                }
            }];
        } else if (cachedImage) {
            //不需要下载，且在缓存中找到了图片
            [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
            [self safelyRemoveOperationFromRunning:strongOperation];
        } else {
            // Image not in cache and download disallowed by delegate
            //不需要下载图片，也没在缓存中找到图片
            [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:nil data:nil error:nil cacheType:SDImageCacheTypeNone finished:YES url:url];
            [self safelyRemoveOperationFromRunning:strongOperation];
        }
    }];

    //返回operation（该operation为SDWebImageCombinedOperation类型，保存了查询队列NSOperation）
    return operation;
}

- (void)saveImageToCache:(nullable UIImage *)image forURL:(nullable NSURL *)url {
    if (image && url) {
        NSString *key = [self cacheKeyForURL:url];
        [self.imageCache storeImage:image forKey:key toDisk:YES completion:nil];
    }
}

- (void)cancelAll {
    LOCK(self.runningOperationsLock);
    NSArray<SDWebImageCombinedOperation *> *copiedOperations = [self.runningOperations copy];
    UNLOCK(self.runningOperationsLock);
    [copiedOperations makeObjectsPerformSelector:@selector(cancel)]; // This will call `safelyRemoveOperationFromRunning:` and remove from the array
}

// 当self.runningOperations中有SDWebImageCombinedOperation对象存在就认为isRunning == YES
- (BOOL)isRunning {
    BOOL isRunning = NO;
    LOCK(self.runningOperationsLock);
    isRunning = (self.runningOperations.count > 0);
    UNLOCK(self.runningOperationsLock);
    return isRunning;
}

- (void)safelyRemoveOperationFromRunning:(nullable SDWebImageCombinedOperation*)operation {
    if (!operation) {
        return;
    }
    LOCK(self.runningOperationsLock);
    [self.runningOperations removeObject:operation];
    UNLOCK(self.runningOperationsLock);
}

- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  error:(nullable NSError *)error
                                    url:(nullable NSURL *)url {
    [self callCompletionBlockForOperation:operation completion:completionBlock image:nil data:nil error:error cacheType:SDImageCacheTypeNone finished:YES url:url];
}

- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  image:(nullable UIImage *)image
                                   data:(nullable NSData *)data
                                  error:(nullable NSError *)error
                              cacheType:(SDImageCacheType)cacheType
                               finished:(BOOL)finished
                                    url:(nullable NSURL *)url {
    dispatch_main_async_safe(^{
        if (operation && !operation.isCancelled && completionBlock) {
            completionBlock(image, data, error, cacheType, finished, url);
        }
    });
}

@end


@implementation SDWebImageCombinedOperation

/*
 1、self.cacheOperation执行取消
 2、SDWebImageDownloader执行取消
    I、SDWebImageDownloaderOperation执行取消
        A、callbackBlocks移除token
        B、如果callbackBlocks移除干净了，则执行真正的取消工作
            a、[opeation cancel]
            b、[dataTask cancel]
            c、发送DownloadStop通知
            d、self.executing = NO、self.finished = YES
            e、清空callbackBlocks
            f、置空dataTask
            g、[ownedSession invalidateAndCancel]
            h、置空ownedSession
    II、如果callbackBlocks移除干净了，则self.manager.imageDownloader.URLOperations移除url
 3、self.manager.runningOperations移除opration
 */
- (void)cancel {
    @synchronized(self) {
        self.cancelled = YES;
        if (self.cacheOperation) {
            [self.cacheOperation cancel];
            self.cacheOperation = nil;
        }
        if (self.downloadToken) {
            [self.manager.imageDownloader cancel:self.downloadToken];
        }
        [self.manager safelyRemoveOperationFromRunning:self];
    }
}

@end
