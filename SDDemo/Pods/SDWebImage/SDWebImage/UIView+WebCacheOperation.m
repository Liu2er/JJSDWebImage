/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIView+WebCacheOperation.h"
#import "objc/runtime.h"

static char loadOperationKey;

// key is copy, value is weak because operation instance is retained by SDWebImageManager's runningOperations property
// we should use lock to keep thread-safe because these method may not be acessed from main queue
typedef NSMapTable<NSString *, id<SDWebImageOperation>> SDOperationsDictionary;

//这些方法用来取消 UIView 的图像加载，它们是内部使用的，而不是公开的。所有这些存储型operations是weak的，所以，图像加载完毕后他们就会销毁，如果你需要存储这些operations，请使用你自己的类强引用他们
//可以这么理解，UIView有个NSMapTable类型的属性operations，它通过键值的方式来保存opration
@implementation UIView (WebCacheOperation)

//相当于通过Associate为UIView添加了一个NSMapTable类型的属性operationDictionary
//通过&loadOperationKey这个key来获得该operationDictionary
//该operationDictionary里的key是@"UIImageView"、@"UIButton"、@"NSButton"、@"UIView"等，value是遵守了SDWebImageOperation协议的id类型的operation
- (SDOperationsDictionary *)sd_operationDictionary {
    @synchronized(self) {
        //operations的真实类型是NSMapTable（相当于NSDictionary）
        SDOperationsDictionary *operationDictionary = objc_getAssociatedObject(self, &loadOperationKey);
        if (operationDictionary) {
            return operationDictionary;
        }
        //operations的key是强引用，value是弱引用
        operationDictionary = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory capacity:0];
        //通过loadOperationKey为UIView绑定一个operations（类似于NSDictionary）
        objc_setAssociatedObject(self, &loadOperationKey, operationDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return operationDictionary;
    }
}

//以键值对的方式将operation存储到UIView的Associated属性里
- (void)sd_setImageLoadOperation:(nullable id<SDWebImageOperation>)operation forKey:(nullable NSString *)key {
    if (key) {
        //添加前先移除
        [self sd_cancelImageLoadOperationWithKey:key];
        if (operation) {
            SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
            @synchronized (self) {
                [operationDictionary setObject:operation forKey:key];
            }
        }
    }
}

// 移除UIView的operationDictionary里key对应的value（遵守了SDWebImageOperation协议的id类型的operation），移除前先对operation做cancel处理
- (void)sd_cancelImageLoadOperationWithKey:(nullable NSString *)key {
    // Cancel in progress downloader from queue
    SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
    id<SDWebImageOperation> operation;
    @synchronized (self) {
        operation = [operationDictionary objectForKey:key];
    }
    if (operation) {
        if ([operation conformsToProtocol:@protocol(SDWebImageOperation)]){
            [operation cancel];
        }
        @synchronized (self) {
            [operationDictionary removeObjectForKey:key];
        }
    }
}

//仅仅移除UIView的operationDictionary里key对应的value，不对其中的operation做cancel处理
- (void)sd_removeImageLoadOperationWithKey:(nullable NSString *)key {
    if (key) {
        SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
        @synchronized (self) {
            [operationDictionary removeObjectForKey:key];
        }
    }
}

@end
