//
//  L2DRenderer.m
//  Live2DIntegration
//
//  Created by admin on 2020/12/18.
//

#import "MetalRender.h"

@interface MetalRender ()
@property (nonatomic, nullable, strong) MTKView *view;
/// Render pipelines.
@property (nonatomic, nonnull, strong) id<MTLRenderPipelineState> pipelineStateBlendingAdditive;
@property (nonatomic, nonnull, strong) id<MTLRenderPipelineState> pipelineStateBlendingMultiplicative;
@property (nonatomic, nonnull, strong) id<MTLRenderPipelineState> pipelineStateBlendingNormal;
@property (nonatomic, nonnull, strong) id<MTLRenderPipelineState> pipelineStateMasking;
/// Live2D drawable parts.
@property (nonatomic, nonnull, strong) NSMutableArray<MetalDrawable *> *drawables;
@property (nonatomic, nonnull, copy) NSArray<MetalDrawable *> *drawableSorted;
/// Buffers.
@property (nonatomic, nonnull, strong) id<MTLBuffer> transformBuffer;
/// Textures.
@property (nonatomic, nonnull, strong) NSMutableArray<id<MTLTexture>> *textures;
@end

@implementation MetalRender

- (instancetype)init {
    self = [super init];
    if (self) {
        _origin = CGPointZero;
        _scale = 1.0;
        _transform = matrix_identity_float4x4;
        _drawables = [NSMutableArray array];
        _drawableSorted = [NSMutableArray array];
        _textures = [NSMutableArray array];
    }
    return self;
}

- (void)createBuffersWithView:(MTKView *)view {
    id<MTLDevice> device = view.device;
    if (!device) {
        return;
    }
    L2DModel *model = self.model;
    if (!model) {
        return;
    }

    matrix_float4x4 transform = self.transform;
    self.transformBuffer = [device newBufferWithBytes:&(transform) length:sizeof(matrix_float4x4) options:MTLResourceCPUCacheModeDefaultCache];

    int drawableCount = model.drawableCount;

    for (int i = 0; i < drawableCount; i++) {
        @autoreleasepool {
            MetalDrawable *drawable = [[MetalDrawable alloc] init];
            drawable.drawableIndex = i;

            RawFloatArray *vertexPositions = [model vertexPositionsForDrawable:i];
            if (vertexPositions) {
                drawable.vertexCount = vertexPositions.count;
                if (drawable.vertexCount > 0) {
                    drawable.vertexPositionBuffer = [device newBufferWithBytes:vertexPositions.floats length:(2 * vertexPositions.count * sizeof(float)) options:MTLResourceCPUCacheModeDefaultCache];
                }
            }

            RawFloatArray *vertexTextureCoords = [model vertexTextureCoordinateForDrawable:i];
            if (vertexTextureCoords) {
                if (drawable.vertexCount > 0) {
                    drawable.vertexTextureCoordinateBuffer = [device newBufferWithBytes:vertexTextureCoords.floats length:(2 * vertexTextureCoords.count * sizeof(float)) options:MTLResourceCPUCacheModeDefaultCache];
                }
            }

            RawUShortArray *vertexIndices = [model vertexIndicesForDrawable:i];
            if (vertexIndices) {
                drawable.indexCount = vertexIndices.count;
                if (drawable.indexCount > 0) {
                    drawable.vertexIndexBuffer = [device newBufferWithBytes:vertexIndices.ushorts length:(vertexIndices.count * sizeof(ushort)) options:MTLResourceCPUCacheModeDefaultCache];
                }
            }

            // Textures.
            drawable.textureIndex = [model textureIndexForDrawable:i];

            // Mask.
            RawIntArray *masks = [model masksForDrawable:i];
            if (masks) {
                drawable.maskCount = masks.count;
                drawable.masks = [masks intArray];
            }

            // Render mode.
            drawable.blendMode = [model blendingModeForDrawable:i];
            drawable.cullingMode = [model cullingModeForDrawable:i];

            // Opacity.
            drawable.opacity = [model opacityForDrawable:i];

            float *list = [self convertFloat2FloatArray:drawable.opacity];
            drawable.opacityBuffer = [device newBufferWithBytes:list length:sizeof(float) options:MTLResourceCPUCacheModeDefaultCache];
            free(list);

            drawable.visibility = [model visibilityForDrawable:i];

            [self.drawables addObject:drawable];
        }
    }
    // Sort drawables.
    NSArray<NSNumber *> *renderOrders = model.renderOrders.intArray;
    self.drawableSorted = [self.drawables sortedArrayUsingComparator:^NSComparisonResult(MetalDrawable *obj1, MetalDrawable *obj2) {
        return renderOrders[obj1.drawableIndex].intValue > renderOrders[obj2.drawableIndex].intValue;
    }];
}

