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
        _drawableIndex = 0;
        _vertexCount = 0;
        _indexCount = 0;
        _textureIndex = 0;
        _maskCount = 0;
        _cullingMode = false;
        _blendMode = NormalBlending;
        _opacity = 1.0;
        _visibility = true;
        _masks = [NSMutableArray array];
    }
    return self;
}
@end
