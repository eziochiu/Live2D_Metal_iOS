//
//  L2DModel.m
//  Live2DMetal
//
//  Copyright (c) 2020-2020 Ian Wang
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
//  LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
//  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import <Foundation/Foundation.h>
#import "L2DModel.h"
#import "Live2DCubismCore.hpp"
#import "CubismUserModel.hpp"
#import "CubismFramework.hpp"
#import "CubismUserModel.hpp"
#import "CubismModelSettingJson.hpp"
#import "CubismIdManager.hpp"

using namespace Live2D::Cubism::Core;
using namespace Live2D::Cubism::Framework;
using namespace Live2D::Cubism::Framework::Rendering;

@interface L2DModel () {
 @private
   NSURL *baseURL;
   
   CubismUserModel *model;
   CubismPhysics *physics;
   ICubismModelSetting *modelSetting;
}

@property (nonatomic, assign, readonly, getter=userModel) CubismUserModel *userModel;
@property (nonatomic, assign, readonly, getter=cubismModel) CubismModel *cubismModel;

@end

@implementation L2DModel

- (instancetype)initWithJsonPath:(NSString *)jsonPath {
    if (self = [super init]) {
        NSURL *url = [NSURL fileURLWithPath:jsonPath];
        // Get base directory name.
        baseURL = [url URLByDeletingLastPathComponent];

        // Read json file.
        NSData *data = [NSData dataWithContentsOfURL:url];

        // Create settings.
        modelSetting = new CubismModelSettingJson((const unsigned char *)[data bytes], (unsigned int)[data length]);

        // Get model file.
        NSString *modelFileName = [NSString stringWithCString:modelSetting->GetModelFileName() encoding:NSUTF8StringEncoding];
        NSData *modelData = [NSData dataWithContentsOfURL:[baseURL URLByAppendingPathComponent:modelFileName]];

        // Create model.
        model = new CubismUserModel();
        model->LoadModel((const unsigned char *)[modelData bytes], (unsigned int)[modelData length]);

        // Create physics.
        NSString *physicsFileName = [NSString stringWithCString:modelSetting->GetPhysicsFileName() encoding:NSUTF8StringEncoding];
        if (physicsFileName.length > 0) {
            NSData *physicsData = [NSData dataWithContentsOfURL:[baseURL URLByAppendingPathComponent:physicsFileName]];
            physics = CubismPhysics::Create((const unsigned char *)[physicsData bytes], (unsigned int)[physicsData length]);
        }
    }

    return self;
}

- (void)dealloc {
    if (modelSetting) {
        free(modelSetting);
    }
    if (model) {
        free(model);
    }
    if (physics) {
        free(physics);
    }
}

- (CubismUserModel*)userModel {
    return model;
}

- (CubismModel*)cubismModel {
    return model->GetModel();
}

- (CGSize)modelSize {
    return CGSizeMake(self.cubismModel->GetCanvasWidth(), self.cubismModel->GetCanvasHeight());
}

- (void)setModelParameterNamed:(NSString *)name withValue:(float)value {
    const auto cubismParamID = CubismFramework::GetIdManager()->GetId((const char *)[name UTF8String]);
    self.cubismModel->SetParameterValue(cubismParamID, value);
}

- (float)getValueForModelParameterNamed:(NSString *)name {
    const auto cubismParamID = CubismFramework::GetIdManager()->GetId((const char *)[name UTF8String]);
    float value = self.cubismModel->GetParameterValue(cubismParamID);
    return value;
}

- (void)setPartsOpacityNamed:(NSString *)name opacity:(float)opacity {
    const auto cubismPartID = CubismFramework::GetIdManager()->GetId((const char *)[name UTF8String]);
    self.cubismModel->SetPartOpacity(cubismPartID, opacity);
}

- (float)getPartsOpacityNamed:(NSString *)name {
    const auto cubismPartID = CubismFramework::GetIdManager()->GetId((const char *)[name UTF8String]);
    float opacity = self.cubismModel->GetPartOpacity(cubismPartID);
    return opacity;
}

