import simd

/// Keep names, order, and types identical to ShaderUniforms in Shaders.metal.
/// Three 64-byte matrices, one padded 48-byte normal matrix, four 16-byte vectors,
/// four 4-byte lighting controls, a 16-byte fill direction, and a 4-byte fill
/// intensity (with trailing alignment padding). Total stride: 352 bytes.
/// SmokeTests checks each offset and actual GPU rendering.
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
    var ambientIntensity: Float
    var diffuseIntensity: Float
    var specularIntensity: Float
    var specularShininess: Float
    var fillLightDirectionWorld: SIMD4<Float>
    var fillIntensity: Float
}

/// Floor-only fragment buffer 2; scene lighting keeps its existing buffer 1.
/// Match FloorUniforms in Shaders.metal: offsets 0/16/32, padded stride 48.
struct FloorUniforms {
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    /// World units per square, independent of the floor mesh's size or camera.
    var checkerSize: Float
}
