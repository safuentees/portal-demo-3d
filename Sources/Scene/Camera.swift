import simd

struct Camera {
    private var baseViewMatrix: simd_float4x4

    /// Movement offset in the base view's coordinate system, not necessarily a world eye.
    private(set) var position = SIMD3<Float>.zero
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0

    init(viewMatrix: simd_float4x4 = matrix_identity_float4x4) {
        self.baseViewMatrix = viewMatrix
    }

    var viewMatrix: simd_float4x4 {
        baseViewMatrix
        * Transforms.translation(-position)
        * Transforms.rotateY(yaw)
        * Transforms.rotateX(pitch)
    }

    var inverseViewMatrix: simd_float4x4 {
        simd_inverse(viewMatrix)
    }

    var worldPosition: SIMD3<Float> {
        // Inverting the complete view includes the base placement and look rotation.
        let p = SIMD4<Float>(0, 0, 0, 1) * inverseViewMatrix
        return SIMD3(p.x, p.y, p.z) / p.w
    }

    mutating func setBaseViewMatrix(_ matrix: simd_float4x4) {
        baseViewMatrix = matrix
        position = .zero
        yaw = 0
        pitch = 0
    }

    mutating func updateMovement(
        direction: SIMD3<Float>,
        deltaTime: Float
    ) {
        guard simd_length_squared(direction) > 0 else { return }

        // The view rotates the world by +yaw; movement uses the inverse (-yaw)
        // to turn camera-local WASD into the base view's movement axes. Ignore
        // pitch so looking up/down preserves the current grounded controls.
        let rotated =
            SIMD4<Float>(direction, 0) *
            Transforms.rotateY(-yaw)

        let movement = SIMD3(rotated.x, rotated.y, rotated.z)
        let step = min(max(deltaTime, 0), 0.1)

        position += simd_normalize(movement)
            * SceneConfiguration.cameraSpeed
            * step
    }

    mutating func updateDirection(_ delta: SIMD2<Float>) {
        // Delta already accumulates mouse travel; multiplying by time again
        // would make the same physical mouse movement depend on frame rate.
        yaw += delta.x * SceneConfiguration.mouseSensitivity
        pitch -= delta.y * SceneConfiguration.mouseSensitivity
    }
}