- (NSArray *)textureURLs {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (int i = 0; i < modelSetting->GetTextureCount(); ++i) {
        @autoreleasepool {
            NSString *name = [NSString stringWithCString:modelSetting->GetTextureFileName(i) encoding:NSUTF8StringEncoding];
            [urls addObject:[NSURL URLWithString:name relativeToURL:baseURL]];
        }
    }
    return urls;
}

- (int) textureIndexForDrawable:(int)index {
    return self.cubismModel->GetDrawableTextureIndices(index);
}

- (int) drawableCount {
    return self.cubismModel->GetDrawableCount();
}

- (RawFloatArray*) vertexPositionsForDrawable: (int)index {
    int vertexCount = self.cubismModel->GetDrawableVertexCount(index);
    const float *positions = self.cubismModel->GetDrawableVertices(index);

    return [[RawFloatArray alloc] initWithCArray:positions count:vertexCount];
}

- (RawFloatArray*) vertexTextureCoordinateForDrawable: (int)index {
    int vertexCount = self.cubismModel->GetDrawableVertexCount(index);
    const csmVector2 *uvs = self.cubismModel->GetDrawableVertexUvs(index);

    return [[RawFloatArray alloc] initWithCArray:reinterpret_cast<const csmFloat32 *>(uvs) count:vertexCount];
}

- (RawUShortArray*) vertexIndicesForDrawable: (int)index {
    int indexCount = self.cubismModel->GetDrawableVertexIndexCount(index);
    const unsigned short *indices = self.cubismModel->GetDrawableVertexIndices(index);

    return [[RawUShortArray alloc] initWithCArray:indices count:indexCount];
}

- (RawIntArray *)masksForDrawable:(int)index {
    const int *maskCounts = self.cubismModel->GetDrawableMaskCounts();
    const int **masks = self.cubismModel->GetDrawableMasks();

    return [[RawIntArray alloc] initWithCArray:masks[index] count:maskCounts[index]];
}

- (bool) cullingModeForDrawable: (int)index {
    return (self.cubismModel->GetDrawableCulling(index) != 0);
}

- (float) opacityForDrawable: (int)index {
    return self.cubismModel->GetDrawableOpacity(index);
}

- (bool) visibilityForDrawable: (int)index {
    return self.cubismModel->GetDrawableDynamicFlagIsVisible(index);
}

- (L2DBlendMode) blendingModeForDrawable: (int)index {
    switch (self.cubismModel->GetDrawableBlendMode(index)) {
    case CubismRenderer::CubismBlendMode_Normal:
        return NormalBlending;
    case CubismRenderer::CubismBlendMode_Additive:
        return AdditiveBlending;
    case CubismRenderer::CubismBlendMode_Multiplicative:
        return MultiplicativeBlending;
    default:
        return NormalBlending;
    }
}

- (RawIntArray *)renderOrders {
    return [[RawIntArray alloc] initWithCArray:self.cubismModel->GetDrawableRenderOrders() count:[self drawableCount]];
}

- (bool) isRenderOrderDidChangedForDrawable: (int)index {
    return self.cubismModel->GetDrawableDynamicFlagRenderOrderDidChange(index);
}

- (bool) isOpacityDidChangedForDrawable: (int)index {
    return self.cubismModel->GetDrawableDynamicFlagOpacityDidChange(index);
}

- (bool) isVisibilityDidChangedForDrawable: (int)index {
    return self.cubismModel->GetDrawableDynamicFlagVisibilityDidChange(index);
}

- (bool) isVertexPositionDidChangedForDrawable: (int)index {
    return self.cubismModel->GetDrawableDynamicFlagVertexPositionsDidChange(index);
}

@end

@implementation L2DModel (UpdateAndPhysics)

- (void) update {
    self.cubismModel->Update();
}

- (void) updatePhysics: (NSTimeInterval)dt {
    if (physics != nil) {
        physics->Evaluate(self.cubismModel, dt);
    }
}
    

@end
