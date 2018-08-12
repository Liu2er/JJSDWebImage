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

//这些方法用来取消 UIView 的图像加载，它们是内部使用的，而不是公开的。所有这些存储型operations是weak的，所以，图像加载完毕后他们呢就会销毁，如果你需要存储这些operations，请使用你自己的类强引用他们
//可以这么理解，UIView有个NSMapTable类型的属性operations，它通过键值的方式来保存opration
@implementation UIView (WebCacheOperation)

//相当于通过Associate为UIView添加了一个NSMapTable类型的属性
- (SDOperationsDictionary *)sd_operationDictionary {
    @synchronized(self) {
        //operations的真实类型是NSMapTable
        SDOperationsDictionary *operations = objc_getAssociatedObject(self, &loadOperationKey);
        if (operations) {
            return operations;
        }
        //operations的key是强引用，value是弱引用
        operations = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory capacity:0];
        //通过loadOperationKey为UIView绑定一个operations（类似于NSDictionary）
        objc_setAssociatedObject(self, &loadOperationKey, operations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return operations;
    }
}

//存储图像加载的operation（该operation通过一个weak的 map table 存储在UIView中）
- (void)sd_setImageLoadOperation:(nullable id<SDWebImageOperation>)operation forKey:(nullable NSString *)key {
    if (key) {
        //先取消
        [self sd_cancelImageLoadOperationWithKey:key];
        if (operation) {
            //获取UIView通过Associate添加的NSMapTable类型的绑定对象operationDictionary
            SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
            @synchronized (self) {
                //将operation通过key添加到UIView的绑定对象operationDictionary里
                [operationDictionary setObject:operation forKey:key];
            }
        }
    }
}

//取消UIView对应key的所有operations
- (void)sd_cancelImageLoadOperationWithKey:(nullable NSString *)key {
    // Cancel in progress downloader from queue
    //相当于通过Associate获得UIView的一个叫sd_operationDictionary的属性，其真实类型是NSMapTable，key是强引用，value是弱引用
    SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
    id<SDWebImageOperation> operation; //operation是一个遵守了SDWebImageOperation协议的对象
    @synchronized (self) {
        //operation是通过key存储在UIView的一个NSMapTable里
        operation = [operationDictionary objectForKey:key];
    }
    if (operation) {
        if ([operation conformsToProtocol:@protocol(SDWebImageOperation)]){
            //先取消
            [operation cancel];
        }
        @synchronized (self) {
            //再移除
            [operationDictionary removeObjectForKey:key];
        }
    }
}

//根据当前的UIVIew和key移除operations，而不取消
- (void)sd_removeImageLoadOperationWithKey:(nullable NSString *)key {
    if (key) {
        SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
        @synchronized (self) {
            [operationDictionary removeObjectForKey:key];
        }
    }
}

@end
