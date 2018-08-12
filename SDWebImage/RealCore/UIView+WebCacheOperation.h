/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"
#import "SDWebImageOperation.h"

// These methods are used to support canceling for UIView image loading, it's designed to be used internal but not external.
// All the stored operations are weak, so it will be dalloced after image loading finished. If you need to store operations, use your own class to keep a strong reference for them.
//这些方法用来取消 UIView 的图像加载，它们是内部使用的，而不是公开的。所有这些存储型operations是weak的，所以，图像加载完毕后他们呢就会销毁，如果你需要存储这些operations，请使用你自己的类强引用他们
@interface UIView (WebCacheOperation)

/**
 *  Set the image load operation (storage in a UIView based weak map table)
 *
 *  @param operation the operation
 *  @param key       key for storing the operation
 */
//存储图像加载的operation（该operation通过一个weak的 map table 存储在UIView中）
- (void)sd_setImageLoadOperation:(nullable id<SDWebImageOperation>)operation forKey:(nullable NSString *)key;

/**
 *  Cancel all operations for the current UIView and key
 *
 *  @param key key for identifying the operations
 */
//取消UIView对应key的所有operations
- (void)sd_cancelImageLoadOperationWithKey:(nullable NSString *)key;

/**
 *  Just remove the operations corresponding to the current UIView and key without cancelling them
 *
 *  @param key key for identifying the operations
 */
//根据当前的UIVIew和key移除operations，而不取消
- (void)sd_removeImageLoadOperationWithKey:(nullable NSString *)key;

@end
