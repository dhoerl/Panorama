//
//  RenderEncoder.metal
//  Panorama
//
//  Copyright © 2020 David Hoerl . All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexInOut
{
    float4 m_Position [[position]];
    float2 m_TexCoord [[user(texturecoord)]];
};

vertex VertexInOut texturedQuadVertex(constant float4         *pPosition   [[ buffer(0) ]],
                                      constant packed_float2  *pTexCoords  [[ buffer(1) ]],
                                      constant float4x4       *pMVP        [[ buffer(2) ]],
                                      uint                     vid         [[ vertex_id ]])
{
    VertexInOut outVertices;

    outVertices.m_Position = pPosition[vid];
    outVertices.m_TexCoord = pTexCoords[vid];

    return outVertices;
}

fragment half4 texturedQuadFragment(VertexInOut     inFrag    [[ stage_in ]],
                                    texture2d<half>  tex2D     [[ texture(0) ]])
{
    constexpr sampler quad_sampler;
    half4 color = tex2D.sample(quad_sampler, inFrag.m_TexCoord);

    return color;
}
