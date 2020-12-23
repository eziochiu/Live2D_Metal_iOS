//
//  L2DRenderer.h
//  Live2DIntegration
//
//  Created by admin on 2020/12/18.
//

#import <Foundation/Foundation.h>
#import "L2DModel.h"
#import "MetalDrawable.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <string.h> 
#include <simd/simd.h>
#include "L2DBufferIndex.h"

#define MTL(r, g, b, a) MTLClearColorMake(r, g, b, a)
#define MakeMTLColor MTL(1.0, 1.0, 1.0, 0.0)

NS_ASSUME_NONNULL_BEGIN

@class MetalRender;

@protocol MetalRenderDelegate <NSObject>
@required

- (void)renderUpdateWithRender:(MetalRender *)renderer durationTime:(NSTimeInterval)duration;

@end

@interface MetalRender : NSObject
@property (nonatomic, weak) id<MetalRenderDelegate> delegate;
@property (nonatomic, strong) L2DModel *model;

/// Model rendering origin, in normalized device coordinate (NDC).
///
/// Default is `(0,0)`.
///
/// Set this property will reset `transform` matrix.
@property (nonatomic, assign) CGPoint origin;

/// Model rendering scale.
///
/// Default is `1.0`.
///
/// Set this property will reset `transform` matrix.
@property (nonatomic, assign) CGFloat scale;

/// Transform matrix of model.
///
/// Note that set `origin` or `scale` will reset transform matrix.
@property (nonatomic, assign) matrix_float4x4 transform;
@end

@interface MetalRender (Renderer)

- (void)startWithView:(MTKView *)view;

- (void)drawableSizeWillChange:(MTKView *)view size:(CGSize)size;

- (void)update:(NSTimeInterval)time;

- (void)beginRenderWithTime:(NSTimeInterval)time viewPort:(MTLViewport)viewPort commandBuffer:(id<MTLCommandBuffer>)commandBuffer passDescriptor:(MTLRenderPassDescriptor *)passDescriptor;

@end



NS_ASSUME_NONNULL_END
