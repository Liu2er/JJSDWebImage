/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"
#import "SDWebImageOperation.h"
#import "SDWebImageDownloader.h"
#import "SDImageCache.h"

typedef NS_OPTIONS(NSUInteger, SDWebImageOptions) {
    /**
     * By default, when a URL fail to be downloaded, the URL is blacklisted so the library won't keep trying.
     * This flag disable this blacklisting.
     */
    // 每一个下载都会提供一个URL，如果这个URL是错误，SD就会把它放入到黑名单之中
    // 黑名单中的URL是不会再次进行下载的,但是，当设置了该选项时，SD会将其在黑名单中移除，重新下载该URL
    SDWebImageRetryFailed = 1 << 0,

    /**
     * By default, image downloads are started during UI interactions, this flags disable this feature,
     * leading to delayed download on UIScrollView deceleration for instance.
     */
    // 一般来说，下载都是按照一定的先后顺序开始的，但是该选项能够延迟下载，也就说他的权限比较低，权限比他高的在他前边下载
    // 默认情况下，图片在交互发生的时候会下载(例如你滑动tableview的时候)，这个flag会禁止这个特性，导致的结果就是在scrollview减速的时候，才会开始下载(也就是你滑动的时候scrollview不下载，你手从屏幕上移走，scrollview开始减速的时候才会开始下载图片）
    SDWebImageLowPriority = 1 << 1,

    /**
     * This flag disables on-disk caching after the download finished, only cache in memory
     */
    // 该选项要求SD下载结束后只把图片缓存到内存中，不缓存到disk中
    SDWebImageCacheMemoryOnly = 1 << 2,

    /**
     * This flag enables progressive download, the image is displayed progressively during download as a browser would do.
     * By default, the image is only displayed once completely downloaded.
     */
    // 默认情况下图片是完全下载完了才立刻展示，这个flag允许图片边下载边展示，一截一截的显示
    SDWebImageProgressiveDownload = 1 << 3,

    /**
     * Even if the image is cached, respect the HTTP response cache control, and refresh the image from remote location if needed.
     * The disk caching will be handled by NSURLCache instead of SDWebImage leading to slight performance degradation.
     * This option helps deal with images changing behind the same request URL, e.g. Facebook graph api profile pics.
     * If a cached image is refreshed, the completion block is called once with the cached image and again with the final image.
     *
     * Use this flag only if you can't make your URLs static with embedded cache busting parameter.
     */
    // 图片即使已经缓存了，还是会根据url进行重新请求，并且缓存策略依据NSURLCache而不是SDWebImage
    // 有时一个图片的资源发生了改变，但是url并没有变，我们就可以使用该选项来刷新数据了
    SDWebImageRefreshCached = 1 << 4,

    /**
     * In iOS 4+, continue the download of the image if the app goes to background. This is achieved by asking the system for
     * extra time in background to let the request finish. If the background task expires the operation will be cancelled.
     */
    // 支持切换到后台也能下载，如果后台下载任务超时，则下载任务会被取消
    SDWebImageContinueInBackground = 1 << 5,

    /**
     * Handles cookies stored in NSHTTPCookieStore by setting
     * NSMutableURLRequest.HTTPShouldHandleCookies = YES;
     */
    SDWebImageHandleCookies = 1 << 6,

    /**
     * Enable to allow untrusted SSL certificates.
     * Useful for testing purposes. Use with caution in production.
     */
    // 允许使用不信任的SSL证书，主要用于测试，正式环境中慎用
    SDWebImageAllowInvalidSSLCertificates = 1 << 7,

    /**
     * By default, images are loaded in the order in which they were queued. This flag moves them to
     * the front of the queue.
     */
    // 默认情况下，图片的下载顺序跟加入队列的顺序一致（先进先出），本falg允许优先下载
    SDWebImageHighPriority = 1 << 8,
    
    /**
     * By default, placeholder images are loaded while the image is loading. This flag will delay the loading
     * of the placeholder image until after the image has finished loading.
     */
    // 默认情况下，占位图会在图片加载期间展示，这个flag开启会延迟占位图显示的时间，等到图片加载完成之后才会显示占位图.
    SDWebImageDelayPlaceholder = 1 << 9,

    /**
     * We usually don't call transformDownloadedImage delegate method on animated images,
     * as most transformation code would mangle it.
     * Use this flag to transform them anyway.
     */
    // 通常我们不调用动图的transformDownloadedImage delegate，因为大多数的变形操作会将图片撕裂，本flag强制变形操作
    SDWebImageTransformAnimatedImage = 1 << 10,
    
    /**
     * By default, image is added to the imageView after download. But in some cases, we want to
     * have the hand before setting the image (apply a filter or add it with cross-fade animation for instance)
     * Use this flag if you want to manually set the image in the completion when success
     */
    // 该选项允许我们在图片下载完成后不会立刻给imageView设置图片，比较常用的使用场景是给赋值的图片添加动画
    SDWebImageAvoidAutoSetImage = 1 << 11,
    
    /**
     * By default, images are decoded respecting their original size. On iOS, this flag will scale down the
     * images to a size compatible with the constrained memory of devices.
     * If `SDWebImageProgressiveDownload` flag is set the scale down is deactivated.
     */
    // 默认情况下，图片根据原始大小进行解压缩，这个flag允许根据设备的内存大小来将图片缩小到合适的大小
    // 如果设置了SDWebImageProgressiveDownload，则本flag不生效
    SDWebImageScaleDownLargeImages = 1 << 12,
    
    /**
     * By default, we do not query disk data when the image is cached in memory. This mask can force to query disk data at the same time.
     * This flag is recommend to be used with `SDWebImageQueryDiskSync` to ensure the image is loaded in the same runloop.
     */
    // 默认情况下，当内存中缓存了图片时就不再去磁盘中查找，这个flag强制同步地去磁盘中查找
    // 推荐和SDWebImageQueryDiskSync一起使用，来保证图片被加载到同一个runloop
    SDWebImageQueryDataWhenInMemory = 1 << 13,
    
    /**
     * By default, we query the memory cache synchronously, disk cache asynchronously. This mask can force to query disk cache synchronously to ensure that image is loaded in the same runloop.
     * This flag can avoid flashing during cell reuse if you disable memory cache or in some other cases.
     */
    // 默认情况下，查找内存缓存是同步的，查找磁盘缓存是异步的，这个flag强制同步地去查询磁盘缓存，来保证图片被加载到同一个runloop
    // 本flat可以避免禁用了内存缓存或其它情况下cell复用时闪烁
    SDWebImageQueryDiskSync = 1 << 14,
    
    /**
     * By default, when the cache missed, the image is download from the network. This flag can prevent network to load from cache only.
     */
    // 通常丢失缓存后会从心从网络下载图片，这个flag可以禁止网络只从缓存加载
    SDWebImageFromCacheOnly = 1 << 15,
    /**
     * By default, when you use `SDWebImageTransition` to do some view transition after the image load finished, this transition is only applied for image download from the network. This mask can force to apply view transition for memory and disk cache as well.
     */
    // 默认情况下，当图片加载完毕后使用SDWebImageTransition做转场时，只有当图片是从网络下载的转场才会生效，这个flag强制图片从内存和磁盘缓存中加载时转场也生效
    SDWebImageForceTransition = 1 << 16
};

