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

NS_ASSUME_NONNULL_BEGIN

@class MetalRender;

@protocol MetalRendererDelegate <NSObject>
@required

- (void)rendererUpdateWithRender:(MetalRender *)renderer durationTime:(NSTimeInterval)duration;

@end

@interface MetalRender : NSObject
@property (nonatomic ,weak) id<MetalRendererDelegate> delegate;
@property (nonatomic) L2DModel *model;
@property (nonatomic) CGPoint origin;
@property (nonatomic) CGFloat scale;
@property (nonatomic) matrix_float4x4 transform;

- (void)startWithView:(MTKView *)view;

- (void)drawableSizeWillChange:(MTKView *)view size:(CGSize)size;

- (void)update:(NSTimeInterval)time;

- (void)beginRenderWithTime:(NSTimeInterval)time viewPort:(MTLViewport)viewPort commandBuffer:(id<MTLCommandBuffer>)commandBuffer passDescriptor:(MTLRenderPassDescriptor *)passDescriptor;

@end



NS_ASSUME_NONNULL_END
