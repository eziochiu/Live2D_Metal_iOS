//
//  MetalDrawable.h
//  Live2DIntegration
//
//  Created by admin on 2020/12/18.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "L2DModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface MetalDrawable : NSObject

/// Index for buffer reference.
@property(nonatomic) int drawableIndex;

/// Number of vertex.
@property(nonatomic) NSInteger vertexCount;

/// Number of draw index.
@property(nonatomic) NSInteger indexCount;

// Textures.
/// Which texture will use for drawable.
@property(nonatomic) NSInteger textureIndex;

// Constant flags.
@property(nonatomic) NSInteger maskCount;

// Constant flags.
/// Culling mode. `True` if culling enable.
@property(nonatomic) BOOL cullingMode;

/// Blend mode.
@property(nonatomic) L2DBlendMode blendMode;

/// Vertex buffers. Create by `MetalRender`.
@property(nonatomic) id <MTLBuffer> vertexPositionBuffer;

/// Vertex UV buffers. Create by `MetalRender`.
@property(nonatomic) id <MTLBuffer> vertexTextureCoordinateBuffer;

/// Draw index buffers. Create by `MetalRender`.
@property(nonatomic, nullable) id <MTLBuffer> vertexIndexBuffer;

/// Masks.
@property (nonatomic, strong) NSArray *masks;

/// Mask texture. Create by `MetalRender`.
@property (nonatomic) id <MTLTexture> maskTexture;

/// Opacity.
@property(nonatomic) float opacity;

/// Opacity buffer. Create by `MetalRender`.
@property (nonatomic) id <MTLBuffer> opacityBuffer;

/// Visibility.
@property(nonatomic) BOOL visibility;
@end

NS_ASSUME_NONNULL_END
