//
//  MetalDrawable.m
//  Live2DIntegration
//
//  Created by admin on 2020/12/18.
//

#import "MetalDrawable.h"

@interface MetalDrawable ()

@end

@implementation MetalDrawable

- (instancetype)init {
    self = [super init];
    if (self) {
        _opacity = 1.0;
        _visibility = YES;
        _blendMode = NormalBlending;
        _masks = @[].mutableCopy;
        _visibility = true;
    }
    return self;
}
@end
