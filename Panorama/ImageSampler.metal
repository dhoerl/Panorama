//
//  ImageSampler.metal
//  Panorama
//
//  Created by David Hoerl on 5/18/20.
//  Copyright © 2020 Robby Kraft. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;


kernel void imageSampler(texture2d<float, access::read> inTexture [[texture(0)]],
                           texture2d<float, access::write> outTexture [[texture(1)]],
                           uint2 gid [[thread_position_in_grid]])
{
     float4 inColor   = inTexture.read(gid);
     //
     // flip texture vertically if it needs to display with right orientation
     //
     outTexture.write(inColor, gid);
}