typedef void(^SDExternalCompletionBlock)(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL);

typedef void(^SDInternalCompletionBlock)(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL);

typedef NSString * _Nullable(^SDWebImageCacheKeyFilterBlock)(NSURL * _Nullable url);

typedef NSData * _Nullable(^SDWebImageCacheSerializerBlock)(UIImage * _Nonnull image, NSData * _Nullable data, NSURL * _Nullable imageURL);


@class SDWebImageManager;

@protocol SDWebImageManagerDelegate <NSObject>

@optional

/**
 * Controls which image should be downloaded when the image is not found in the cache.
 *
 * @param imageManager The current `SDWebImageManager`
 * @param imageURL     The url of the image to be downloaded
 *
 * @return Return NO to prevent the downloading of the image on cache misses. If not implemented, YES is implied.
 */
// 当缓存中没找到图片时，本方法用来控制要不要下载图片，返回NO时不下载
- (BOOL)imageManager:(nonnull SDWebImageManager *)imageManager shouldDownloadImageForURL:(nullable NSURL *)imageURL;

/**
 * Controls the complicated logic to mark as failed URLs when download error occur.
 * If the delegate implement this method, we will not use the built-in way to mark URL as failed based on error code;
 @param imageManager The current `SDWebImageManager`
 @param imageURL The url of the image
 @param error The download error for the url
 @return Whether to block this url or not. Return YES to mark this URL as failed.
 */