- (float *)convertFloat2FloatArray:(float)f {
    float *list = (float *)malloc(sizeof(float));
    list[0] = f;
    return list;
}

- (void)createTexturesWithView:(MTKView *)view {
    id<MTLDevice> device = view.device;
    if (!device) {
        return;
    }
    L2DModel *model = self.model;
    if (!model) {
        return;
    }

    CGSize size = view.drawableSize;
    if (model.textureURLs) {
        MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:device];
        for (NSURL *url in model.textureURLs) {
            @autoreleasepool {
                id<MTLTexture> texture = [loader newTextureWithContentsOfURL:url
                                                                     options:@{MTKTextureLoaderOptionTextureStorageMode: @(MTLStorageModePrivate),
                                                                               MTKTextureLoaderOptionTextureUsage: @(MTLTextureUsageShaderRead),
                                                                               MTKTextureLoaderOptionSRGB: @(false)}
                                                                       error:nil];
                [self.textures addObject:texture];
            }
        }
    }

    for (MetalDrawable *drawable in self.drawables) {
        @autoreleasepool {
            if (drawable.maskCount > 0) {
                MTLTextureDescriptor *desc = [[MTLTextureDescriptor alloc] init];
                desc.pixelFormat = MTLPixelFormatBGRA8Unorm;
                desc.storageMode = MTLStorageModePrivate;
                desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                desc.width = (int)size.width;
                desc.height = (int)size.height;
                drawable.maskTexture = [device newTextureWithDescriptor:desc];
            }
        }
    }
}

- (void)createPipelineStatesWithView:(MTKView *)view {
    id<MTLDevice> device = view.device;
    if (!device) {
        return;
    }

    NSError *error;

    // Library for shaders.
    id<MTLLibrary> library = [device newDefaultLibraryWithBundle:[NSBundle mainBundle] error:&error];

    if (!library || error) {
        return;
    }

    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = [library newFunctionWithName:@"basic_vertex"];
    pipelineDesc.fragmentFunction = [library newFunctionWithName:@"basic_fragment"];

    // Vertex descriptor.
    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];

    // Vertex attributes.
    vertexDesc.attributes[L2DAttributeIndexPosition].bufferIndex = L2DBufferIndexPosition;
    vertexDesc.attributes[L2DAttributeIndexPosition].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[L2DAttributeIndexPosition].offset = 0;

    vertexDesc.attributes[L2DAttributeIndexUV].bufferIndex = L2DBufferIndexUV;
    vertexDesc.attributes[L2DAttributeIndexUV].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[L2DAttributeIndexUV].offset = 0;

    vertexDesc.attributes[L2DAttributeIndexOpacity].bufferIndex = L2DBufferIndexOpacity;
    vertexDesc.attributes[L2DAttributeIndexOpacity].format = MTLVertexFormatFloat;
    vertexDesc.attributes[L2DAttributeIndexOpacity].offset = 0;

    // Buffer layouts.
    vertexDesc.layouts[L2DBufferIndexPosition].stride = sizeof(float) * 2;

    vertexDesc.layouts[L2DBufferIndexUV].stride = sizeof(float) * 2;

    vertexDesc.layouts[L2DBufferIndexOpacity].stride = sizeof(float);
    vertexDesc.layouts[L2DBufferIndexOpacity].stepFunction = MTLVertexStepFunctionConstant;
    vertexDesc.layouts[L2DBufferIndexOpacity].stepRate = 0;

    pipelineDesc.vertexDescriptor = vertexDesc;

    // Color attachments.
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    // Blending.
    pipelineDesc.colorAttachments[0].blendingEnabled = true;

    pipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    pipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    self.pipelineStateBlendingNormal = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];

    // Additive Blending.
    pipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;

    pipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;

    self.pipelineStateBlendingAdditive = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];

    // Multiplicative Blending.
    pipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorDestinationColor;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    pipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorZero;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;

    self.pipelineStateBlendingMultiplicative = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];

    // Masking.
    pipelineDesc.vertexFunction = [library newFunctionWithName:@"basic_vertex"];
    pipelineDesc.fragmentFunction = [library newFunctionWithName:@"mask_fragment"];

    pipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    self.pipelineStateMasking = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
}

