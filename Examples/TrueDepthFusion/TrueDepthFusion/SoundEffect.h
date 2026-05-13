//
//  SoundEffect.h


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SoundEffect : NSObject

- (instancetype)initWithSoundNamed:(NSString *)name type:(NSString *)type NS_SWIFT_NAME(init(named:type:));

- (void)play;

@end

NS_ASSUME_NONNULL_END