// 当发生下载错误时，本方法用来控制是否把URL加入错误URL列表
- (BOOL)imageManager:(nonnull SDWebImageManager *)imageManager shouldBlockFailedURL:(nonnull NSURL *)imageURL withError:(nonnull NSError *)error;

/**
 * Allows to transform the image immediately after it has been downloaded and just before to cache it on disk and memory.
 * NOTE: This method is called from a global queue in order to not to block the main thread.
 *
 * @param imageManager The current `SDWebImageManager`
 * @param image        The image to transform
 * @param imageURL     The url of the image to transform
 *
 * @return The transformed image object.
 */
// 本方法允许图片下载结束后还没来得及缓存时就立刻transform，为了防止阻塞主线程本方法要在全局队列中使用
- (nullable UIImage *)imageManager:(nonnull SDWebImageManager *)imageManager transformDownloadedImage:(nullable UIImage *)image withURL:(nullable NSURL *)imageURL;

@end

/**
 * The SDWebImageManager is the class behind the UIImageView+WebCache category and likes.
 * It ties the asynchronous downloader (SDWebImageDownloader) with the image cache store (SDImageCache).
 * You can use this class directly to benefit from web image downloading with caching in another context than
 * a UIView.
 *
 * Here is a simple example of how to use SDWebImageManager:
 *
 * @code

SDWebImageManager *manager = [SDWebImageManager sharedManager];
[manager loadImageWithURL:imageURL
                  options:0
                 progress:nil
                completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                    if (image) {
                        // do something with image
                    }
                }];

 * @endcode
 */
@interface SDWebImageManager : NSObject

@property (weak, nonatomic, nullable) id <SDWebImageManagerDelegate> delegate;

@property (strong, nonatomic, readonly, nullable) SDImageCache *imageCache;
@property (strong, nonatomic, readonly, nullable) SDWebImageDownloader *imageDownloader;

/**
 * The cache filter is a block used each time SDWebImageManager need to convert an URL into a cache key. This can
 * be used to remove dynamic part of an image URL.
 *
 * The following example sets a filter in the application delegate that will remove any query-string from the
 * URL before to use it as a cache key:
 *
 * @code

SDWebImageManager.sharedManager.cacheKeyFilter = ^(NSURL * _Nullable url) {
    url = [[NSURL alloc] initWithScheme:url.scheme host:url.host path:url.path];
    return [url absoluteString];
};

 * @endcode
 */
// 这是一个block，用来将url转为缓存的key，可以在block里面移除url的动态部分
@property (nonatomic, copy, nullable) SDWebImageCacheKeyFilterBlock cacheKeyFilter;

