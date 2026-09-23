import simd

/// Keep names, order, and types identical to ShaderUniforms in Shaders.metal.
/// Three 64-byte matrices, one padded 48-byte normal matrix, four 16-byte vectors.
/// Total stride: 304 bytes. SmokeTests checks each offset and actual GPU rendering.
struct ShaderUniforms {
    /// Complete local-to-world transform, including any camera/portal mapping.
    var modelMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
    var normalMatrix: simd_float3x3
    var color: SIMD4<Float>
    var lightColor: SIMD4<Float>
    var lightPositionWorld: SIMD4<Float>
    var eyeWorld: SIMD4<Float>
}
