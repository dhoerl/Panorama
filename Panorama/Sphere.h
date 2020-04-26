//
//  Sphere.h
//  Panorama
//
//  Created by David Hoerl on 4/25/20.
//  Copyright © 2020 Robby Kraft. All rights reserved.
//

#ifdef FROGGY2

#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

@interface Sphere : NSObject

-(bool) execute;
-(id) init:(GLint)stacks slices:(GLint)slices radius:(GLfloat)radius textureFile:(NSString *)textureFile;
-(void) swapTexture:(NSString*)textureFile;
-(void) swapTextureWithImage:(UIImage*)image;
-(CGSize) getTextureSize;

@end

#else

#import "Panorama-Swift.h"

#endif