/**
 * The cache serializer is a block used to convert the decoded image, the source downloaded data, to the actual data used for storing to the disk cache. If you return nil, means to generate the data from the image instance, see `SDImageCache`.
 * For example, if you are using WebP images and facing the slow decoding time issue when later retriving from disk cache again. You can try to encode the decoded image to JPEG/PNG format to disk cache instead of source downloaded data.
 * @note The `image` arg is nonnull, but when you also provide a image transformer and the image is transformed, the `data` arg may be nil, take attention to this case.
 * @note This method is called from a global queue in order to not to block the main thread.
 * @code
 SDWebImageManager.sharedManager.cacheSerializer = ^NSData * _Nullable(UIImage * _Nonnull image, NSData * _Nullable data, NSURL * _Nullable imageURL) {
    SDImageFormat format = [NSData sd_imageFormatForImageData:data];
    switch (format) {
        case SDImageFormatWebP:
            return image.images ? data : nil;
        default:
            return data;
    }
 };
 * @endcode
 * The default value is nil. Means we just store the source downloaded data to disk cache.
 */
// 这是一个block，用来将解码后的图片（下载的源数据），转换为用来存储到磁盘的数据
// 例如，如果使用的图片是WebP格式，且面临着再次从磁盘中缓存中检索后解码慢的问题，您可以尝试将解码后的图像编码为JPEG/PNG格式，而不是源下载数据
@property (nonatomic, copy, nullable) SDWebImageCacheSerializerBlock cacheSerializer;

/**
 * Returns global SDWebImageManager instance.
 *
 * @return SDWebImageManager shared instance
 */
+ (nonnull instancetype)sharedManager;

/**
 * Allows to specify instance of cache and image downloader used with image manager.
 * @return new instance of `SDWebImageManager` with specified cache and downloader.
 */
- (nonnull instancetype)initWithCache:(nonnull SDImageCache *)cache downloader:(nonnull SDWebImageDownloader *)downloader NS_DESIGNATED_INITIALIZER;

/**
 * Downloads the image at the given URL if not present in cache or return the cached version otherwise.
 *
 * @param url            The URL to the image
 * @param options        A mask to specify options to use for this request
 * @param progressBlock  A block called while image is downloading
 *                       @note the progress block is executed on a background queue
 * @param completedBlock A block called when operation has been completed.
 *
 *   This parameter is required.
 * 
 *   This block has no return value and takes the requested UIImage as first parameter and the NSData representation as second parameter.
 *   In case of error the image parameter is nil and the third parameter may contain an NSError.
 *
 *   The forth parameter is an `SDImageCacheType` enum indicating if the image was retrieved from the local cache
 *   or from the memory cache or from the network.
 *
 *   The fith parameter is set to NO when the SDWebImageProgressiveDownload option is used and the image is
 *   downloading. This block is thus called repeatedly with a partial image. When image is fully downloaded, the
 *   block is called a last time with the full image and the last parameter set to YES.
 *
 *   The last parameter is the original image URL
 *
 * @return Returns an NSObject conforming to SDWebImageOperation. Should be an instance of SDWebImageDownloaderOperation
 */
- (nullable id <SDWebImageOperation>)loadImageWithURL:(nullable NSURL *)url
                                              options:(SDWebImageOptions)options
                                             progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                            completed:(nullable SDInternalCompletionBlock)completedBlock;

/**
 * Saves image to cache for given URL
 *
 * @param image The image to cache
 * @param url   The URL to the image
 *
 */

- (void)saveImageToCache:(nullable UIImage *)image forURL:(nullable NSURL *)url;

/**
 * Cancel all current operations
 */
- (void)cancelAll;

/**
 * Check one or more operations running
 */
- (BOOL)isRunning;

/**
 *  Async check if image has already been cached
 *
 *  @param url              image url
 *  @param completionBlock  the block to be executed when the check is finished
 *  
 *  @note the completion block is always executed on the main queue
 */
- (void)cachedImageExistsForURL:(nullable NSURL *)url
                     completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock;

/**
 *  Async check if image has already been cached on disk only
 *
 *  @param url              image url
 *  @param completionBlock  the block to be executed when the check is finished
 *
 *  @note the completion block is always executed on the main queue
 */
- (void)diskImageExistsForURL:(nullable NSURL *)url
                   completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock;


/**
 *Return the cache key for a given URL
 */
- (nullable NSString *)cacheKeyForURL:(nullable NSURL *)url;

@end
