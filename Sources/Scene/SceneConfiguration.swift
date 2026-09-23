import Metal
import simd

/// Start here when changing the scene. RGBA components use the 0...1 range.
enum SceneConfiguration {
    // Opaque role palette, authored for direct .bgra8Unorm output (no sRGB transfer).
    // The FOV is unlit and deliberately dimmer than the solid objects.
    static let backgroundColor = MTLClearColor(red: 24.0 / 255, green: 24.0 / 255, blue: 27.0 / 255, alpha: 1)
    // Pale cool solids, blue portals, and teal mapped representations.
    static let sceneObjectColor = SIMD4<Float>(0.54, 0.59, 0.64, 1.0)
    static let portalColor = SIMD4<Float>(0.38, 0.49, 0.64, 1.0)
    static let mappedPlayerColor = SIMD4<Float>(0.38, 0.65, 0.58, 1.0)
    static let mappedFOVColor = SIMD4<Float>(0.14, 0.27, 0.25, 1.0)

    static let lightColor = SIMD4<Float>(repeating: 1.0)
    // A neutral, elevated main light, fixed in world space. No distance falloff.
    static let lightPositionWorld = SIMD4<Float>(-3, 5, -1, 1)
    // Ambient retains the darkest faces; diffuse carries the main light's shape.
    static let ambientIntensity: Float = 0.38
    static let diffuseIntensity: Float = 0.85
    // A broad, restrained Blinn–Phong highlight leaves the material color visible.
    static let specularIntensity: Float = 0.045
    static let specularShininess: Float = 20
    // Weak diffuse-only fill from the opposite side separates rear-facing planes.
    // This is a world-space direction TOWARD the light, not a position (w = 0).
    static let fillLightDirectionWorld = SIMD4<Float>(2, 3, 5, 0)
    static let fillIntensity: Float = 0.22

    static let sphereExtent = SIMD3<Float>(repeating: 0.75)
    static let sphereSegments = SIMD2<UInt32>(30, 30)

    static let cubeSegments = SIMD3<UInt32>(1, 1, 1)
    static let cubeExtent = SIMD3<Float>(repeating: 1.0)

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
