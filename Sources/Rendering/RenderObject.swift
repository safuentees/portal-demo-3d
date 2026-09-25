import MetalKit

enum ObjectID: Hashable {
    case sphere, cube, torus, player, entrance, exit, fov, quad
    case floor, entranceBoundary(Int)
    case foregroundBlock, nearBlock, farPillar, edgePillar, nearSideProbe
}

/// Editable placement is the source of truth; every matrix is derived from it.
/// Scene objects use world space. Player/FOV placements use source-camera space.
struct ObjectPlacement {
    var position: SIMD3<Float> = .zero
    var scale = SIMD3<Float>(repeating: 1)
    /// Radians: yaw rotates around local Y, then pitch around X.
    var yaw: Float = 0
    var pitch: Float = 0

    var translation: simd_float4x4 { Transforms.translation(position) }
    var rotation: simd_float4x4 { Transforms.rotateY(yaw) * Transforms.rotateX(pitch) }

    /// Rotation and translation only. Decorative scale never stretches a portal mapping.
    var rigidFrame: simd_float4x4 { rotation * translation }
    var modelMatrix: simd_float4x4 { Transforms.scaling(scale) * rigidFrame }

    var isValid: Bool {
        (0..<3).allSatisfy { position[$0].isFinite && scale[$0].isFinite && scale[$0] != 0 }
            && yaw.isFinite && pitch.isFinite
    }
}

struct RenderObject {
    let id: ObjectID
    let mesh: MTKMesh
    var placement: ObjectPlacement = ObjectPlacement()

    var modelMatrix: simd_float4x4 { placement.modelMatrix }
    var rigidFrame: simd_float4x4 { placement.rigidFrame }
}
