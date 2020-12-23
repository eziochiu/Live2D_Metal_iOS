//
//  ViewController.m
//  Live2DIntegration
//
//  Created by VanJay on 2020/12/17.
//

#import "ViewController.h"
#import "L2DModel.h"
#import "MetalRender.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface ViewController () <MTKViewDelegate, MetalRenderDelegate>
@property (nonatomic) L2DModel *model;
@property (nonatomic) MetalRender *renderer;
@property (nonatomic) MetalRender *OCRenderer;
@property (nonatomic) MTKView *mtkView;
@property (nonatomic) MTLViewport viewPort;
@property (nonatomic) id<MTLCommandQueue> commandQueue;
@property (nonatomic) NSMutableArray <MetalRender *> *renderers;
@property (nonatomic) CGPoint fingerPosition;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor redColor];
    self.renderers = @[].mutableCopy;
    [self setupMtkView];
    [self startRenderWithMetal];
    [self load2DResources];
}

- (void)load2DResources {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Shanbao/Shanbao.model3" ofType:@"json"];
    self.model = [[L2DModel alloc] initWithJsonPath:path];
    if (self.renderer) {
        [self removeRenderer:self.renderer];
    }
    self.renderer = [[MetalRender alloc] init];
    self.renderer.scale = 1.0;
    self.renderer.delegate = self;
    self.renderer.model = self.model;
    [self addRenderer:self.renderer];
}

- (void)startRenderWithMetal {
    if (!self.mtkView) {
        return;
    }
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    
    self.commandQueue = device.newCommandQueue;
    
    self.mtkView.device = device;
    
    self.mtkView.paused = false;
    self.mtkView.hidden = false;
    
    for (MetalRender *render in self.renderers) {
        [render startWithView:self.mtkView];
    }
}

- (void)stopMetalRender {
    self.mtkView.paused = true;
    self.mtkView.hidden = true;
    self.mtkView.device = nil;
}

- (void)addRenderer:(MetalRender *)render {
    if (!self.mtkView) {
        return;
    }
    [self.renderers addObject:render];
    
    if (self.mtkView.paused) {
        if (self.renderers.count == 1) {
            [self startRenderWithMetal];
        }
    } else {
        [render startWithView:self.mtkView];
    }
}

- (void)removeRenderer:(MetalRender *)render {
    [self.renderers removeAllObjects];
    if (self.renderers.count == 0) {
        [self stopMetalRender];
    }
}

- (void)setupMtkView {
    self.mtkView = [[MTKView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.mtkView];
    self.mtkView.delegate = self;
    self.mtkView.framebufferOnly = true;
    self.mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.mtkView.clearColor = MakeMTLColor;
    [self updateMTKViewPort];
}

- (void)updateMTKViewPort {
    CGSize size = self.mtkView.drawableSize;
    MTLViewport viewport = {};
    viewport.znear = 0.0;
    viewport.zfar = 1.0;
    if (size.width > size.height) {
        viewport.originX = 0.0;
        viewport.originY = (size.height - size.width) * 0.5;
        viewport.width = size.width;
        viewport.height = size.width;
    } else {
        viewport.originX = (size.width - size.height) * 0.5;
        viewport.originY = 0.0;
        viewport.width = size.height;
        viewport.height = size.height;
    }
    // 调整显示大小
    self.viewPort = viewport;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    [self updateMTKViewPort];
    for (MetalRender *render in self.renderers) {
        [render drawableSizeWillChange:self.mtkView size:size];
    }
}

- (void)drawInMTKView:(MTKView *)view {
    NSTimeInterval time = 1.0 / NSTimeInterval(view.preferredFramesPerSecond);
    
    for (MetalRender *render in self.renderers) {
        [render update:time];
    }
    
    if (view.currentDrawable) {
        id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
        if (!commandBuffer) {
            return;
        }
        //先清空一次
        MTLRenderPassDescriptor *renderOldDescriptor = [[MTLRenderPassDescriptor alloc] init];
        renderOldDescriptor.colorAttachments[0].texture = view.currentDrawable.texture;
        renderOldDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        renderOldDescriptor.colorAttachments[0].clearColor = MakeMTLColor; // 设置默认颜色
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderOldDescriptor];
        [encoder endEncoding];
        // 然后创建
        MTLRenderPassDescriptor *renderPassDescriptor = [[MTLRenderPassDescriptor alloc] init];
        renderPassDescriptor.colorAttachments[0].texture = view.currentDrawable.texture;
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
        renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        renderPassDescriptor.colorAttachments[0].clearColor = MakeMTLColor; // 设置默认颜色
        
        for (MetalRender *render in self.renderers) {
            [render beginRenderWithTime:time viewPort:self.viewPort commandBuffer:commandBuffer passDescriptor:renderPassDescriptor];
        }
        [commandBuffer presentDrawable:view.currentDrawable];
        [commandBuffer commit];
    }
}

- (void)renderUpdateWithRender:(MetalRender *)renderer durationTime:(NSTimeInterval)duration {
    CGPoint origin = self.view.frame.origin;
    
    CGSize size = self.view.frame.size;
    
    CGPoint ndcOrigin = renderer.origin;
    
    CGFloat scale = MAX(size.width, size.height);
    
    CGPoint newPoint = CGPointMake(self.fingerPosition.x - origin.x - scale*(0.5+ndcOrigin.x), self.fingerPosition.y - origin.y - scale*(0.5+ndcOrigin.y));
    
    [self.model setModelParameterNamed:@"ParamAngleX" withValue:(2.0 * newPoint.x / size.width) * 30.0];
    
    [self.model setModelParameterNamed:@"ParamAngleY" withValue:(2.0 * newPoint.y / size.height) * 30.0];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [[event allTouches] anyObject];
    self.fingerPosition = [touch locationInView:self.view];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [[event allTouches] anyObject];
    self.fingerPosition = [touch locationInView:self.view];
}

@end
