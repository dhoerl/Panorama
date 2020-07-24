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

struct Uniforms {
  float4x4 projectionMatrix;
  float4x4 attitudeMatrix;
  float4x4 offsetMatrix;
};

vertex VertexInOut texturedQuadVertex(constant float4         *pPosition   [[ buffer(0) ]],
                                      constant packed_float2  *pTexCoords  [[ buffer(1) ]],
                                      const device Uniforms&  uniforms     [[ buffer(2) ]],
                                      //constant float4x4       *pMVP        [[ buffer(2) ]],
                                      uint                     vid         [[ vertex_id ]])
{

    float4x4 projection_matrix = uniforms.projectionMatrix;
    float4x4 attitude_matrix = uniforms.attitudeMatrix;
    float4x4 offset_matrix = uniforms.offsetMatrix;

    VertexInOut outVertices;

    //outVertices.m_Position = pPosition[vid];
    outVertices.m_Position = projection_matrix * attitude_matrix * offset_matrix * pPosition[vid];
    outVertices.m_TexCoord = pTexCoords[vid];

    return outVertices;
}

fragment half4 texturedQuadFragment(VertexInOut     inFrag    [[ stage_in ]],
                                    texture2d<half>  tex2D    [[ texture(0) ]])
{
    constexpr sampler s(coord::normalized, address::repeat, filter::linear);
    constexpr sampler quad_sampler;
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, filter::linear);

    half4 color = tex2D.sample(textureSampler, inFrag.m_TexCoord);

    return color;
}
