#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 positionWorld;
    float3 normalWorld;
};

// Match the field order and types in Rendering/ShaderUniforms.swift.
struct ShaderUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
    float4 color;
    float4 lightColor;
    float4 lightPositionWorld;
    float4 eyeWorld;
};

vertex VertexOut scene_vertex(
    VertexIn in [[stage_in]],
    constant ShaderUniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    // Model already includes the complete placement in world space. Row vectors,
    // +Z forward: enter viewing/clip space only for rasterization.
    out.positionWorld = float4(in.position, 1.0) * uniforms.modelMatrix;
    out.position = out.positionWorld * uniforms.viewMatrix * uniforms.projectionMatrix;
    out.normalWorld = normalize(in.normal * uniforms.normalMatrix);
    return out;
}

// A debug outline should remain readable regardless of the light's direction.
fragment float4 fov_fragment(
    VertexOut out [[stage_in]],
    constant ShaderUniforms &uniforms [[buffer(1)]]
) {
    return uniforms.color;
}

fragment float4 lit_fragment(
    VertexOut out [[stage_in]],
    constant ShaderUniforms &uniforms [[buffer(1)]]
) {
    float3 N = normalize(out.normalWorld);

    float3 lightDirection = normalize(
        uniforms.lightPositionWorld.xyz - out.positionWorld.xyz
    );

    float3 cameraDirection = normalize(
        uniforms.eyeWorld.xyz - out.positionWorld.xyz
    );

    float ambientStrength = 0.35;
    float specularIntensity = 0.12;
    float shininess = 32.0;

    float3 ambient =
        ambientStrength *
        uniforms.lightColor.rgb *
        uniforms.color.rgb;

    float diffuseStrength =
        max(dot(N, lightDirection), 0.0);

    float3 diffuse =
        diffuseStrength *
        uniforms.lightColor.rgb *
        uniforms.color.rgb;

    float3 H = normalize(lightDirection + cameraDirection);

    float specularStrength = 0.0;

    if (diffuseStrength > 0.0) {
        specularStrength =
            specularIntensity *
            pow(max(dot(N, H), 0.0), shininess);
    }

    // Not multiplied by object color, so it reflects the light's color.
    float3 specular =
        specularStrength *
        uniforms.lightColor.rgb;

    float3 finalColor = ambient + diffuse + specular;

    return float4(finalColor, uniforms.color.a);
}
