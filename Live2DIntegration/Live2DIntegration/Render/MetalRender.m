//
//  L2DRenderer.m
//  Live2DIntegration
//
//  Created by admin on 2020/12/18.
//

#import "MetalRender.h"

@interface MetalRender ()
@property (nonatomic, nullable) MTKView *view;
@property (nonatomic, nonnull) id<MTLRenderPipelineState> pipelineStateBlendingAdditive;
@property (nonatomic, nonnull) id<MTLRenderPipelineState> pipelineStateBlendingMultiplicative;
@property (nonatomic, nonnull) id<MTLRenderPipelineState> pipelineStateBlendingNormal;
@property (nonatomic, nonnull) id<MTLRenderPipelineState> pipelineStateMasking;
@property (nonatomic, nonnull) NSMutableArray <MetalDrawable *> *drawables;
@property (nonatomic, nonnull) NSMutableArray <MetalDrawable *> *drawableSorted;
@property (nonatomic, nonnull) id<MTLBuffer> transformBuffer;
@property (nonatomic, nonnull) NSMutableArray <id<MTLTexture>> *textures;
@end

@implementation MetalRender

- (instancetype)init {
    self = [super init];
    if (self) {
        _origin = CGPointZero;
        _scale = 1.0;
        _transform = matrix_identity_float4x4;
        _drawables = @[].mutableCopy;
        _drawableSorted = @[].mutableCopy;
        _textures = @[].mutableCopy;
    }
    return self;
}

- (void)setTransform:(matrix_float4x4)transform {
    _transform = transform;
    id<MTLBuffer> buffer = self.transformBuffer;
    if (buffer) {
        memcpy(buffer.contents, &transform, sizeof(simd_float4x4));
    }
    self.transformBuffer = buffer;
}

- (void)setScale:(CGFloat)scale {
    _scale = scale;
    simd_float4x4 translationMatrix = {
        simd_make_float4(self.scale, 0.0, 0.0, self.origin.x),
        simd_make_float4(0.0, self.scale, 0.0, self.origin.y),
        simd_make_float4(0.0, 0.0, 1.0, 0.0),
        simd_make_float4(self.origin.x, self.origin.y, 0.0, 1.0)
    };
    self.transform = translationMatrix;
}

-(void)setOrigin:(CGPoint)origin {
    _origin = origin;
    simd_float4x4 translationMatrix = {
        simd_make_float4(self.scale, 0.0, 0.0, self.origin.x),
        simd_make_float4(0.0, self.scale, 0.0, self.origin.y),
        simd_make_float4(0.0, 0.0, 1.0, 0.0),
        simd_make_float4(self.origin.x, self.origin.y, 0.0, 1.0)
    };
    self.transform = translationMatrix;
}

- (void)setModel:(L2DModel *)model {
    _model = model;
    if (self.view && model) {
        [self createBuffersWithView:self.view];
        [self createTexturesWithView:self.view];
    }
}

- (void)createBuffersWithView:(MTKView *)view {
    if (!view.device) {
        return;
    }
    if (!self.model) {
        return;
    }
    
    matrix_float4x4 transform = self.transform;
    
    self.transformBuffer = [self.view.device newBufferWithBytes:&(transform) length:sizeof(matrix_float4x4) options:MTLResourceCPUCacheModeDefaultCache];
    
    int drawableCount = self.model.drawableCount;
    
    for (int i = 0; i < drawableCount; i++) {
        MetalDrawable *drawable = [[MetalDrawable alloc] init];
        drawable.drawableIndex = i;
        
        RawFloatArray *vertexPositions = [self.model vertexPositionsForDrawable:i];
        if (vertexPositions) {
            drawable.vertexCount = vertexPositions.count;
            if (drawable.vertexCount > 0) {
                drawable.vertexPositionBuffer = [view.device newBufferWithBytes:vertexPositions.floats length:(2 * vertexPositions.count * sizeof(float)) options:MTLResourceCPUCacheModeDefaultCache];
                
            }
        }
        
        RawFloatArray *vertexTextureCoords = [self.model vertexTextureCoordinateForDrawable:i];
        if (vertexTextureCoords) {
            if (drawable.vertexCount > 0) {
                drawable.vertexTextureCoordinateBuffer = [view.device newBufferWithBytes:vertexTextureCoords.floats length:(2 * vertexTextureCoords.count * sizeof(float)) options:MTLResourceCPUCacheModeDefaultCache];
                
            }
        }
        
        RawUShortArray *vertexIndices = [self.model vertexIndicesForDrawable:i];
        if (vertexIndices) {
            drawable.indexCount = vertexIndices.count;
            if (drawable.indexCount > 0) {
                drawable.vertexIndexBuffer = [self.view.device newBufferWithBytes:vertexIndices.ushorts length:(vertexIndices.count * sizeof(ushort)) options:MTLResourceCPUCacheModeDefaultCache];
            }
        }
        
        drawable.textureIndex = [self.model textureIndexForDrawable:i];
        
        RawIntArray *masks = [self.model masksForDrawable:i];
        if (masks) {
            drawable.maskCount = masks.count;
            drawable.masks = [masks intArray];
        }
        
        drawable.blendMode = [self.model blendingModeForDrawable:i];
        drawable.cullingMode = [self.model cullingModeForDrawable:i];
        
        drawable.opacity = [self.model opacityForDrawable:i];
        
        drawable.opacityBuffer = [self.view.device newBufferWithBytes:[self convertFloat2FloatArray:drawable.opacity] length:sizeof(float) options:MTLResourceCPUCacheModeDefaultCache];
        
        drawable.visibility = [self.model visibilityForDrawable:i];
        
        [self.drawables addObject:drawable];
    }
    NSArray *renderOrders = self.model.renderOrders.intArray;
    self.drawableSorted = [self.drawables sortedArrayUsingComparator:^NSComparisonResult(MetalDrawable *obj1, MetalDrawable *obj2) {
        return [renderOrders[obj1.drawableIndex] compare:renderOrders[obj2.drawableIndex]];
    }];
}

