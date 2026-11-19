// CoreGraphics' private virtual-display classes (the same ones DeskPad,
// BetterDisplay and Sidecar itself use). Declared here so Swift can call them.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@property (readonly) unsigned int width;
@property (readonly) unsigned int height;
@property (readonly) double refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain) NSArray<CGVirtualDisplayMode *> *modes;
@property unsigned int hiDPI;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain) dispatch_queue_t queue;
@property (retain) NSString *name;
@property unsigned int maxPixelsWide;
@property unsigned int maxPixelsHigh;
@property CGSize sizeInMillimeters;
@property unsigned int vendorID;
@property unsigned int productID;
@property unsigned int serialNum;
@property (copy) void (^terminationHandler)(id, id);
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (readonly) CGDirectDisplayID displayID;
@end
