import Metal
import simd

/// Start here when changing the scene. RGBA components use the 0...1 range.
enum SceneConfiguration {
    static let sceneColor = SIMD4<Float>(0.20, 0.45, 0.90, 1.0)
    static let lightColor = SIMD4<Float>(repeating: 1.0)
    static let lightPositionWorld = SIMD4<Float>(1, 1, 0, 1.0)

    static let backgroundColor = MTLClearColor(red: 1, green: 1, blue: 0.8, alpha: 1)

    static let sphereExtent = SIMD3<Float>(repeating: 0.75)
    static let sphereSegments = SIMD2<UInt32>(30, 30)

    static let cubeSegments = SIMD3<UInt32>(1, 1, 1)
    static let cubeExtent = SIMD3<Float>(repeating: 1.0)

    static let fovColor = SIMD4<Float>(0.20, 0.45, 0.90, 1.0)

    // Portal placements are world-space; player placement is source-camera-local.
    static let entrancePlacement = ObjectPlacement(position: [0, 0, 2.5], scale: [1, 1.5, 0.1])
    static let exitPlacement = ObjectPlacement(position: [1, 0, 3], scale: [1, 1.5, 0.1], yaw: .pi / 2)
    static let playerPlacement = ObjectPlacement(scale: [0.01, 0.01, 0.01], yaw: .pi / 2)

    // Shared by the camera projection and its FOV outline. FOV is vertical;
    // near/far are distances from the eye along camera-local +Z, in world units.
    static let fieldOfViewRadians: Float = 70 * .pi / 180
    static let nearPlane: Float = 0.1
    static let farPlane: Float = 100
    static let cameraSpeed: Float = 1.5
    static let mouseSensitivity: Float = 0.01
}