/// Update drawables with dynamics flag.
- (void)updateDrawables {
    L2DModel *model = self.model;
    if (!model) {
        return;
    }
    BOOL needSorting = false;
    for (MetalDrawable *drawable in self.drawables) {
        @autoreleasepool {
            int index = drawable.drawableIndex;
            if ([model isOpacityDidChangedForDrawable:index]) {
                drawable.opacity = [model opacityForDrawable:index];
                if (drawable.opacityBuffer.contents) {
                    float *list = [self convertFloat2FloatArray:drawable.opacity];
                    memcpy(drawable.opacityBuffer.contents, list, sizeof(float));
                    free(list);
                }
            }

            if ([model visibilityForDrawable:index]) {
                drawable.visibility = [model visibilityForDrawable:index];
            }

            if ([model isRenderOrderDidChangedForDrawable:index]) {
                needSorting = true;
            }

            if ([model isVertexPositionDidChangedForDrawable:index]) {
                RawFloatArray *vertexPositions = [model vertexPositionsForDrawable:index];
                if (vertexPositions) {
                    if (drawable.vertexPositionBuffer.contents) {
                        memcpy(drawable.vertexPositionBuffer.contents, vertexPositions.floats, 2 * drawable.vertexCount * sizeof(float));
                    }
                }
            }

        }
    }
    if (needSorting) {
        NSArray<NSNumber *> *renderOrders = model.renderOrders.intArray;
        self.drawableSorted = [self.drawables sortedArrayUsingComparator:^NSComparisonResult(MetalDrawable *obj1, MetalDrawable *obj2) {
            return renderOrders[obj1.drawableIndex].intValue > renderOrders[obj2.drawableIndex].intValue;
        }];
    }
}

- (void)renderMasksWithViewPort:(MTLViewport)viewPort commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    MTLRenderPassDescriptor *passDesc = [[MTLRenderPassDescriptor alloc] init];
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0); // 设置默认颜色
    for (MetalDrawable *drawable in self.drawables) {
        @autoreleasepool {
            if (drawable.maskCount > 0) {
                passDesc.colorAttachments[0].texture = drawable.maskTexture;
                id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];

                if (!encoder) {
                    return;
                }

                [encoder setRenderPipelineState:self.pipelineStateBlendingNormal];
                [encoder setViewport:viewPort];

                for (NSNumber *index in drawable.masks) {
                    MetalDrawable *mask = self.drawables[index.intValue];
                    // Bind vertex buffers.
                    [encoder setVertexBuffer:self.transformBuffer
                                      offset:0
                                     atIndex:L2DBufferIndexTransform];
                    [encoder setVertexBuffer:mask.vertexPositionBuffer
                                      offset:0
                                     atIndex:L2DBufferIndexPosition];
                    [encoder setVertexBuffer:mask.vertexTextureCoordinateBuffer
                                      offset:0
                                     atIndex:L2DBufferIndexUV];
                    [encoder setVertexBuffer:mask.opacityBuffer
                                      offset:0
                                     atIndex:L2DBufferIndexOpacity];

                    // Bind uniform texture.
                    [encoder setFragmentTexture:self.textures[mask.textureIndex]
                                        atIndex:L2DTextureIndexUniform];
                    if (mask.vertexIndexBuffer) {
                        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                            indexCount:mask.indexCount
                                             indexType:MTLIndexTypeUInt16
                                           indexBuffer:mask.vertexIndexBuffer
                                     indexBufferOffset:0];
                    }
                }
                [encoder endEncoding];
            }
        }
    }
}

