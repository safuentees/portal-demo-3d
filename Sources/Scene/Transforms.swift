import simd

/// Matches metsl: row vectors, +Z forward, and Metal depth in the 0...1 range.
/// Shaders multiply position * model * view * projection.
enum Transforms {
    /// Identity connection: source world -> entrance-local -> destination world.
    static func portalMapping(
        entranceFrame: simd_float4x4,
        exitFrame: simd_float4x4
    ) -> PortalMapping {
        precondition(simd_determinant(entranceFrame).isFinite && simd_determinant(entranceFrame) != 0)
        precondition(simd_determinant(exitFrame).isFinite && simd_determinant(exitFrame) != 0)
        return PortalMapping(transferAB: simd_inverse(entranceFrame) * exitFrame)
    }

    /// Row-vector normals remain perpendicular to surfaces after nonuniform scale.
    static func normalMatrix(for modelMatrix: simd_float4x4) -> simd_float3x3 {
        let linear = simd_float3x3(
            SIMD3(modelMatrix.columns.0.x, modelMatrix.columns.0.y, modelMatrix.columns.0.z),
            SIMD3(modelMatrix.columns.1.x, modelMatrix.columns.1.y, modelMatrix.columns.1.z),
            SIMD3(modelMatrix.columns.2.x, modelMatrix.columns.2.y, modelMatrix.columns.2.z)
        )
        precondition(simd_determinant(linear).isFinite && simd_determinant(linear) != 0)
        return simd_transpose(simd_inverse(linear))
    }

    static func translation(_ offset: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, offset.x),
            SIMD4<Float>(0, 1, 0, offset.y),
            SIMD4<Float>(0, 0, 1, offset.z),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func scaling(_ offset: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(offset.x, 0, 0, 0),
            SIMD4<Float>(0, offset.y, 0, 0),
            SIMD4<Float>(0, 0, offset.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func rotateZ(_ a: Float) -> simd_float4x4 {
        let c = cos(a)
        let s = sin(a)
        return simd_float4x4(columns: (
            SIMD4<Float>(c, -s, 0, 0),
            SIMD4<Float>(s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func rotateY(_ a: Float) -> simd_float4x4 {
        let c = cos(a)
        let s = sin(a)
        return simd_float4x4(columns: (
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func rotateX(_ a: Float) -> simd_float4x4 {
        let c = cos(a)
        let s = sin(a)
        return simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, -s, 0),
            SIMD4<Float>(0, s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func perspective(
        aspect: Float,
        fieldOfView: Float,
        near: Float,
        far: Float
    ) -> simd_float4x4 {
        precondition(aspect.isFinite && aspect > 0)
        precondition(fieldOfView.isFinite && fieldOfView > 0 && fieldOfView < .pi)
        precondition(near.isFinite && far.isFinite && near > 0 && far > near)
        let yScale = 1 / tan(fieldOfView / 2)
        let zScale = far / (far - near)
        return simd_float4x4(columns: (
            SIMD4<Float>(yScale / aspect, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -near * zScale),
            SIMD4<Float>(0, 0, 1, 0)
        ))
    }
}

/// Directed rigid mappings. Callers supply rotation/translation frames, never visual scale.
struct PortalMapping {
    let transferAB: simd_float4x4
    var transferBA: simd_float4x4 { simd_inverse(transferAB) }
}
