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
    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;
    float specularShininess;
    float4 fillLightDirectionWorld;
    float fillIntensity;
};

// Coincident light/eye positions and opposing L/V have no defined direction.
// Returning zero also gives those cases zero diffuse/specular contribution.
float3 directionOrZero(float3 vector) {
    float lengthSquared = dot(vector, vector);
    return lengthSquared > 1e-12 ? vector * rsqrt(lengthSquared) : float3(0.0);
}

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

struct TexturePreviewOut {
    float4 position [[position]];
};

struct TexturedVertexIn {
    float3 position [[attribute(0)]];
    float2 uv [[attribute(2)]];
};

struct TexturedSurfaceOut {
    float4 position [[position]];
    float2 uv;
};

vertex TexturedSurfaceOut texture_surface_vertex(
    TexturedVertexIn in [[stage_in]],
    constant ShaderUniforms &uniforms [[buffer(1)]]
) {
    TexturedSurfaceOut out;
    out.position = float4(in.position, 1.0) * uniforms.modelMatrix
        * uniforms.viewMatrix * uniforms.projectionMatrix;
    // QuadMesh has V = 0 at the bottom; a rendered Metal image starts at the top.
    out.uv = float2(in.uv.x, 1.0 - in.uv.y);
    return out;
}

fragment float4 texture_surface_fragment(
    TexturedSurfaceOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]]
) {
    float2 viewportSize = float2(
        cameraTexture.get_width(),
        cameraTexture.get_height()
    );

    float2 screenUV = in.position.xy / viewportSize;

    constexpr sampler imageSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    return cameraTexture.sample(imageSampler, screenUV);
}
// One oversized triangle covers the viewport; no mesh or vertex buffer is needed.
vertex TexturePreviewOut texture_preview_vertex(uint vertexID [[vertex_id]]) {
    const float2 corners[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    TexturePreviewOut out;
    out.position = float4(corners[vertexID], 0, 1);
    return out;
}

fragment float4 texture_preview_fragment(
    TexturePreviewOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    constant float4 &viewportRect [[buffer(2)]]
) {
    constexpr sampler imageSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    // Fragment position and texture UVs both start at the top left. Subtract the
    // right viewport's drawable-pixel origin before normalizing within that view.
    float2 uv = (in.position.xy - viewportRect.xy) / viewportRect.zw;
    return cameraTexture.sample(imageSampler, uv);
}

fragment float4 lit_fragment(
    VertexOut out [[stage_in]],
    constant ShaderUniforms &uniforms [[buffer(1)]]
) {
    float3 N = normalize(out.normalWorld);

    float3 lightDirection = directionOrZero(
        uniforms.lightPositionWorld.xyz - out.positionWorld.xyz
    );

    float3 cameraDirection = directionOrZero(
        uniforms.eyeWorld.xyz - out.positionWorld.xyz
    );

    float3 ambient =
        uniforms.ambientIntensity *
        uniforms.lightColor.rgb *
        uniforms.color.rgb;

    float diffuseStrength =
        max(dot(N, lightDirection), 0.0);

    float3 diffuse =
        uniforms.diffuseIntensity *
        diffuseStrength *
        uniforms.lightColor.rgb *
        uniforms.color.rgb;

    // A weaker, neutral Lambert fill distinguishes faces away from the main light.
    // It is fixed in world space and intentionally contributes no specular highlight.
    float fillStrength = max(dot(N, directionOrZero(uniforms.fillLightDirectionWorld.xyz)), 0.0);
    float3 fill = uniforms.fillIntensity * fillStrength * uniforms.lightColor.rgb * uniforms.color.rgb;

    float3 H = directionOrZero(lightDirection + cameraDirection);

    float specularStrength = 0.0;

    if (diffuseStrength > 0.0 && dot(cameraDirection, cameraDirection) > 0.0) {
        specularStrength =
            uniforms.specularIntensity *
            pow(max(dot(N, H), 0.0), uniforms.specularShininess);
    }

    // Not multiplied by object color, so it reflects the light's color.
    float3 specular =
        specularStrength *
        uniforms.lightColor.rgb;

    // Artistic display-value shading: the .bgra8Unorm attachment stores these
    // values directly. Keep this in sync with the palette's encoding convention.
    float3 finalColor = ambient + diffuse + fill + specular;

    return float4(finalColor, uniforms.color.a);
}