- (void)renderDrawablesWithViewPort:(MTLViewport)viewPort commandBuffer:(id<MTLCommandBuffer>)commandBuffer passDescriptor:(MTLRenderPassDescriptor *)passDescriptor {
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    if (!encoder) {
        return;
    }
    [encoder setViewport:viewPort];
    [encoder setVertexBuffer:self.transformBuffer
                      offset:0
                     atIndex:L2DBufferIndexTransform];
    for (MetalDrawable *drawable in self.drawableSorted) {
        @autoreleasepool {
            // Bind vertex buffer.
            [encoder setVertexBuffer:drawable.vertexPositionBuffer
                              offset:0
                             atIndex:L2DBufferIndexPosition];
            [encoder setVertexBuffer:drawable.vertexTextureCoordinateBuffer
                              offset:0
                             atIndex:L2DBufferIndexUV];
            [encoder setVertexBuffer:drawable.opacityBuffer
                              offset:0
                             atIndex:L2DBufferIndexOpacity];

            if (drawable.cullingMode) {
                [encoder setCullMode:MTLCullModeBack];
            } else {
                [encoder setCullMode:MTLCullModeNone];
            }

            if (drawable.maskCount > 0) {
                // Bind mask.
                [encoder setRenderPipelineState:self.pipelineStateMasking];
                [encoder setFragmentTexture:drawable.maskTexture atIndex:L2DTextureIndexMask];
            } else {
                switch (drawable.blendMode) {
                    case AdditiveBlending:
                        [encoder setRenderPipelineState:self.pipelineStateBlendingAdditive];
                        break;
                    case MultiplicativeBlending:
                        [encoder setRenderPipelineState:self.pipelineStateBlendingMultiplicative];
                        break;
                    case NormalBlending:
                        [encoder setRenderPipelineState:self.pipelineStateBlendingNormal];
                        break;
                    default:
                        [encoder setRenderPipelineState:self.pipelineStateBlendingNormal];
                        break;
                }
            }

            if (drawable.visibility) {
                // Bind uniform texture.
                [encoder setFragmentTexture:self.textures[drawable.textureIndex] atIndex:L2DTextureIndexUniform];
                if (drawable.vertexIndexBuffer) {
                    [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                        indexCount:drawable.indexCount
                                         indexType:MTLIndexTypeUInt16
                                       indexBuffer:drawable.vertexIndexBuffer
                                 indexBufferOffset:0];
                }
            }
        }
    }
    [encoder endEncoding];
}

- (void)setModel:(L2DModel *)model {
    _model = model;

    if (self.view && model) {
        [self createBuffersWithView:self.view];
        [self createTexturesWithView:self.view];
    }
}

- (void)setScale:(CGFloat)scale {
    _scale = scale;

    simd_float4x4 translationMatrix = {
        simd_make_float4(self.scale, 0.0, 0.0, self.origin.x),
        simd_make_float4(0.0, self.scale, 0.0, self.origin.y),
        simd_make_float4(0.0, 0.0, 1.0, 0.0),
        simd_make_float4(self.origin.x, self.origin.y, 0.0, 1.0)};
    self.transform = translationMatrix;
}

- (void)setOrigin:(CGPoint)origin {
    _origin = origin;

    simd_float4x4 translationMatrix = simd_matrix_from_rows(
        simd_make_float4(self.scale, 0.0, 0.0, self.origin.x),
        simd_make_float4(0.0, self.scale, 0.0, self.origin.y),
        simd_make_float4(0.0, 0.0, 1.0, 0.0),
        simd_make_float4(self.origin.x, self.origin.y, 0.0, 1.0));
    self.transform = translationMatrix;
}

- (void)setTransform:(matrix_float4x4)transform {
    _transform = transform;

    id<MTLBuffer> buffer = self.transformBuffer;
    if (!buffer) {
        return;
    }
    memcpy(buffer.contents, &transform, sizeof(matrix_float4x4));
    self.transformBuffer = buffer;
}

@end

@implementation MetalRender (Renderer)

- (void)startWithView:(MTKView *)view {
    self.view = view;

    [self createPipelineStatesWithView:view];

    if (self.model) {
        [self createBuffersWithView:view];
        [self createTexturesWithView:view];
    }
}

- (void)drawableSizeWillChange:(MTKView *)view size:(CGSize)size {
    id<MTLDevice> device = view.device;
    if (!device) {
        return;
    }

    /// Reset mask texture.
    for (MetalDrawable *drawable in self.drawables) {
        @autoreleasepool {
            if (drawable.maskCount > 0) {
                MTLTextureDescriptor *maskTextureDesc = [[MTLTextureDescriptor alloc] init];
                maskTextureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
                maskTextureDesc.storageMode = MTLStorageModePrivate;
                maskTextureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                maskTextureDesc.width = size.width;
                maskTextureDesc.height = size.height;
                drawable.maskTexture = [device newTextureWithDescriptor:maskTextureDesc];
            }
        }
    }
}

- (void)update:(NSTimeInterval)time {
    if (self.delegate && [self.delegate respondsToSelector:@selector(renderUpdateWithRender:durationTime:)]) {
        [self.delegate renderUpdateWithRender:self durationTime:time];
    }
    [self.model updatePhysics:time];
    [self.model update];
    [self updateDrawables];
}

- (void)beginRenderWithTime:(NSTimeInterval)time viewPort:(MTLViewport)viewPort commandBuffer:(id<MTLCommandBuffer>)commandBuffer passDescriptor:(MTLRenderPassDescriptor *)passDescriptor {
    [self renderMasksWithViewPort:viewPort commandBuffer:commandBuffer];
    [self renderDrawablesWithViewPort:viewPort
                        commandBuffer:commandBuffer
                       passDescriptor:passDescriptor];
}
@end