- (float *)convertFloat2FloatArray:(float)f {
    float *list = (float *)malloc(sizeof(float));
    list[0] = 1.5 * f;
    return list;
}

- (void)createTexturesWithView:(MTKView *)view {
    if (!view.device) {
        return;
    }
    if (!self.model) {
        return;
    }
    
    CGSize size = view.drawableSize;
    if (self.model.textureURLs) {
        MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:view.device];
        for (NSURL *url in self.model.textureURLs) {
            id <MTLTexture> texture = [loader newTextureWithContentsOfURL:url options:@{} error:nil];
            [self.textures addObject:texture];
        }
    }
    
    for (MetalDrawable *drawable in self.drawables) {
        if (drawable.maskCount > 0) {
            MTLTextureDescriptor* desc = [[MTLTextureDescriptor alloc] init];
            desc.pixelFormat = MTLPixelFormatBGRA8Unorm;
            desc.storageMode = MTLStorageModePrivate;
            desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
            desc.width = size.width;
            desc.height = size.height;
            drawable.maskTexture = [self.view.device newTextureWithDescriptor:desc];
        }
    }
}

- (void)createPipelineStatesWuthView:(MTKView *)view {
    if (!view.device) {
        return;
    }
    
    NSError *error;
    
    id<MTLLibrary> library = [view.device newDefaultLibrary];
    
    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = [library newFunctionWithName:@"basic_vertex"];
    pipelineDesc.fragmentFunction = [library newFunctionWithName:@"basic_fragment"];
    
    MTLVertexDescriptor *vertexDesc = [MTLVertexDescriptor new];
    
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
    
    self.pipelineStateBlendingNormal = [self.view.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    
    // MARK: Additive Blending.
    pipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    
    pipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
    
    self.pipelineStateBlendingAdditive = [self.view.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    
    // MARK: Multiplicative Blending.
    pipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorDestinationColor;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    pipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorZero;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;

    self.pipelineStateBlendingMultiplicative = [self.view.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    
    // MARK: Masking.
    pipelineDesc.vertexFunction = [library newFunctionWithName:@"basic_vertex"];
    pipelineDesc.fragmentFunction = [library newFunctionWithName:@"mask_fragment"];
    
    pipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    pipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    self.pipelineStateMasking = [self.view.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
}

- (void)startWithView:(MTKView *)view {
    self.view = view;
    [self createPipelineStatesWuthView:view];
    if (self.model) {
        [self createBuffersWithView:view];
        [self createTexturesWithView:view];
    }
}

- (void)drawableSizeWillChange:(MTKView *)view size:(CGSize)size {
    if (!view.device) {
        return;
    }
    
    for (MetalDrawable *drawable in self.drawables) {
        if (drawable.maskCount > 0) {
            MTLTextureDescriptor *maskTextureDesc = [[MTLTextureDescriptor alloc] init];
            maskTextureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
            maskTextureDesc.storageMode = MTLStorageModePrivate;
            maskTextureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
            maskTextureDesc.width = size.width;
            maskTextureDesc.height = size.height;
            drawable.maskTexture = [view.device newTextureWithDescriptor:maskTextureDesc];
        }
    }
}

- (void)update:(NSTimeInterval)time {
    if (self.delegate && [self.delegate respondsToSelector:@selector(rendererUpdateWithRender:durationTime:)]) {
        [self.delegate rendererUpdateWithRender:self durationTime:time];
    }
    [self.model updatePhysics:time];
    [self.model update];
    [self updateDrawables];
}

- (void)updateDrawables {
    if (!self.model) {
        return;
    }
    BOOL needSorting = false;
    for (MetalDrawable *drawable in self.drawables) {
        int index = drawable.drawableIndex;
        if ([self.model isOpacityDidChangedForDrawable:index]) {
            drawable.opacity = [self.model opacityForDrawable:index];
            memcpy(drawable.opacityBuffer.contents, [self convertFloat2FloatArray:drawable.opacity], sizeof(float));
        }
        
        if ([self.model visibilityForDrawable:index]) {
            drawable.visibility = [self.model visibilityForDrawable:index];
        }
        
        if ([self.model isRenderOrderDidChangedForDrawable:index]) {
            needSorting = true;
        }
        
        if ([self.model isVertexPositionDidChangedForDrawable:index]) {
            RawFloatArray *vertexPositions = [self.model vertexPositionsForDrawable:index];
            if (vertexPositions) {
                memcpy(drawable.vertexPositionBuffer.contents, vertexPositions.floats, 2*drawable.vertexCount * sizeof(float));
            }
        }
        
        if (needSorting) {
            NSArray *renderOrders = self.model.renderOrders.intArray;
            self.drawableSorted = [self.drawables sortedArrayUsingComparator:^NSComparisonResult(MetalDrawable *obj1, MetalDrawable *obj2) {
                return [renderOrders[obj1.drawableIndex] compare:renderOrders[obj2.drawableIndex]];
            }];
        }
    }
}

- (void)beginRenderWithTime:(NSTimeInterval)time viewPort:(MTLViewport)viewPort commandBuffer:(id<MTLCommandBuffer>)commandBuffer passDescriptor:(MTLRenderPassDescriptor *)passDescriptor {
    [self renderMasksWithViewPort:viewPort commandBuffer:commandBuffer];
    [self renderDrawablesWithViewPort:viewPort commandBuffer:commandBuffer passDescriptor:passDescriptor];
}

- (void)renderMasksWithViewPort:(MTLViewport)viewPort commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    MTLRenderPassDescriptor *passDesc = [[MTLRenderPassDescriptor alloc] init];
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0); // 设置默认颜色
    for (MetalDrawable *drawable in self.drawables) {
        if (drawable.maskCount > 0) {
            passDesc.colorAttachments[0].texture = drawable.maskTexture;
            id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
            [encoder setRenderPipelineState:self.pipelineStateBlendingNormal];
            [encoder setViewport:viewPort];
            
            for (NSNumber *index in drawable.masks) {
                MetalDrawable *mask = self.drawables[index.intValue];
                [encoder setVertexBuffer:self.transformBuffer offset:0 atIndex:L2DBufferIndexTransform];
                [encoder setVertexBuffer:mask.vertexPositionBuffer offset:0 atIndex:L2DBufferIndexPosition];
                [encoder setVertexBuffer:mask.vertexTextureCoordinateBuffer offset:0 atIndex:L2DBufferIndexUV];
                [encoder setVertexBuffer:mask.opacityBuffer offset:0 atIndex:L2DBufferIndexOpacity];
                
                [encoder setFragmentTexture:self.textures[mask.textureIndex] atIndex:L2DTextureIndexUniform];
                if (mask.vertexIndexBuffer) {
                    [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:mask.indexCount indexType:MTLIndexTypeUInt16 indexBuffer:mask.vertexIndexBuffer indexBufferOffset:0];
                }
            }
            [encoder endEncoding];
        }
    }
}

- (void)renderDrawablesWithViewPort:(MTLViewport)viewPort commandBuffer:(id<MTLCommandBuffer>)commandBuffer passDescriptor:(MTLRenderPassDescriptor *)passDescriptor {
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    [encoder setViewport:viewPort];
    [encoder setVertexBuffer:self.transformBuffer offset:0 atIndex:L2DBufferIndexTransform];
    for (MetalDrawable *drawable in self.drawableSorted) {
        [encoder setVertexBuffer:drawable.vertexPositionBuffer offset:0 atIndex:L2DBufferIndexPosition];
        [encoder setVertexBuffer:drawable.vertexTextureCoordinateBuffer offset:0 atIndex:L2DBufferIndexUV];
        [encoder setVertexBuffer:drawable.opacityBuffer offset:0 atIndex:L2DBufferIndexOpacity];
        
        if (drawable.cullingMode) {
            [encoder setCullMode:MTLCullModeBack];
        } else {
            [encoder setCullMode:MTLCullModeNone];
        }
        
        if (drawable.maskCount > 0) {
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
            [encoder setFragmentTexture:self.textures[drawable.textureIndex] atIndex:L2DTextureIndexUniform];
            if (drawable.vertexIndexBuffer) {
                [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:drawable.indexCount indexType:MTLIndexTypeUInt16 indexBuffer:drawable.vertexIndexBuffer indexBufferOffset:0];
            }
        }
    }
    [encoder endEncoding];
}

@end
